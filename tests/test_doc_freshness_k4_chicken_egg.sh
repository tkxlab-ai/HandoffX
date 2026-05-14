#!/bin/bash
# test_doc_freshness_k4_chicken_egg.sh — Gotcha #14 (K4 chicken-egg) regression
#
# Why: release pipeline first bumps root VERSION + doc references to v-next, then
# stages docs into Release/handoff-v-next/ tarball, only finally flips Release/latest
# symlink. If `test_doc_freshness.sh` sources its truth from `Release/latest`,
# any doc reference to v-next fails the gate while latest still points to v-prev,
# forcing the K4 workaround (revert docs → release → re-bump) that poisons the tarball.
#
# Contract: `test_doc_freshness.sh` MUST source the project version from
# root `VERSION` file, not from `Release/latest`. This test repoints Release/latest
# to a bogus stale value and asserts the doc-freshness gate still passes.
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

LATEST_LINK="$ROOT_DIR/Release/latest"
ORIGINAL_TARGET=""
if [ -L "$LATEST_LINK" ]; then
    ORIGINAL_TARGET=$(readlink "$LATEST_LINK")
fi

restore_latest() {
    if [ -n "$ORIGINAL_TARGET" ]; then
        ln -sfn "$ORIGINAL_TARGET" "$LATEST_LINK"
    fi
}
trap restore_latest EXIT

# Repoint Release/latest to a bogus stale value.
ln -sfn "handoff-v0.0.1-stale" "$LATEST_LINK"

# Run the doc-freshness gate as subprocess. With Release/latest stale, the gate
# must still PASS because version truth is sourced from root VERSION.
output=$(bash "$ROOT_DIR/tests/test_doc_freshness.sh" 2>&1)
ec=$?

restore_latest
trap - EXIT

if [ "$ec" -eq 0 ]; then
    echo "  ✅ test_doc_freshness.sh insensitive to stale Release/latest (K4 fixed)"
    PASS=$((PASS+1))
else
    echo "  ❌ test_doc_freshness.sh sensitive to Release/latest → K4 chicken-egg present"
    echo ""
    echo "  ── subprocess output ──"
    echo "$output" | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

summary
