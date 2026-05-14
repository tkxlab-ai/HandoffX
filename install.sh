#!/bin/bash
# install.sh — Handoff Skill Installer (v1.1+)
#
# Usage:
#   ./install.sh                          # 全局安装到所有已检测到的 AI CLI
#   ./install.sh --claude                 # 仅安装到 Claude Code
#   ./install.sh --opencode               # 仅安装到 OpenCode
#   ./install.sh --codex                  # 仅安装到 Codex CLI
#   ./install.sh --project <dir>          # 项目级安装（Claude Code）
#   ./install.sh --template <dir>         # 在 <dir> 创建 HANDOFF.md
#   ./install.sh --uninstall              # 卸载所有全局安装
#   ./install.sh --dry-run                # 显示计划（当前版本为兼容保留）
#   ./install.sh --force                  # 覆盖确认（当前安装本身幂等）
#   ./install.sh --help
#
# 支持平台：macOS / Linux / Windows (WSL)
# 支持 CLI：Claude Code / OpenCode / Codex CLI

set -e

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$PLUGIN_DIR/skills/handoff"
BOOTSTRAP_TMP=""

cleanup_bootstrap() {
    local _exit=$?
    [ -n "$BOOTSTRAP_TMP" ] && [ -d "$BOOTSTRAP_TMP" ] && rm -rf "$BOOTSTRAP_TMP"
    exit $_exit
}
trap cleanup_bootstrap EXIT

show_help() {
    sed -n '2,14p' "$0" | sed 's/^# \?//'
    exit 0
}

[ "$#" -gt 0 ] && case "$1" in -h|--help) show_help ;; esac

# ── 平台 & 路径检测 ───────────────────────────────────────────────────────────

detect_platform() {
    if [ -n "${HANDOFF_TEST_PLATFORM:-}" ]; then
        PLATFORM="$HANDOFF_TEST_PLATFORM"
        return
    fi
    case "$(uname -s)" in
        Darwin) PLATFORM="macos" ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                PLATFORM="wsl"
            else
                PLATFORM="linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*) PLATFORM="gitbash" ;;
        *) PLATFORM="unknown" ;;
    esac
}

# 解析 WSL 下 Windows 用户名，找到 Windows AppData 路径
wsl_windows_appdata() {
    if [ -n "${HANDOFF_TEST_WSL_APPDATA:-}" ]; then
        [ -d "$HANDOFF_TEST_WSL_APPDATA" ] && echo "$HANDOFF_TEST_WSL_APPDATA" && return 0
        return 1
    fi

    # 优先用 cmd.exe 取 APPDATA，回退到枚举 /mnt/c/Users/
    local win_user
    win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || true)
    if [ -n "$win_user" ] && [ -d "/mnt/c/Users/$win_user/AppData/Roaming" ]; then
        echo "/mnt/c/Users/$win_user/AppData/Roaming"
        return 0
    fi
    # fallback: 找第一个有 AppData 的用户目录
    for d in /mnt/c/Users/*/AppData/Roaming; do
        [ -d "$d" ] && echo "$d" && return 0
    done
    return 1
}

# Claude Code 配置目录
claude_config_dir() {
    if [ "$PLATFORM" = "wsl" ]; then
        local appdata
        appdata=$(wsl_windows_appdata 2>/dev/null || true)
        if [ -n "$appdata" ] && [ -d "$appdata/Claude" ]; then
            echo "$appdata/Claude"
            return
        fi
        # fallback to WSL home (e.g. Claude Code for Linux running in WSL)
    fi
    echo "$HOME/.claude"
}

# OpenCode 全局配置目录
opencode_config_dir() {
    # OpenCode 遵循 XDG: ~/.config/opencode/
    local xdg="${XDG_CONFIG_HOME:-$HOME/.config}"
    echo "$xdg/opencode"
}

# Codex CLI 官方用户 skills 目录
codex_config_dir() {
    echo "$HOME/.agents"
}

detect_platform

# ── 自举（从 .skill / tarball）──────────────────────────────────────────────

if [ ! -d "$SKILL_SRC" ]; then
    SKILL_ZIP=$(ls "$PLUGIN_DIR"/handoff-*.skill 2>/dev/null | head -n1 || true)
    SOURCE_TAR=$(ls "$PLUGIN_DIR"/handoff-*-source.tar.gz 2>/dev/null | head -n1 || true)
    if [ -n "$SKILL_ZIP" ]; then
        echo "📦 未找到源码目录，自举解压 $(basename "$SKILL_ZIP")..."
        BOOTSTRAP_TMP=$(mktemp -d)
        if ! command -v unzip >/dev/null 2>&1; then
            echo "❌ unzip is required for .skill bootstrap but was not found" >&2
            echo "   Install it with: brew install unzip  OR  apt-get install unzip" >&2
            exit 1
        fi
        unzip -q "$SKILL_ZIP" -d "$BOOTSTRAP_TMP"
        if [ -d "$BOOTSTRAP_TMP/handoff" ]; then
            mkdir -p "$BOOTSTRAP_TMP/skills"
            mv "$BOOTSTRAP_TMP/handoff" "$BOOTSTRAP_TMP/skills/handoff"
            PLUGIN_DIR="$BOOTSTRAP_TMP"
            SKILL_SRC="$PLUGIN_DIR/skills/handoff"
        fi
    elif [ -n "$SOURCE_TAR" ]; then
        echo "📦 未找到源码目录，自举解压 $(basename "$SOURCE_TAR")..."
        BOOTSTRAP_TMP=$(mktemp -d)
        tar xzf "$SOURCE_TAR" -C "$BOOTSTRAP_TMP"
        EXTRACTED_ROOT=$(ls -d "$BOOTSTRAP_TMP"/handoff-* 2>/dev/null | head -n1 || true)
        if [ -n "$EXTRACTED_ROOT" ] && [ -d "$EXTRACTED_ROOT/skills/handoff" ]; then
            PLUGIN_DIR="$EXTRACTED_ROOT"
            SKILL_SRC="$PLUGIN_DIR/skills/handoff"
        fi
    fi
fi

if [ ! -d "$SKILL_SRC" ]; then
    echo "❌ 找不到 skills/handoff/"
    echo "   install.sh 需要以下其一（同目录）："
    echo "     • Handoff 源码根目录（含 skills/handoff/ 子目录），或"
    echo "     • 同目录的 handoff-*.skill 单文件包，或"
    echo "     • 同目录的 handoff-*-source.tar.gz"
    exit 1
fi

# v2.1.3 backward compat: 旧 .skill / source tarball（v2.1.2 及更早）的 shim 源
# 目录叫 commands/；v2.1.3 起改名 command-shims/（让"这是 install.sh 的 shim 源
# 镜像，不是 Claude Code 直读路径"明示，Gotcha #5 同根）。从旧包 bootstrap 时
# 自动迁名，让下游 install_to_dir / install_codex_aliases 统一只看 command-shims/。
# v2.1.5（Round 1 review I4）: 处理 both-exist 边角——若两个目录都在，
# command-shims/ 是 canonical，删掉 legacy commands/ 防 silent revival。
if [ -d "$SKILL_SRC/commands" ]; then
    if [ ! -d "$SKILL_SRC/command-shims" ]; then
        mv "$SKILL_SRC/commands" "$SKILL_SRC/command-shims"  # 老包 bootstrap: rename
    else
        rm -rf "$SKILL_SRC/commands"  # both exist: legacy cleanup（canonical 是 command-shims/）
    fi
fi

# ── 参数解析 ─────────────────────────────────────────────────────────────────

MODE="auto"        # auto = 安装到所有检测到的 CLI
TARGET_CLAUDE=0
TARGET_OPENCODE=0
TARGET_CODEX=0
PROJECT=""
TEMPLATE_TARGET=""
UNINSTALL=0
DRY_RUN=0
FORCE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --claude)     TARGET_CLAUDE=1;   MODE="explicit" ;;
        --opencode)   TARGET_OPENCODE=1; MODE="explicit" ;;
        --codex)      TARGET_CODEX=1;    MODE="explicit" ;;
        --global)     MODE="auto" ;;
        --project)
            case "${2:-}" in
                ""|-*) echo "❌ --project 需要目录参数（不能为空或以 - 开头）" >&2; exit 1 ;;
            esac
            MODE="project"; PROJECT="$2"; shift ;;
        --template)
            case "${2:-}" in
                ""|-*) echo "❌ --template 需要目录参数（不能为空或以 - 开头）" >&2; exit 1 ;;
            esac
            TEMPLATE_TARGET="$2"; shift ;;
        --uninstall)  UNINSTALL=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        --force)      FORCE=1 ;;
        *) echo "❌ 未知参数: $1"; show_help ;;
    esac
    shift
done

# ── Unified install banner (TKX standard, v2.2.0) ───────────────────────────
# Helper provides install_banner_top / install_checkpoint / install_step_ok /
# install_banner_bottom / install_cli_row + table — same visual as gitx-release
# v1.5.0 / mac-release v0.2.0 / future TKX skills.
HANDOFF_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HANDOFF_SELF_DIR/scripts/lib/install-output-style.sh" ]; then
    # shellcheck source=scripts/lib/install-output-style.sh
    source "$HANDOFF_SELF_DIR/scripts/lib/install-output-style.sh"
elif [ -f "$SKILL_SRC/scripts/lib/install-output-style.sh" ]; then
    # shellcheck source=skills/handoff/scripts/lib/install-output-style.sh
    source "$SKILL_SRC/scripts/lib/install-output-style.sh"
else
    # Graceful degradation: when bootstrap-mode extracts an older .skill bundle
    # (pre-v2.2.0) that predates the unified install-output-style.sh helper,
    # define no-op stubs so the install proceeds with legacy echo style. The
    # next install (which uses a v2.2.0+ bundle) gets the full unified banner.
    install_style_init()      { :; }
    install_banner_top()      { echo "📦 handoff installer ${1:-} ${2:-} (legacy mode)"; }
    install_checkpoint()      { echo "── ${2:-step} ──"; }
    install_step_ok()         { echo "  ✅ ${1:-}"; }
    install_step_warn()       { echo "  ⚠️  ${1:-}" >&2; }
    install_step_fail()       { echo "  ❌ ${1:-}" >&2; }
    install_banner_bottom()   { echo "🎉 handoff installer complete"; }
    install_cli_table_begin() { echo "Installed CLI commands:"; }
    install_cli_row()         { printf '  [%s] %s  %s\n' "${1:-}" "${2:-}" "${3:-}"; }
    install_cli_table_end()   { :; }
    install_next_block()      { echo "Next:"; for h in "$@"; do echo "  • $h"; done; }
    install_next_hint()       { echo "  • ${1:-}"; }
    _TKX_E_PKG="📦"; _TKX_E_LOCK="🔐"; _TKX_E_SEARCH="🔍"; _TKX_E_DIR="📂"
    _TKX_E_LINK="🔗"; _TKX_E_BROOM="🧹"; _TKX_E_CHECK="✓"; _TKX_E_OK="✅"
    _TKX_E_WARN="⚠️"; _TKX_E_FAIL="❌"; _TKX_E_PARTY="🎉"
fi
_HANDOFF_VERSION="$(tr -d '[:space:]' < "$HANDOFF_SELF_DIR/VERSION" 2>/dev/null \
    || tr -d '[:space:]' < "$SKILL_SRC/VERSION" 2>/dev/null \
    || echo unknown)"
if [ "$UNINSTALL" = "1" ]; then
    _HANDOFF_MODE="uninstall"
elif [ "$DRY_RUN" = "1" ]; then
    _HANDOFF_MODE="--dry-run"
elif [ -n "$PROJECT" ]; then
    _HANDOFF_MODE="install --project $PROJECT"
elif [ "$MODE" = "explicit" ]; then
    _HANDOFF_MODE="install (explicit targets)"
else
    _HANDOFF_MODE="install (auto)"
fi
install_style_init 0
install_banner_top "handoff" "$_HANDOFF_VERSION" "$_HANDOFF_MODE" "$HANDOFF_SELF_DIR"

if [ "$DRY_RUN" = "1" ]; then
    install_checkpoint "$_TKX_E_SEARCH" "Dry-run preview"
    install_step_ok "Targets parsed successfully; no filesystem changes performed."
    install_banner_bottom "handoff" "$_HANDOFF_VERSION (dry-run)"
    exit 0
fi
[ "$FORCE" = "1" ] && true

# auto 模式：检测已安装的 CLI，自动决定安装目标
if [ "$MODE" = "auto" ]; then
    command -v claude   >/dev/null 2>&1 && TARGET_CLAUDE=1
    command -v opencode >/dev/null 2>&1 && TARGET_OPENCODE=1
    command -v codex    >/dev/null 2>&1 && TARGET_CODEX=1
    # 即使未检测到 claude，默认也装 Claude Code（最常见场景）
    TARGET_CLAUDE=1
fi

install_checkpoint "$_TKX_E_SEARCH" "Preflight: targets detected"
[ "$TARGET_CLAUDE" = "1" ]   && install_step_ok "Claude Code   targeted"
[ "$TARGET_OPENCODE" = "1" ] && install_step_ok "OpenCode      targeted"
[ "$TARGET_CODEX" = "1" ]    && install_step_ok "Codex CLI     targeted"

# ── 工具函数 ─────────────────────────────────────────────────────────────────

install_to_dir() {
    local target_skills="$1"
    local target_commands="$2"   # 可为空（Codex 无 commands）
    local cli_name="$3"

    mkdir -p "$target_skills"
    rm -rf "$target_skills/handoff"
    cp -r "$SKILL_SRC" "$target_skills/handoff"
    # 不要把 command-shims/ 留在 skill 目录里——它只是 slash shim 的源镜像，
    # Claude Code 会把 skill 内部 commands/ 当成额外命令登记（Gotcha #5）。
    # v2.1.3 起源目录改名 command-shims/ 让职责更清楚——但仍要剥离，同时清掉
    # v2.1.2 及更早 installed copy 中残留的 commands/（防 in-place 升级残留）。
    rm -rf "$target_skills/handoff/command-shims" "$target_skills/handoff/commands"
    chmod +x "$target_skills/handoff/scripts/"*.sh 2>/dev/null || true

    local ver
    ver=$(grep "^# " "$target_skills/handoff/SKILL.md" 2>/dev/null | head -1 | sed 's/^# //' || echo "unknown")
    echo "  ✅ [$cli_name] Skill → $target_skills/handoff/  [$ver]"

    if [ -n "$target_commands" ] && [ -d "$SKILL_SRC/command-shims" ]; then
        mkdir -p "$target_commands"
        # 默认装 recall / tidy / memory / init 四个 shim。/handoff 是否需要单独 shim
        # 取决于 CLI：Claude Code 从 SKILL.md `name: handoff` 自动注册，再拷 handoff.md
        # 进 commands/ 会让 palette 里出现两条重复的 /handoff（Gotcha #5）；
        # OpenCode 不会自动注册 skill name，必须显式 shim 主命令（Gotcha #9）。
        local cmds=(handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md)
        case "$cli_name" in
            *OpenCode*) cmds+=(handoff.md) ;;
        esac
        for cmd in "${cmds[@]}"; do
            [ -f "$SKILL_SRC/command-shims/$cmd" ] && cp "$SKILL_SRC/command-shims/$cmd" "$target_commands/$cmd"
        done
        # Claude Code 路径主动删旧版残留的 handoff.md（防重复）
        case "$cli_name" in
            *OpenCode*) ;;
            *) [ -f "$target_commands/handoff.md" ] && rm -f "$target_commands/handoff.md" ;;
        esac
        echo "  ✅ [$cli_name] Commands → $target_commands/"
    fi

    # 验证
    local ok=1
    [ -f "$target_skills/handoff/SKILL.md" ] || { echo "  ❌ SKILL.md 缺失"; ok=0; }
    if [ -n "$target_commands" ]; then
        [ -f "$target_commands/handoff-recall.md" ] || { echo "  ❌ commands/handoff-recall.md 缺失"; ok=0; }
        [ -f "$target_commands/handoff-tidy.md" ]   || { echo "  ❌ commands/handoff-tidy.md 缺失"; ok=0; }
        [ -f "$target_commands/handoff-memory.md" ] || { echo "  ❌ commands/handoff-memory.md 缺失"; ok=0; }
        [ -f "$target_commands/handoff-init.md" ]   || { echo "  ❌ commands/handoff-init.md 缺失"; ok=0; }
    fi
    [ "$ok" = "1" ] && echo "  ✅ [$cli_name] 安装验证通过" || echo "  ❌ [$cli_name] 验证失败"
}

yaml_single_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/''/g")"
}

install_codex_aliases() {
    local target_skills="$1"

    [ -d "$SKILL_SRC/command-shims" ] || return 0
    mkdir -p "$target_skills"

    for cmd_path in "$SKILL_SRC"/command-shims/*.md; do
        [ -f "$cmd_path" ] || continue
        local cmd_name
        cmd_name=$(basename "$cmd_path" .md)

        # $handoff is the primary skill already installed at skills/handoff.
        [ "$cmd_name" = "handoff" ] && continue

        rm -rf "$target_skills/$cmd_name"
        mkdir -p "$target_skills/$cmd_name"
        {
            echo "---"
            printf "name: %s\n" "$(yaml_single_quote "$cmd_name")"
            printf "description: %s\n" "$(yaml_single_quote "Codex \$$cmd_name alias. Use skill: handoff.")"
            echo "---"
            echo ""
            echo "# /$cmd_name"
            echo ""
            echo "Use skill: handoff."
            echo ""
            echo "This Codex alias mirrors \`skills/handoff/command-shims/$cmd_name.md\` so \`\$$cmd_name\` works like \`/$cmd_name\` in Claude Code / OpenCode."
            echo ""
            awk '
                BEGIN { state = "body" }
                NR == 1 && $0 == "---" { state = "frontmatter"; next }
                state == "frontmatter" && $0 == "---" { state = "body"; next }
                state == "body" { print }
            ' "$cmd_path"
        } > "$target_skills/$cmd_name/SKILL.md"
    done

    echo "  ✅ [Codex] Skill aliases → $target_skills/{handoff-*}/"
}

cleanup_codex_legacy_mirrors() {
    local legacy_skills="$HOME/.codex/skills"
    [ -d "$legacy_skills" ] || return 0
    local removed=0
    for name in handoff handoff-recall handoff-tidy handoff-memory handoff-init; do
        if [ -e "$legacy_skills/$name" ]; then
            rm -rf "$legacy_skills/$name"
            removed=$((removed+1))
        fi
    done
    if [ "$removed" -gt 0 ]; then
        echo "  🧹 [Codex] removed $removed legacy ~/.codex/skills/handoff* mirror(s)"
    fi
    # 显式 return 0：避免末尾 `[ -gt ]` 测试在 removed=0 时返回 1 让 set -e 抓到（Gotcha #6）
    return 0
}

cleanup_legacy() {
    local root="$1"
    local removed=0
    for f in "$root/.claude/commands/handoff.md" \
             "$root/.claude/commands/handoff-recall.md" \
             "$root/.claude/commands/handoff-tidy.md" \
             "$root/.claude/commands/handoff-memory.md" \
             "$root/.claude/commands/handoff-init.md" \
             "$root/.claude/commands/hand-off.md"; do
        [ -f "$f" ] && { rm -f "$f"; removed=1; }
    done
    [ -d "$root/.claude/handoff-scripts" ] && { rm -rf "$root/.claude/handoff-scripts"; removed=1; }
    [ "$removed" = "1" ] && echo "  🧹 清理了旧版残留（$root/.claude/）"
    return 0
}

uninstall_from() {
    local dir="$1"
    local label="$2"
    if [ -d "$dir/handoff" ]; then
        rm -rf "$dir/handoff"
        echo "  ✅ [$label] 已卸载 $dir/handoff"
    else
        echo "  ➖ [$label] $dir/handoff 不存在"
    fi
}

# ── v2 layout warning (D1) ───────────────────────────────────────────────────
# Non-blocking informational notice when the user's CWD has a v1 HANDOFF.md.
# install.sh installs the *skill*; project HANDOFF.md is migrated by /handoff-tidy.
warn_if_v1_layout() {
    local target="${1:-$PWD/HANDOFF.md}"
    [ -f "$target" ] || return 0
    if grep -qF -- '<!-- HANDOFF v2 schema -->' "$target" 2>/dev/null; then
        return 0   # already v2
    fi
    if grep -qE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' "$target" 2>/dev/null; then
        echo ""
        echo "⚠️  Detected v1 HANDOFF.md at $target"
        echo "   v2.0.0 stores Dev Log / Decision / Gotchas in sibling files."
        echo "   Run /handoff-tidy after install completes — it will offer migration."
        echo ""
    fi
}
[ "${HANDOFF_INSTALL_SKIP_V2_GATE:-0}" = "1" ] || warn_if_v1_layout

# ── 卸载 ──────────────────────────────────────────────────────────────────────

if [ "$UNINSTALL" = "1" ]; then
    echo "🗑  卸载 Handoff Skill..."
    echo ""

    CLAUDE_DIR=$(claude_config_dir)
    uninstall_from "$CLAUDE_DIR/skills" "Claude Code"
    for cmd in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md hand-off.md; do
        [ -f "$CLAUDE_DIR/commands/$cmd" ] && rm -f "$CLAUDE_DIR/commands/$cmd"
    done
    rm -rf "$CLAUDE_DIR/handoff-scripts" 2>/dev/null || true

    OC_DIR=$(opencode_config_dir)
    uninstall_from "$OC_DIR/skills" "OpenCode"
    # OpenCode 用 command/（单数）；同时清理 v1.2.5 及之前误装到 commands/（复数）的残留
    for cmd in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
        [ -f "$OC_DIR/command/$cmd" ]  && rm -f "$OC_DIR/command/$cmd"
        [ -f "$OC_DIR/commands/$cmd" ] && rm -f "$OC_DIR/commands/$cmd"
    done

    CODEX_DIR=$(codex_config_dir)
    uninstall_from "$CODEX_DIR/skills" "Codex"
    for alias in handoff-recall handoff-tidy handoff-memory handoff-init; do
        [ -d "$CODEX_DIR/skills/$alias" ] && rm -rf "$CODEX_DIR/skills/$alias"
    done

    echo ""
    echo "✅ 全局卸载完成"
    echo ""
    echo "⚠️  如有项目级安装（--project 模式），请进入各项目目录手动检查："
    echo "   find <project> -name 'handoff*.md' -path '*/.claude/commands/*' 2>/dev/null"
    exit 0
fi

# ── 安装：项目级 ──────────────────────────────────────────────────────────────

if [ "$MODE" = "project" ]; then
    [ -n "$PROJECT" ] || { echo "❌ --project 需要目录参数"; exit 1; }
    [ -d "$PROJECT" ] || { echo "❌ 项目目录不存在: $PROJECT"; exit 1; }
    PROJECT_ABS="$(cd "$PROJECT" && pwd)"
    echo "📦 项目级安装 → $PROJECT_ABS/.claude/"
    cleanup_legacy "$PROJECT_ABS"
    install_to_dir \
        "$PROJECT_ABS/.claude/skills" \
        "$PROJECT_ABS/.claude/commands" \
        "Claude Code (project)"
    echo "   → 仅在该项目目录下生效"
    # 同时装到 .opencode/ 和 .codex/（如已检测）
    if command -v opencode >/dev/null 2>&1; then
        echo ""
        echo "📦 项目级安装 → $PROJECT_ABS/.opencode/"
        # 双路径旧版残留清理：v1.2.5 时代误写 commands/（复数）/ v1.2.6–v2.1.2
        # 时代写 command/（单数，OpenCode 当时 canonical）/ v2.1.3 起跟随官方文档
        # 写 commands/（复数）。OpenCode v1.14+ 双路径都读但**不去重**，所以两个
        # 都清才不会出现 5+5=10 个 /handoff 重复（同根 Gotcha #5 / Gotcha #9）。
        for cmd in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
            [ -f "$PROJECT_ABS/.opencode/command/$cmd" ]  && rm -f "$PROJECT_ABS/.opencode/command/$cmd"
            [ -f "$PROJECT_ABS/.opencode/commands/$cmd" ] && rm -f "$PROJECT_ABS/.opencode/commands/$cmd"
        done
        install_to_dir \
            "$PROJECT_ABS/.opencode/skills" \
            "$PROJECT_ABS/.opencode/commands" \
            "OpenCode (project)"
    fi
    if command -v codex >/dev/null 2>&1; then
        echo ""
        echo "📦 项目级安装 → $PROJECT_ABS/.agents/"
        cleanup_codex_legacy_mirrors
        install_to_dir \
            "$PROJECT_ABS/.agents/skills" \
            "" \
            "Codex (project)"
        install_codex_aliases "$PROJECT_ABS/.agents/skills"
    fi
    echo ""
fi

# ── 安装：全局 ────────────────────────────────────────────────────────────────

if [ "$MODE" = "auto" ] || [ "$MODE" = "explicit" ]; then
    install_checkpoint "$_TKX_E_DIR" "Global install"
    echo "📦 全局安装 Handoff Skill"
    echo "   平台: $PLATFORM"
    echo ""

    # ── Claude Code ──
    if [ "$TARGET_CLAUDE" = "1" ]; then
        CLAUDE_DIR=$(claude_config_dir)
        echo "── Claude Code ($CLAUDE_DIR) ──"
        cleanup_legacy "$HOME"
        install_to_dir \
            "$CLAUDE_DIR/skills" \
            "$CLAUDE_DIR/commands" \
            "Claude Code"

        # WSL 额外提示：Claude Code 路径是否已正确桥接
        if [ "$PLATFORM" = "wsl" ]; then
            APPDATA=$(wsl_windows_appdata 2>/dev/null || true)
            if [ -n "$APPDATA" ] && [ -d "$APPDATA/Claude" ]; then
                echo "  ✅ [WSL] 已写入 Windows Claude Code 路径: $CLAUDE_DIR"
            else
                echo "  ⚠️  [WSL] 未找到 Windows AppData/Claude，已写入 WSL 本地 ~/.claude/"
                echo "       如使用 Windows 版 Claude Code，请手动复制到 %APPDATA%\\Claude\\"
            fi
        fi
        echo ""
    fi

    # ── OpenCode ──
    if [ "$TARGET_OPENCODE" = "1" ]; then
        OC_DIR=$(opencode_config_dir)
        echo "── OpenCode ($OC_DIR) ──"
        # 双路径旧版残留清理（同项目级注释逻辑）
        for cmd in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
            [ -f "$OC_DIR/command/$cmd" ]  && rm -f "$OC_DIR/command/$cmd"
            [ -f "$OC_DIR/commands/$cmd" ] && rm -f "$OC_DIR/commands/$cmd"
        done
        install_to_dir \
            "$OC_DIR/skills" \
            "$OC_DIR/commands" \
            "OpenCode"
        echo ""
    fi

    # ── Codex CLI ──
    if [ "$TARGET_CODEX" = "1" ]; then
        CODEX_DIR=$(codex_config_dir)
        echo "── Codex CLI ($CODEX_DIR) ──"
        cleanup_codex_legacy_mirrors
        # Codex 无自定义 slash commands，只装 skill
        install_to_dir \
            "$CODEX_DIR/skills" \
            "" \
            "Codex"
        install_codex_aliases "$CODEX_DIR/skills"
        echo "  ℹ️  Codex 使用 \$handoff、\$handoff-recall、\$handoff-tidy、\$handoff-memory、\$handoff-init"
        echo ""
    fi
fi

# ── 可选：创建 HANDOFF.md ────────────────────────────────────────────────────

if [ -n "$TEMPLATE_TARGET" ]; then
    [ -d "$TEMPLATE_TARGET" ] || { echo "❌ 模板目标不存在: $TEMPLATE_TARGET"; exit 1; }
    TEMPLATE_ABS="$(cd "$TEMPLATE_TARGET" && pwd)"
    if [ -f "$TEMPLATE_ABS/HANDOFF.md" ]; then
        echo "⚠️  $TEMPLATE_ABS/HANDOFF.md 已存在，跳过（保留现有内容）"
    else
        cp "$SKILL_SRC/assets/HANDOFF.template.md" "$TEMPLATE_ABS/HANDOFF.md"
        echo "✅ HANDOFF.md 从模板创建于 $TEMPLATE_ABS/"
    fi
fi

# ── Unified completion banner (TKX standard) ────────────────────────────────

install_checkpoint "$_TKX_E_CHECK" "Validation"
install_step_ok "All targeted CLIs received the handoff skill"

install_banner_bottom "handoff" "$_HANDOFF_VERSION"
install_cli_table_begin
[ "$TARGET_CLAUDE" = "1" ]   && install_cli_row "Claude Code" "/handoff"          "$(claude_config_dir)/skills/handoff"
[ "$TARGET_OPENCODE" = "1" ] && install_cli_row "OpenCode"    "/handoff"          "$(opencode_config_dir)/skills/handoff"
[ "$TARGET_CODEX" = "1" ]    && install_cli_row "Codex CLI"   "\$handoff"          "$(codex_config_dir)/skills/handoff"
install_cli_table_end
install_next_block \
    "Run /handoff-init in a project root to create the v2 four-file scaffold" \
    "Run /handoff-recall to read an existing HANDOFF.md and report status" \
    "Sub-commands: \$handoff-init / \$handoff-recall / \$handoff-tidy / \$handoff-memory"
