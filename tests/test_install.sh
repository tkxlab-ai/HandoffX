#!/bin/bash
# test_install.sh — install.sh 行为测试
# 使用隔离的临时 HOME 目录做沙箱，不污染真实环境
source "$(dirname "$0")/common.sh"

INSTALL="$ROOT_DIR/install.sh"
SKILL_SRC="$ROOT_DIR/skills/handoff"

# ── 沙箱工具 ────────────────────────────────────────────────────────────────

setup_sandbox() {
    SANDBOX=$(mktemp -d)
    export HOME="$SANDBOX"
    export XDG_CONFIG_HOME="$SANDBOX/.config"
}

teardown_sandbox() {
    [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
    unset HOME XDG_CONFIG_HOME SANDBOX
}

run_install() {
    # 在子 shell 里跑，隔离 set -e
    bash "$INSTALL" "$@" > /dev/null 2>&1
    echo $?
}

assert_skill_frontmatter_valid() {
    local label="$1"
    local path="$2"
    ruby -ryaml -e '
path = ARGV.fetch(0)
frontmatter = File.read(path).split(/^---\s*$/, 3).fetch(1)
data = YAML.safe_load(frontmatter)
raise "missing name" if data.fetch("name").to_s.empty?
description = data.fetch("description").to_s
raise "missing description" if description.empty?
raise "description too long" if description.length > 160
' "$path" >/dev/null 2>&1
    assert_exit "$label" 0 "$?"
}

assert_codex_command_available() {
    local label="$1"
    local root="$2"
    local cmd_name="$3"
    local target="$root/.agents/skills/$cmd_name/SKILL.md"

    [ "$cmd_name" = "handoff" ] && target="$root/.agents/skills/handoff/SKILL.md"

    assert_file_exists "$label: Codex skill entry exists" "$target"
    assert_skill_frontmatter_valid "$label: frontmatter valid and concise" "$target"

    if [ "$cmd_name" != "handoff" ]; then
        assert_contains "$label: alias points to parent handoff skill" \
            "$(cat "$target" 2>/dev/null || true)" \
            "Use skill: handoff."
        assert_contains "$label: alias preserves command title" \
            "$(cat "$target" 2>/dev/null || true)" \
            "# /$cmd_name"
        assert_contains "$label: alias documents Codex dollar command" \
            "$(cat "$target" 2>/dev/null || true)" \
            "so \`\$$cmd_name\` works like"
    fi
}

assert_no_claude_handoff_duplicates() {
    local label="$1"
    local root="$2"
    local bad=0

    if [ -f "$root/.claude/commands/handoff.md" ]; then
        echo "  ❌ $label: ~/.claude/commands/handoff.md 不该存在（/handoff 只由 skill name 注册）"
        bad=1
    fi
    if [ -d "$root/.claude/skills/handoff/commands" ]; then
        echo "  ❌ $label: skill 目录内 commands/ 不该存在（Claude Code 会重复登记）"
        bad=1
    fi
    if find "$root/.claude/skills" -path '*/commands/handoff.md' -type f 2>/dev/null | grep -q .; then
        echo "  ❌ $label: skill 内嵌 handoff.md shim 残留"
        bad=1
    fi
    if [ "$bad" = "0" ]; then
        echo "  ✅ $label: Claude Code /handoff 单源注册"
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
}

# ── Case 1: 默认安装到 Claude Code ──────────────────────────────────────────
setup_sandbox
exit_code=$(run_install)
assert_exit "C1: exit 0"              0   "$exit_code"
assert_file_exists "C1: SKILL.md 安装到 Claude" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
assert_file_exists "C1: handoff-recall.md command" \
    "$SANDBOX/.claude/commands/handoff-recall.md"
assert_file_exists "C1: handoff-tidy.md command" \
    "$SANDBOX/.claude/commands/handoff-tidy.md"
assert_file_exists "C1: handoff-memory.md command (experimental)" \
    "$SANDBOX/.claude/commands/handoff-memory.md"
assert_file_exists "C1: handoff-init.md command" \
    "$SANDBOX/.claude/commands/handoff-init.md"
# /handoff 由 skill name 注册，不再装 commands shim（否则 palette 会出现重复）
if [ -f "$SANDBOX/.claude/commands/handoff.md" ]; then
    echo "  ❌ C1: handoff.md shim 不该存在（避免 palette 重复）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C1: handoff.md shim 未安装（正确 — 由 skill name 注册）"
    PASS=$((PASS+1))
fi
# scripts 应有执行权限
if [ -x "$SANDBOX/.claude/skills/handoff/scripts/validate-handoff.sh" ]; then
    echo "  ✅ C1: scripts 有执行权限"
    PASS=$((PASS+1))
else
    echo "  ❌ C1: scripts 缺执行权限"
    FAIL=$((FAIL+1))
fi
assert_no_claude_handoff_duplicates "C1" "$SANDBOX"
teardown_sandbox

# ── Case 2: --claude 只装 Claude Code，不装 OpenCode ────────────────────────
setup_sandbox
run_install --claude > /dev/null 2>&1
assert_file_exists "C2: Claude skills 安装" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
if [ -d "$SANDBOX/.config/opencode/skills/handoff" ]; then
    echo "  ❌ C2: OpenCode 不应被安装"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C2: OpenCode 未被安装（正确）"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 3: --opencode 只装 OpenCode ────────────────────────────────────────
# OpenCode 读 ~/.config/opencode/command/（单数），不像 Claude Code 那样从
# SKILL.md `name:` 自动注册主命令——所以必须显式拷 handoff.md 进 command/。
# 详见 Gotcha #9（HANDOFF.md）。
setup_sandbox
run_install --opencode > /dev/null 2>&1
assert_file_exists "C3: OpenCode skills 安装" \
    "$SANDBOX/.config/opencode/skills/handoff/SKILL.md"
assert_file_exists "C3: OpenCode handoff.md shim（OpenCode 必须显式注册主命令）" \
    "$SANDBOX/.config/opencode/command/handoff.md"
assert_file_exists "C3: OpenCode handoff-recall shim 安装" \
    "$SANDBOX/.config/opencode/command/handoff-recall.md"
assert_file_exists "C3: OpenCode handoff-tidy shim 安装" \
    "$SANDBOX/.config/opencode/command/handoff-tidy.md"
assert_file_exists "C3: OpenCode handoff-memory shim 安装" \
    "$SANDBOX/.config/opencode/command/handoff-memory.md"
assert_file_exists "C3: OpenCode handoff-init shim 安装" \
    "$SANDBOX/.config/opencode/command/handoff-init.md"
if [ -d "$SANDBOX/.config/opencode/commands" ] && \
   ls "$SANDBOX/.config/opencode/commands/handoff"*.md >/dev/null 2>&1; then
    echo "  ❌ C3: OpenCode commands/（复数，旧路径）不该残留 handoff*.md"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C3: OpenCode commands/（复数）无 handoff 残留（正确）"
    PASS=$((PASS+1))
fi
if [ -d "$SANDBOX/.claude/skills/handoff" ]; then
    echo "  ❌ C3: Claude Code 不应被安装"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C3: Claude Code 未被安装（正确）"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 4: --codex 安装到官方 .agents/skills + $ aliases，无 .codex mirror ──
setup_sandbox
run_install --codex > /dev/null 2>&1
assert_file_exists "C4: Codex skills 安装" \
    "$SANDBOX/.agents/skills/handoff/SKILL.md"
for cmd_file in "$SKILL_SRC"/commands/*.md; do
    cmd_name=$(basename "$cmd_file" .md)
    assert_file_exists "C4: Codex \$${cmd_name} alias" \
        "$SANDBOX/.agents/skills/$cmd_name/SKILL.md"
done
assert_contains "C4: Codex recall alias points to parent skill" \
    "$(cat "$SANDBOX/.agents/skills/handoff-recall/SKILL.md" 2>/dev/null || true)" \
    "Use skill: handoff"
assert_skill_frontmatter_valid "C4: Codex recall alias frontmatter is valid YAML" \
    "$SANDBOX/.agents/skills/handoff-recall/SKILL.md"
for cmd_file in "$SKILL_SRC"/commands/*.md; do
    cmd_name=$(basename "$cmd_file" .md)
    assert_codex_command_available "C4: Codex \$${cmd_name} usable" "$SANDBOX" "$cmd_name"
done
if [ -d "$SANDBOX/.codex/commands" ]; then
    echo "  ❌ C4: Codex 不应有 commands 目录"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C4: Codex 无 commands 目录（正确）"
    PASS=$((PASS+1))
fi
if find "$SANDBOX/.codex/skills" -maxdepth 1 -type d -name 'handoff*' 2>/dev/null | grep -q .; then
    echo "  ❌ C4: Codex 不应生成 ~/.codex/skills/handoff* 镜像"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C4: Codex 未生成 ~/.codex/skills/handoff* 镜像"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 4b: ~/.codex/skills 存在但无 legacy mirror → install 不能 abort ─────
# Regression for v1.2.10 bug：cleanup_codex_legacy_mirrors 在 removed=0 时
# 末尾 `[ ... -gt 0 ] && echo` 返回 1，set -e 触发 abort。
# 触发条件：用户装过 Codex CLI（~/.codex/skills 已被其他 skill 创建）但没装过
# 旧版 handoff（无 handoff* 子目录）。任何 fresh Codex 用户首次装 handoff 都踩。
setup_sandbox
mkdir -p "$SANDBOX/.codex/skills"
# 故意放一个无关 skill，证明 "目录存在但无 legacy handoff*" 的真实场景
mkdir -p "$SANDBOX/.codex/skills/some-other-skill"
ec=$(run_install --codex)
assert_exit "C4b: --codex 在 ~/.codex/skills 存在但无 legacy mirror 时 exit 0" 0 "$ec"
assert_file_exists "C4b: --codex 安装成功（agents/skills/handoff 存在）" \
    "$SANDBOX/.agents/skills/handoff/SKILL.md"
if [ -d "$SANDBOX/.codex/skills/some-other-skill" ]; then
    echo "  ✅ C4b: cleanup 没误删非 handoff 的其他 skill"
    PASS=$((PASS+1))
else
    echo "  ❌ C4b: cleanup 误删了 ~/.codex/skills/some-other-skill"
    FAIL=$((FAIL+1))
fi
teardown_sandbox

# ── Case 5: --claude + --opencode 同时安装两个 CLI ───────────────────────────
setup_sandbox
run_install --claude --opencode > /dev/null 2>&1
assert_file_exists "C5: Claude 安装" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
assert_file_exists "C5: OpenCode 安装" \
    "$SANDBOX/.config/opencode/skills/handoff/SKILL.md"
teardown_sandbox

# ── Case 6: --uninstall 删除 Claude 安装 ────────────────────────────────────
setup_sandbox
run_install --claude --codex > /dev/null 2>&1
# 先确认安装成功
[ -d "$SANDBOX/.claude/skills/handoff" ] || { echo "  ➖ C6: 安装前提失败，跳过"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX/.agents/skills/handoff-recall" ] || { echo "  ➖ C6: Codex alias 安装前提失败，跳过"; FAIL=$((FAIL+1)); }
run_install --uninstall > /dev/null 2>&1
if [ -d "$SANDBOX/.claude/skills/handoff" ]; then
    echo "  ❌ C6: --uninstall 未删除 Claude skills"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C6: --uninstall 删除 Claude skills"
    PASS=$((PASS+1))
fi
if [ -f "$SANDBOX/.claude/commands/handoff-recall.md" ]; then
    echo "  ❌ C6: --uninstall 未删除 commands shim"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C6: --uninstall 删除 commands shim"
    PASS=$((PASS+1))
fi
if [ -d "$SANDBOX/.agents/skills/handoff-recall" ]; then
    echo "  ❌ C6: --uninstall 未删除 Codex alias"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C6: --uninstall 删除 Codex alias"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 7: --project 安装到指定目录 ─────────────────────────────────────────
setup_sandbox
PROJECT_DIR=$(mktemp -d)
FAKE_BIN="$SANDBOX/bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' > "$FAKE_BIN/codex"
chmod +x "$FAKE_BIN/codex"
PATH="$FAKE_BIN:$PATH" run_install --project "$PROJECT_DIR" > /dev/null 2>&1
assert_file_exists "C7: 项目级 SKILL.md" \
    "$PROJECT_DIR/.claude/skills/handoff/SKILL.md"
assert_file_exists "C7: 项目级 commands" \
    "$PROJECT_DIR/.claude/commands/handoff-recall.md"
assert_file_exists "C7: 项目级 handoff-memory shim" \
    "$PROJECT_DIR/.claude/commands/handoff-memory.md"
assert_file_exists "C7: 项目级 handoff-init shim" \
    "$PROJECT_DIR/.claude/commands/handoff-init.md"
assert_file_exists "C7: 项目级 Codex 使用 .agents/skills" \
    "$PROJECT_DIR/.agents/skills/handoff/SKILL.md"
if find "$PROJECT_DIR/.codex/skills" -maxdepth 1 -type d -name 'handoff*' 2>/dev/null | grep -q .; then
    echo "  ❌ C7: 项目级 Codex 不应生成 .codex/skills/handoff*"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C7: 项目级 Codex 未生成 .codex/skills/handoff*"
    PASS=$((PASS+1))
fi
assert_no_claude_handoff_duplicates "C7 project install" "$PROJECT_DIR"
rm -rf "$PROJECT_DIR"
teardown_sandbox

# ── Case 8: --project 传入不存在目录 → exit 1 ────────────────────────────────
setup_sandbox
exit_code=$(run_install --project /nonexistent_dir_xyz)
assert_exit "C8: 无效项目目录 exit 1" 1 "$exit_code"
teardown_sandbox

# ── Case 9: --template 创建 HANDOFF.md ───────────────────────────────────────
setup_sandbox
TARGET_DIR=$(mktemp -d)
run_install --claude --template "$TARGET_DIR" > /dev/null 2>&1
assert_file_exists "C9: HANDOFF.md 从模板创建" \
    "$TARGET_DIR/HANDOFF.md"
# 第二次运行不覆盖
original_size=$(wc -c < "$TARGET_DIR/HANDOFF.md")
echo "extra line" >> "$TARGET_DIR/HANDOFF.md"
run_install --claude --template "$TARGET_DIR" > /dev/null 2>&1
new_size=$(wc -c < "$TARGET_DIR/HANDOFF.md")
if [ "$new_size" -gt "$original_size" ]; then
    echo "  ✅ C9: 第二次 --template 不覆盖（保留现有内容）"
    PASS=$((PASS+1))
else
    echo "  ❌ C9: 第二次 --template 覆盖了文件"
    FAIL=$((FAIL+1))
fi
rm -rf "$TARGET_DIR"
teardown_sandbox

# ── Case 10: 从 .skill bootstrap 安装 ────────────────────────────────────────
if [ -L "$ROOT_DIR/Release/latest" ] && ls "$ROOT_DIR"/Release/latest/handoff-*.skill >/dev/null 2>&1; then
    SKILL_FILE=$(ls "$ROOT_DIR"/Release/latest/handoff-*.skill 2>/dev/null | head -1 || true)
else
    SKILL_FILE=$(find "$ROOT_DIR/Release" -mindepth 2 -maxdepth 2 -name 'handoff-*.skill' 2>/dev/null | sort -V | tail -1)
fi
if [ -n "$SKILL_FILE" ] && [ -f "$SKILL_FILE" ]; then
    setup_sandbox
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$SKILL_FILE" "$BOOTSTRAP_DIR/"
    cp "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    exit_code=$(bash "$BOOTSTRAP_DIR/install.sh" --claude 2>/dev/null; echo $?)
    # 重新跑并捕获 exit
    actual_exit=0
    bash "$BOOTSTRAP_DIR/install.sh" --claude > /dev/null 2>&1 || actual_exit=$?
    assert_exit "C10: .skill bootstrap exit 0" 0 "$actual_exit"
    assert_file_exists "C10: .skill bootstrap 安装 SKILL.md" \
        "$SANDBOX/.claude/skills/handoff/SKILL.md"
    assert_file_exists "C10: .skill bootstrap 安装 commands" \
        "$SANDBOX/.claude/commands/handoff-recall.md"
    assert_no_claude_handoff_duplicates "C10 bootstrap" "$SANDBOX"
    # 注：旧 .skill 包不含 handoff-memory.md（experimental 是新增），bootstrap 后没有该 shim 是正常的
    rm -rf "$BOOTSTRAP_DIR"
    teardown_sandbox
else
    echo "  ➖ C10: 无 Release/*.skill 可用，跳过 bootstrap 测试"
fi

# ── Case 11: 旧版三源残留 → 重装后必须清到单源 ───────────────────────────────
setup_sandbox
mkdir -p "$SANDBOX/.claude/commands" "$SANDBOX/.claude/skills/handoff/commands"
cat > "$SANDBOX/.claude/commands/handoff.md" <<'EOF'
---
description: legacy global handoff shim
---
EOF
cat > "$SANDBOX/.claude/skills/handoff/commands/handoff.md" <<'EOF'
---
description: legacy nested handoff shim
---
EOF
run_install --claude > /dev/null 2>&1
assert_file_exists "C11: Claude SKILL.md installed after legacy cleanup" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
assert_no_claude_handoff_duplicates "C11 legacy cleanup" "$SANDBOX"
teardown_sandbox

# ── Case 12: WSL 模拟 → Claude Code 优先安装到 Windows AppData/Claude ───────
setup_sandbox
WIN_APPDATA="$SANDBOX/win/AppData/Roaming"
mkdir -p "$WIN_APPDATA/Claude"
HANDOFF_TEST_PLATFORM=wsl HANDOFF_TEST_WSL_APPDATA="$WIN_APPDATA" \
    run_install --claude > /dev/null 2>&1
assert_file_exists "C12: WSL Claude installs into Windows AppData" \
    "$WIN_APPDATA/Claude/skills/handoff/SKILL.md"
assert_file_exists "C12: WSL Claude command shim in Windows AppData" \
    "$WIN_APPDATA/Claude/commands/handoff-recall.md"
if [ -d "$SANDBOX/.claude/skills/handoff" ]; then
    echo "  ❌ C12: WSL 有 Windows Claude 时不应落到 WSL HOME"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C12: WSL 未落到 WSL HOME（正确）"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 13: WSL 模拟 → Windows AppData 无 Claude 时回退 WSL HOME ───────────
setup_sandbox
WIN_APPDATA="$SANDBOX/win-no-claude/AppData/Roaming"
mkdir -p "$WIN_APPDATA"
HANDOFF_TEST_PLATFORM=wsl HANDOFF_TEST_WSL_APPDATA="$WIN_APPDATA" \
    run_install --claude > /dev/null 2>&1
assert_file_exists "C13: WSL fallback installs into WSL HOME" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
if [ -d "$WIN_APPDATA/Claude/skills/handoff" ]; then
    echo "  ❌ C13: WSL fallback 不应创建 Windows Claude 目录"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C13: WSL fallback 未创建 Windows Claude 目录"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 14 (D1): install.sh warns when PWD has v1 HANDOFF.md ───────────────
setup_sandbox
PROJECT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$PROJECT/HANDOFF.md"
out_14=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
ec_14=$?
assert_exit "C14: install with v1 in PWD → exit 0" 0 "$ec_14"
assert_contains "C14: warns about v1 HANDOFF.md" "$out_14" "v1 HANDOFF.md"
assert_contains "C14: hints /handoff-tidy" "$out_14" "/handoff-tidy"
assert_file_exists "C14: skill still installs despite v1 warning" \
    "$SANDBOX/.claude/skills/handoff/SKILL.md"
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14b (D1): no warning when PWD has v2 HANDOFF.md ────────────────────
setup_sandbox
PROJECT=$(mktemp -d)
cat > "$PROJECT/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
## 📦 Project Overview
test
EOF
out_14b=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14b" | grep -q "v1 HANDOFF.md"; then
    echo "  ❌ C14b: warned on v2 file"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14b: no warning on v2-marker file"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14c (D1): no warning when PWD lacks HANDOFF.md ─────────────────────
setup_sandbox
PROJECT=$(mktemp -d)
out_14c=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14c" | grep -q "v1 HANDOFF.md"; then
    echo "  ❌ C14c: warned without HANDOFF.md"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14c: no warning when no HANDOFF.md present"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14d (D1): HANDOFF_INSTALL_SKIP_V2_GATE=1 silences warning ──────────
setup_sandbox
PROJECT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$PROJECT/HANDOFF.md"
out_14d=$( (cd "$PROJECT" && HANDOFF_INSTALL_SKIP_V2_GATE=1 bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14d" | grep -q "v1 HANDOFF.md"; then
    echo "  ❌ C14d: gate not silenced by env var"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14d: HANDOFF_INSTALL_SKIP_V2_GATE silences warning"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

summary
