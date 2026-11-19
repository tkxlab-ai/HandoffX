#!/bin/bash
# review-loop.sh — maintainer-only cyclic code-review harness (P0: A/B/C/E).
# Dev tool: NOT dual-sourced to skills/handoffx/scripts/, NOT in .skill (ADR-0003 ⑦).
# usage: review-loop.sh {start|record|status|finalize|override|help} ...
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$SCRIPT_DIR/../scripts/lib/handoff-schema.sh"
# shellcheck source=tools/lib/review-ledger.sh
. "$SCRIPT_DIR/lib/review-ledger.sh"

usage() {
    cat <<'EOF'
review-loop.sh — cyclic code-review harness (P0)

  start    --topic <slug> <file...>         begin a loop over a content set
  record   --reviewer <id> --verdict <V> [--ground credential|privacy|-]
           [--findings <file>] <file...>    record one reviewer round
  status                                    show streak / state / rounds
  finalize [--devlog <path>] [--cap]        emit durable outcome line
  override --reason <text>                  Boss-only: lift a credential/privacy veto
  help                                      this text

Verdicts: PASS WARN BLOCKED USER_DECISION ERROR N-A
Exit: 0 ok / 1 error / 2 usage / 3 escalation-to-Boss (veto or cap)
EOF
}

RL_DIR=".review-loop/current"

rl_die() { echo "❌ $1" >&2; exit "${2:-1}"; }
# A value flag needs a non-empty value; `shift 2` on a trailing flag would never
# advance and spin the parse loop forever.
need_val() { [ $# -ge 2 ] && [ -n "$2" ] || rl_die "$1 needs a value" 2; }
# A loop dir without a regular ledger file or a readable state holding one of the
# five enum values is corruption, not a fresh loop: refuse instead of reading
# "0 rounds" or writing a forged/blank verdict into the durable outcome line.
rl_load_loop() {
    [ -d "$RL_DIR" ] || rl_die "no active loop — run 'start' first" 1
    [ -f "$RL_DIR/ledger.tsv" ] || rl_die "ledger is not a regular file: $RL_DIR/ledger.tsv (loop state corrupted — rm -rf $RL_DIR and start again)" 1
    st=$(cat "$RL_DIR/state" 2>/dev/null) || rl_die "state unreadable: $RL_DIR/state" 1
    case "$st" in
        ACTIVE|VETOED|CONVERGED|CAPPED|OVERRIDDEN) ;;
        *) rl_die "state corrupted (not one of ACTIVE/VETOED/CONVERGED/CAPPED/OVERRIDDEN): $RL_DIR/state" 1 ;;
    esac
}
# Every state transition is only real once it is on disk.
set_state() { printf '%s\n' "$1" > "$RL_DIR/state" || rl_die "cannot write state: $RL_DIR/state" 1; }

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
    -h|--help|help) usage; exit 0 ;;

    start)
        topic=""
        files=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --topic) need_val "$@"; topic="$2"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) files+=("$1"); shift ;;
            esac
        done
        [ -n "$topic" ] || rl_die "start needs --topic <slug>" 2
        # topic lands in meta next to the file= lines; a newline in it could forge one.
        case "$topic" in *[[:space:]]*) rl_die "--topic must be a single token (no whitespace)" 2 ;; esac
        [ ${#files[@]} -ge 1 ] || rl_die "start needs >=1 content file" 2
        [ -d "$RL_DIR" ] && rl_die "a loop is already active ($RL_DIR) — finalize it first" 2
        # Anything else at that path is not ours: the failure branch below rm -rf's it.
        { [ -e "$RL_DIR" ] || [ -L "$RL_DIR" ]; } && rl_die "$RL_DIR exists but is not a loop dir — remove it first" 2
        ch=$(rl_content_hash "${files[@]}") || rl_die "content hash failed" 1
        mkdir -p "$RL_DIR" && : > "$RL_DIR/ledger.tsv" && printf 'ACTIVE\n' > "$RL_DIR/state" &&
        # The start set is the loop's truth: every later round must cover exactly it.
        { printf 'topic=%s\ncontent_hash=%s\n' "$topic" "$ch" &&
          printf '%s\n' "${files[@]}" | LC_ALL=C sort -u | sed 's/^/file=/'; } > "$RL_DIR/meta" ||
            { rm -rf "$RL_DIR"; rl_die "cannot create $RL_DIR" 1; }   # half-made dir would block the next start
        echo "✅ loop started: topic=$topic content_hash=${ch%${ch#????????}}…"
        ;;

    status)
        rl_load_loop
        n=$(rl_round_count "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        s=$(rl_convergence_streak "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        echo "state=$st rounds=$n streak=$s"
        ;;

    record)
        reviewer=""; verdict=""; ground="-"; findings=""; maxr=12
        files=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --reviewer)   need_val "$@"; reviewer="$2"; shift 2 ;;
                --verdict)    need_val "$@"; verdict="$2"; shift 2 ;;
                --ground)     need_val "$@"; ground="$2"; shift 2 ;;
                --findings)   need_val "$@"; findings="$2"; shift 2 ;;
                --max-rounds) need_val "$@"; maxr="$2"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) files+=("$1"); shift ;;
            esac
        done
        rl_load_loop
        [ "$st" = "ACTIVE" ] || {
            if [ "$st" = "CAPPED" ]; then
                rl_die "loop CAPPED (no auto-continue — Decision 0009/0010) — finalize to emit the durable outcome (exit 3), then start a new loop" 3
            fi
            rl_die "loop not ACTIVE (state=$st) — finalize/override first" 1
        }
        # A credential/privacy BLOCKED round already in the ledger while state is still
        # ACTIVE means that veto never reached disk; the veto test below only sees the
        # current round, so without this the loop would forget it and converge.
        if grep -qE ' verdict=BLOCKED ground=(credential|privacy) ' "$RL_DIR/ledger.tsv" 2>/dev/null; then
            rl_die "ledger holds an unresolved credential/privacy veto but state is ACTIVE (corrupted) — write VETOED into $RL_DIR/state then override, or rm -rf $RL_DIR" 1
        fi
        [ -n "$reviewer" ] || rl_die "record needs --reviewer <id>" 2
        [ -n "$verdict" ] || rl_die "record needs --verdict <V>" 2
        [ ${#files[@]} -ge 1 ] || rl_die "record needs the content file(s) under review" 2
        # Boundary: reviewer and ground must be single tokens (no whitespace/newline/control).
        # A newline payload could split rl_append_round output into multiple ledger lines,
        # forging rounds that rl_convergence_streak would count (defeats Spec B+C).
        case "$reviewer" in
            *[[:space:]]*) rl_die "reviewer/ground must be a single token (no whitespace)" 2 ;;
        esac
        case "$ground" in
            *[[:space:]]*) rl_die "reviewer/ground must be a single token (no whitespace)" 2 ;;
        esac
        # Validate --max-rounds is a positive integer at parse time (not at cap check time).
        # maxr=0 would cap on the very first record; negative/non-integer are nonsensical.
        case "$maxr" in
            ''|*[!0-9]*) rl_die "--max-rounds must be a positive integer" 2 ;;
        esac
        [ "$maxr" -ge 1 ] || rl_die "--max-rounds must be a positive integer" 2
        # --findings given ⇒ it must be a readable regular file. A missing/unreadable
        # path used to fall through `[ -s ]` and be recorded as "no findings".
        [ -z "$findings" ] || { [ -f "$findings" ] && [ -r "$findings" ]; } || \
            rl_die "--findings must be a readable file: $findings" 2
        # A round attests the loop's WHOLE start set, never a subset: the hash may
        # change between rounds (fixes), the file set may not. Compared as sorted
        # sets of the literal paths given to `start`.
        exp=$(sed -n 's/^file=//p' "$RL_DIR/meta" 2>/dev/null)
        [ -n "$exp" ] || rl_die "meta has no start set (unreadable, or loop started by an older review-loop) — finalize --cap and start again" 1
        got=$(printf '%s\n' "${files[@]}" | LC_ALL=C sort -u)
        if [ "$got" != "$exp" ]; then
            printf '❌ content set differs from the loop start set — a round must cover the whole set (finalize --cap and start a new loop to change it)\n   start:  %s\n   record: %s\n' \
                "$(printf '%s' "$exp" | tr '\n' ' ')" "$(printf '%s' "$got" | tr '\n' ' ')" >&2
            exit 2
        fi
        ch=$(rl_content_hash "${files[@]}") || rl_die "content hash failed" 1
        # C: distrust self-report — effective verdict may be downgraded to ERROR
        eff=$(rl_validate_round "$ch" "$verdict" "$findings")
        # rl_round_count guarantees a single integer line (bd03d14); no strip needed.
        n=$(rl_round_count "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        n=$((n + 1))
        ts=$(date "+%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/')
        fc=0; [ -n "$findings" ] && [ -s "$findings" ] && fc=$(grep -c '' "$findings")
        # Keep the findings copy BEFORE the ledger line: a round must never exist
        # in the ledger without the evidence it cites.
        if [ -n "$findings" ] && [ -s "$findings" ]; then
            cp "$findings" "$RL_DIR/round-$n.findings" || rl_die "cannot keep findings copy in $RL_DIR" 1
        fi
        rl_append_round "$RL_DIR/ledger.tsv" "$n" "$reviewer" "$ch" "$eff" "$ground" "$ts" "$fc" || {
            rm -f "$RL_DIR/round-$n.findings"
            rl_die "ledger append failed: $RL_DIR/ledger.tsv" 1
        }
        s=$(rl_convergence_streak "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        # E: credential/privacy veto — machinery hard-stops, escalate to Boss
        if rl_is_credential_privacy_veto "$eff" "$ground"; then
            set_state VETOED
            echo "🛑 credential/privacy VETO (reviewer=$reviewer). Machinery cannot override." >&2
            echo "   Escalated to Boss. To lift: review-loop.sh override --reason <text> (Boss only)." >&2
            exit 3
        fi
        if rl_is_converged "$RL_DIR/ledger.tsv"; then
            set_state CONVERGED
            echo "✅ converged: 3 consecutive PASS (round $n, streak=$s)"
            exit 0
        fi
        if [ "$n" -ge "$maxr" ]; then
            set_state CAPPED
            echo "🛑 iteration cap reached ($n ≥ $maxr) without convergence. Escalated to Boss (no auto-continue — Decision 0009/0010)." >&2
            exit 3
        fi
        echo "recorded round=$n verdict=$eff streak=$s"
        ;;

    finalize)
        devlog=""; cap=0
        while [ $# -gt 0 ]; do
            case "$1" in
                --devlog) need_val "$@"; devlog="$2"; shift 2 ;;
                --cap) cap=1; shift ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) rl_die "unexpected arg: $1" 2 ;;
            esac
        done
        rl_load_loop
        # Count before any state flip: an unreadable ledger must not leave the loop CAPPED.
        n=$(rl_round_count "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        if [ "$st" = "ACTIVE" ]; then
            [ "$cap" = "1" ] || rl_die "loop still ACTIVE (not converged) — pass --cap to force-close + escalate" 1
            set_state CAPPED; st="CAPPED"
        fi
        reason=""
        [ "$st" = "VETOED" ] && reason=" reason=credential/privacy-veto-unresolved"
        [ "$st" = "CAPPED" ] && reason=" reason=iteration-cap-no-convergence"
        line="[review-loop] verdict=$st rounds=$n$reason"
        printf '%s\n' "$line" > "$RL_DIR/outcome.txt" || rl_die "cannot write $RL_DIR/outcome.txt" 1
        echo "$line"
        if [ -n "$devlog" ]; then
            [ -f "$devlog" ] || rl_die "devlog not found: $devlog" 1
            # The only durable trace of the loop: a failed append must not be reported as done.
            printf '> %s\n' "$line" >> "$devlog" || rl_die "cannot append to devlog: $devlog" 1
            echo "↳ appended to $devlog"
        fi
        echo "ℹ ephemeral ledger kept at $RL_DIR until you 'rm -rf' it; only this line is durable (ADR-0003)."
        # Exit code signals machinery: 0 = resolved (CONVERGED or Boss-overridden),
        # 3 = escalation still live (VETOED or CAPPED) — callers gate on this code
        # (ADR-0006: machinery must never let a veto pass silently).
        case "$st" in
            CONVERGED|OVERRIDDEN) exit 0 ;;
            *) exit 3 ;;
        esac
        ;;

    override)
        reason=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --reason) need_val "$@"; reason="$2"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) rl_die "unexpected arg: $1" 2 ;;
            esac
        done
        rl_load_loop
        [ "$st" = "VETOED" ] || rl_die "override valid only on a VETOED loop (state=$st)" 2
        [ -n "$reason" ] || rl_die "override needs --reason <text> — Boss override must be explicit + recorded (ADR-0006)" 2
        # Boundary: --reason must be single-line (no newline/CR) — a newline payload
        # would write a multi-line outcome.txt and bleed a forged verdict line into the
        # durable evidence ADR-0006 guarantees (same injection class as C1 for record).
        case "$reason" in
            *$'\n'*|*$'\r'*) rl_die "--reason must be single-line (no newline/CR) — durable evidence integrity (ADR-0006)" 2 ;;
        esac
        n=$(rl_round_count "$RL_DIR/ledger.tsv") || rl_die "ledger unreadable: $RL_DIR/ledger.tsv" 1
        line="[review-loop] verdict=OVERRIDDEN rounds=$n Boss-override reason=$reason"
        printf '%s\n' "$line" > "$RL_DIR/outcome.txt" || rl_die "cannot write $RL_DIR/outcome.txt" 1
        set_state OVERRIDDEN
        echo "⚠ credential/privacy veto OVERRIDDEN by explicit Boss action. Recorded:"
        echo "  $line"
        echo "ℹ fold this line into the ${HX_LOGS_DIR}/ Dev Log outcome — it is durable evidence (ADR-0006)."
        ;;

    *) rl_die "not yet implemented: $cmd" 2 ;;
esac
