#!/bin/bash
# handoff-postflight.sh — v2.2.0 parallel orchestration: read-only checks run
# concurrently; archive-devlog runs serially after (it mv-s files → no race).
# Wall-clock ≈ max(single check) ≈ 3-4s, down from ~8.7s serial sum.
#
# usage: handoff-postflight.sh [--quiet] [file]   (default: ./$HX_MAIN_FILE)
# exit:  0 all clean / 1 any check failed / 2 file not found or usage error
#
# Checks, numbered in execution order (v4.1.1: the replay used to print
# 1 2 3 4 6 5 because xref-lint was numbered after archive-devlog although it
# runs in the parallel batch before it):
#   1. scan-credentials      — block plaintext API keys / tokens / passwords
#   2. validate-handoff      — structure + recall-readiness invariants
#   3. handoff-lint          — per-file frontmatter + body field invariants (v2)
#   4. rotation-reminder     — credential rotation warnings
#   5. handoff-xref-lint     — only with --files= (B①); parallel with 1-4
#   6. archive-devlog        — v2: yearly archive of $HX_LOGS_DIR/ (v1: >50 entries); serial殿后

set -u

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "$0")/lib/handoff-schema.sh"

QUIET=0
FILE=""
FILES_CSV=""
FILES_CSV_SET=0
for arg in "$@"; do
    case "$arg" in
        --files=*)
            FILES_CSV="${arg#--files=}"
            FILES_CSV_SET=1
            ;;
        -h|--help)
            # Heredoc body unquoted (<<EOF, not <<'EOF') so $HX_MAIN_FILE
            # expands — the help text follows P2.2 rename, no split-brain
            # with the runtime FILE default (L67 `${FILE:-$HX_MAIN_FILE}`).
            # Body has zero other shell metachars (`$`, backticks, `\`) so
            # unquoting is a no-op for everything else (Tacit#4 Why: prove
            # safe before relaxing quotes — verified line-by-line).
            cat <<EOF
Usage: handoff-postflight.sh [--quiet] [--files=a.md,b.md] [file]   (default file: ./$HX_MAIN_FILE)
       --files=  this write's file set → runs check 5, handoff-xref-lint (B①), on exactly those files

Aggregates the post-handoffx verification checks into a single command
with a unified PASS/FAIL summary. Equivalent to running these in sequence:

  1. scan-credentials      — block plaintext credentials in project tree
  2. validate-handoff      — section structure + recall-readiness
  3. handoff-lint          — per-file frontmatter + body fields (v2)
  4. rotation-reminder     — credential rotation warnings
  5. handoff-xref-lint     — only with --files= (B①)
  6. archive-devlog        — v2: yearly archive of $HX_LOGS_DIR/ (v1: >50 entries)

Options:
  --quiet    suppress per-check output AND failing-tool detail; only the
             summary line is printed. Re-run without --quiet to diagnose.
  -h, --help show this help

Exit: 0 all clean / 1 any check failed / 2 file not found or usage error
EOF
            exit 0
            ;;
        --quiet|-q)
            QUIET=1
            ;;
        -*)
            echo "❌ unknown flag: $arg" >&2
            echo "   Run $0 --help for usage." >&2
            exit 2
            ;;
        *)
            [ -z "$FILE" ] && FILE="$arg"
            ;;
    esac
done
FILE="${FILE:-$HX_MAIN_FILE}"

# Legacy-layout gate (P2.4 design §4b-4) — same rule as tidy-handoff.sh. Why:
# five checks against a missing new main (or against a legacy main whose
# sibling dirs the checks no longer look for) would report noise or a false
# pass; name the exact upgrade command and exit 2 before running any check.
# Scoped to main-file basenames so ad-hoc files are never judged by siblings.
_lg_root="$(dirname "$FILE")"; _lg_base="$(basename "$FILE")"
if [ "$_lg_base" = "$HX_MAIN_FILE" ] || [ "$_lg_base" = "$HX_LEGACY_MAIN_FILE" ]; then
    # An explicit v1 single file is left to this tool's own v1 path; every
    # other legacy shape is refused with the command that upgrades it.
    if ! { [ -e "$FILE" ] && [ "$(hx_legacy_layout_kind "$_lg_root")" = "v1" ]; }; then
        hx_refuse_if_legacy_layout "$_lg_root" "handoff-postflight.sh" || exit 2
    fi
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    exit 2
fi

# F2: caller-input validation — before any temp infra; fast-fail, no wait needed
if [ "${FILES_CSV_SET:-0}" = "1" ] && [ -z "$FILES_CSV" ]; then
    echo "❌ postflight: --files= given but empty (broken write-target set)" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "$FILE")" && pwd)"

PF_TMP=$(mktemp -d) || { echo "❌ postflight: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$PF_TMP"' EXIT

# PARALLEL-ORCHESTRATION: rc/out 落 $PF_TMP，不即删，供 wait 后回放+聚合
run_check() {
    local n="$1" name="$2"
    shift 2
    local ec=0
    "$@" >"$PF_TMP/$n.out" 2>&1 || ec=$?
    echo "$ec" > "$PF_TMP/$n.rc"
    echo "$name" > "$PF_TMP/$n.name"
}

# 只读 check 后台并行（1 scan-credentials / 2 validate / 3 lint / 4 rotation）
run_check 1 "scan-credentials"  bash "$SCRIPT_DIR/scan-credentials.sh"  "$ROOT_DIR" &
run_check 2 "validate-handoff"  bash "$SCRIPT_DIR/validate-handoff.sh"  --readiness "$FILE" &
run_check 3 "handoff-lint"      bash "$SCRIPT_DIR/handoff-lint.sh"      "$FILE" &
run_check 4 "rotation-reminder" bash "$SCRIPT_DIR/rotation-reminder.sh" "$FILE" &

# B① xref-lint（只读 lint，可并行）
if [ -n "${FILES_CSV:-}" ]; then
    # Split CSV without touching IFS: tr replaces commas with newlines,
    # read loop builds positional params one token at a time (bash 3.2 safe).
    # A relative entry is relative to the project root (the main file's dir),
    # not the cwd: SKILL.md's own example passes relative paths, and from any
    # other cwd every target was reported missing. Absolute entries stay as-is.
    (
        set --
        while read -r _f; do
            [ -n "$_f" ] || continue
            case "$_f" in /*) ;; *) _f="$ROOT_DIR/$_f" ;; esac
            set -- "$@" "$_f"
        done <<_SPLIT
$(printf '%s\n' "$FILES_CSV" | tr ',' '\n')
_SPLIT
        run_check 5 "xref-lint(B①)" bash "$SCRIPT_DIR/handoff-xref-lint.sh" "$@"
    ) &
fi

wait   # 墙钟 = max(单只读 check)，非 sum

# archive-devlog 串行殿后：它 mv Dev Log 文件，与只读 check 读同目录会 race
# 传 $FILE（尊重显式选中的文件）：archive-devlog 对带 v2 marker 的文件自己分派
# 到兄弟 Logs 目录按年归档并刷新指针；v1 文件走 >50 条计数。此前它对 v2
# 永远 no-op（2026-10-29 发现写入流程文档承诺的步骤 5 从未触发）。
run_check 6 "archive-devlog"    bash "$SCRIPT_DIR/archive-devlog.sh"    "$FILE"

[ "$QUIET" = "0" ] && echo

fail_count=0
fail_list=""
# 固定顺序回放 + 聚合。rc 文件缺失 = worker 半死 → 当失败，绝不默认 pass
for n in 1 2 3 4 5 6; do
    if [ "$n" = "5" ] && [ -z "${FILES_CSV:-}" ] && [ ! -f "$PF_TMP/$n.rc" ]; then
        continue
    fi
    if [ ! -f "$PF_TMP/$n.rc" ]; then
        fail_count=$((fail_count + 1)); fail_list="$fail_list check#$n(no-rc)"; continue
    fi
    nm=$(cat "$PF_TMP/$n.name" 2>/dev/null || echo "check#$n")
    rc=$(cat "$PF_TMP/$n.rc")
    if [ "$QUIET" = "0" ]; then
        echo "→ ${n}. ${nm}"
        if [ "$rc" = "0" ]; then echo "   ✅"
        else echo "   ❌ exit=$rc"; [ -s "$PF_TMP/$n.out" ] && sed 's/^/   /' "$PF_TMP/$n.out"; fi
    fi
    [ "$rc" = "0" ] || { fail_count=$((fail_count + 1)); fail_list="$fail_list $nm"; }
done

rm -rf "$PF_TMP"; trap - EXIT

if [ "$fail_count" = "0" ]; then
    echo "✅ postflight: all checks passed"
    exit 0
else
    echo "❌ postflight: $fail_count check(s) failed:$fail_list"
    exit 1
fi
