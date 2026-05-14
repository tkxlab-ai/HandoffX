#!/bin/bash
# test_scripts_sync.sh — meta-test: scripts/ (dev) and skills/handoff/scripts/
# (bundle) must always contain the same files with the same content.
# Prevents the class of bug where a new script is added to one side only.
source "$(dirname "$0")/common.sh"

DEV="$ROOT_DIR/scripts"
BUNDLE="$ROOT_DIR/skills/handoff/scripts"

assert_file_exists "dev scripts/ exists"    "$DEV/validate-handoff.sh"
assert_file_exists "bundle scripts/ exists" "$BUNDLE/validate-handoff.sh"

# 列表必须完全一致（同名同数）
dev_list=$(ls "$DEV" 2>/dev/null | sort | tr '\n' ' ')
bundle_list=$(ls "$BUNDLE" 2>/dev/null | sort | tr '\n' ' ')

if [ "$dev_list" = "$bundle_list" ]; then
    echo "  ✅ script filename sets are identical"
    PASS=$((PASS+1))
else
    echo "  ❌ dev vs bundle script filenames diverge:"
    echo "    dev:    $dev_list"
    echo "    bundle: $bundle_list"
    FAIL=$((FAIL+1))
fi

# 每个同名文件的内容必须字节级相等（diff -q -r 空输出 = 相等）
diff_out=$(diff -q -r "$DEV" "$BUNDLE" 2>&1 || true)
if [ -z "$diff_out" ]; then
    echo "  ✅ all scripts have identical content between dev and bundle"
    PASS=$((PASS+1))
else
    echo "  ❌ dev / bundle content mismatch:"
    echo "$diff_out" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

# 所有 .sh 必须可执行（install.sh chmod +x 前置假设）
for f in "$BUNDLE"/*.sh; do
    [ -x "$f" ] \
        && { echo "  ✅ executable: $(basename "$f")"; PASS=$((PASS+1)); } \
        || { echo "  ❌ not executable: $(basename "$f")"; FAIL=$((FAIL+1)); }
done

summary
