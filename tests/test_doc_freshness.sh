#!/bin/bash
# test_doc_freshness.sh — 验证文档中引用的版本号和测试用例数与实际一致
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

DOC_DIR="$ROOT_DIR"

# ── Helper: 从 Release/ 目录取最新版本号 ──
get_latest_release_version() {
    local latest_link="$ROOT_DIR/Release/latest"
    if [ -L "$latest_link" ]; then
        basename "$(readlink "$latest_link")"
    elif [ -d "$latest_link" ]; then
        ls -d "$ROOT_DIR"/Release/v* 2>/dev/null | sort -V | tail -1 | xargs basename
    else
        echo "NONE"
    fi
}

LATEST_VERSION=$(get_latest_release_version)

echo ""
echo "  📊 Latest release: $LATEST_VERSION"
echo ""

# ── Test 1: INSTALL.md 不包含旧测试用例数 "99" ──
INSTALL_CONTENTS=$(cat "$DOC_DIR/INSTALL.md" 2>/dev/null || echo "")
if echo "$INSTALL_CONTENTS" | grep -qE '99 (用例|test|assertion)'; then
    echo "  ❌ INSTALL.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ INSTALL.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 2: README.md 不包含旧测试用例数 "99" ──
README_CONTENTS=$(cat "$DOC_DIR/README.md" 2>/dev/null || echo "")
if echo "$README_CONTENTS" | grep -qE '99 (用例|test|assertion)'; then
    echo "  ❌ README.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 3: TEST-SCENARIOS.md 不包含旧测试用例数 "99" ──
TEST_SCENARIOS_CONTENTS=$(cat "$DOC_DIR/TEST-SCENARIOS.md" 2>/dev/null || echo "")
if echo "$TEST_SCENARIOS_CONTENTS" | grep -qE '99 (用例|test|assertion)'; then
    echo "  ❌ TEST-SCENARIOS.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ TEST-SCENARIOS.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 4: README.md Release/latest 引用与实际一致 ──
README_LATEST_REF=$(echo "$README_CONTENTS" | grep -oE 'latest\s*→\s*(handoff-)?v[0-9]+(\.[0-9]+)*' | head -1 | sed -E 's/.*→[[:space:]]*//')
if [ -n "$README_LATEST_REF" ] && [ "$README_LATEST_REF" != "$LATEST_VERSION" ]; then
    echo "  ❌ README.md Release/latest 引用: $README_LATEST_REF, 实际: $LATEST_VERSION"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md Release/latest 引用与实际一致 ($LATEST_VERSION)"
    PASS=$((PASS+1))
fi

# ── Test 5: HANDOFF.md Current State 版本号与实际一致 ──
HANDOFF_CONTENTS=$(cat "$DOC_DIR/HANDOFF.md" 2>/dev/null || echo "")
HANDOFF_VERSION=$(echo "$HANDOFF_CONTENTS" | grep -oE '当前版本.*(handoff-)?v[0-9]+(\.[0-9]+)*' | grep -oE '(handoff-)?v[0-9]+(\.[0-9]+)*' | head -1)
if [ -n "$HANDOFF_VERSION" ] && [ "$HANDOFF_VERSION" != "$LATEST_VERSION" ]; then
    echo "  ❌ HANDOFF.md Current State 版本: $HANDOFF_VERSION, 实际最新: $LATEST_VERSION"
    FAIL=$((FAIL+1))
else
    echo "  ✅ HANDOFF.md Current State 版本号与实际一致 ($LATEST_VERSION)"
    PASS=$((PASS+1))
fi

# ── Test 6: 安装文档不得用 commands/*.md 通配复制 slash shims ──
# /handoff 由 SKILL.md name 注册；通配复制会重新安装 handoff.md，导致 Claude Code palette 重复。
if grep -RInE 'cp .*commands/\*\.md|cp .*commands/handoff\.md|cp .*commands/.*[[:space:]]handoff\.md' "$DOC_DIR/README.md" "$DOC_DIR/INSTALL.md" >/dev/null 2>&1; then
    echo "  ❌ README/INSTALL 含 commands/*.md 或 handoff.md 通配安装说明"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README/INSTALL 未使用会重复注册 /handoff 的通配安装说明"
    PASS=$((PASS+1))
fi

# ── Test 7: recall N<=0 语义统一为拒绝，不回默认 ──
if grep -RInE '非正整数.*回默认|0 / 负数.*回退|N=0 / 负数.*回退' \
    "$DOC_DIR/skills/handoff/SKILL.md" \
    "$DOC_DIR/skills/handoff/commands/handoff-recall.md" \
    "$DOC_DIR/skills/handoff/references/handoff-recall.md" \
    "$DOC_DIR/TEST-SCENARIOS.md" >/dev/null 2>&1; then
    echo "  ❌ recall N<=0 文档仍含回默认/回退语义"
    FAIL=$((FAIL+1))
else
    echo "  ✅ recall N<=0 文档统一为拒绝语义"
    PASS=$((PASS+1))
fi

# ── Test 8: 不再用旧的“三条命令、五个脚本”描述当前产品面 ──
if {
    grep -RInE '三条命令、五个脚本|三条命令对应|三条互补的命令|三条 slash 命令|5 个脚本|五个脚本|四个命令|4 commands|7 个脚本' \
        "$DOC_DIR/README.md" \
        "$DOC_DIR/INSTALL.md" \
        "$DOC_DIR/CONTRIBUTING.md" \
        "$DOC_DIR/skills/handoff/SKILL.md"
    sed -n '1,230p' "$DOC_DIR/HANDOFF.md" | grep -nE '三条命令、五个脚本|三条命令对应|三条互补的命令|三条 slash 命令|5 个脚本|五个脚本|四个命令|4 commands|7 个脚本'
} >/dev/null 2>&1; then
    echo "  ❌ 文档仍含旧命令/脚本数量描述"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 文档避免硬编码命令/脚本数量"
    PASS=$((PASS+1))
fi

# ── Test 9: 手动 .skill 升级说明必须包含所有非主命令 shim ──
if ! echo "$README_CONTENTS" | grep -q 'handoff-init.md'; then
    echo "  ❌ README.md 手动 .skill 升级说明缺 handoff-init.md"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 手动 .skill 升级说明包含 handoff-init.md"
    PASS=$((PASS+1))
fi

# ── Test 10: 当前文档不得停留在旧断言统计 ──
if {
    grep -RInE '(228|270|279) (断言|assertions)|(228|270|279) passed|(228|270|279) assertions|(228|270|279) 断言' \
        "$DOC_DIR/README.md" \
        "$DOC_DIR/INSTALL.md" \
        "$DOC_DIR/CONTRIBUTING.md" \
        "$DOC_DIR/TEST-SCENARIOS.md"
    sed -n '1,420p' "$DOC_DIR/HANDOFF.md" | grep -nE '(228|270|279) (断言|assertions)|(228|270|279) passed|(228|270|279) assertions|(228|270|279) 断言'
} >/dev/null 2>&1; then
    echo "  ❌ 当前文档仍含旧断言统计"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 当前文档未停留在旧断言统计"
    PASS=$((PASS+1))
fi

# ── Test 11: Codex 文档不得推荐 ~/.codex/skills 作为 Handoff 安装/镜像路径 ──
if grep -RInE '~/.codex/skills|\\.codex/skills|sync-codex-skills.*镜像|合并到 `~/.codex/skills`' \
    "$DOC_DIR/README.md" \
    "$DOC_DIR/INSTALL.md" \
    "$DOC_DIR/skills/handoff/SKILL.md" \
    "$DOC_DIR/skills/handoff/references" >/dev/null 2>&1; then
    echo "  ❌ 文档仍推荐 Codex ~/.codex/skills 镜像路径"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 文档未推荐 Codex ~/.codex/skills 镜像路径"
    PASS=$((PASS+1))
fi

# ── Test 12: /handoff 与 /handoff-tidy 后置校验必须使用 readiness 模式 ──
# v2: arg may be HANDOFF.md (single-file legacy mode) or <project-root> (multi-file).
if grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoff/references/handoff-write.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoff/references/handoff-tidy.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoff/references/handoff-init.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoff/SKILL.md"; then
    echo "  ✅ handoff 后置校验使用 readiness 模式"
    PASS=$((PASS+1))
else
    echo "  ❌ handoff 后置校验未统一使用 validate-handoff.sh --readiness"
    FAIL=$((FAIL+1))
fi

# ── Test 13: README.md 凭证前缀数量说明不得停留在旧值 "8 种" ──
if grep -q "8 种密钥前缀" "$DOC_DIR/README.md"; then
    echo "  ❌ README.md 凭证前缀数量说明已过时（'8 种'应为当前实际数量）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 凭证前缀数量未停留在旧值 '8 种'"
    PASS=$((PASS+1))
fi

# ── Test 14: README.md 凭证前缀数量必须与扫描器实际匹配（当前 11 种）──
# 更新扫描器 pattern 数量后必须同步更新 README.md 此处说明，否则此测试 FAIL
if ! grep -q "11 种密钥前缀" "$DOC_DIR/README.md"; then
    echo "  ❌ README.md 未找到当前凭证前缀数量说明 '11 种密钥前缀'（更新 pattern 后需同步 README）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 凭证前缀数量说明与扫描器一致（11 种）"
    PASS=$((PASS+1))
fi

summary
