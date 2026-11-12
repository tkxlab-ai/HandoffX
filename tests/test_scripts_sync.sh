#!/bin/bash
# test_scripts_sync.sh — meta-test: scripts/ (dev) and skills/handoffx/scripts/
# (bundle) must always contain the same files with the same content.
# Prevents the class of bug where a new script is added to one side only.
source "$(dirname "$0")/common.sh"

DEV="$ROOT_DIR/scripts"
BUNDLE="$ROOT_DIR/skills/handoffx/scripts"

assert_file_exists "dev scripts/ exists"    "$DEV/validate-handoff.sh"
assert_file_exists "bundle scripts/ exists" "$BUNDLE/validate-handoff.sh"

# Dev-only scripts: 仅在 dev side 维护，不进 .skill bundle（端用户不需要）
# - publish-github*.sh: GitHub 发版工具（Decision 0018），项目维护者用，非 /handoffx 用户
# - release-sanitize-public.sh: publish 流程脱敏（Decision 0018），同上
# - review-loop.sh / review-ledger.sh 已移至 tools/（维护者专用 code-review 循环，
#   ADR-0003 ⑦）：gitx 双源闸只容忍 scripts/ 下根级 release-*，故不再列于此
DEV_ONLY='release-publish-github.sh release-publish-github-backfill.sh release-sanitize-public.sh release-layout.sh'

# 列表必须完全一致（同名同数）；dev 侧排除 DEV_ONLY 后比对
dev_list=$(ls "$DEV" 2>/dev/null | grep -vxF -f <(printf '%s\n' $DEV_ONLY) | sort | tr '\n' ' ')
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

# 每个同名文件的内容必须字节级相等（dev 排除 DEV_ONLY 后 diff bundle）
DEV_EXCLUDES=()
for f in $DEV_ONLY; do DEV_EXCLUDES+=(--exclude="$f"); done
diff_out=$(diff -q -r "${DEV_EXCLUDES[@]}" "$DEV" "$BUNDLE" 2>&1 || true)
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
