#!/bin/bash
# review-ledger.sh — P0 review-loop primitives (A/B/C/E). Sourced, not executed.
# A: content-hash + two-tier ledger (ADR-0003). B: 3-consecutive-PASS convergence
# (CONTEXT.md "Converged"). C: orchestrator validation (CONTEXT.md). E: credential/
# privacy veto detection (ADR-0006). NO git in any predicate (§1 git-orthogonal).
# Pure functions only — escalation policy + scratch I/O live in review-loop.sh.

# idempotent source guard
[ -n "${_RL_LEDGER_SOURCED:-}" ] && return 0
_RL_LEDGER_SOURCED=1

# A: sha256 of the SORTED concatenation of explicitly-passed file contents.
# Truth = the explicit file list (same discipline as ADR-0004 write-target set),
# NEVER a git rev — keeps §1 intact. Cross-platform: sha256sum ‖ shasum -a 256.
_rl_sha256() {
    local d
    if command -v sha256sum >/dev/null 2>&1; then d=$(sha256sum | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then d=$(shasum -a 256 | awk '{print $1}')
    else echo "review-ledger: no sha256 tool (need sha256sum or shasum)" >&2; return 2; fi
    # The pipeline's status is awk's, so a failing/garbled digest tool is only
    # visible in its output: accept exactly 64 hex chars, otherwise fail (2).
    case "$d" in *[!0-9a-f]*|'') d="" ;; esac
    [ "${#d}" -eq 64 ] || { echo "review-ledger: sha256 tool produced no digest" >&2; return 2; }
    printf '%s\n' "$d"
}

rl_content_hash() {
    [ $# -ge 1 ] || { echo "review-ledger: rl_content_hash needs >=1 file" >&2; return 2; }
    local f h manifest
    for f in "$@"; do
        case "$f" in *$'\n'*) echo "review-ledger: content path contains newline: $f" >&2; return 2 ;; esac
        [ -e "$f" ] || { echo "review-ledger: content file missing: $f" >&2; return 2; }
        [ -f "$f" ] || { echo "review-ledger: content path is not a regular file: $f" >&2; return 2; }
        [ -r "$f" ] || { echo "review-ledger: content file unreadable: $f" >&2; return 2; }
    done
    # One "<sha256> <path>" line per file, sorted as a set, digested again. The
    # per-file digest keeps the file boundary and the path inside the hash, so
    # moving a line between files or renaming one is a content change. A read
    # failure aborts (2) instead of hashing whatever the other files held.
    manifest=$(for f in "$@"; do
        h=$(_rl_sha256 < "$f") || exit 2
        printf '%s %s\n' "$h" "$f"
    done) || return 2
    printf '%s\n' "$manifest" | LC_ALL=C sort -u | _rl_sha256
}

# A durable-tier helpers. Ledger line is flat & grep-decidable (no `|` — Gotcha #2).
rl_append_round() {
    # args: ledger round reviewer content_hash verdict ground ts findings_count
    [ $# -eq 8 ] || { echo "review-ledger: rl_append_round needs 8 args" >&2; return 2; }
    # Defensive: reject any arg containing a newline — one forged newline can split
    # a single append into two lines, letting parsers (rl_convergence_streak,
    # rl_round_count) count a fabricated record.  The single-line-per-round
    # invariant must hold at the writer; callers must sanitize before calling.
    local _a
    for _a in "$2" "$3" "$4" "$5" "$6" "$7" "$8"; do
        case "$_a" in
            *$'\n'*) echo "review-ledger: rl_append_round arg contains newline" >&2; return 2 ;;
        esac
    done
    printf 'round=%s reviewer=%s content_hash=%s verdict=%s ground=%s ts=%s findings=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$1"
}

# A ledger that is absent reads as 0 rounds; one that exists but is not a readable
# regular file is an error (2, nothing on stdout) — a silent 0 here would feed the
# iteration cap and finalize's durable "rounds=N" line.
_rl_ledger_readable() {
    [ -e "$1" ] || return 1
    { [ -f "$1" ] && [ -r "$1" ]; } && return 0
    echo "review-ledger: ledger unreadable: $1" >&2; return 2
}

rl_round_count() {
    _rl_ledger_readable "$1"; case $? in 1) echo 0; return 0 ;; 2) return 2 ;; esac
    local c
    # grep -c: 0 = matches, 1 = none (prints 0); anything else is a read error, not "0 rounds".
    c=$(grep -c '^round=' "$1" 2>/dev/null); case $? in 0|1) ;; *) echo "review-ledger: ledger read failed: $1" >&2; return 2 ;; esac
    echo "${c:-0}"
}

# B: streak of trailing consecutive PASS on the SAME content_hash (CONTEXT.md
# "Round keyed by content_hash" + "Converged"). A PASS on a NEW content_hash
# starts a fresh streak of 1 — it does not extend the previous streak, because
# the previous content was never attested by this pass. Any non-PASS resets to 0.
rl_convergence_streak() {
    local led="$1" streak=0 shash="" v h line
    _rl_ledger_readable "$led"; case $? in 1) echo 0; return 0 ;; 2) return 2 ;; esac
    while IFS= read -r line; do
        case "$line" in round=*) ;; *) continue ;; esac
        v=$(printf '%s\n' "$line" | sed -n 's/.*content_hash=\([^ ]*\) verdict=.*/\1/p')
        h="$v"
        v=$(printf '%s\n' "$line" | sed -n 's/.* verdict=\([A-Z_-]*\) ground=.*/\1/p')
        if [ "$v" = "PASS" ]; then
            if [ "$streak" -eq 0 ]; then
                streak=1; shash="$h"
            elif [ "$h" = "$shash" ]; then
                streak=$((streak + 1))
            else
                # PASS but content changed — fresh 1-streak on the new content
                streak=1; shash="$h"
            fi
        else
            streak=0; shash=""
        fi
    done < "$led"
    echo "$streak"
}

rl_is_converged() { local s; s=$(rl_convergence_streak "$1") || return 2; [ "$s" -ge 3 ]; }

# C: orchestrator does not trust self-report. Returns effective verdict:
# the claimed verdict, or ERROR if the round is unvalidatable. Never silently
# drops — the caller records whatever this returns (CONTEXT.md).
rl_validate_round() {
    # args: content_hash claimed_verdict findings_file
    local ch="$1" v="$2" ff="$3"
    if [ -z "$ch" ] || [ "$ch" = "-" ]; then echo "ERROR"; return 0; fi
    case "$v" in
        PASS|WARN|BLOCKED|USER_DECISION|ERROR|N-A) ;;
        *) echo "ERROR"; return 0 ;;
    esac
    if [ -n "$ff" ]; then
        # A findings path that is not a readable regular file is unvalidatable —
        # ERROR, never "no findings".
        { [ -f "$ff" ] && [ -r "$ff" ]; } || { echo "ERROR"; return 0; }
    fi
    if [ -n "$ff" ] && [ -s "$ff" ]; then
        # Reviewers separate findings with blank lines; ignore empty/whitespace-only
        # lines before the conformance check, otherwise a blank separator downgrades
        # an honest PASS/WARN to ERROR.  A non-blank line lacking `path:line ` is
        # still an ERROR (Spec C integrity).
        if grep -vE '^[[:space:]]*$' "$ff" | grep -qvE '^[^:[:space:]]+:[0-9]+ '; then
            echo "ERROR"; return 0
        fi
    fi
    echo "$v"
}

# E: the one-vote veto = BLOCKED raised on credential|privacy grounds (ADR-0006).
# Pure predicate; tier policy (machinery-never / Boss-explicit) is in review-loop.sh.
rl_is_credential_privacy_veto() {
    # args: verdict ground  -> exit 0 iff this is the credential/privacy veto
    [ "$1" = "BLOCKED" ] || return 1
    [ "$2" = "credential" ] || [ "$2" = "privacy" ]
}
