#!/bin/bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
FAIL=0
for t in "$ROOT"/test_*.sh; do
    echo ""
    echo "🧪 $(basename "$t")"
    bash "$t" || FAIL=$((FAIL+1))
done
echo ""
echo "════════════"
[ "$FAIL" = "0" ] && echo "All suites passed ✅" || { echo "Failing suites: $FAIL ❌"; exit 1; }
