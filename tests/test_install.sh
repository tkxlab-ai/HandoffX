#!/bin/bash
# test_install.sh — install.sh 行为测试
# 使用隔离的临时 HOME 目录做沙箱，不污染真实环境
source "$(dirname "$0")/common.sh"

INSTALL="$ROOT_DIR/install.sh"
SKILL_SRC="$ROOT_DIR/skills/handoffx"

# ── 沙箱工具 ────────────────────────────────────────────────────────────────

setup_sandbox() {
    SANDBOX=$(mktemp -d)
    export HOME="$SANDBOX"
    export XDG_CONFIG_HOME="$SANDBOX/.config"
    # 本机若是 WSL，不能让探测落到真实 /mnt/c/Users/*/AppData
    export HANDOFF_TEST_WSL_APPDATA="$SANDBOX/wsl"
}

teardown_sandbox() {
    [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"
    unset HOME XDG_CONFIG_HOME HANDOFF_TEST_WSL_APPDATA SANDBOX
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

    [ "$cmd_name" = "handoffx" ] && target="$root/.agents/skills/handoffx/SKILL.md"

    assert_file_exists "$label: Codex skill entry exists" "$target"
    assert_skill_frontmatter_valid "$label: frontmatter valid and concise" "$target"

    if [ "$cmd_name" != "handoffx" ]; then
        assert_contains "$label: alias points to parent handoffx skill" \
            "$(cat "$target" 2>/dev/null || true)" \
            "Use skill: handoffx."
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

    if [ -f "$root/.claude/commands/handoffx.md" ]; then
        echo "  ❌ $label: ~/.claude/commands/handoffx.md 不该存在（/handoffx 只由 skill name 注册）"
        bad=1
    fi
    if [ -d "$root/.claude/skills/handoffx/commands" ] || [ -d "$root/.claude/skills/handoffx/command-shims" ]; then
        echo "  ❌ $label: skill 目录内 commands/ 或 command-shims/ 不该存在（Claude Code 会重复登记 — Gotcha #5）"
        bad=1
    fi
    if find "$root/.claude/skills" -path '*/commands/handoffx.md' -type f 2>/dev/null | grep -q .; then
        echo "  ❌ $label: skill 内嵌 handoffx.md shim 残留"
        bad=1
    fi
    if [ "$bad" = "0" ]; then
        echo "  ✅ $label: Claude Code /handoffx 单源注册"
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
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
assert_file_exists "C1: handoffx-recall.md command" \
    "$SANDBOX/.claude/commands/handoffx-recall.md"
assert_file_exists "C1: handoffx-tidy.md command" \
    "$SANDBOX/.claude/commands/handoffx-tidy.md"
assert_file_exists "C1: handoffx-memory.md command (experimental)" \
    "$SANDBOX/.claude/commands/handoffx-memory.md"
assert_file_exists "C1: handoffx-init.md command" \
    "$SANDBOX/.claude/commands/handoffx-init.md"
# /handoffx 由 skill name 注册，不再装 commands shim（否则 palette 会出现重复）
if [ -f "$SANDBOX/.claude/commands/handoffx.md" ]; then
    echo "  ❌ C1: handoffx.md shim 不该存在（避免 palette 重复）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C1: handoffx.md shim 未安装（正确 — 由 skill name 注册）"
    PASS=$((PASS+1))
fi
# scripts 应有执行权限
if [ -x "$SANDBOX/.claude/skills/handoffx/scripts/validate-handoff.sh" ]; then
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
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
if [ -d "$SANDBOX/.config/opencode/skills/handoffx" ]; then
    echo "  ❌ C2: OpenCode 不应被安装"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C2: OpenCode 未被安装（正确）"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 3: --opencode 只装 OpenCode ────────────────────────────────────────
# OpenCode v1.14+ canonical 路径是 ~/.config/opencode/commands/（**复数**，per
# 官方文档 opencode.ai/docs/commands）。v1.2.x 时代是单数 command/——Gotcha #9
# 当时记录的发现已**作废**（见 Gotcha #16），install.sh v2.1.3 起跟随官方文档
# 写复数。OpenCode v1.14+ 同时读 command/ + commands/ 但**不去重**，所以装新版
# 必须清掉旧的单数残留。OpenCode 不像 Claude Code 那样从 SKILL.md `name:` 自动
# 注册主命令——所以必须显式拷 handoffx.md 进 commands/。
setup_sandbox
run_install --opencode > /dev/null 2>&1
assert_file_exists "C3: OpenCode skills 安装" \
    "$SANDBOX/.config/opencode/skills/handoffx/SKILL.md"
assert_file_exists "C3: OpenCode handoffx.md shim（OpenCode 必须显式注册主命令）" \
    "$SANDBOX/.config/opencode/commands/handoffx.md"
assert_file_exists "C3: OpenCode handoffx-recall shim 安装" \
    "$SANDBOX/.config/opencode/commands/handoffx-recall.md"
assert_file_exists "C3: OpenCode handoffx-tidy shim 安装" \
    "$SANDBOX/.config/opencode/commands/handoffx-tidy.md"
assert_file_exists "C3: OpenCode handoffx-memory shim 安装" \
    "$SANDBOX/.config/opencode/commands/handoffx-memory.md"
assert_file_exists "C3: OpenCode handoffx-init shim 安装" \
    "$SANDBOX/.config/opencode/commands/handoffx-init.md"
# 反向检查：单数 command/ 是 v2.1.3 前的旧路径，新装应该不存在 handoffx* 残留
if [ -d "$SANDBOX/.config/opencode/command" ] && \
   ls "$SANDBOX/.config/opencode/command/handoffx"*.md >/dev/null 2>&1; then
    echo "  ❌ C3: OpenCode command/（单数，v2.1.3 前的旧路径）不该残留 handoffx*.md"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C3: OpenCode command/（单数）无 handoff 残留（正确）"
    PASS=$((PASS+1))
fi
if [ -d "$SANDBOX/.claude/skills/handoffx" ]; then
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
    "$SANDBOX/.agents/skills/handoffx/SKILL.md"
for cmd_file in "$SKILL_SRC"/command-shims/*.md; do
    cmd_name=$(basename "$cmd_file" .md)
    assert_file_exists "C4: Codex \$${cmd_name} alias" \
        "$SANDBOX/.agents/skills/$cmd_name/SKILL.md"
done
assert_contains "C4: Codex recall alias points to parent skill" \
    "$(cat "$SANDBOX/.agents/skills/handoffx-recall/SKILL.md" 2>/dev/null || true)" \
    "Use skill: handoffx"
assert_skill_frontmatter_valid "C4: Codex recall alias frontmatter is valid YAML" \
    "$SANDBOX/.agents/skills/handoffx-recall/SKILL.md"
for cmd_file in "$SKILL_SRC"/command-shims/*.md; do
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
if find "$SANDBOX/.codex/skills" -maxdepth 1 -type d -name 'handoffx*' 2>/dev/null | grep -q .; then
    echo "  ❌ C4: Codex 不应生成 ~/.codex/skills/handoffx* 镜像"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C4: Codex 未生成 ~/.codex/skills/handoffx* 镜像"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 4b: ~/.codex/skills 存在但无 legacy mirror → install 不能 abort ─────
# Regression for v1.2.10 bug：cleanup_codex_legacy_mirrors 在 removed=0 时
# 末尾 `[ ... -gt 0 ] && echo` 返回 1，set -e 触发 abort。
# 触发条件：用户装过 Codex CLI（~/.codex/skills 已被其他 skill 创建）但没装过
# 旧版 handoff（无 handoffx* 子目录）。任何 fresh Codex 用户首次装 handoff 都踩。
setup_sandbox
mkdir -p "$SANDBOX/.codex/skills"
# 故意放一个无关 skill，证明 "目录存在但无 legacy handoffx*" 的真实场景
mkdir -p "$SANDBOX/.codex/skills/some-other-skill"
ec=$(run_install --codex)
assert_exit "C4b: --codex 在 ~/.codex/skills 存在但无 legacy mirror 时 exit 0" 0 "$ec"
assert_file_exists "C4b: --codex 安装成功（agents/skills/handoffx 存在）" \
    "$SANDBOX/.agents/skills/handoffx/SKILL.md"
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
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
assert_file_exists "C5: OpenCode 安装" \
    "$SANDBOX/.config/opencode/skills/handoffx/SKILL.md"
teardown_sandbox

# ── Case 6: --uninstall 删除 Claude 安装 ────────────────────────────────────
setup_sandbox
run_install --claude --codex > /dev/null 2>&1
# 先确认安装成功
[ -d "$SANDBOX/.claude/skills/handoffx" ] || { echo "  ➖ C6: 安装前提失败，跳过"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX/.agents/skills/handoffx-recall" ] || { echo "  ➖ C6: Codex alias 安装前提失败，跳过"; FAIL=$((FAIL+1)); }
run_install --uninstall > /dev/null 2>&1
if [ -d "$SANDBOX/.claude/skills/handoffx" ]; then
    echo "  ❌ C6: --uninstall 未删除 Claude skills"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C6: --uninstall 删除 Claude skills"
    PASS=$((PASS+1))
fi
if [ -f "$SANDBOX/.claude/commands/handoffx-recall.md" ]; then
    echo "  ❌ C6: --uninstall 未删除 commands shim"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C6: --uninstall 删除 commands shim"
    PASS=$((PASS+1))
fi
if [ -d "$SANDBOX/.agents/skills/handoffx-recall" ]; then
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
    "$PROJECT_DIR/.claude/skills/handoffx/SKILL.md"
assert_file_exists "C7: 项目级 commands" \
    "$PROJECT_DIR/.claude/commands/handoffx-recall.md"
assert_file_exists "C7: 项目级 handoffx-memory shim" \
    "$PROJECT_DIR/.claude/commands/handoffx-memory.md"
assert_file_exists "C7: 项目级 handoffx-init shim" \
    "$PROJECT_DIR/.claude/commands/handoffx-init.md"
assert_file_exists "C7: 项目级 Codex 使用 .agents/skills" \
    "$PROJECT_DIR/.agents/skills/handoffx/SKILL.md"
if find "$PROJECT_DIR/.codex/skills" -maxdepth 1 -type d -name 'handoffx*' 2>/dev/null | grep -q .; then
    echo "  ❌ C7: 项目级 Codex 不应生成 .codex/skills/handoffx*"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C7: 项目级 Codex 未生成 .codex/skills/handoffx*"
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

# ── Case 9: --template 创建主文件（目标名 = $HX_MAIN_FILE）────────────────────
setup_sandbox
TARGET_DIR=$(mktemp -d)
run_install --claude --template "$TARGET_DIR" > /dev/null 2>&1
assert_file_exists "C9: $HX_MAIN_FILE 从模板创建" \
    "$TARGET_DIR/$HX_MAIN_FILE"
# 第二次运行不覆盖
original_size=$(wc -c < "$TARGET_DIR/$HX_MAIN_FILE")
echo "extra line" >> "$TARGET_DIR/$HX_MAIN_FILE"
run_install --claude --template "$TARGET_DIR" > /dev/null 2>&1
new_size=$(wc -c < "$TARGET_DIR/$HX_MAIN_FILE")
if [ "$new_size" -gt "$original_size" ]; then
    echo "  ✅ C9: 第二次 --template 不覆盖（保留现有内容）"
    PASS=$((PASS+1))
else
    echo "  ❌ C9: 第二次 --template 覆盖了文件"
    FAIL=$((FAIL+1))
fi
rm -rf "$TARGET_DIR"
teardown_sandbox

# ── Case 9b (P2.4 §4b-4): --template 目标含旧布局 → 安装前拒绝、零写入 ─────────
# 判定对象是解析后的目标目录（不是 PWD）；拒绝发生在参数校验阶段，故各 CLI 安装根也不得出现。
setup_sandbox
TARGET_DIR=$(mktemp -d); OTHER_PWD=$(mktemp -d)
p21_materialize "$TARGET_DIR" || FAIL=$((FAIL+1))
before_tpl=$(ls -laR "$TARGET_DIR"); before_home=$(ls -laR "$SANDBOX")
ec_9b=0; out_9b=$( (cd "$OTHER_PWD" && bash "$INSTALL" --claude --opencode --codex --template "$TARGET_DIR") 2>&1 ) || ec_9b=$?
assert_exit "C9b: legacy-layout --template target → exit 1" 1 "$ec_9b"
assert_contains "C9b: hints schema-upgrade" "$out_9b" "/handoffx-tidy schema-upgrade"
assert_exit "C9b: template target ls -laR unchanged" 0 "$([ "$before_tpl" = "$(ls -laR "$TARGET_DIR")" ] && echo 0 || echo 1)"
assert_exit "C9b: sandboxed HOME (all CLI install roots) unchanged" 0 "$([ "$before_home" = "$(ls -laR "$SANDBOX")" ] && echo 0 || echo 1)"
assert_exit "C9b: no $HX_MAIN_FILE created" 0 "$([ ! -e "$TARGET_DIR/$HX_MAIN_FILE" ] && echo 0 || echo 1)"
rm -rf "$TARGET_DIR" "$OTHER_PWD"
teardown_sandbox

# C9c: v1 single-file legacy target → refused too, hint routes to migrate-to-v2
setup_sandbox
TARGET_DIR=$(mktemp -d); OTHER_PWD=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$TARGET_DIR/$HX_LEGACY_MAIN_FILE"
before_tpl=$(ls -laR "$TARGET_DIR"); before_home=$(ls -laR "$SANDBOX")
ec_9c=0; out_9c=$( (cd "$OTHER_PWD" && bash "$INSTALL" --claude --template "$TARGET_DIR") 2>&1 ) || ec_9c=$?
assert_exit "C9c: v1 legacy --template target → exit 1" 1 "$ec_9c"
assert_contains "C9c: hints migrate-to-v2 --apply" "$out_9c" "migrate-to-v2.sh --apply"
assert_not_contains "C9c: v1 hint is not the schema-upgrade one" "$out_9c" "schema-upgrade"
assert_exit "C9c: template target and HOME unchanged" 0 "$([ "$before_tpl" = "$(ls -laR "$TARGET_DIR")" ] && [ "$before_home" = "$(ls -laR "$SANDBOX")" ] && echo 0 || echo 1)"
rm -rf "$TARGET_DIR" "$OTHER_PWD"
teardown_sandbox

# C9c-dangling (fix wave 1 A4): a dangling legacy symlink is still a legacy
# piece — `-e` alone missed it and the template went ahead beside it.
setup_sandbox
TARGET_DIR=$(mktemp -d); OTHER_PWD=$(mktemp -d)
ln -s "$TARGET_DIR/nowhere" "$TARGET_DIR/$HX_LEGACY_MAIN_FILE"
ec_9e=0; out_9e=$( (cd "$OTHER_PWD" && bash "$INSTALL" --claude --template "$TARGET_DIR") 2>&1 ) || ec_9e=$?
assert_exit "C9c-dangling: dangling legacy main symlink → exit 1" 1 "$ec_9e"
assert_exit "C9c-dangling: no $HX_MAIN_FILE created" 0 "$([ ! -e "$TARGET_DIR/$HX_MAIN_FILE" ] && echo 0 || echo 1)"
rm -rf "$TARGET_DIR" "$OTHER_PWD"
teardown_sandbox

# C9e (fix wave 2, m6): a dangling-symlink new main in the template target is
# an existing main (hx_present) — `-f` missed it and cp wrote THROUGH the link.
setup_sandbox
TARGET_DIR=$(mktemp -d); LINK_DST=$(mktemp -d)
ln -s "$LINK_DST/elsewhere.md" "$TARGET_DIR/$HX_MAIN_FILE"
ec_9f=0; out_9f=$(bash "$INSTALL" --claude --template "$TARGET_DIR" 2>&1) || ec_9f=$?
assert_exit "C9e: dangling new-main symlink target → install still exit 0" 0 "$ec_9f"
assert_exit "C9e: nothing written through the symlink" 0 "$([ ! -e "$LINK_DST/elsewhere.md" ] && echo 0 || echo 1)"
assert_contains "C9e: reports the existing main and skips" "$out_9f" "已存在，跳过"
rm -rf "$TARGET_DIR" "$LINK_DST"
teardown_sandbox

# C9d (positive control): the refusal keys on the TARGET, not PWD — a legacy
# layout in PWD with a clean target still creates the main file in the target.
setup_sandbox
TARGET_DIR=$(mktemp -d); LEGACY_PWD=$(mktemp -d)
p21_materialize "$LEGACY_PWD" || FAIL=$((FAIL+1))
ec_9d=0; (cd "$LEGACY_PWD" && bash "$INSTALL" --claude --template "$TARGET_DIR") > /dev/null 2>&1 || ec_9d=$?
assert_exit "C9d: legacy PWD + clean target → exit 0" 0 "$ec_9d"
assert_file_exists "C9d: $HX_MAIN_FILE created in the target" "$TARGET_DIR/$HX_MAIN_FILE"
assert_exit "C9d: nothing written into the legacy PWD" 0 "$([ ! -e "$LEGACY_PWD/$HX_MAIN_FILE" ] && echo 0 || echo 1)"
rm -rf "$TARGET_DIR" "$LEGACY_PWD"
teardown_sandbox

# ── Case 10: 从 .skill bootstrap 安装 ────────────────────────────────────────
# 现场打包，不用 Release/ 里的旧版包：旧包 ZIP 根是旧 skill 名，
# hard-cut 后不可自举，且测试不应依赖正在变化的发布产物（Gotcha #8 同根）。
# ZIP 根按 release.sh 打包布局 = skill 目录名；产物名 handoffx-<ver>.skill。
SKILL_FILE=""; PKG_DIR=$(mktemp -d)
if command -v zip >/dev/null 2>&1 && cp -R "$SKILL_SRC" "$PKG_DIR/handoffx" && \
   (cd "$PKG_DIR" && zip -qr handoffx-v0.0.0-test.skill handoffx); then
    SKILL_FILE="$PKG_DIR/handoffx-v0.0.0-test.skill"
fi
if [ -n "$SKILL_FILE" ] && [ -f "$SKILL_FILE" ]; then
    setup_sandbox
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$SKILL_FILE" "$BOOTSTRAP_DIR/"
    cp "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    actual_exit=0
    c10_out=$(bash "$BOOTSTRAP_DIR/install.sh" --claude 2>&1) || actual_exit=$?
    assert_exit "C10: .skill bootstrap exit 0" 0 "$actual_exit"
    # X2 (v4.1.1): say WHY it extracts, and let the banner name the real source
    # (it used to print the install.sh directory as "Source" after extracting).
    assert_contains "X2: bootstrap names the missing source tree" "$c10_out" "不是源码树（无 skills/handoffx/），自举解压 handoffx-v0.0.0-test.skill"
    assert_contains "X2: banner Source names the extracted .skill" "$c10_out" "Source : $BOOTSTRAP_DIR/handoffx-v0.0.0-test.skill（自举解压）"
    assert_file_exists "C10: .skill bootstrap 安装 SKILL.md" \
        "$SANDBOX/.claude/skills/handoffx/SKILL.md"
    assert_file_exists "C10: .skill bootstrap 安装 commands" \
        "$SANDBOX/.claude/commands/handoffx-recall.md"
    assert_no_claude_handoff_duplicates "C10 bootstrap" "$SANDBOX"
    assert_file_exists "C10: .skill bootstrap 安装 memory shim" "$SANDBOX/.claude/commands/handoffx-memory.md"
    rm -rf "$BOOTSTRAP_DIR"
    teardown_sandbox
else echo "  ➖ C10: zip 不可用，跳过 bootstrap 测试"; fi
rm -rf "$PKG_DIR"

# ── Case 10b: 从 source tarball bootstrap 安装 ───────────────────────────────
# 与 C10 对称覆盖另一条自举分支：同目录只有 tarball + install.sh（无 .skill、无源码树），
# 压缩包根目录 = handoffx-<ver>/（release.sh 布局），EXTRACTED_ROOT glob 必须命中它。
TAR_FILE=""; PKG_DIR=$(mktemp -d)
if mkdir -p "$PKG_DIR/handoffx-v0.0.0-test/skills" && \
   cp -R "$SKILL_SRC" "$PKG_DIR/handoffx-v0.0.0-test/skills/handoffx" && \
   (cd "$PKG_DIR" && tar czf handoffx-v0.0.0-test-source.tar.gz handoffx-v0.0.0-test); then
    TAR_FILE="$PKG_DIR/handoffx-v0.0.0-test-source.tar.gz"
fi
if [ -n "$TAR_FILE" ] && [ -f "$TAR_FILE" ]; then
    setup_sandbox
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$TAR_FILE" "$BOOTSTRAP_DIR/"
    cp "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    actual_exit=0
    bash "$BOOTSTRAP_DIR/install.sh" --claude > /dev/null 2>&1 || actual_exit=$?
    assert_exit "C10b: tarball bootstrap exit 0" 0 "$actual_exit"
    assert_file_exists "C10b: tarball bootstrap 安装 SKILL.md" \
        "$SANDBOX/.claude/skills/handoffx/SKILL.md"
    # 与 C10 对称：tarball 分支同样要把 slash 命令 shim 装上，不只是 skill 本体
    for c in handoffx-recall handoffx-tidy handoffx-init handoffx-memory; do
        assert_file_exists "C10b: tarball bootstrap 安装 $c shim" "$SANDBOX/.claude/commands/$c.md"
    done
    assert_no_claude_handoff_duplicates "C10b bootstrap" "$SANDBOX"
    rm -rf "$BOOTSTRAP_DIR"
    teardown_sandbox
else
    # not a skip: tar is a declared dependency and the fixture is built on the spot —
    # a ➖ here would hide the only tarball-bootstrap coverage (Gotcha #12)
    echo "  ❌ C10b: tar 打包失败 — tarball bootstrap 无法验证"; FAIL=$((FAIL+1))
fi

# ── Case 10c: .skill 的 zip 根不是 handoffx/ ─────────────────────────────────
# 以前 .skill 优先且根不对时静默不自举，落到泛泛的"请放 .skill 或 tarball"——
# 而 tarball 就在旁边。根不对必须点名，有 tarball 就回落到它。
BADSKILL_DIR=$(mktemp -d)
mkdir -p "$BADSKILL_DIR/wrongroot"; printf 'x\n' > "$BADSKILL_DIR/wrongroot/SKILL.md"
if command -v zip >/dev/null 2>&1 && [ -n "$TAR_FILE" ] && [ -f "$TAR_FILE" ] && \
   (cd "$BADSKILL_DIR" && zip -qr handoffx-v0.0.0-test.skill wrongroot); then
    # 回落证据：tarball 里的 skill 带一个 .skill 里没有的标记文件
    (cd "$PKG_DIR" && printf 'from-tarball\n' > handoffx-v0.0.0-test/skills/handoffx/.c10c-marker && \
        tar czf handoffx-v0.0.0-test-source.tar.gz handoffx-v0.0.0-test)
    setup_sandbox
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$BADSKILL_DIR/handoffx-v0.0.0-test.skill" "$TAR_FILE" "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    actual_exit=0
    out=$(bash "$BOOTSTRAP_DIR/install.sh" --claude 2>&1) || actual_exit=$?
    assert_exit "C10c: bad-root .skill + good tarball → exit 0" 0 "$actual_exit"
    assert_contains "C10c: 点名 .skill 顶层目录不对" "$out" "的顶层目录不是 handoffx/"
    assert_file_exists "C10c: 回落 tarball 安装（标记文件来自 tarball）" \
        "$SANDBOX/.claude/skills/handoffx/.c10c-marker"
    rm -rf "$BOOTSTRAP_DIR"
    teardown_sandbox

    setup_sandbox
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$BADSKILL_DIR/handoffx-v0.0.0-test.skill" "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    actual_exit=0
    out=$(bash "$BOOTSTRAP_DIR/install.sh" --claude 2>&1) || actual_exit=$?
    assert_exit "C10c: bad-root .skill alone → exit 1" 1 "$actual_exit"
    assert_contains "C10c: 单独 bad-root .skill 报精确原因" "$out" "handoffx-v0.0.0-test.skill 的顶层目录不是 handoffx/"
    assert_not_contains "C10c: 不落到泛泛的找不到提示" "$out" "找不到 skills/handoffx/"
    assert_exit "C10c: 什么都没装" 0 "$([ ! -e "$SANDBOX/.claude/skills/handoffx" ] && echo 0 || echo 1)"
    rm -rf "$BOOTSTRAP_DIR"
    teardown_sandbox
else
    echo "  ❌ C10c: zip/tar fixture 构建失败 — bad-root .skill 回落无法验证"; FAIL=$((FAIL+1))
fi
rm -rf "$BADSKILL_DIR"
rm -rf "$PKG_DIR"

# ── Case 11: 旧版三源残留 → 重装后必须清到单源 ───────────────────────────────
setup_sandbox
mkdir -p "$SANDBOX/.claude/commands" "$SANDBOX/.claude/skills/handoffx/commands"
cat > "$SANDBOX/.claude/commands/handoffx.md" <<'EOF'
---
description: legacy global handoffx shim
---
EOF
cat > "$SANDBOX/.claude/skills/handoffx/commands/handoffx.md" <<'EOF'
---
description: legacy nested handoffx shim
---
EOF
run_install --claude > /dev/null 2>&1
assert_file_exists "C11: Claude SKILL.md installed after legacy cleanup" \
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
assert_no_claude_handoff_duplicates "C11 legacy cleanup" "$SANDBOX"
teardown_sandbox

# ── Case 12: WSL 模拟 → Claude Code 优先安装到 Windows AppData/Claude ───────
setup_sandbox
WIN_APPDATA="$SANDBOX/win/AppData/Roaming"
mkdir -p "$WIN_APPDATA/Claude"
HANDOFF_TEST_PLATFORM=wsl HANDOFF_TEST_WSL_APPDATA="$WIN_APPDATA" \
    run_install --claude > /dev/null 2>&1
assert_file_exists "C12: WSL Claude installs into Windows AppData" \
    "$WIN_APPDATA/Claude/skills/handoffx/SKILL.md"
assert_file_exists "C12: WSL Claude command shim in Windows AppData" \
    "$WIN_APPDATA/Claude/commands/handoffx-recall.md"
if [ -d "$SANDBOX/.claude/skills/handoffx" ]; then
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
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
if [ -d "$WIN_APPDATA/Claude/skills/handoffx" ]; then
    echo "  ❌ C13: WSL fallback 不应创建 Windows Claude 目录"
    FAIL=$((FAIL+1))
else
    echo "  ✅ C13: WSL fallback 未创建 Windows Claude 目录"
    PASS=$((PASS+1))
fi
teardown_sandbox

# ── Case 14 (D1): install.sh warns when PWD has a legacy v1 main file ──────
setup_sandbox
PROJECT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$PROJECT/$HX_LEGACY_MAIN_FILE"
out_14=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
ec_14=$?
assert_exit "C14: install with v1 in PWD → exit 0" 0 "$ec_14"
assert_contains "C14: warns about v1 $HX_LEGACY_MAIN_FILE" "$out_14" "legacy v1 $HX_LEGACY_MAIN_FILE"
# fix wave 2: the tidy shim does not forward --apply, so the hint names the
# migrator only (a "/handoffx-tidy --apply" alternative led nowhere).
assert_contains "C14: hint names migrate-to-v2 --apply" "$out_14" "migrate-to-v2.sh --apply"
assert_not_contains "C14: hint does not offer /handoffx-tidy --apply" "$out_14" "/handoffx-tidy --apply"
assert_contains "C14: hints migrate-to-v2" "$out_14" "migrate-to-v2.sh --dry-run"
assert_file_exists "C14: skill still installs despite v1 warning" \
    "$SANDBOX/.claude/skills/handoffx/SKILL.md"
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14b (D1 → P2.4): no warning when PWD has the current main file ────
setup_sandbox
PROJECT=$(mktemp -d)
cat > "$PROJECT/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
## 📦 Project Overview
test
EOF
out_14b=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14b" | grep -q "Detected legacy"; then
    echo "  ❌ C14b: warned on v2 file"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14b: no warning on v2-marker file"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14c (D1): no warning when PWD lacks any main file ─────────────────
setup_sandbox
PROJECT=$(mktemp -d)
out_14c=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14c" | grep -q "Detected legacy"; then
    echo "  ❌ C14c: warned without $HX_LEGACY_MAIN_FILE"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14c: no warning when no $HX_LEGACY_MAIN_FILE present"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14d (D1): HANDOFF_INSTALL_SKIP_V2_GATE=1 silences warning ──────────
setup_sandbox
PROJECT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$PROJECT/$HX_LEGACY_MAIN_FILE"
out_14d=$( (cd "$PROJECT" && HANDOFF_INSTALL_SKIP_V2_GATE=1 bash "$INSTALL" --claude) 2>&1 )
if echo "$out_14d" | grep -q "Detected legacy"; then
    echo "  ❌ C14d: gate not silenced by env var"; FAIL=$((FAIL+1))
else
    echo "  ✅ C14d: HANDOFF_INSTALL_SKIP_V2_GATE silences warning"; PASS=$((PASS+1))
fi
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 14e (P2.4 §4b-4): v3 legacy four-piece in PWD → warn, still install ─
# S:60 contract: the installer warns and continues (rc 0); refusing would block
# the very install that ships schema-upgrade.
setup_sandbox
PROJECT=$(mktemp -d)
p21_materialize "$PROJECT" || FAIL=$((FAIL+1))
ec_14e=0; out_14e=$( (cd "$PROJECT" && bash "$INSTALL" --claude) 2>&1 ) || ec_14e=$?
assert_exit "C14e: v3 legacy layout in PWD → exit 0" 0 "$ec_14e"
assert_contains "C14e: warns about the legacy four-piece layout" "$out_14e" "Detected legacy four-piece layout"
assert_contains "C14e: hints schema-upgrade" "$out_14e" "/handoffx-tidy schema-upgrade"
assert_file_exists "C14e: skill still installs despite the warning" "$SANDBOX/.claude/skills/handoffx/SKILL.md"
rm -rf "$PROJECT"
teardown_sandbox

# ── Case 15: 过时 Codex alias 命名 sweep（防升级残留 → 重复命令）─────────────
# Regression：< May-2026 install.sh 用 `source-command-handoff-*` 命名 Codex
# alias，现用 `handoffx-*`；install_codex_aliases / cleanup_codex_legacy_mirrors
# / --uninstall 三处都未 sweep 旧名 → 用户在 Codex 看到 $source-command-handoff-*
# 与 $handoff-* 重复对（Boss 实测 + Codex stop-time 连环命中）。三处 sweep 此前
# 无任何测试覆盖——bug 当初就因没测才 ship（Gotcha #20）。
setup_sandbox
# C15a: install 路径 sweep 当前 .agents + legacy ~/.codex 两处旧名
mkdir -p "$SANDBOX/.agents/skills/source-command-handoff-recall" \
         "$SANDBOX/.agents/skills/source-command-handoff-init" \
         "$SANDBOX/.codex/skills/source-command-handoff-tidy"
exit_code=$(run_install --codex)
assert_exit "C15a: --codex install exit 0（旧名存在不应 abort）" 0 "$exit_code"
for stale in \
    "$SANDBOX/.agents/skills/source-command-handoff-recall" \
    "$SANDBOX/.agents/skills/source-command-handoff-init" \
    "$SANDBOX/.codex/skills/source-command-handoff-tidy"; do
    if [ -e "$stale" ]; then
        echo "  ❌ C15a: 过时 alias 未清除：$stale"; FAIL=$((FAIL+1))
    else
        echo "  ✅ C15a: 过时 alias 已清除：${stale##*/}"; PASS=$((PASS+1))
    fi
done
assert_file_exists "C15a: canonical handoffx-recall alias 未被误删" \
    "$SANDBOX/.agents/skills/handoffx-recall/SKILL.md"
teardown_sandbox

# C15b: --uninstall 也 sweep 当前 .agents 旧名（卸载不留孤儿）
setup_sandbox
run_install --codex > /dev/null 2>&1
mkdir -p "$SANDBOX/.agents/skills/source-command-handoff-memory"
bash "$INSTALL" --uninstall > /dev/null 2>&1
if [ -e "$SANDBOX/.agents/skills/source-command-handoff-memory" ]; then
    echo "  ❌ C15b: --uninstall 残留过时 alias"; FAIL=$((FAIL+1))
else
    echo "  ✅ C15b: --uninstall 已 sweep 过时 alias"; PASS=$((PASS+1))
fi
if [ -e "$SANDBOX/.agents/skills/handoffx" ]; then
    echo "  ❌ C15b: --uninstall 未移除 Codex skill"; FAIL=$((FAIL+1))
else
    echo "  ✅ C15b: --uninstall 移除 Codex skill"; PASS=$((PASS+1))
fi
teardown_sandbox

# C15c: --uninstall 也清 legacy ~/.codex/skills 旧名 + canonical mirror
setup_sandbox
mkdir -p "$SANDBOX/.codex/skills/source-command-handoff-recall" \
         "$SANDBOX/.codex/skills/handoffx"
bash "$INSTALL" --uninstall > /dev/null 2>&1
for legacy in \
    "$SANDBOX/.codex/skills/source-command-handoff-recall" \
    "$SANDBOX/.codex/skills/handoffx"; do
    if [ -e "$legacy" ]; then
        echo "  ❌ C15c: --uninstall 残留 legacy：$legacy"; FAIL=$((FAIL+1))
    else
        echo "  ✅ C15c: --uninstall 清除 legacy：${legacy##*/}"; PASS=$((PASS+1))
    fi
done
teardown_sandbox

# ══ P2.2a Task 2：事务式安装 + 名集合（Decision 0028 决策 3–4）══════════════════
# 旧名全集：独立于 install.sh 的期望值（种植用的 L4 清扫操作数）。名字与 install.sh
# 的 OLD_* 若不一致，种下的旧物会残留 → 下面 D1 断言变红。
T_OLD_SKILL="handoff"
T_OLD_SHIMS="handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md hand-off.md"
T_OLD_ALIASES="$T_OLD_SKILL handoff-recall handoff-tidy handoff-memory handoff-init"
T_OLD_PREFIXED="source-command-handoff-recall source-command-handoff-init"
T_OLD_MISC=".claude/handoff-scripts"
UNRELATED="${T_OLD_SKILL}-something-else"   # 共享旧前缀的无关 skill，必须原样保留
NEW_SHIMS_T="handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md"
NEW_ALIASES_T="handoffx-recall handoffx-tidy handoffx-memory handoffx-init"
FAIL_POINTS="cleanup skill-copy shim-copy alias-gen second-cli"

# 内容 + 目录结构 + 可执行位快照（cksum 在 macOS / Linux 都有）
snap() {
    (cd "$1" && {
        find . -type f -exec cksum {} + | LC_ALL=C sort -k3
        find . -type d | LC_ALL=C sort
        find . -type f -perm -u+x | LC_ALL=C sort | sed 's/^/x /'
    })
}
# snap minus the install's own backups: since Z3 a successful run keeps its
# bak.<ts>, so "reinstall is byte-identical" is a statement about the installed
# tree, not about the backup store that grows by one dir per run.
snap_inst() { snap "$1" | grep -v -F './.handoffx-install'; }

# 只含 /usr/bin:/bin + 指定假 CLI 的 PATH，使 auto 检测与本机装了什么无关
iso_path() {   # iso_path <cli>... → 打印 PATH
    local b="$SANDBOX/bin" c
    mkdir -p "$b"
    for c in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$b/$c"; chmod +x "$b/$c"; done
    echo "$b:/usr/bin:/bin"
}

# 在三家根（+ legacy ~/.codex/skills）种下 OLD_* 全集 + 无关 skill + P2.1 的 handoffx-tidy alias
seed_old_world() {
    local r n
    for r in "$SANDBOX/.claude/skills" "$SANDBOX/.config/opencode/skills" \
             "$SANDBOX/.agents/skills" "$SANDBOX/.codex/skills"; do
        for n in $T_OLD_ALIASES $T_OLD_PREFIXED; do
            mkdir -p "$r/$n"; echo "old $n" > "$r/$n/SKILL.md"
        done
    done
    for r in "$SANDBOX/.claude/commands" "$SANDBOX/.config/opencode/command" \
             "$SANDBOX/.config/opencode/commands"; do
        mkdir -p "$r"
        for n in $T_OLD_SHIMS; do echo "old $n" > "$r/$n"; done
    done
    mkdir -p "$SANDBOX/$T_OLD_MISC"; echo "old" > "$SANDBOX/$T_OLD_MISC/x.sh"
    mkdir -p "$SANDBOX/.claude/skills/$UNRELATED" "$SANDBOX/.agents/skills/$UNRELATED"
    echo "user skill" > "$SANDBOX/.claude/skills/$UNRELATED/SKILL.md"
    echo "user skill" > "$SANDBOX/.agents/skills/$UNRELATED/SKILL.md"
    mkdir -p "$SANDBOX/.agents/skills/handoffx-tidy"
    printf -- '---\nname: handoffx-tidy\n---\nP2.1 alias body\n' > "$SANDBOX/.agents/skills/handoffx-tidy/SKILL.md"
}

# 列出沙箱里仍存在的种植旧物（空 = 全清）
old_leftovers() {
    local r n
    for r in "$SANDBOX/.claude/skills" "$SANDBOX/.config/opencode/skills" \
             "$SANDBOX/.agents/skills" "$SANDBOX/.codex/skills"; do
        for n in $T_OLD_ALIASES $T_OLD_PREFIXED; do [ -e "$r/$n" ] && echo "$r/$n"; done
    done
    for r in "$SANDBOX/.claude/commands" "$SANDBOX/.config/opencode/command" \
             "$SANDBOX/.config/opencode/commands"; do
        for n in $T_OLD_SHIMS; do [ -e "$r/$n" ] && echo "$r/$n"; done
    done
    [ -e "$SANDBOX/$T_OLD_MISC" ] && echo "$SANDBOX/$T_OLD_MISC"
    return 0
}

assert_eq() {   # assert_eq <label> <expected> <actual>
    if [ "$2" = "$3" ]; then echo "  ✅ $1"; PASS=$((PASS+1))
    else echo "  ❌ $1"; diff <(echo "$2") <(echo "$3") | head -8 | sed 's/^/      /'; FAIL=$((FAIL+1)); fi
}

assert_absent() {
    if [ -e "$2" ]; then echo "  ❌ $1: 不应存在 $2"; FAIL=$((FAIL+1))
    else echo "  ✅ $1"; PASS=$((PASS+1)); fi
}

# ── D1：默认安装（三家 CLI 均检测到）→ OLD_* 全清、无关保留、P2.1 alias 被替换、NEW 齐全
setup_sandbox
seed_old_world
unrel_before=$(snap "$SANDBOX/.claude/skills/$UNRELATED"; snap "$SANDBOX/.agents/skills/$UNRELATED")
P=$(iso_path claude opencode codex)
ec=0; PATH="$P" "$BASH" "$INSTALL" > /dev/null 2>&1 || ec=$?
assert_exit "D1: default install over seeded OLD world exit 0" 0 "$ec"
assert_eq "D1: every seeded OLD_* path removed across all roots" "" "$(old_leftovers)"
assert_eq "D1: unrelated ${UNRELATED} untouched" "$unrel_before" \
    "$(snap "$SANDBOX/.claude/skills/$UNRELATED"; snap "$SANDBOX/.agents/skills/$UNRELATED")"
assert_not_contains "D1: P2.1 handoffx-tidy alias content replaced" \
    "$(cat "$SANDBOX/.agents/skills/handoffx-tidy/SKILL.md")" "P2.1 alias body"
assert_contains "D1: handoffx-tidy alias now points at handoffx" \
    "$(cat "$SANDBOX/.agents/skills/handoffx-tidy/SKILL.md")" "Use skill: handoffx."
missing=""
for f in "$SANDBOX/.claude/skills/handoffx/SKILL.md" "$SANDBOX/.config/opencode/skills/handoffx/SKILL.md" \
         "$SANDBOX/.agents/skills/handoffx/SKILL.md" "$SANDBOX/.config/opencode/commands/handoffx.md"; do
    [ -f "$f" ] || missing="$missing $f"
done
for s in $NEW_SHIMS_T; do
    [ -f "$SANDBOX/.claude/commands/$s" ] || missing="$missing claude:$s"
    [ -f "$SANDBOX/.config/opencode/commands/$s" ] || missing="$missing opencode:$s"
done
for a in $NEW_ALIASES_T; do [ -f "$SANDBOX/.agents/skills/$a/SKILL.md" ] || missing="$missing codex:$a"; done
assert_eq "D1: all NEW_* present (3 skills, 4+5 shims, 4 aliases)" "" "$missing"
assert_absent "D1: Claude has no commands/handoffx.md" "$SANDBOX/.claude/commands/handoffx.md"
assert_eq "D1: journal removed after commit" "" "$(ls -d "$SANDBOX/.handoffx-install"/journal.* 2>/dev/null)"
assert_eq "D1: the backup of the displaced OLD world is kept (Z3)" "1" "$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | wc -l | tr -d ' ')"

# ── D2：重装幂等（第二次运行后整棵沙箱 byte-identical）
first=$(snap_inst "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" > /dev/null 2>&1 || ec=$?
assert_exit "D2: reinstall exit 0" 0 "$ec"
assert_eq "D2: reinstall is byte-identical" "$first" "$(snap_inst "$SANDBOX")"
teardown_sandbox

# ── D1b：只检测到 Claude 的默认安装也清扫所有根；handoffx-tidy alias 不被其他 CLI 碰
setup_sandbox
seed_old_world
tidy_before=$(cat "$SANDBOX/.agents/skills/handoffx-tidy/SKILL.md")
ec=0; PATH="$(iso_path claude)" "$BASH" "$INSTALL" > /dev/null 2>&1 || ec=$?
assert_exit "D1b: claude-only default install exit 0" 0 "$ec"
assert_eq "D1b: OLD_* removed in OpenCode/Codex roots too (cleanup independent of CLI)" "" "$(old_leftovers)"
assert_eq "D1b: P2.1 handoffx-tidy alias untouched by non-Codex install" "$tidy_before" \
    "$(cat "$SANDBOX/.agents/skills/handoffx-tidy/SKILL.md")"
assert_absent "D1b: no Codex skill installed" "$SANDBOX/.agents/skills/handoffx"
teardown_sandbox

# ── D3：Claude 不装主命令 shim（Gotcha #5）；OpenCode 必须装（Gotcha #9）
setup_sandbox
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
assert_absent "D3: --claude produces no commands/handoffx.md" "$SANDBOX/.claude/commands/handoffx.md"
PATH="$P" "$BASH" "$INSTALL" --opencode > /dev/null 2>&1 || true
assert_file_exists "D3: --opencode produces commands/handoffx.md" "$SANDBOX/.config/opencode/commands/handoffx.md"
teardown_sandbox

# ── D4：--project 不动项目目录以外的任何东西（全局根含种植旧物，校验和不变）
setup_sandbox
seed_old_world
PROJECT_DIR=$(mktemp -d)
P=$(iso_path claude opencode codex)
global_before=$(snap "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" --project "$PROJECT_DIR" > /dev/null 2>&1 || ec=$?
assert_exit "D4: --project exit 0" 0 "$ec"
assert_eq "D4: --project leaves every global root byte-identical" "$global_before" "$(snap "$SANDBOX")"
for f in .claude/skills/handoffx/SKILL.md .claude/commands/handoffx-recall.md \
         .opencode/skills/handoffx/SKILL.md .opencode/commands/handoffx.md \
         .agents/skills/handoffx/SKILL.md .agents/skills/handoffx-tidy/SKILL.md; do
    assert_file_exists "D4: project gets $f" "$PROJECT_DIR/$f"
done
rm -rf "$PROJECT_DIR"
teardown_sandbox

# ── D5：注入失败 → 安装前状态逐字节还原 + exit≠0；还原全部成功时 journal/bak 一并删除
# （有还原失败才保留 journal/bak 供人工检查——见 install.sh 头注释）
for pt in $FAIL_POINTS; do
    setup_sandbox
    seed_old_world
    mkdir -p "$SANDBOX/.claude/skills/handoffx"            # 上一版 handoffx 安装（将被覆盖的目标）
    echo "prior handoffx" > "$SANDBOX/.claude/skills/handoffx/SKILL.md"
    P=$(iso_path)
    before=$(snap "$SANDBOX")
    ec=0
    out=$(PATH="$P" HANDOFFX_INSTALL_FAIL_AT="$pt" "$BASH" "$INSTALL" --claude --opencode --codex 2>&1) || ec=$?
    assert_exit "D5[$pt]: injected failure exits 1" 1 "$ec"
    assert_contains "D5[$pt]: failure came from the hook" "$out" "injected failure at $pt"
    assert_eq "D5[$pt]: pre-install state restored byte-for-byte" "$before" "$(snap "$SANDBOX")"
    assert_absent "D5[$pt]: journal/bak cleaned after full restore" "$SANDBOX/.handoffx-install"
    teardown_sandbox
done

# ── D5b：非注入的真实失败（OpenCode 目标父路径是文件 → mkdir 失败）同样整体还原
setup_sandbox
seed_old_world
mkdir -p "$SANDBOX/.config"; rm -rf "$SANDBOX/.config/opencode"; echo "not a dir" > "$SANDBOX/.config/opencode"
P=$(iso_path)
before=$(snap "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude --opencode > /dev/null 2>&1 || ec=$?
assert_exit "D5b: real mid-install failure exits 1" 1 "$ec"
assert_eq "D5b: real failure restores pre-install state" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── D6：跨 CLI 顺序——先 --codex，再 --claude / --opencode，Codex 树 byte-identical 且完整
setup_sandbox
seed_old_world
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --codex > /dev/null 2>&1 || true
codex_tree() { (cd "$SANDBOX/.agents/skills" && for d in handoffx*; do snap "$d" | sed "s#^#$d #"; done); }
codex_before=$(codex_tree)
assert_eq "D6: Codex tree complete (skill + 4 aliases)" "handoffx handoffx-init handoffx-memory handoffx-recall handoffx-tidy" \
    "$(cd "$SANDBOX/.agents/skills" && echo handoffx*)"
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
PATH="$P" "$BASH" "$INSTALL" --opencode > /dev/null 2>&1 || true
assert_eq "D6: Codex tree byte-identical after --claude and --opencode" "$codex_before" "$(codex_tree)"
teardown_sandbox

# ── D7：--journal-only 打印全部根、op 全在沙箱内、零改动
setup_sandbox
seed_old_world
WIN_APPDATA="$SANDBOX/win/AppData/Roaming"; mkdir -p "$WIN_APPDATA/Claude"
P=$(iso_path)
before=$(snap "$SANDBOX")
ec=0
jo=$(PATH="$P" HANDOFF_TEST_PLATFORM=wsl HANDOFF_TEST_WSL_APPDATA="$WIN_APPDATA" \
     "$BASH" "$INSTALL" --journal-only --claude --opencode --codex 2>/dev/null) || ec=$?
assert_exit "D7: --journal-only exit 0" 0 "$ec"
# 根按物理路径归一（macOS 的 mktemp 目录在 /var → /private/var 链接之下）；bak 目录仍在 $HOME 下
SP=$(cd "$SANDBOX" && pwd -P)
for r in .claude/skills .claude/commands .config/opencode/skills .config/opencode/command \
         .config/opencode/commands .agents/skills .codex/skills win/AppData/Roaming/Claude/skills \
         win/AppData/Roaming/Claude/commands; do
    assert_contains "D7: prints root $r" "$jo" "root $SP/$r"
done
assert_eq "D7: every line is root/bak/absent/new on a path inside the sandbox" "" \
    "$(echo "$jo" | grep -v -E "^(root|bak|absent|new) $SP/")"
assert_contains "D7: OLD hit listed as bak" "$jo" "bak $SP/.claude/commands/hand-off.md $SANDBOX/.handoffx-install/bak."
assert_contains "D7: missing target listed as absent" "$jo" "absent $SP/win/AppData/Roaming/Claude/skills/handoffx"
assert_eq "D7: --journal-only changed nothing" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── X2/X5 (v4.1.1)：从源码树跑不提自举；--journal-only 给图例与"无动作"的根
# Why stderr: stdout stays pure op lines (D7 / W1 contract — scripts parse it);
# the legend and per-root verdicts are for the human reading the terminal.
setup_sandbox
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
SP=$(cd "$SANDBOX" && pwd -P)
ec=0; je=$(cd "$ROOT_DIR" && PATH="$P" "$BASH" "$INSTALL" --journal-only --claude 2>&1 >/dev/null) || ec=$?
assert_exit "X5: --journal-only exit 0" 0 "$ec"
assert_contains "X2: source tree named explicitly" "$je" "源码树: $ROOT_DIR"
assert_not_contains "X2: no bootstrap message from inside the source tree" "$je" "自举"
for l in "root   = 安装根" "bak    = 将备份" "absent = 预期不存在" "new    = 将新建"; do
    assert_contains "X5: legend line '$l'" "$je" "$l"
done
assert_contains "X5: a root with zero ops says so" "$je" "$SP/.codex/skills: 已是最新，无动作"
assert_not_contains "X5: a root with ops is not called idle" "$je" "$SP/.claude/skills: 已是最新"
teardown_sandbox

# ── D8：assert_disjoint 自检——往 OLD 集注入一个 NEW 名 → exit 2，且不动文件
setup_sandbox
before=$(snap "$SANDBOX")
ec=0; out=$(HANDOFFX_TEST_OLD_EXTRA=handoffx-tidy "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "D8: OLD/NEW overlap → exit 2" 2 "$ec"
assert_contains "D8: overlap named" "$out" "name-set overlap: 'handoffx-tidy'"
assert_eq "D8: overlap abort touched nothing" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── D9：清扫根下的换行怪名目录 → 拒绝整次调用（exit 1），诱饵与沙箱均不变
# 攻击形态：前缀族目录名 "<OLD 前缀>\nvictim.txt"。单个路径分量不能含 "/"，所以按行
# 拆出的第二段是**相对 cwd** 的名字；安装器在 cwd 下跑时它会被当成 sweep 目标移入
# bak、随提交删除。cwd = 沙箱，诱饵就放在 cwd。
setup_sandbox
seed_old_world
DECOY="$SANDBOX/victim.txt"; echo "do not touch" > "$DECOY"
mkdir -p "$SANDBOX/.codex/skills/source-command-handoff-"$'\n'"victim.txt"
P=$(iso_path)
before=$(snap "$SANDBOX")
ec=0; out=$(cd "$SANDBOX" && PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "D9: newline-named sweep candidate → exit 1" 1 "$ec"
assert_contains "D9: refusal is explicit" "$out" "refusing suspicious path"
assert_file_exists "D9: cwd decoy survives" "$DECOY"
assert_eq "D9: refusal changed nothing (no bak / journal left behind)" "$before" "$(snap "$SANDBOX")"
ec=0; jo=$(cd "$SANDBOX" && PATH="$P" "$BASH" "$INSTALL" --journal-only --claude 2>&1) || ec=$?
assert_exit "D9: --journal-only refuses too" 1 "$ec"
assert_eq "D9: no op line names a non-absolute (split-off) path" "" \
    "$(echo "$jo" | grep -E '^(root|bak|absent|new) ' | grep -v -E '^(root|bak|absent|new) /')"
teardown_sandbox

# ══ 静默失败复核 F1–F10：每例先红后绿 ════════════════════════════════════════
# root 绕过 chmod，权限类用例在 EUID=0 下不可复现（Gotcha #15）
IS_ROOT=0; [ "${EUID:-$(id -u)}" -eq 0 ] && IS_ROOT=1

# ── F1：回滚删不掉本次新建项 → 必须报部分还原失败、保留 journal/bak，且不把备份 mv 进残留目录
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ F1 SKIPPED (root bypasses chmod 555 — Gotcha #15)"
else
    setup_sandbox
    SRC_COPY="$SANDBOX/src"; mkdir -p "$SRC_COPY/skills"
    cp "$INSTALL" "$SRC_COPY/install.sh"; cp -R "$SKILL_SRC" "$SRC_COPY/skills/handoffx"
    mkdir -p "$SRC_COPY/skills/handoffx/locked"; echo x > "$SRC_COPY/skills/handoffx/locked/f"
    chmod 555 "$SRC_COPY/skills/handoffx/locked"
    mkdir -p "$SANDBOX/.claude/skills/handoffx"; echo "prior handoffx" > "$SANDBOX/.claude/skills/handoffx/SKILL.md"
    ec=0
    out=$(PATH="$(iso_path)" HANDOFFX_INSTALL_FAIL_AT=skill-copy "$BASH" "$SRC_COPY/install.sh" --claude 2>&1) || ec=$?
    assert_exit "F1: undeletable new item → exit 1" 1 "$ec"
    assert_contains "F1: partial-restore failure reported" "$out" "部分还原失败"
    assert_eq "F1: journal preserved" "1" "$(ls -d "$SANDBOX/.handoffx-install"/journal.* 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "F1: bak preserved" "1" "$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | wc -l | tr -d ' ')"
    assert_absent "F1: backup not nested into leftover dir" "$SANDBOX/.claude/skills/handoffx/handoffx/SKILL.md"
    chmod -R u+rwx "$SANDBOX"
    teardown_sandbox
fi

# ── F2：已有 Codex alias 是外指符号链接 → 不得写穿；回滚恢复链接，外部文件始终不变
setup_sandbox
EXT="$SANDBOX/external/recall"; mkdir -p "$EXT"; echo "external marker" > "$EXT/SKILL.md"
mkdir -p "$SANDBOX/.agents/skills"; ln -s "$EXT" "$SANDBOX/.agents/skills/handoffx-recall"
P=$(iso_path)
ec=0; PATH="$P" HANDOFFX_INSTALL_FAIL_AT=alias-gen "$BASH" "$INSTALL" --codex > /dev/null 2>&1 || ec=$?
assert_exit "F2: injected alias-gen failure exits 1" 1 "$ec"
assert_eq "F2: external SKILL.md unchanged after rollback" "external marker" "$(cat "$EXT/SKILL.md")"
assert_eq "F2: rollback restored the symlink" "$EXT" "$(readlink "$SANDBOX/.agents/skills/handoffx-recall")"
ec=0; PATH="$P" "$BASH" "$INSTALL" --codex > /dev/null 2>&1 || ec=$?
assert_exit "F2: --codex over symlinked alias exit 0" 0 "$ec"
assert_eq "F2: external SKILL.md unchanged after install" "external marker" "$(cat "$EXT/SKILL.md")"
a="$SANDBOX/.agents/skills/handoffx-recall"
assert_eq "F2: alias is now a real directory" "dir" "$([ -d "$a" ] && [ ! -L "$a" ] && echo dir)"
teardown_sandbox

# ── F3：OpenCode skills 根经符号链接指向 Claude 根 → 不得嵌套复制
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills" "$SANDBOX/.config/opencode"
ln -s ../../.claude/skills "$SANDBOX/.config/opencode/skills"
P=$(iso_path)
for i in 1 2; do
    ec=0; PATH="$P" "$BASH" "$INSTALL" --claude --opencode > /dev/null 2>&1 || ec=$?
    assert_exit "F3[$i]: shared physical skills root exit 0" 0 "$ec"
    assert_absent "F3[$i]: no nested skill copy" "$SANDBOX/.claude/skills/handoffx/handoffx"
    assert_file_exists "F3[$i]: skill installed once" "$SANDBOX/.claude/skills/handoffx/SKILL.md"
done
teardown_sandbox

# ── F4：~/.codex/skills → ~/.agents/skills 符号链接 → 旧物清扫与 Codex 安装都不得自相冲突
setup_sandbox
mkdir -p "$SANDBOX/.agents/skills/$T_OLD_SKILL"; echo old > "$SANDBOX/.agents/skills/$T_OLD_SKILL/SKILL.md"
mkdir -p "$SANDBOX/.codex"; ln -s ../.agents/skills "$SANDBOX/.codex/skills"
P=$(iso_path)
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || ec=$?
assert_exit "F4: --claude with aliased legacy root exit 0" 0 "$ec"
assert_absent "F4: old skill dir swept" "$SANDBOX/.agents/skills/$T_OLD_SKILL"
for i in 1 2; do
    ec=0; PATH="$P" "$BASH" "$INSTALL" --codex > /dev/null 2>&1 || ec=$?
    assert_exit "F4[$i]: --codex with aliased legacy root exit 0" 0 "$ec"
done
assert_file_exists "F4: Codex skill present" "$SANDBOX/.agents/skills/handoffx/SKILL.md"
teardown_sandbox

# ── F5 / F6：--project 与全局开关 / --uninstall 互斥 → exit 2，什么都不动
setup_sandbox
PROJECT_DIR=$(mktemp -d)
P=$(iso_path)
for args in "--project $PROJECT_DIR --claude" "--codex --project $PROJECT_DIR" "--project $PROJECT_DIR --global"; do
    ec=0
    # shellcheck disable=SC2086  # args 是测试内构造的已知词表，需按词拆分
    PATH="$P" "$BASH" "$INSTALL" $args > /dev/null 2>&1 || ec=$?
    assert_exit "F5: '${args//$PROJECT_DIR/<dir>}' → usage error" 2 "$ec"
done
assert_absent "F5: no global install" "$SANDBOX/.claude/skills/handoffx"
assert_absent "F5: no project install" "$PROJECT_DIR/.claude"
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || ec=$?
before=$(snap "$SANDBOX")
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --project "$PROJECT_DIR" --uninstall 2>&1) || ec=$?
assert_exit "F6: --project + --uninstall → usage error" 2 "$ec"
assert_contains "F6: says project uninstall is not implemented" "$out" "项目级卸载"
assert_eq "F6: global install untouched" "$before" "$(snap "$SANDBOX")"
rm -rf "$PROJECT_DIR"
teardown_sandbox

# ── F7：上次被杀留下的 journal → 拒绝开始新事务，点名遗留物，什么都不动
setup_sandbox
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
mkdir -p "$SANDBOX/.handoffx-install"; echo "new /nowhere" > "$SANDBOX/.handoffx-install/journal.x"
before=$(snap "$SANDBOX")
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "F7: stale journal → exit 1" 1 "$ec"
assert_contains "F7: stale journal named" "$out" "$SANDBOX/.handoffx-install/journal.x"
assert_eq "F7: nothing changed" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── F8：测试钩子值是 glob → 拒收并告警；cwd 下同名目录与用户 skill 都不得被清扫
setup_sandbox
mkdir -p "$SANDBOX/cwd/precious" "$SANDBOX/.claude/skills/precious"
echo mine > "$SANDBOX/.claude/skills/precious/SKILL.md"
ec=0
out=$(cd "$SANDBOX/cwd" && PATH="$(iso_path)" HANDOFFX_TEST_OLD_EXTRA='*' "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "F8: glob hook value ignored, install exit 0" 0 "$ec"
assert_file_exists "F8: user skill 'precious' survives" "$SANDBOX/.claude/skills/precious/SKILL.md"
assert_contains "F8: warning printed" "$out" "HANDOFFX_TEST_OLD_EXTRA"
teardown_sandbox

# ── F9：--template 目标不存在 → 安装前就 usage error，不留半截
setup_sandbox
ec=0; out=$(PATH="$(iso_path)" "$BASH" "$INSTALL" --claude --template "$SANDBOX/nope" 2>&1) || ec=$?
assert_exit "F9: missing --template dir → exit 2" 2 "$ec"
assert_absent "F9: no install happened" "$SANDBOX/.claude/skills/handoffx"
teardown_sandbox

# ── F10：清扫根不可读 → fail-closed（Gotcha #24），旧物与新目标都不动
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ F10 SKIPPED (root bypasses chmod 600 — Gotcha #15)"
else
    setup_sandbox
    LOCKED="$SANDBOX/.config/opencode/skills"
    mkdir -p "$LOCKED/$T_OLD_SKILL"; echo old > "$LOCKED/$T_OLD_SKILL/SKILL.md"
    chmod 600 "$LOCKED"
    trap 'chmod 700 "$LOCKED" 2>/dev/null' EXIT
    ec=0; out=$(PATH="$(iso_path)" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
    chmod 700 "$LOCKED"; trap - EXIT
    assert_exit "F10: unreadable sweep root → exit 1" 1 "$ec"
    assert_contains "F10: names the unreadable root" "$out" "无法读取清扫根"
    assert_file_exists "F10: old item left in place" "$LOCKED/$T_OLD_SKILL/SKILL.md"
    assert_absent "F10: no install happened" "$SANDBOX/.claude/skills/handoffx"
    teardown_sandbox
fi

# ══ 复核 N1–N7：每例先红后绿 ══════════════════════════════════════════════════

# ── N2a：legacy ~/.codex/skills 经链接就是 Claude 的 skills 根 → --codex 的 NEW 名去重不得删 Claude 的安装
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills" "$SANDBOX/.codex"; ln -s ../.claude/skills "$SANDBOX/.codex/skills"
SP=$(cd "$SANDBOX" && pwd -P)
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "N2a: --codex with legacy root = Claude skills root exit 0" 0 "$ec"
assert_file_exists "N2a: Claude's skill survives" "$SANDBOX/.claude/skills/handoffx/SKILL.md"
assert_not_contains "N2a: Claude's skill never swept" "$out" "移除：$SP/.claude/skills/handoffx"
teardown_sandbox

# ── N2b：同一布局下 --claude --codex 重装 → 不得把刚装的 skill 当旧物，重装逐字节一致
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills" "$SANDBOX/.codex"; ln -s ../.claude/skills "$SANDBOX/.codex/skills"
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude --codex > /dev/null 2>&1 || true
first=$(snap_inst "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude --codex > /dev/null 2>&1 || ec=$?
assert_exit "N2b: reinstall with legacy root = Claude skills root exit 0" 0 "$ec"
assert_eq "N2b: reinstall byte-identical" "$first" "$(snap_inst "$SANDBOX")"
teardown_sandbox

# ── N2c：OpenCode 单数 command/ 经链接就是复数 commands/ → 不得清扫刚装的 NEW shim
setup_sandbox
mkdir -p "$SANDBOX/.config/opencode/commands"; ln -s commands "$SANDBOX/.config/opencode/command"
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude --opencode > /dev/null 2>&1 || true
first=$(snap_inst "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude --opencode > /dev/null 2>&1 || ec=$?
assert_exit "N2c: reinstall with command/ = commands/ exit 0" 0 "$ec"
assert_eq "N2c: reinstall byte-identical" "$first" "$(snap_inst "$SANDBOX")"
teardown_sandbox

# ── N2d：Claude 与 OpenCode 的 commands 是同一物理目录 → 主命令 shim 要求互斥，改动前 exit 2
setup_sandbox
mkdir -p "$SANDBOX/.claude/commands" "$SANDBOX/.config/opencode"
ln -s ../../.claude/commands "$SANDBOX/.config/opencode/commands"
P=$(iso_path)
before=$(snap "$SANDBOX")
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude --opencode 2>&1) || ec=$?
assert_exit "N2d: shared commands dir → exit 2" 2 "$ec"
assert_contains "N2d: names the contradiction" "$out" "同一物理目录"
assert_eq "N2d: refusal changed nothing" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── N1：清扫根的上级目录不可进入 → [ -d ] 假阴性不得当"根不存在"放行
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ N1 SKIPPED (root bypasses chmod 600 — Gotcha #15)"
else
    setup_sandbox
    LOCKED="$SANDBOX/.agents"
    mkdir -p "$LOCKED/skills/$T_OLD_SKILL"; echo old > "$LOCKED/skills/$T_OLD_SKILL/SKILL.md"
    P=$(iso_path)
    before=$(snap "$SANDBOX")
    chmod 600 "$LOCKED"
    trap 'chmod 700 "$LOCKED" 2>/dev/null' EXIT
    # 显式 /bin/bash + UTF-8：bash 3.2 才会把 $var 后紧跟的全角字节吞进变量名（Gotcha #26）
    ec=0; out=$(PATH="$P" LC_ALL=en_US.UTF-8 /bin/bash "$INSTALL" --claude 2>&1) || ec=$?
    chmod 700 "$LOCKED"; trap - EXIT
    assert_exit "N1: unsearchable parent of sweep root → exit 1" 1 "$ec"
    assert_contains "N1: names the unsearchable parent" "$out" "上级目录不可进入"
    assert_contains "N1: message carries the parent path" "$out" "上级目录不可进入：${LOCKED}）"
    assert_eq "N1: nothing changed" "$before" "$(snap "$SANDBOX")"
    teardown_sandbox
fi

# ── N3：两家 CLI 共用物理 skills 根 → --journal-only 每个目标只出现一次（与实际 journal 一致）
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills" "$SANDBOX/.config/opencode"
ln -s ../../.claude/skills "$SANDBOX/.config/opencode/skills"
SP=$(cd "$SANDBOX" && pwd -P)
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude --opencode > /dev/null 2>&1 || true
jo=$(PATH="$P" "$BASH" "$INSTALL" --journal-only --claude --opencode 2>&1) || true
assert_eq "N3: shared skill target backed up once" "1" \
    "$(echo "$jo" | grep -c "^bak $SP/.claude/skills/handoffx ")"
assert_eq "N3: shared skill target created once" "1" \
    "$(echo "$jo" | grep -cx "new $SP/.claude/skills/handoffx")"
teardown_sandbox

# ── N4：备份与原物都不见了 → 回滚必须报失败，不得声称已还原
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills/handoffx"; echo "prior handoffx" > "$SANDBOX/.claude/skills/handoffx/SKILL.md"
P=$(iso_path)
# 假 cp：模拟备份在事务中途丢失，再让拷贝失败触发回滚
printf '#!/bin/sh\nrm -rf "$HOME"/.handoffx-install/bak.*/*\nexit 1\n' > "$SANDBOX/bin/cp"; chmod +x "$SANDBOX/bin/cp"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "N4: lost backup → exit 1" 1 "$ec"
assert_contains "N4: lost backup reported" "$out" "备份与原物均不存在"
assert_not_contains "N4: no false full-restore claim" "$out" "已还原到安装前状态"
teardown_sandbox

# ── N5：--template 目录不可写 → 安装前 usage error，不留半截
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ N5 SKIPPED (root bypasses chmod 555 — Gotcha #15)"
else
    setup_sandbox
    TPL="$SANDBOX/tpl"; mkdir -p "$TPL"; chmod 555 "$TPL"
    trap 'chmod 755 "$TPL" 2>/dev/null' EXIT
    ec=0; PATH="$(iso_path)" "$BASH" "$INSTALL" --claude --template "$TPL" > /dev/null 2>&1 || ec=$?
    chmod 755 "$TPL"; trap - EXIT
    assert_exit "N5: unwritable --template dir → exit 2" 2 "$ec"
    assert_absent "N5: no install happened" "$SANDBOX/.claude/skills/handoffx"
    teardown_sandbox
fi

# ── N6：--uninstall 与 --template 同用 → usage error，不静默忽略模板
setup_sandbox
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
before=$(snap "$SANDBOX")
ec=0; PATH="$P" "$BASH" "$INSTALL" --uninstall --template "$SANDBOX" > /dev/null 2>&1 || ec=$?
assert_exit "N6: --uninstall + --template → exit 2" 2 "$ec"
assert_eq "N6: nothing uninstalled" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ── N7：事务目录位置被普通文件占用 → 明确报错 exit 1，什么都不动
setup_sandbox
echo "user file" > "$SANDBOX/.handoffx-install"
P=$(iso_path)
before=$(snap "$SANDBOX")
ec=0; out=$(PATH="$P" LC_ALL=en_US.UTF-8 /bin/bash "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "N7: txn dir occupied by a file → exit 1" 1 "$ec"
assert_contains "N7: occupation reported" "$out" "事务目录被非目录占用"
assert_contains "N7: message carries the occupied path" "$out" "事务目录被非目录占用：$SANDBOX/.handoffx-install（"
assert_eq "N7: nothing changed" "$before" "$(snap "$SANDBOX")"
teardown_sandbox

# ══ 复核 R2–R3：每例先红后绿 ══════════════════════════════════════════════════

# ── R2a：清扫根本身是链接、指进不可进入的目录 → [ -d 链接 ] 假阴性不得退到链接父目录放行
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ R2a SKIPPED (root bypasses chmod 600 — Gotcha #15)"
else
    setup_sandbox
    LOCKED="$SANDBOX/elsewhere/locked"
    mkdir -p "$LOCKED/skills/$T_OLD_SKILL" "$SANDBOX/.codex"; echo old > "$LOCKED/skills/$T_OLD_SKILL/SKILL.md"
    ln -s "$LOCKED/skills" "$SANDBOX/.codex/skills"
    P=$(iso_path)
    before=$(snap "$SANDBOX")
    chmod 600 "$LOCKED"
    trap 'chmod 700 "$LOCKED" 2>/dev/null' EXIT
    ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
    chmod 700 "$LOCKED"; trap - EXIT
    assert_exit "R2a: symlinked sweep root into unsearchable dir → exit 1" 1 "$ec"
    assert_contains "R2a: names the unreadable sweep root" "$out" "无法读取清扫根"
    assert_eq "R2a: nothing changed" "$before" "$(snap "$SANDBOX")"
    teardown_sandbox
fi

# ── R2b：Claude skills 根是指进不可进入目录的链接 → --uninstall 不得报"卸载完成"却留下安装
if [ "$IS_ROOT" = "1" ]; then
    echo "  ➖ R2b SKIPPED (root bypasses chmod 600 — Gotcha #15)"
else
    setup_sandbox
    LOCKED="$SANDBOX/elsewhere/locked"
    mkdir -p "$LOCKED/skills" "$SANDBOX/.claude"; ln -s "$LOCKED/skills" "$SANDBOX/.claude/skills"
    P=$(iso_path)
    PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
    before=$(snap "$SANDBOX")
    chmod 600 "$LOCKED"
    trap 'chmod 700 "$LOCKED" 2>/dev/null' EXIT
    ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --uninstall 2>&1) || ec=$?
    chmod 700 "$LOCKED"; trap - EXIT
    assert_exit "R2b: uninstall through link into unsearchable dir → exit 1" 1 "$ec"
    assert_contains "R2b: names the unreadable sweep root" "$out" "无法读取清扫根"
    assert_file_exists "R2b: installed skill untouched" "$LOCKED/skills/handoffx/SKILL.md"
    assert_eq "R2b: nothing changed" "$before" "$(snap "$SANDBOX")"
    teardown_sandbox
fi

# ── R3：Claude 与 OpenCode 共用 commands 目录，但本次只装 Codex → 不碰该目录就不该拒绝
setup_sandbox
mkdir -p "$SANDBOX/.claude/commands" "$SANDBOX/.config/opencode"
ln -s ../../.claude/commands "$SANDBOX/.config/opencode/commands"
P=$(iso_path)
ec=0; PATH="$P" "$BASH" "$INSTALL" --codex > /dev/null 2>&1 || ec=$?
assert_exit "R3: --codex alone with shared commands dir → exit 0" 0 "$ec"
assert_file_exists "R3: Codex installed" "$SANDBOX/.agents/skills/handoffx/SKILL.md"
# Claude 的主命令 shim 清扫会删掉 OpenCode 必需的那份，单装 Claude 仍须拒绝
ec=0; PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || ec=$?
assert_exit "R3: --claude alone with shared commands dir → still exit 2" 2 "$ec"
teardown_sandbox

# ══ 0066 B：只警告不删的两类重复（Gotcha #28；0065 R5）═══════════════════════════
# ── W1：canonical 根下嵌套/隐藏目录里的旧名 skill 目录（备份残留）不在清扫范围（只动直接
#        子项），但 OpenCode 递归扫 skills/**/SKILL.md、含隐藏目录、跟随符号链接，旧名会从那里
#        复活 → 每个命中各 ⚠️ 恰好一行、原样保留。不报：无 SKILL.md 的同名目录、本次要移走/
#        替换的子树里的嵌套项（报了用户去看已没了）；无残留时不得出现该警告（Gotcha #25）；
#        警告只走 stderr，--journal-only 的 stdout 仍是纯 op 行（D7 契约）
setup_sandbox
BK="$SANDBOX/.agents/skills/.backup-$T_OLD_SKILL-v1"
NESTED="$SANDBOX/.claude/skills/nested/$T_OLD_SKILL"
ELSEWHERE="$SANDBOX/elsewhere/real"
SWEPT_INNER="$SANDBOX/.agents/skills/$T_OLD_SKILL/$T_OLD_SKILL"
REPLACED_INNER="$SANDBOX/.agents/skills/handoffx/.old/$T_OLD_SKILL"
KEPT_INNER="$SANDBOX/.claude/skills/handoffx/.old/$T_OLD_SKILL"
mkdir -p "$BK/$T_OLD_SKILL" "$BK/${T_OLD_SKILL}-recall" "$BK/bare/$T_OLD_SKILL" "$BK/linkdir" "$BK/locked/$T_OLD_SKILL" \
         "$NESTED" "$ELSEWHERE" "$SWEPT_INNER" "$REPLACED_INNER" "$KEPT_INNER"
for d in "$BK/$T_OLD_SKILL" "$BK/${T_OLD_SKILL}-recall" "$BK/locked/$T_OLD_SKILL" "$NESTED" "$ELSEWHERE" \
         "$SWEPT_INNER" "$REPLACED_INNER" "$KEPT_INNER"; do
    printf -- '---\nname: %s\n---\nold\n' "${d##*/}" > "$d/SKILL.md"
done
ln -s "$ELSEWHERE" "$BK/linkdir/$T_OLD_SKILL"
# 同一物理根经两个字符串到达（legacy ~/.codex/skills → ~/.agents/skills）：只扫一次
mkdir -p "$SANDBOX/.codex"; ln -s ../.agents/skills "$SANDBOX/.codex/skills"
SP=$(cd "$SANDBOX" && pwd -P)
w1_before=$(snap "$BK"; snap "$NESTED")
[ "$IS_ROOT" = "1" ] || chmod 000 "$BK/locked"
P=$(iso_path codex)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "W1: --codex with nested old-name skill dirs (one unreadable) exit 0 — scan errors never abort" 0 "$ec"
assert_contains "W1: warns about the hidden backup copy" "$out" "⚠️  嵌套旧名 skill 目录：$SP/.agents/skills/.backup-$T_OLD_SKILL-v1/${T_OLD_SKILL}（"
assert_contains "W1: warns about the backup alias copy too" "$out" "$SP/.agents/skills/.backup-$T_OLD_SKILL-v1/${T_OLD_SKILL}-recall（"
assert_contains "W1: warns across roots, not only the installed CLI's" "$out" "$SP/.claude/skills/nested/${T_OLD_SKILL}（"
assert_contains "W1: follows symlinks like OpenCode does" "$out" "$SP/.agents/skills/.backup-$T_OLD_SKILL-v1/linkdir/${T_OLD_SKILL}（"
assert_contains "W1: inside another CLI's installed skill (not replaced this run) is still reported" "$out" "$SP/.claude/skills/handoffx/.old/${T_OLD_SKILL}（"
assert_not_contains "W1: a same-named dir without SKILL.md is not a skill" "$out" "/bare/${T_OLD_SKILL}（"
assert_not_contains "W1: nested under a swept old dir is not reported (gone after this run)" "$out" "$SP/.agents/skills/${T_OLD_SKILL}/${T_OLD_SKILL}（"
assert_not_contains "W1: nested under this run's own target is not reported (replaced wholesale)" "$out" "$SP/.agents/skills/handoffx/.old/${T_OLD_SKILL}（"
assert_eq "W1: each hit reported exactly once (aliased root scanned once)" "1" "$(printf '%s\n' "$out" | grep -c -F "/.backup-$T_OLD_SKILL-v1/${T_OLD_SKILL}（")"
[ "$IS_ROOT" = "1" ] || chmod 755 "$BK/locked"
assert_eq "W1: nested copies untouched (warn only)" "$w1_before" "$(snap "$BK"; snap "$NESTED")"
assert_file_exists "W1: the kept inner copy really survived" "$KEPT_INNER/SKILL.md"
assert_absent "W1: the replaced inner copy really went with its parent" "$REPLACED_INNER/SKILL.md"
jo=$(PATH="$P" "$BASH" "$INSTALL" --journal-only --codex 2>/dev/null) || true
je=$(PATH="$P" "$BASH" "$INSTALL" --journal-only --codex 2>&1 >/dev/null) || true
assert_not_contains "W1: --journal-only stdout stays pure op lines" "$jo" "嵌套旧名"
assert_contains "W1: --journal-only still warns on stderr" "$je" "嵌套旧名 skill 目录"
rm -rf "$BK" "$SANDBOX/.claude/skills/nested" "$SANDBOX/.claude/skills/handoffx/.old"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "W1: reinstall without nested old-name dirs exit 0" 0 "$ec"
assert_not_contains "W1: no warning without nested old-name dirs" "$out" "嵌套旧名 skill 目录"
teardown_sandbox

# ── W2：legacy ~/.codex/skills 经链接就是 Claude 的 skills 根 → 不清扫是对的（N2a），但该路径
#        下的 NEW 名会被经 legacy 路径再看到一份；静默跳过 = 把重复留给用户猜 → ⚠️ 一行。
#        legacy 根就是 Codex 自己的根（→ ~/.agents/skills）只有一棵树 → 不报；legacy 根是普通
#        目录 → 正常清扫不报；--project 不传 legacy 根 → 不得打出空路径警告
setup_sandbox
mkdir -p "$SANDBOX/.claude/skills" "$SANDBOX/.codex"; ln -s ../.claude/skills "$SANDBOX/.codex/skills"
SP=$(cd "$SANDBOX" && pwd -P)
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "W2: --codex with legacy root = Claude skills root exit 0" 0 "$ec"
assert_contains "W2: warns that the legacy root was left unswept" "$out" "⚠️  未清扫 legacy 根 $SP/.claude/skills（"
teardown_sandbox
setup_sandbox
mkdir -p "$SANDBOX/.agents/skills" "$SANDBOX/.codex"; ln -s ../.agents/skills "$SANDBOX/.codex/skills"
P=$(iso_path)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "W2: --codex with legacy root = Codex's own skills root exit 0" 0 "$ec"
assert_not_contains "W2: one tree, no legacy warning" "$out" "未清扫 legacy 根"
teardown_sandbox
setup_sandbox
mkdir -p "$SANDBOX/.codex/skills/some-other-skill"
P=$(iso_path)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --codex 2>&1) || ec=$?
assert_exit "W2: --codex with a plain legacy dir exit 0" 0 "$ec"
assert_not_contains "W2: plain legacy dir is swept, not warned about" "$out" "未清扫 legacy 根"
PROJECT_DIR="$SANDBOX/proj"; mkdir -p "$PROJECT_DIR"
P=$(iso_path codex)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --project "$PROJECT_DIR" 2>&1) || ec=$?
assert_exit "W2: --project with codex on PATH exit 0" 0 "$ec"
assert_not_contains "W2: --project passes no legacy root, no (empty-path) warning" "$out" "未清扫 legacy 根"
teardown_sandbox

# ── H1：--help 剥掉头注释的 "# "。Why：BSD sed（macOS）不认 `\?`，旧表达式在 Mac 上原样
#        输出 "# Usage:"——只在 GNU 上测过就会漏
ec=0; out=$(bash "$INSTALL" --help 2>&1) || ec=$?
assert_exit "H1: --help exit 0" 0 "$ec"
assert_contains "H1: --help shows Usage" "$out" "Usage:"
assert_exit "H1: --help has no line starting with '# '" 0 "$(printf '%s\n' "$out" | grep -q '^# ' && echo 1 || echo 0)"

# ══ Z3 (v4.1.1 wave 2)：第四份现场报告的 install 行为 ══════════════════════════
# ── Z3a：成功安装保留备份并打印还原命令；--purge-backups 只删比本次早的备份
# Why: 成功即删 bak 时，新版装上后发现问题就没有退路（report 4 #4）。
setup_sandbox
seed_old_world
P=$(iso_path)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "Z3a: install over an OLD world exit 0" 0 "$ec"
bk=$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null)
assert_eq "Z3a: exactly one backup dir kept" "1" "$(printf '%s\n' "$bk" | grep -c .)"
assert_file_exists "Z3a: the displaced OLD skill is in the kept backup" "$bk$(cd "$SANDBOX" && pwd -P)/.claude/skills/$T_OLD_SKILL/SKILL.md"
assert_contains "Z3a: backup and restore line printed" "$out" "🗄  旧版备份: ${bk}（还原: bash "
rline=$(printf '%s\n' "$out" | sed -n 's/^🗄  旧版备份: .*（还原: \(.*\)）$/\1/p')
ec=0; (PATH="$P"; eval "$rline") > /dev/null 2>&1 || ec=$?
assert_exit "Z3a: the printed restore line runs" 0 "$ec"
assert_eq "Z3a: restore brings back the OLD skill" "old $T_OLD_SKILL" "$(cat "$SANDBOX/.claude/skills/$T_OLD_SKILL/SKILL.md" 2>/dev/null)"
assert_absent "Z3a: restore removes what the install created" "$SANDBOX/.claude/skills/handoffx"
assert_absent "Z3a: a finished restore removes its backup" "$bk"
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
mkdir -p "$SANDBOX/.handoffx-install/bak.20000101000000.1/x" "$SANDBOX/.handoffx-install/bak.99999999999999.1/x"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude --purge-backups 2>&1) || ec=$?
assert_exit "Z3a: --purge-backups install exit 0" 0 "$ec"
assert_absent "Z3a: --purge-backups removes an older backup" "$SANDBOX/.handoffx-install/bak.20000101000000.1"
assert_eq "Z3a: --purge-backups keeps this run's backup and anything newer" "2" "$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | wc -l | tr -d ' ')"
assert_exit "Z3a: the newer-named backup survives" 0 "$([ -d "$SANDBOX/.handoffx-install/bak.99999999999999.1" ] && echo 0 || echo 1)"
teardown_sandbox
# fix2：同秒的备份按 pid 数值排，不按文本——"10003" 按文本排在 "9998" 前，曾让更早的备份
# 活下来（Z3a 偶发红）。本次事务名用测试钩子固定为 <T>.10000。
setup_sandbox
seed_old_world
P=$(iso_path)
H="$SANDBOX/.handoffx-install"; TS=20300101000000
mkdir -p "$H/bak.$TS.9998/x" "$H/bak.$TS.10003/x" "$H/bak.20291231235959.99999/x" "$H/bak.junk/x"
ec=0; out=$(PATH="$P" HANDOFFX_TEST_TXN_TS="$TS.10000" "$BASH" "$INSTALL" --claude --purge-backups 2>&1) || ec=$?
assert_exit "fix2: --purge-backups install exit 0" 0 "$ec"
assert_absent "fix2: same second, smaller pid (9998 < 10000) → purged" "$H/bak.$TS.9998"
assert_exit "fix2: same second, larger pid (10003 > 10000) → kept" 0 "$([ -d "$H/bak.$TS.10003" ] && echo 0 || echo 1)"
assert_absent "fix2: earlier timestamp → purged" "$H/bak.20291231235959.99999"
assert_exit "fix2: a name that is not <ts>.<pid> → never touched" 0 "$([ -d "$H/bak.junk" ] && echo 0 || echo 1)"
assert_exit "fix2: this run's backup kept" 0 "$([ -d "$H/bak.$TS.10000" ] && echo 0 || echo 1)"
teardown_sandbox
# 无可备份内容（全新安装）→ 不留空备份、不打还原行
setup_sandbox
P=$(iso_path)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "Z3a: fresh install exit 0" 0 "$ec"
assert_eq "Z3a: fresh install keeps no empty backup" "" "$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null)"
assert_not_contains "Z3a: fresh install prints no restore line" "$out" "旧版备份"
# ── Z3c：成功安装末尾提示已打开的会话
assert_contains "Z3c: session hint at the end of a successful install" "$out" "ℹ️ 已打开的会话请改用 /handoffx*；看不到新命令就退出会话后 claude --continue"
# ── Codex C2：--restore 与 --dry-run / --journal-only 同用 → 先拒绝（exit 2），一个文件不动
seed_old_world
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
bk=$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | sed -n 1p)
for pv in --dry-run --journal-only; do
    before=$(snap "$SANDBOX")
    ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --restore "$bk" "$pv" 2>&1) || ec=$?
    assert_exit "C2: --restore + $pv → exit 2" 2 "$ec"
    assert_contains "C2: --restore + $pv → refusal names the conflict" "$out" "--restore 不能与 --dry-run / --journal-only 同用"
    assert_eq "C2: --restore + $pv → zero filesystem changes" "$before" "$(snap "$SANDBOX")"
done
teardown_sandbox
# ── Codex C3：部分失败的 --restore 重试不得删掉第一次已还原的原物
# 同一路径既有 bak 又有 new（第二次安装覆盖第一次装的件）：倒序重放先删 new、再移回 bak；
# 第一次在第一项移回之后中断（倒序第一个 bak 是最后装的 init shim），重试若照旧重放就会把
# 已移回的原物当 new 删掉、而 bak 已用掉 → 原物丢失。
setup_sandbox
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
C3_SH="$SANDBOX/.claude/commands/handoffx-init.md"
printf 'sentinel-first-install\n' >> "$C3_SH"
printf 'sentinel-first-install\n' >> "$SANDBOX/.claude/skills/handoffx/SKILL.md"
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
bk=$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | sed -n 1p)
assert_exit "C3: second install kept a backup with a journal" 0 "$([ -f "$bk/.journal" ] && echo 0 || echo 1)"
ec=0; out=$(PATH="$P" HANDOFFX_INSTALL_FAIL_AT=restore-after-bak "$BASH" "$INSTALL" --restore "$bk" 2>&1) || ec=$?
assert_exit "C3: injected partial restore → exit 1" 1 "$ec"
assert_contains "C3: partial restore already moved the first-install shim back" "$(cat "$C3_SH" 2>/dev/null)" "sentinel-first-install"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --restore "$bk" 2>&1) || ec=$?
assert_exit "C3: retried restore → exit 0" 0 "$ec"
assert_contains "C3: retry keeps the shim restored by the first attempt" "$(cat "$C3_SH" 2>/dev/null)" "sentinel-first-install"
assert_contains "C3: retry restores the rest (first-install skill)" "$(cat "$SANDBOX/.claude/skills/handoffx/SKILL.md" 2>/dev/null)" "sentinel-first-install"
assert_absent "C3: a finished retry removes the backup" "$bk"
teardown_sandbox
# 保留的备份里少了 payload → 重放前就拒绝（exit 2），一个文件不动
setup_sandbox
seed_old_world
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
bk=$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | sed -n 1p)
rm -rf "$bk$(cd "$SANDBOX" && pwd -P)/.claude/skills/$T_OLD_SKILL"
before=$(snap "$SANDBOX")
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --restore "$bk" 2>&1) || ec=$?
assert_exit "C3: missing bak payload → restore refused (exit 2)" 2 "$ec"
assert_contains "C3: refusal names the missing payload" "$out" "备份内容缺失"
assert_eq "C3: refused restore → zero filesystem changes" "$before" "$(snap "$SANDBOX")"
teardown_sandbox
# ── fix3 N1：还原循环的输入建不出来（here-document 写不了临时文件 / 逆序 journal
# 写不出）时循环一项都没跑；旧代码照样删备份与 journal 并报「已还原」。
# ulimit -f 0 让任何普通文件写入失败（bash 3.2 的 here-doc 临时文件不认不可写的
# TMPDIR，会退回 /tmp，所以用写入上限而不是 TMPDIR 来构造）；XFSZ 忽略，写入只报错。
setup_sandbox
seed_old_world
P=$(iso_path)
PATH="$P" "$BASH" "$INSTALL" --claude > /dev/null 2>&1 || true
bk=$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | sed -n 1p)
before=$(snap "$SANDBOX")
ec=0; out=$( (trap '' XFSZ; ulimit -f 0; PATH="$P" exec "$BASH" "$INSTALL" --restore "$bk") 2>&1) || ec=$?
assert_exit "fix3-N1: write-starved restore → non-zero (exit 1)" 1 "$ec"
assert_not_contains "fix3-N1: write-starved restore → no false full-restore claim" "$out" "已还原到安装前状态"
assert_file_exists "fix3-N1: write-starved restore → journal kept" "$bk/.journal"
assert_contains "fix3-N1: write-starved restore → names the kept backup" "$out" "$bk"
assert_eq "fix3-N1: write-starved restore → nothing touched" "$before" "$(snap "$SANDBOX")"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ fix3-N1 unwritable TMPDIR restore SKIPPED (root writes into mode-555 dirs)"
else
    mkdir "$SANDBOX.ro"; chmod 555 "$SANDBOX.ro"
    ec=0; out=$(TMPDIR="$SANDBOX.ro" PATH="$P" "$BASH" "$INSTALL" --restore "$bk" 2>&1) || ec=$?
    chmod 755 "$SANDBOX.ro"; rmdir "$SANDBOX.ro"
    assert_exit "fix3-N1: unwritable TMPDIR restore → non-zero (exit 1)" 1 "$ec"
    assert_file_exists "fix3-N1: unwritable TMPDIR restore → journal kept" "$bk/.journal"
    assert_eq "fix3-N1: unwritable TMPDIR restore → nothing touched" "$before" "$(snap "$SANDBOX")"
fi
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --restore "$bk" 2>&1) || ec=$?
assert_exit "fix3-N1: the kept backup still restores afterwards → exit 0" 0 "$ec"
assert_eq "fix3-N1: restore brings back the OLD skill" "old $T_OLD_SKILL" "$(cat "$SANDBOX/.claude/skills/$T_OLD_SKILL/SKILL.md" 2>/dev/null)"
teardown_sandbox
# ── Codex C8：journal 移入非空备份失败 → 两者都保留并说明，绝不 rm -rf
setup_sandbox
seed_old_world
P=$(iso_path)
ec=0; out=$(PATH="$P" HANDOFFX_INSTALL_FAIL_AT=journal-keep "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "C8: journal-keep failure → install still exit 0" 0 "$ec"
assert_contains "C8: degraded recovery is reported" "$out" "无法把 journal 移入备份"
assert_eq "C8: the non-empty backup is kept" "1" "$(ls -d "$SANDBOX/.handoffx-install"/bak.* 2>/dev/null | grep -c .)"
assert_eq "C8: the journal is kept" "1" "$(ls "$SANDBOX/.handoffx-install"/journal.* 2>/dev/null | grep -c .)"
assert_not_contains "C8: no restore line is promised" "$out" "旧版备份: "
teardown_sandbox

# ── Z3b：skills 根下目录名不同、但 SKILL.md 仍是旧名的副本 → 只警告不删
# Why: Claude Code 按 SKILL.md 的 name 注册，`handoff.v1.2.5.bak-…` 这种改名备份仍会被加载。
setup_sandbox
STRAY="$SANDBOX/.claude/skills/$T_OLD_SKILL.v1.2.5.bak-20260101"
mkdir -p "$STRAY" "$SANDBOX/.claude/skills/innocent"
printf -- '---\nname: %s\ndescription: old\n---\nold\n' "$T_OLD_SKILL" > "$STRAY/SKILL.md"
printf -- '---\nname: innocent\n---\nx\n' > "$SANDBOX/.claude/skills/innocent/SKILL.md"
stray_before=$(snap "$STRAY")
SP=$(cd "$SANDBOX" && pwd -P)
P=$(iso_path)
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_exit "Z3b: install with a renamed old-name copy exit 0" 0 "$ec"
assert_contains "Z3b: the renamed copy is named" "$out" "⚠️ 发现旧名 skill 副本（Claude Code 仍会加载）: $SP/.claude/skills/$T_OLD_SKILL.v1.2.5.bak-20260101"
assert_not_contains "Z3b: an unrelated skill is not named" "$out" "副本（Claude Code 仍会加载）: $SP/.claude/skills/innocent"
assert_not_contains "Z3b: the new skill itself is not named" "$out" "副本（Claude Code 仍会加载）: $SP/.claude/skills/handoffx"
assert_eq "Z3b: the copy is left untouched" "$stray_before" "$(snap "$STRAY")"
teardown_sandbox

# ── Z3d：--dry-run = --journal-only；stdout 只有 op 行（含自举时）；gemini 只提示一次
setup_sandbox
mkdir -p "$SANDBOX/.gemini"
P=$(iso_path)
SP=$(cd "$SANDBOX" && pwd -P)
before=$(snap "$SANDBOX")
jo=$(PATH="$P" "$BASH" "$INSTALL" --journal-only --claude 2>/dev/null) || true
dr=$(PATH="$P" "$BASH" "$INSTALL" --dry-run --claude 2>/dev/null) || true
assert_eq "Z3d: --dry-run prints exactly what --journal-only prints" "$jo" "$dr"
assert_eq "Z3d: --dry-run changed nothing" "$before" "$(snap "$SANDBOX")"
assert_contains "Z3d: usage says --dry-run is an alias of --journal-only" "$(bash "$INSTALL" --help 2>&1)" "--dry-run                # 同 --journal-only"
je=$(PATH="$P" "$BASH" "$INSTALL" --journal-only --claude 2>&1 >/dev/null) || true
assert_eq "Z3d: gemini notice printed once" "1" "$(printf '%s\n' "$je" | grep -c -F 'ℹ️ 检测到 gemini CLI，但当前不是安装目标')"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || ec=$?
assert_eq "Z3d: gemini notice once on a real install too" "1" "$(printf '%s\n' "$out" | grep -c -F 'ℹ️ 检测到 gemini CLI')"
SKILL_FILE=""; PKG_DIR=$(mktemp -d)
if command -v zip >/dev/null 2>&1 && cp -R "$SKILL_SRC" "$PKG_DIR/handoffx" && \
   (cd "$PKG_DIR" && zip -qr handoffx-v0.0.0-test.skill handoffx); then
    BOOTSTRAP_DIR=$(mktemp -d)
    cp "$PKG_DIR/handoffx-v0.0.0-test.skill" "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
    jo=$(PATH="$P" "$BASH" "$BOOTSTRAP_DIR/install.sh" --dry-run --claude 2>/dev/null) || true
    assert_contains "Z3d: bootstrap --dry-run still lists op lines" "$jo" "root $SP/.claude/skills"
    assert_eq "Z3d: bootstrap --dry-run stdout is pure op lines" "" "$(printf '%s\n' "$jo" | grep -v -E '^(root|bak|absent|new) ')"
    rm -rf "$BOOTSTRAP_DIR"
else echo "  ➖ Z3d: zip 不可用，跳过自举 stdout 纯净性"; fi
rm -rf "$PKG_DIR"
teardown_sandbox

# ── W2a (v4.1.1, report 5 HX-02)：扁平下载目录（只有 install.sh + .skill，无 VERSION）
# 安装成功却在 stderr 打 "VERSION: No such file or directory"：`tr < f 2>/dev/null`
# 里输入重定向先失败，stderr 重定向还没生效。断言退出码 + 版本 + stderr，而不只看装没装上；
# 当前 bash 与 /bin/bash（macOS 上是 3.2）各跑一遍——报告里两条都复现过。
W2_VER=$(tr -d '[:space:]' < "$SKILL_SRC/VERSION")
PKG_DIR=$(mktemp -d)
if command -v zip >/dev/null 2>&1 && cp -R "$SKILL_SRC" "$PKG_DIR/handoffx" && \
   (cd "$PKG_DIR" && zip -qr handoffx-v0.0.0-test.skill handoffx); then
    w2_seen=""
    for w2_sh in "$BASH" /bin/bash "$(command -v bash)"; do
        [ -x "$w2_sh" ] || { echo "  ➖ W2a: $w2_sh 不存在"; continue; }
        case " $w2_seen " in *" $w2_sh "*) continue ;; esac
        w2_seen="$w2_seen $w2_sh"
        setup_sandbox
        P=$(iso_path claude)
        BOOTSTRAP_DIR=$(mktemp -d)
        cp "$PKG_DIR/handoffx-v0.0.0-test.skill" "$ROOT_DIR/install.sh" "$BOOTSTRAP_DIR/"
        ec=0; w2_err=$(PATH="$P" "$w2_sh" "$BOOTSTRAP_DIR/install.sh" --claude 2>&1 >"$BOOTSTRAP_DIR/out") || ec=$?
        assert_exit "W2a ($w2_sh): flattened download dir install → exit 0" 0 "$ec"
        assert_contains "W2a ($w2_sh): banner names $W2_VER (read from the .skill)" "$(cat "$BOOTSTRAP_DIR/out")" "handoffx $W2_VER installed"
        assert_not_contains "W2a ($w2_sh): stderr has no 'No such file'" "$w2_err" "No such file"
        rm -rf "$BOOTSTRAP_DIR"
        teardown_sandbox
    done
else echo "  ➖ W2a: zip 不可用，跳过扁平目录自举"; fi
rm -rf "$PKG_DIR"

# ── W2b (v4.1.1, report 5 HX-06)：预览的收尾不说 installed；--force 明说不改变行为
setup_sandbox
P=$(iso_path claude)
for w2_flag in --dry-run --journal-only; do
    w2_all=$(PATH="$P" "$BASH" "$INSTALL" "$w2_flag" --claude 2>&1) || true
    assert_contains "W2b: $w2_flag closes with 'preview complete — 未安装'" "$(printf '%s\n' "$w2_all" | tail -1)" "preview complete — 未安装"
    assert_not_contains "W2b: $w2_flag never says installed" "$w2_all" "installed"
done
assert_contains "W2b: usage says --force changes nothing" "$(bash "$INSTALL" --help 2>&1)" "--force                  # 不改变任何行为"
ec=0; out=$(PATH="$P" "$BASH" "$INSTALL" --claude --force 2>&1) || ec=$?
assert_exit "W2b: --force install exit 0" 0 "$ec"
assert_contains "W2b: --force run says it changed nothing" "$out" "ℹ️ --force 不改变任何行为：重装总是覆盖已装版本"
out=$(PATH="$P" "$BASH" "$INSTALL" --claude 2>&1) || true
assert_not_contains "W2b: no --force note without the flag" "$out" "--force 不改变"
teardown_sandbox

summary
