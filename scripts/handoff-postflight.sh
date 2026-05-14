#!/bin/bash
# handoff-postflight.sh — v2.1.0 UX #3: aggregator for all post-handoff
# verification checks. Replaces the friction of running 5 scripts separately
# and reading 5 exit codes — runs them in sequence, prints ✅/❌ per check,
# exits with the worst of the 5.
#
# usage: handoff-postflight.sh [--quiet] [file]   (default: ./HANDOFF.md)
# exit:  0 all clean / 1 any check failed / 2 file not found or usage error
#
# Five checks in order:
#   1. scan-credentials      — block plaintext API keys / tokens / passwords
#                              (runs against project dir, not just HANDOFF.md,
#                              so it catches residue in Handoff_Logs/ etc.)
#   2. validate-handoff      — structure + recall-readiness invariants
#   3. handoff-lint          — per-file frontmatter + body field invariants (v2)
#   4. rotation-reminder     — credential rotation warnings
#   5. archive-devlog        — auto-archive when Dev Log > 50

set -u

QUIET=0
FILE=""
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            cat <<'EOF'
Usage: handoff-postflight.sh [--quiet] [file]   (default file: ./HANDOFF.md)

Aggregates the 5 post-handoff verification checks into a single command
with a unified PASS/FAIL summary. Equivalent to running these in sequence:

  1. scan-credentials      — block plaintext credentials in project tree
  2. validate-handoff      — section structure + recall-readiness
  3. handoff-lint          — per-file frontmatter + body fields (v2)
  4. rotation-reminder     — credential rotation warnings
  5. archive-devlog        — auto-archive when Dev Log > 50 entries

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
FILE="${FILE:-HANDOFF.md}"

if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "$FILE")" && pwd)"

# Track failures across checks. Names are space-separated for the summary;
# avoids requiring bash 4+ arrays.
fail_count=0
fail_list=""

# Run a single check via the args passed (no eval — safer + clearer).
# Captures stdout+stderr to a tempfile so quiet mode can drop it cleanly
# and verbose mode can indent it under the step header.
run_check() {
    local n="$1" name="$2"
    shift 2
    local out_file ec=0
    out_file=$(mktemp)
    [ "$QUIET" = "0" ] && echo "→ ${n}. ${name}"
    "$@" >"$out_file" 2>&1 || ec=$?
    if [ "$ec" = "0" ]; then
        [ "$QUIET" = "0" ] && echo "   ✅"
    else
        if [ "$QUIET" = "0" ]; then
            echo "   ❌ exit=$ec"
            # Indent the failing tool's output for readability
            [ -s "$out_file" ] && sed 's/^/   /' "$out_file"
        fi
        fail_count=$((fail_count + 1))
        fail_list="$fail_list $name"
    fi
    rm -f "$out_file"
}

run_check 1 "scan-credentials"  bash "$SCRIPT_DIR/scan-credentials.sh"  "$ROOT_DIR"
run_check 2 "validate-handoff"  bash "$SCRIPT_DIR/validate-handoff.sh"  --readiness "$FILE"
run_check 3 "handoff-lint"      bash "$SCRIPT_DIR/handoff-lint.sh"      "$FILE"
run_check 4 "rotation-reminder" bash "$SCRIPT_DIR/rotation-reminder.sh" "$FILE"
run_check 5 "archive-devlog"    bash "$SCRIPT_DIR/archive-devlog.sh"    "$FILE"

[ "$QUIET" = "0" ] && echo

if [ "$fail_count" = "0" ]; then
    echo "✅ postflight: all 5 checks passed"
    exit 0
else
    echo "❌ postflight: $fail_count of 5 checks failed:$fail_list"
    exit 1
fi
