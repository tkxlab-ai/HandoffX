#!/bin/bash
# test_no_legacy_templates.sh — 验证 templates/ legacy 镜像已清理
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

# ── Test 1: canonical template 存在 ──
CANONICAL="$ROOT_DIR/skills/handoffx/assets/${HX_MAIN_FILE%.md}.template.md"
if [ -f "$CANONICAL" ]; then
    echo "  ✅ canonical template 存在: skills/handoffx/assets/${HX_MAIN_FILE%.md}.template.md"
    PASS=$((PASS+1))
else
    echo "  ❌ canonical template 缺失: $CANONICAL"
    FAIL=$((FAIL+1))
fi

# ── Test 1b: pre-v4 asset name is gone ──
# Why: install derives the source name from $HX_MAIN_FILE; a stale copy under the
# legacy name would ship in the bundle and could be picked up by hand-written docs.
LEGACY_TPL="$ROOT_DIR/skills/handoffx/assets/${HX_LEGACY_MAIN_FILE%.md}.template.md"
assert_exit "legacy template name absent: ${HX_LEGACY_MAIN_FILE%.md}.template.md" 0 "$([ ! -e "$LEGACY_TPL" ] && echo 0 || echo 1)"

# ── Test 2: templates/ 目录不存在（已清理） ──
if [ -d "$ROOT_DIR/templates" ]; then
    echo "  ❌ templates/ 目录仍存在（应已删除）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ templates/ 目录已清理"
    PASS=$((PASS+1))
fi

# ── Test 3: common.sh 不引用旧 TEMPLATES_DIR ──
COMMON_CONTENTS=$(cat "$ROOT_DIR/tests/common.sh" 2>/dev/null || echo "")
if echo "$COMMON_CONTENTS" | grep -q 'TEMPLATES_DIR.*\$ROOT_DIR/templates'; then
    echo "  ❌ common.sh 仍引用旧 TEMPLATES_DIR"
    FAIL=$((FAIL+1))
else
    echo "  ✅ common.sh 不引用旧 TEMPLATES_DIR"
    PASS=$((PASS+1))
fi

# ── Test 4: test_validate_handoff.sh 不引用旧 templates/ 路径 ──
VALIDATE_CONTENTS=$(cat "$ROOT_DIR/tests/test_validate_handoff.sh" 2>/dev/null || echo "")
if echo "$VALIDATE_CONTENTS" | grep -qE '\$ROOT_DIR/templates|/templates/'; then
    echo "  ❌ test_validate_handoff.sh 仍引用旧 templates/ 路径"
    FAIL=$((FAIL+1))
else
    echo "  ✅ test_validate_handoff.sh 不引用旧 templates/ 路径"
    PASS=$((PASS+1))
fi

# ── Test 5: CONTRIBUTING.md 不把 templates/ 作为当前路径引用 ──
# 允许 "已删除" / "legacy" 等历史说明，但不允许作为当前目录结构列出
CONTRIB_CONTENTS=$(cat "$ROOT_DIR/CONTRIBUTING.md" 2>/dev/null || echo "")
if echo "$CONTRIB_CONTENTS" | grep -qE '^templates/.*→'; then
    echo "  ❌ CONTRIBUTING.md 仍把 templates/ 列为当前目录结构"
    FAIL=$((FAIL+1))
else
    echo "  ✅ CONTRIBUTING.md 不把 templates/ 列为当前目录结构"
    PASS=$((PASS+1))
fi

summary
