#!/bin/bash
# test_doc_freshness_k4_chicken_egg.sh — Gotcha #14 (K4 chicken-egg) regression
#
# Why: release pipeline first bumps root VERSION + doc references to v-next, then
# stages docs into Release/handoffx-v-next/ tarball, only finally flips Release/latest
# symlink. If `test_doc_freshness.sh` sources its truth from `Release/latest`,
# any doc reference to v-next fails the gate while latest still points to v-prev,
# forcing the K4 workaround (revert docs → release → re-bump) that poisons the tarball.
#
# Contract: `test_doc_freshness.sh` MUST source the project version from
# root `VERSION` file, not from `Release/latest`. This test repoints Release/latest
# to a bogus stale value and asserts the doc-freshness gate still passes.
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

RELEASE_DIR="$ROOT_DIR/Release"
LATEST_LINK="$RELEASE_DIR/latest"
POISON="handoffx-v0.0.1-stale"
ORIGINAL_TARGET=""
CREATED_LINK=0
CREATED_DIR=0

# Fail closed without guessing at Release/latest (Gotcha #24 / #27).
refuse() {
    echo "  ❌ $1"
    [ -n "${2:-}" ] && echo "     $2"
    FAIL=$((FAIL+1))
    summary
    exit 1
}

if [ -L "$LATEST_LINK" ]; then
    ORIGINAL_TARGET=$(readlink "$LATEST_LINK")
    # A previous run killed before its EXIT trap (SIGKILL) leaves the poison in
    # place. Treating it as the "original" would write it back on every run and
    # make test_release_artifact_content skip forever (Gotcha #27 / #24). The true
    # original is unknowable here, so refuse instead of guessing.
    [ "$ORIGINAL_TARGET" != "$POISON" ] || refuse \
        "Release/latest 已指向上次中断运行留下的毒值 ${POISON}，真实原值无从得知" \
        "手工修复：ln -sfn handoffx-<已发布版本> ${LATEST_LINK}（指回最近一次真实发布目录；若此前本无 latest，rm 它即可）后重跑"
elif [ -e "$LATEST_LINK" ]; then
    # `ln -sfn <name> <real-dir>` creates a dangling link *inside* the directory
    # instead of replacing it; nothing here could restore that.
    refuse "Release/latest 存在但不是 symlink，本测试只对 symlink 做毒值替换"
else
    # fresh-clone / CI case — Release/ is gitignored, so the dir and the link may
    # both be absent. Create what is missing (removed on cleanup); otherwise `ln`
    # fails and the gate runs against no stale link at all — a vacuous ✅.
    CREATED_LINK=1
    if [ ! -d "$RELEASE_DIR" ]; then
        mkdir "$RELEASE_DIR" || refuse "无法创建 ${RELEASE_DIR}，毒值替换的前置条件不成立"
        CREATED_DIR=1
    fi
fi

# Restore, then assert the target state: an unchecked `ln`/`rm` would report a
# clean restore while leaving the poison behind (Gotcha #27).
restore_latest() {
    if [ "$CREATED_LINK" -eq 1 ]; then
        rm -f "$LATEST_LINK"
        [ "$CREATED_DIR" -eq 1 ] && rmdir "$RELEASE_DIR"
        [ ! -e "$LATEST_LINK" ] && [ ! -L "$LATEST_LINK" ] && \
            { [ "$CREATED_DIR" -eq 0 ] || [ ! -e "$RELEASE_DIR" ]; }
    else
        # keyed on CREATED_LINK, not on ORIGINAL_TARGET being non-empty: an
        # empty-target symlink is a real original and must be put back too.
        ln -sfn "$ORIGINAL_TARGET" "$LATEST_LINK"
        [ "$(readlink "$LATEST_LINK")" = "$ORIGINAL_TARGET" ]
    fi
}
# trap EXIT 涵盖 normal exit + INT/TERM/HUP（bash 3.2 与 5 实测均 fire）。
# **SIGKILL (-9) 例外**：trap 不 fire，Release/latest 留在毒值；该残留由下一次
# 运行开头的毒值检查 fail-closed 拦住，不会被当作原值永久化。若需彻底根除
# 残留，把整段移到 mktemp -d 副本里跑。
trap restore_latest EXIT

# Repoint Release/latest to the poison and verify it took: a failed `ln` would
# run the gate against the real latest and still print "K4 fixed".
ln -sfn "$POISON" "$LATEST_LINK"
[ "$(readlink "$LATEST_LINK" 2>/dev/null)" = "$POISON" ] || \
    refuse "无法把 Release/latest 指向毒值（Release/ 不可写？），K4 无法验证"

# Run the doc-freshness gate as subprocess. With Release/latest stale, the gate
# must still PASS because version truth is sourced from root VERSION.
output=$(bash "$ROOT_DIR/tests/test_doc_freshness.sh" 2>&1)
ec=$?

if ! restore_latest; then
    echo "  ❌ Release/latest 还原失败：现在是 $(readlink "$LATEST_LINK" 2>/dev/null || echo '<absent>')，预期 ${ORIGINAL_TARGET:-<absent>}"
    [ "$CREATED_DIR" -eq 1 ] && [ -e "$RELEASE_DIR" ] && echo "     本测试自建的 ${RELEASE_DIR} 未能删除（非空？）"
    FAIL=$((FAIL+1))
fi
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
