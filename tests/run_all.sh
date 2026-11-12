#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
# tests/.tmp is per-run scratch (common.sh TMP_DIR). Older suites write
# <name>_$$.md there and never remove it; left alone it grew to ~10k files
# and slowed anything that copies tests/. Sweep at the start of every run.
rm -rf "${ROOT:?}/.tmp"
FAIL=0
for t in "$ROOT"/test_*.sh; do
    echo ""
    echo "🧪 $(basename "$t")"
    bash "$t" || FAIL=$((FAIL+1))
done
echo ""
echo "════════════"
[ "$FAIL" = "0" ] && echo "All suites passed ✅" || { echo "Failing suites: $FAIL ❌"; exit 1; }
