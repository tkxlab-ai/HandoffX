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

# ── Test 6 (v4.1.1 W3, report 5 HX-05)：skill 包自包含 ──
# 已安装的 skill 只有 skills/handoffx/ 这一棵树：SKILL.md:17 指向 MIGRATION_GUIDE_v2.md、
# :37 指向 README，Agent 照相对路径去读拿到 ENOENT。规则：SKILL.md / command-shims /
# references 里的 references|assets|scripts|lib 相对路径必须在包内解析到文件；
# 仓库级文档（MIGRATION_GUIDE_v2.md / README*.md / CONTRIBUTING.md）只能出现在同时
# 写明「（完整发行包）」或「(full distribution)」的行上。
# 输出格式 `<file>:<line>: <ref>`，失败时直接点名。
bundle_refs_unresolved() {   # $1 = skill 根
    local sk="$1" f rel ln line ref p
    for f in "$sk/SKILL.md" "$sk"/command-shims/*.md "$sk"/references/*.md; do
        [ -f "$f" ] || continue
        rel="${f#"$sk"/}"
        grep -nE '(MIGRATION_GUIDE_v2|README(_CN)?|CONTRIBUTING)\.md|(^|[`/ (])(references|assets|scripts|lib)/[A-Za-z0-9_.-]+' "$f" |
        while IFS= read -r line; do
            ln="${line%%:*}"; line="${line#*:}"
            case "$line" in *"（完整发行包）"*|*"(full distribution)"*) continue ;; esac
            printf '%s\n' "$line" | grep -oE '(MIGRATION_GUIDE_v2|README(_CN)?|CONTRIBUTING)\.md' |
                while IFS= read -r ref; do echo "$rel:$ln: $ref"; done
            printf '%s\n' "$line" | grep -oE '(^|[`/ (])(references|assets|scripts|lib)/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*' |
            while IFS= read -r ref; do
                ref="${ref#[\`/ (]}"
                case "$ref" in lib/*) p="scripts/$ref" ;; *) p="$ref" ;; esac
                # 只校验文件形态（带扩展名）；`scripts/` 这类目录泛指不算引用
                case "$p" in *.*) [ -f "$sk/$p" ] || echo "$rel:$ln: $ref" ;; esac
            done
        done
    done
}
SK="$ROOT_DIR/skills/handoffx"
BAD=$(bundle_refs_unresolved "$SK")
if [ -z "$BAD" ]; then
    echo "  ✅ skill 包内引用全部自包含（或标明「（完整发行包）」）"; PASS=$((PASS+1))
else
    echo "  ❌ skill 包内引用指向包外文件:"; printf '%s\n' "$BAD" | sed 's/^/     /'; FAIL=$((FAIL+1))
fi
# 门禁自检：植入一条包外引用与一条不存在的包内路径，必须被点名；标了「（完整发行包）」的放行
GT=$(mktemp -d); mkdir -p "$GT/references" "$GT/command-shims" "$GT/scripts/lib"
printf 'x\n' > "$GT/scripts/lib/ok.sh"
printf '见 `README.md` §4\n见 `references/nope.md`\n见 `lib/ok.sh`\n历史见 `MIGRATION_GUIDE_v2.md`（完整发行包）\n' > "$GT/SKILL.md"
GBAD=$(bundle_refs_unresolved "$GT"); rm -rf "$GT"
assert_contains "自检: 点名包外 README.md" "$GBAD" "SKILL.md:1: README.md"
assert_contains "自检: 点名不存在的 references/nope.md" "$GBAD" "SKILL.md:2: references/nope.md"
assert_not_contains "自检: lib/ok.sh 按 scripts/lib 解析" "$GBAD" "lib/ok.sh"
assert_not_contains "自检: 标了（完整发行包）的行放行" "$GBAD" "MIGRATION_GUIDE"

summary
