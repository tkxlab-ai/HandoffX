#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
# tests/.tmp is per-run scratch (common.sh TMP_DIR). Older suites write
# <name>_$$.md there and never remove it; left alone it grew to ~10k files
# and slowed anything that copies tests/. Sweep at the start of every run.
rm -rf "${ROOT:?}/.tmp"
FAIL=0
SKIP=0
# Each suite's output is teed to a scratch copy so its ➖ lines can be counted:
# a green summary that hides a skipped gate is how a gate silently stops
# running. The count is printed for the human / controller to compare with the
# expected skip set of the distribution contract — this script does NOT gate on
# it (the exit status reflects failing suites only).
OUT=$(mktemp "${TMPDIR:-/tmp}/run_all.XXXXXX") || exit 2
trap 'rm -f "$OUT"' EXIT
for t in "$ROOT"/test_*.sh; do
    echo ""
    echo "🧪 $(basename "$t")"
    bash "$t" 2>&1 | tee "$OUT"
    [ "${PIPESTATUS[0]}" = "0" ] || FAIL=$((FAIL+1))
    n=$(grep -c '^[[:space:]]*➖' "$OUT")
    # An unreadable capture must not read as "no skips" (Gotcha #24).
    case "$n" in ''|*[!0-9]*) echo "❌ run_all: cannot count ➖ lines of $(basename "$t")"; FAIL=$((FAIL+1)); n=0 ;; esac
    SKIP=$((SKIP + n))
done
echo ""
echo "════════════"
[ "$FAIL" = "0" ] && echo "All suites passed ✅ (skipped: $SKIP)" || { echo "Failing suites: $FAIL ❌ (skipped: $SKIP)"; exit 1; }
