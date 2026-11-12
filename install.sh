#!/bin/bash
# install.sh — HandoffX Skill Installer (v1.1+)
#
# Usage:
#   ./install.sh                          # 全局安装到所有已检测到的 AI CLI
#   ./install.sh --claude                 # 仅安装到 Claude Code
#   ./install.sh --opencode               # 仅安装到 OpenCode
#   ./install.sh --codex                  # 仅安装到 Codex CLI
#   ./install.sh --project <dir>          # 项目级安装（Claude Code）
#   ./install.sh --template <dir>         # 在 <dir> 创建主文件（名取 schema 常量）
#   ./install.sh --uninstall              # 卸载所有全局安装
#   ./install.sh --dry-run                # 显示计划（当前版本为兼容保留）
#   ./install.sh --journal-only           # 只解析并打印事务 op 清单（root/bak/absent/new），不改任何文件
#   ./install.sh --force                  # 覆盖确认（当前安装本身幂等）
#   ./install.sh --help
#
# 支持平台：macOS / Linux / Windows (WSL) · 支持 CLI：Claude Code / OpenCode / Codex CLI
#
# 事务（Decision 0028 决策 4）：一次调用一个 journal `$HOME/.handoffx-install/journal.<ts>`
# + 备份目录 `bak.<ts>/`，行格式 `bak <abs> <bak>` / `absent <abs>` / `new <abs>`。
# 先把所有 OLD_* 命中与将被覆盖的目标移入 bak，再拷贝/生成并逐项验证；所有选中 CLI
# 都成功才删 bak + journal。任一步失败 → 按 journal 逆序还原（删 new、移回 bak）→ exit 1；
# 还原全部成功则 journal/bak 一并删除，有还原失败则保留二者供人工检查。
# 仅供测试的 env（生产勿用）：HANDOFFX_INSTALL_FAIL_AT=<cleanup|skill-copy|shim-copy|
# alias-gen|second-cli> 在该点注入失败；HANDOFFX_TEST_OLD_EXTRA=<name> 往 OLD 集追加一个
# 名字，用来验证 assert_disjoint 自检（重叠 → exit 2）。

set -e

# ── 名集合（单一真相源；P2.2 hard-cut，Decision 0028 决策 3）──────────────────
# 文件系统操作只经由下列精确集合；绝不用前缀 glob 区分新旧（旧名是新名的前缀）。
# Claude Code 由 SKILL.md `name: handoffx` 注册 /handoffx，故不装 commands/handoffx.md
# （同名双源 = palette 重复，Gotcha #5）；OpenCode 不按 skill name 注册，另装主命令
# shim（Gotcha #9）。handoffx-tidy 不在任何 OLD 集：P2.1 已发过同名 alias，Codex 安装
# 时原子覆盖其内容（写 .new 再 mv），其他 CLI 不碰。Codex 旧主 skill 目录名即旧主 alias。
NEW_SKILL=handoffx
NEW_SHIMS="handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md"
NEW_MAIN_SHIM=handoffx.md
NEW_CODEX_ALIASES="handoffx-recall handoffx-tidy handoffx-memory handoffx-init"
OLD_SKILL_DIRS="handoff"
OLD_SHIMS="handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md hand-off.md"
OLD_CODEX_ALIASES="$OLD_SKILL_DIRS handoff-recall handoff-tidy handoff-memory handoff-init"
OLD_CODEX_PREFIX="source-command-handoff-"
OLD_MISC=".claude/handoff-scripts"
# 钩子值会进入清扫名集合：只收单个 [a-z][a-z0-9-]* 名，否则 glob / 多词会按 cwd 展开或
# 混入任意名字，把无关目录当旧物清扫。字母逐个列出，避免区间受 locale 排序影响。
if [ -n "${HANDOFFX_TEST_OLD_EXTRA:-}" ]; then
    case "$HANDOFFX_TEST_OLD_EXTRA" in
        [!abcdefghijklmnopqrstuvwxyz]*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
            echo "⚠️  忽略非法 HANDOFFX_TEST_OLD_EXTRA（须为单个 [a-z][a-z0-9-]* 名）" >&2 ;;
        *) OLD_CODEX_ALIASES="$OLD_CODEX_ALIASES $HANDOFFX_TEST_OLD_EXTRA" ;;
    esac
fi

# 安装布局（--journal-only 打印的就是它在本机的解析结果）：
#   Claude Code  ~/.claude/skills/handoffx/
#                ~/.claude/commands/handoffx-recall.md   ~/.claude/commands/handoffx-tidy.md
#                ~/.claude/commands/handoffx-memory.md   ~/.claude/commands/handoffx-init.md
#   OpenCode     ${XDG_CONFIG_HOME:-~/.config}/opencode/skills/handoffx/ + opencode/commands/ 下 5 个 shim
#   Codex CLI    ~/.agents/skills/handoffx/ + ~/.agents/skills/handoffx-{recall,tidy,memory,init}/
# OLD_* 清扫跨全部根进行，与选中哪家 CLI 无关；legacy ~/.codex/skills/handoffx* 镜像
# 只在 Codex 安装时去重（Gotcha #7）。--project 只动 <dir>/.claude .opencode .agents。

# 名集合自检：OLD_* 与 NEW_* 任一重叠即 exit 2（handoffx-tidy 进 OLD 集会被当旧物删掉）。
# 名集合按词拆分时一律 set -f：任何元素都不得按 cwd 做路径展开（下同）。
assert_disjoint() {
    local o n
    set -f
    for o in $OLD_SKILL_DIRS $OLD_SHIMS $OLD_CODEX_ALIASES "${OLD_MISC##*/}"; do
        for n in $NEW_SKILL $NEW_SHIMS $NEW_MAIN_SHIM $NEW_CODEX_ALIASES; do
            if [ "$o" = "$n" ]; then
                echo "❌ name-set overlap: '$o' is in both OLD_* and NEW_*" >&2
                exit 2
            fi
        done
    done
    for n in $NEW_SKILL $NEW_SHIMS $NEW_MAIN_SHIM $NEW_CODEX_ALIASES; do
        case "$n" in
            "$OLD_CODEX_PREFIX"*) echo "❌ name-set overlap: '$n' matches OLD prefix $OLD_CODEX_PREFIX" >&2; exit 2 ;;
        esac
    done
    set +f
    return 0
}
assert_disjoint

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$PLUGIN_DIR/skills/handoffx"
BOOTSTRAP_TMP=""
TXN_ACTIVE=0

cleanup_bootstrap() {
    local _exit=$?
    # 事务未提交就退出（set -e 中止 / 注入失败 / 信号）→ 按 journal 还原后 exit 1
    if [ "$TXN_ACTIVE" = "1" ]; then
        txn_rollback
        _exit=1
    fi
    [ -n "$BOOTSTRAP_TMP" ] && [ -d "$BOOTSTRAP_TMP" ] && rm -rf "$BOOTSTRAP_TMP"
    exit $_exit
}
trap cleanup_bootstrap EXIT
trap 'exit 130' INT TERM

show_help() {
    sed -n '2,15p' "$0" | sed -E 's/^# ?//'
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

# WSL 下 Windows 版 Claude Code 的配置目录（不存在则空）
wsl_claude_dir() {
    [ "$PLATFORM" = "wsl" ] || return 0
    local appdata
    appdata=$(wsl_windows_appdata 2>/dev/null || true)
    if [ -n "$appdata" ] && [ -d "$appdata/Claude" ]; then
        echo "$appdata/Claude"
    fi
    return 0
}

# Claude Code 配置目录：WSL 有 Windows Claude 时优先，否则 WSL / 本机 HOME
claude_config_dir() {
    local w
    w=$(wsl_claude_dir)
    if [ -n "$w" ]; then
        echo "$w"
        return
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
    SKILL_ZIP=$(ls "$PLUGIN_DIR"/handoffx-*.skill 2>/dev/null | head -n1 || true)
    SOURCE_TAR=$(ls "$PLUGIN_DIR"/handoffx-*-source.tar.gz 2>/dev/null | head -n1 || true)
    if [ -n "$SKILL_ZIP" ]; then
        echo "📦 未找到源码目录，自举解压 $(basename "$SKILL_ZIP")..."
        BOOTSTRAP_TMP=$(mktemp -d)
        if ! command -v unzip >/dev/null 2>&1; then
            echo "❌ unzip is required for .skill bootstrap but was not found" >&2
            echo "   Install it with: brew install unzip  OR  apt-get install unzip" >&2
            exit 1
        fi
        unzip -q "$SKILL_ZIP" -d "$BOOTSTRAP_TMP"
        if [ -d "$BOOTSTRAP_TMP/handoffx" ]; then
            mkdir -p "$BOOTSTRAP_TMP/skills"
            mv "$BOOTSTRAP_TMP/handoffx" "$BOOTSTRAP_TMP/skills/handoffx"
            PLUGIN_DIR="$BOOTSTRAP_TMP"
            SKILL_SRC="$PLUGIN_DIR/skills/handoffx"
        else
            # 根不对时不能静默落到下面的泛泛提示：点名原因，有 tarball 就回落
            echo "❌ $(basename "$SKILL_ZIP") 的顶层目录不是 handoffx/" >&2
            rm -rf "$BOOTSTRAP_TMP"; BOOTSTRAP_TMP=""
            if [ -z "$SOURCE_TAR" ]; then
                echo "   同目录也没有 handoffx-*-source.tar.gz 可回落；请换一个顶层为 handoffx/ 的 .skill" >&2
                exit 1
            fi
            echo "   改用同目录的 $(basename "$SOURCE_TAR")" >&2
        fi
    fi
    if [ ! -d "$SKILL_SRC" ] && [ -n "$SOURCE_TAR" ]; then
        echo "📦 未找到源码目录，自举解压 $(basename "$SOURCE_TAR")..."
        BOOTSTRAP_TMP=$(mktemp -d)
        tar xzf "$SOURCE_TAR" -C "$BOOTSTRAP_TMP"
        EXTRACTED_ROOT=$(ls -d "$BOOTSTRAP_TMP"/handoffx-* 2>/dev/null | head -n1 || true)
        if [ -n "$EXTRACTED_ROOT" ] && [ -d "$EXTRACTED_ROOT/skills/handoffx" ]; then
            PLUGIN_DIR="$EXTRACTED_ROOT"
            SKILL_SRC="$PLUGIN_DIR/skills/handoffx"
        fi
    fi
fi

if [ ! -d "$SKILL_SRC" ]; then
    echo "❌ 找不到 skills/handoffx/"
    echo "   install.sh 需要以下其一（同目录）："
    echo "     • HandoffX 源码根目录（含 skills/handoffx/ 子目录），或"
    echo "     • 同目录的 handoffx-*.skill 单文件包，或"
    echo "     • 同目录的 handoffx-*-source.tar.gz"
    exit 1
fi

# v2.1.3 backward compat: 旧 .skill / source tarball（v2.1.2 及更早）的 shim 源
# 目录叫 commands/；v2.1.3 起改名 command-shims/（让"这是 install.sh 的 shim 源
# 镜像，不是 Claude Code 直读路径"明示，Gotcha #5 同根）。从旧包 bootstrap 时
# 自动迁名，让下游安装统一只看 command-shims/。
# v2.1.5（Round 1 review I4）: 处理 both-exist 边角——若两个目录都在，
# command-shims/ 是 canonical，删掉 legacy commands/ 防 silent revival。
if [ -d "$SKILL_SRC/commands" ]; then
    if [ ! -d "$SKILL_SRC/command-shims" ]; then
        mv "$SKILL_SRC/commands" "$SKILL_SRC/command-shims"  # 老包 bootstrap: rename
    else
        rm -rf "$SKILL_SRC/commands"  # both exist: legacy cleanup（canonical 是 command-shims/）
    fi
fi

# Four-piece names from the single schema source (P2.4). Fail-closed: without
# the tree there is nothing to install anyway, and a fallback copy of the names
# here would drift from the scripts the install ships. The bundle twin under
# $SKILL_SRC covers .skill / tarball bootstrap (no scripts/ next to install.sh).
_HX_SCHEMA_LIB="$(cd "$(dirname "$0")" && pwd)/scripts/lib/handoff-schema.sh"
[ -f "$_HX_SCHEMA_LIB" ] || _HX_SCHEMA_LIB="$SKILL_SRC/scripts/lib/handoff-schema.sh"
if [ ! -f "$_HX_SCHEMA_LIB" ]; then
    echo "❌ 找不到 schema 常量库 scripts/lib/handoff-schema.sh（install.sh 需要完整源码树或 .skill 包）" >&2
    exit 1
fi
# shellcheck source=scripts/lib/handoff-schema.sh
. "$_HX_SCHEMA_LIB"
# Legacy layouts are classified by hx_legacy_layout_kind (schema lib). Why the
# shared one: the install warning and the --template refusal must name the
# same upgrade path the tidy / validate / postflight guards name.

# ── 参数解析 ─────────────────────────────────────────────────────────────────

MODE="auto"        # auto = 安装到所有检测到的 CLI
TARGET_CLAUDE=0
TARGET_OPENCODE=0
TARGET_CODEX=0
PROJECT=""
TEMPLATE_TARGET=""
UNINSTALL=0
DRY_RUN=0
JOURNAL_ONLY=0
FORCE=0
GLOBAL_FLAG=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --claude)     TARGET_CLAUDE=1;   MODE="explicit" ;;
        --opencode)   TARGET_OPENCODE=1; MODE="explicit" ;;
        --codex)      TARGET_CODEX=1;    MODE="explicit" ;;
        --global)     MODE="auto"; GLOBAL_FLAG=1 ;;
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
        --uninstall)    UNINSTALL=1 ;;
        --dry-run)      DRY_RUN=1 ;;
        --journal-only) JOURNAL_ONLY=1 ;;
        --force)        FORCE=1 ;;
        *) echo "❌ 未知参数: $1（--help 查看用法）" >&2; exit 2 ;;
    esac
    shift
done

# 互斥组合在任何文件改动之前拒绝：后出现的全局开关会覆盖 MODE 而 PROJECT 仍在，
# banner 说项目级、实际却装到全局；--uninstall 分支又先于 project 分支，会卸掉全局安装
if [ -n "$PROJECT" ]; then
    if [ "$TARGET_CLAUDE$TARGET_OPENCODE$TARGET_CODEX$GLOBAL_FLAG" != "0000" ]; then
        echo "❌ --project 不能与 --claude/--opencode/--codex/--global 同用（项目级安装按本机检测到的 CLI 决定）" >&2
        exit 2
    fi
    if [ "$UNINSTALL" = "1" ]; then
        echo "❌ --project 不能与 --uninstall 同用：尚未实现项目级卸载（请手动删除 <dir>/.claude .opencode .agents 下的安装）" >&2
        exit 2
    fi
fi
# 卸载分支在模板步骤之前就退出，模板会被静默忽略
if [ "$UNINSTALL" = "1" ] && [ -n "$TEMPLATE_TARGET" ]; then
    echo "❌ --uninstall 不能与 --template 同用（卸载不创建 ${HX_MAIN_FILE}）" >&2
    exit 2
fi
# 模板目标若到提交后才检查，失败时安装已落盘、却以错误退出
if [ -n "$TEMPLATE_TARGET" ] && [ ! -d "$TEMPLATE_TARGET" ]; then
    echo "❌ 模板目标不存在: $TEMPLATE_TARGET" >&2
    exit 2
fi
if [ -n "$TEMPLATE_TARGET" ] && [ ! -w "$TEMPLATE_TARGET" ]; then
    echo "❌ 模板目标不可写: $TEMPLATE_TARGET" >&2
    exit 2
fi
# 模板目标仍是旧布局 → 在任何安装动作之前拒绝（P2.4 §4b-4）：在旧布局旁再造一个新名
# 主文件 = 人为制造新旧并存（schema-upgrade 会判 MIXED 拒迁）。判定看解析后的目标目录，
# 不看 PWD；拒绝时零写入（目标与各 CLI 安装根都不动）。
if [ -n "$TEMPLATE_TARGET" ]; then
    _tpl_abs="$(cd "$TEMPLATE_TARGET" && pwd)"
    if [ "$(hx_legacy_layout_kind "$_tpl_abs")" != none ]; then
        echo "❌ --template 目标 ${_tpl_abs} 含旧布局（${HX_LEGACY_MAIN_FILE} / ${HX_LEGACY_LOGS_DIR}/ / ${HX_LEGACY_DEC_DIR}/），拒绝创建 ${HX_MAIN_FILE}，未做任何改动" >&2
        case "$(hx_legacy_layout_kind "$_tpl_abs")" in
            v1) echo "   先迁移：migrate-to-v2.sh --dry-run --root ${_tpl_abs}，再 migrate-to-v2.sh --apply --root ${_tpl_abs}" >&2 ;;
            v3) echo "   先升级：在该目录运行 /handoffx-tidy schema-upgrade（tidy-handoff.sh schema-upgrade --dry-run|--apply --root ${_tpl_abs}）" >&2 ;;
            *)  echo "   先在该目录运行 /handoffx-tidy：它按内容判定并给出确切命令（v1 → migrate-to-v2.sh，四件套 → schema-upgrade，新旧并存 → 先处理冲突）" >&2 ;;
        esac
        exit 1
    fi
fi

# auto 模式：检测已安装的 CLI，自动决定安装目标
if [ "$MODE" = "auto" ]; then
    command -v claude   >/dev/null 2>&1 && TARGET_CLAUDE=1
    command -v opencode >/dev/null 2>&1 && TARGET_OPENCODE=1
    command -v codex    >/dev/null 2>&1 && TARGET_CODEX=1
    # 即使未检测到 claude，默认也装 Claude Code（最常见场景）
    TARGET_CLAUDE=1
fi

if [ "$MODE" = "project" ] && [ "$UNINSTALL" != "1" ]; then
    [ -d "$PROJECT" ] || { echo "❌ 项目目录不存在: $PROJECT"; exit 1; }
    PROJECT_ABS="$(cd "$PROJECT" && pwd)"
fi

# ── 事务：journal + 备份目录 ─────────────────────────────────────────────────
# 解析阶段只填下面四个换行分隔的清单，不碰文件系统（--journal-only 到此为止）：
#   ROOTS   扫描/安装涉及的根（供 --journal-only 与 Task 6 沙箱断言）
#   SWEEPS  将被移入 bak 且不再重建的路径（OLD_* 命中 + 选中 CLI 的同名去重目标）
#   TARGETS "<cli> <kind> <abs>"，kind = skill | shim | alias（将被重建）
#   CLIS    选中 CLI 的安装顺序
TXN_HOME="$HOME/.handoffx-install"
TXN_TS="$(date +%Y%m%d%H%M%S).$$"
JOURNAL="$TXN_HOME/journal.$TXN_TS"
BAK_DIR="$TXN_HOME/bak.$TXN_TS"
NL='
'
ROOTS="$NL"
SWEEPS="$NL"
TARGETS=""
CLIS=""

# 清单是换行分隔的字符串、journal 是逐行文本（Task 6 按行派生备份清单），所以任何
# 进清单的路径都不得含换行 / 控制字符：否则一个怪名目录会被拆成两条"路径"，第二
# 段可以是任意绝对路径，被移入 bak 后随提交删除。发现即拒绝整次调用（此时尚未
# 改动任何文件），绝不静默跳过。只拒控制字符而非"不可打印"：C locale 下非 ASCII
# 的合法用户目录（如中文用户名）会被 [:print:] 误判。
# 下面两个扫描函数只经 sweep_add 登记路径；校验与登记函数（add_root / sweep_add /
# safe_abs / owned_name / refuse_path）定义在它们之后——bash 在调用时才解析函数名，
# 而所有调用都发生在后面的解析阶段。

# skill 类根：OLD 主 skill 目录、OLD Codex alias、过时 source-command-handoff-* 前缀
sweep_skills_root() {
    local n p r
    check_root_readable "$1"
    r=$(phys_path "$1")
    add_root "$r"
    set -f
    for n in $OLD_SKILL_DIRS $OLD_CODEX_ALIASES; do sweep_add "$r" "$n"; done
    set +f
    for p in "$r/$OLD_CODEX_PREFIX"*; do
        if [ -e "$p" ] || [ -L "$p" ]; then sweep_add "$r" "${p#"$r"/}"; fi
    done
    case "$SKILL_ROOTS" in *"$NL$r$NL"*) ;; *) SKILL_ROOTS="$SKILL_ROOTS$r$NL" ;; esac
    return 0
}

# 嵌套/隐藏目录里的旧名 skill 目录（备份残留等）不在清扫范围——清扫只动直接子项，且那是
# 用户数据；但 OpenCode 递归扫 skills/**/SKILL.md、含隐藏目录、跟随符号链接，旧名会从那里
# 复活（Gotcha #28）。只报不删。顶层分量本次会被移走（在 SWEEPS）或整体替换（在 TARGETS）
# 的不报——报了用户去看时已经没了；所以这一步只能在解析全部完成之后做。同一物理根可经
# 不同字符串到达，SKILL_ROOTS 登记时已按物理路径去重。深度封顶防止走进 node_modules 之类
# 的大树；find 自己的报错照常进 stderr，它的退出码不得中止安装——赋值后接 || true，中间
# 不能再有任何会失败的管道（set -e 下命令替换的状态会随赋值传出来）。
SKILL_ROOTS="$NL"
warn_nested_old() {   # <phys-root>
    local n p top hits first=1
    local -a expr
    [ -d "$1" ] || return 0
    set -f
    for n in $OLD_SKILL_DIRS $OLD_CODEX_ALIASES; do
        if [ "$first" = 1 ]; then expr=(-name "$n"); first=0; else expr+=(-o -name "$n"); fi
    done
    set +f
    hits=$(find -L "$1" -mindepth 2 -maxdepth 6 -type d \( "${expr[@]}" \) \
                -exec sh -c 'test -f "$1/SKILL.md"' _ '{}' \; -print) || true
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        top=${p#"$1"/}; top="$1/${top%%/*}"
        case "$SWEEPS" in *"$NL$top$NL"*) continue ;; esac
        case "$TARGETS" in *" $top$NL"*) continue ;; esac
        echo "⚠️  嵌套旧名 skill 目录：${p}（不在清扫范围；OpenCode 会递归扫到并复活旧名，请手工处理——Gotcha #28）" >&2
    done <<EOF
$hits
EOF
    return 0
}
warn_nested_all() {
    local r
    while IFS= read -r r; do [ -n "$r" ] && warn_nested_old "$r"; done <<EOF
$SKILL_ROOTS
EOF
    return 0
}

# command 类根：OLD shim 精确基名
sweep_commands_root() {
    local n r
    check_root_readable "$1"
    r=$(phys_path "$1")
    add_root "$r"
    set -f
    for n in $OLD_SHIMS; do sweep_add "$r" "$n"; done
    set +f
    return 0
}

# 同一物理目录可经符号链接以不同字符串出现（如 opencode/skills → ~/.claude/skills）；
# 按字符串去重会把它当两个根：第二家 CLI 拷进已装目录造成嵌套，同一旧物被移两次而
# 第二次失败。故所有根先归一到物理路径：最深的已存在祖先取 pwd -P，其余分量原样拼回，
# 使不存在的根也与经链接到达的同一目录得到相同字符串。末尾加 . 再剥掉，防 $() 吞掉
# 目录名末尾换行而绕过 safe_abs 的控制字符检查。
phys_path() {   # <abs>
    local d="$1" rest="" p
    safe_abs "$1"
    while [ ! -d "$d" ]; do rest="/${d##*/}$rest"; d=$(dirname "$d"); done
    # 回退成未归一的字符串会让同一物理目录再次以两个根出现（F3/F4 母题），只能拒绝
    p=$(cd -P -- "$d" 2>/dev/null && pwd -P && echo .) || {
        echo "❌ 无法解析物理路径：$1（$d 不可进入）" >&2
        exit 1
    }
    p=${p%"$NL".}
    [ "$p" = / ] && p=""
    printf '%s%s\n' "$p" "$rest"
}

# 无 r/x 权限的根里 [ -e ] 看不见旧物，会静默"清扫干净"；fail-closed（Gotcha #24）。
# 上级目录不可进入时 [ -d 根 ] 同样为假，与"根不存在"无从区分，故检查最深的可见祖先
check_root_readable() {   # <root> [link-hops]
    local d="$1" t hops="${2:-0}"
    if [ -d "$d" ]; then
        if [ ! -r "$d" ] || [ ! -x "$d" ]; then
            echo "❌ 无法读取清扫根：$1（请修复权限后重试）" >&2
            exit 1
        fi
        return 0
    fi
    while [ ! -d "$d" ]; do
        # 指进不可进入目录的链接同样 [ -d ] 为假；若只看链接父目录就放行，旧物被静默保留、
        # 卸载谎报完成。故沿链接目标再查一次；目标祖先可进入、仅目标缺失的悬空链接照常放行。
        # 环形链接里本就看不到任何旧物，跳数上限只为防递归不止
        if [ -L "$d" ] && [ "$hops" -lt 40 ]; then
            t=$(readlink "$d")
            case "$t" in /*) ;; *) t="$(dirname "$d")/$t" ;; esac
            check_root_readable "$t" $((hops+1))
        fi
        d=$(dirname "$d")
    done
    if [ ! -r "$d" ] || [ ! -x "$d" ]; then
        echo "❌ 无法读取清扫根：$1（上级目录不可进入：${d}）" >&2
        exit 1
    fi
    return 0
}

refuse_path() {
    echo "❌ refusing suspicious path: $(printf '%q' "$1") ($2)" >&2
    exit 1
}

safe_abs() {   # <path> — 绝对路径、无控制字符、无 . / .. 段
    case "$1" in
        *[[:cntrl:]]*) refuse_path "$1" "control character in path" ;;
        /*) ;;
        *) refuse_path "$1" "not absolute" ;;
    esac
    case "$1/" in
        */./*|*/../*) refuse_path "$1" "dot segment" ;;
    esac
    return 0
}

# 本安装器认领的基名：精确 OLD_* / NEW_* 名，或 OLD_CODEX_PREFIX 前缀族
owned_name() {   # <name> → 0 = ours
    local n hit=1
    case "$1" in
        ""|.|..|*/*|*[[:cntrl:]]*) return 1 ;;
        "$OLD_CODEX_PREFIX"?*) return 0 ;;
    esac
    set -f
    for n in $OLD_SKILL_DIRS $OLD_SHIMS $OLD_CODEX_ALIASES "${OLD_MISC##*/}" \
             $NEW_SKILL $NEW_SHIMS $NEW_MAIN_SHIM $NEW_CODEX_ALIASES; do
        if [ "$1" = "$n" ]; then
            hit=0; break
        fi
    done
    set +f
    return $hit
}

add_root() {
    safe_abs "$1"
    case "$ROOTS" in *"$NL$1$NL"*) ;; *) ROOTS="$ROOTS$1$NL" ;; esac
    return 0
}

# sweep_add <root> <name>：只登记 root 的直接子项、且基名属于本安装器；不存在则不登记；
# 完整路径行匹配去重（多根重合时不重复移动）
sweep_add() {
    local p="$1/$2"
    safe_abs "$p"
    if ! owned_name "$2"; then
        refuse_path "$p" "not an exact installer-owned name under $1"
    fi
    if [ -e "$p" ] || [ -L "$p" ]; then
        case "$SWEEPS" in *"$NL$p$NL"*) ;; *) SWEEPS="$SWEEPS$p$NL" ;; esac
    fi
    return 0
}

add_target() {   # <cli> <kind> <abs>
    safe_abs "$3"
    if ! owned_name "${3##*/}"; then
        refuse_path "$3" "target basename is not a NEW_* name"
    fi
    TARGETS="$TARGETS$1 $2 $3$NL"
    return 0
}

add_cli() {
    CLIS="$CLIS$1$NL"
    return 0
}

# 三家 CLI 的规范安装根（物理路径），与选中哪家无关：NEW 名去重只针对"非任何 CLI 安装根"
# 的旁路目录；旁路目录若经链接就是某家的安装根，清扫 NEW 名 = 删掉那家刚装好的东西
CANON="$NL"
set_canon_roots() {   # <claude-dir> <opencode-dir> <agents-dir> <touches-commands 0|1>
    local cs cc os oc as
    # 每个 $() 单独赋值：一条赋值里多个替换只有最后一个的失败会触发 set -e
    cs=$(phys_path "$1/skills"); cc=$(phys_path "$1/commands")
    os=$(phys_path "$2/skills"); oc=$(phys_path "$2/commands")
    as=$(phys_path "$3/skills")
    # Claude 的 commands 不得有主命令 shim（Gotcha #5），OpenCode 的必须有（Gotcha #9）；
    # 同一物理目录无法同时满足，任何一家的安装都会破坏另一家。本次不装这两家（如只装
    # Codex）时根本不写该目录，拒绝只会挡掉无关安装
    if [ "$4" = "1" ] && [ "$cc" = "$oc" ]; then
        echo "❌ Claude Code 与 OpenCode 的 commands 是同一物理目录：$cc" >&2
        echo "   两家对 $NEW_MAIN_SHIM 的要求在共享目录中互相矛盾（Claude 不得有、OpenCode 必须有）；请拆成两个独立目录后重试" >&2
        exit 2
    fi
    CANON="$NL$cs$NL$cc$NL$os$NL$oc$NL$as$NL"
    return 0
}

is_canon_root() {   # <phys-root>
    case "$CANON" in *"$NL$1$NL"*) return 0 ;; esac
    return 1
}

cli_label() {
    case "$1" in
        claude)   echo "Claude Code" ;;
        opencode) echo "OpenCode" ;;
        codex)    echo "Codex" ;;
        *)        echo "$1" ;;
    esac
}

# 全局根矩阵。OLD_* 清扫对每个根都做，与选中哪家 CLI 无关（OpenCode 也读
# ~/.claude/skills 与 ~/.agents/skills，旧物留在任一根都会重复出现）。
resolve_global_sweeps() {
    local oc ag wsl_cl r m
    oc=$(opencode_config_dir); ag=$(codex_config_dir); wsl_cl=$(wsl_claude_dir)
    for r in "$HOME/.claude/skills" "$oc/skills" "$ag/skills" "$HOME/.codex/skills"; do
        sweep_skills_root "$r"
    done
    for r in "$HOME/.claude/commands" "$oc/command" "$oc/commands"; do
        sweep_commands_root "$r"
    done
    m=$(phys_path "$HOME/${OLD_MISC%/*}")
    add_root "$m/${OLD_MISC##*/}"
    sweep_add "$m" "${OLD_MISC##*/}"
    if [ -n "$wsl_cl" ]; then
        sweep_skills_root "$wsl_cl/skills"
        sweep_commands_root "$wsl_cl/commands"
        m=$(phys_path "$wsl_cl")
        add_root "$m/${OLD_MISC#.claude/}"
        sweep_add "$m" "${OLD_MISC##*/}"
    fi
    return 0
}

# 某 CLI 的安装目标：skill 目录 + shim（+ OpenCode 主命令）+ Codex alias
plan_claude() {   # <claude-dir>
    local s sk cm
    sk=$(phys_path "$1/skills"); cm=$(phys_path "$1/commands")
    add_cli claude
    add_root "$sk"; add_root "$cm"
    add_target claude skill "$sk/$NEW_SKILL"
    set -f
    for s in $NEW_SHIMS; do add_target claude shim "$cm/$s"; done
    set +f
    # /handoffx 只由 SKILL.md name 注册；旧版若留下主命令 shim 则移除（Gotcha #5）
    sweep_add "$cm" "$NEW_MAIN_SHIM"
    return 0
}

plan_opencode() {   # <opencode-dir>
    local s sk c1 cs
    sk=$(phys_path "$1/skills"); c1=$(phys_path "$1/command"); cs=$(phys_path "$1/commands")
    add_cli opencode
    add_root "$sk"; add_root "$c1"; add_root "$cs"
    add_target opencode skill "$sk/$NEW_SKILL"
    set -f
    for s in $NEW_SHIMS $NEW_MAIN_SHIM; do
        add_target opencode shim "$cs/$s"
        # OpenCode v1.14+ 同时读单数 command/ 与复数 commands/，按命令名合并（Gotcha #9/#16；
        # 1.14.30 实测同名只留一份）；command/ 若经链接就是某家的安装根，这些 NEW 名正是刚装的
        # 目标，跳过即可——按名合并意味着这里不会出现重复，无需警告
        if ! is_canon_root "$c1"; then sweep_add "$c1" "$s"; fi
    done
    set +f
    return 0
}

plan_codex() {   # <agents-dir> [legacy-codex-skills-dir]
    local a sk lg=""
    sk=$(phys_path "$1/skills")
    if [ -n "${2:-}" ]; then lg=$(phys_path "$2"); fi
    add_cli codex
    add_root "$sk"
    add_target codex skill "$sk/$NEW_SKILL"
    set -f
    for a in $NEW_CODEX_ALIASES; do add_target codex alias "$sk/$a"; done
    set +f
    # legacy 根若经链接就是任一家的安装根（不只 agents 根），再清扫 NEW 名等于删掉那家的安装
    if [ -n "$lg" ] && ! is_canon_root "$lg"; then
        add_root "$lg"
        set -f
        for a in $NEW_SKILL $NEW_CODEX_ALIASES; do sweep_add "$lg" "$a"; done
        set +f
    elif [ -n "$lg" ] && [ "$lg" != "$sk" ]; then
        # 跳过了就要说：经 legacy 路径仍能看到那家装的东西，重复不是本安装器能消的。
        # legacy 根就是 Codex 自己的 skills 根时（~/.codex/skills → ~/.agents/skills）只有一棵树，不报
        echo "⚠️  未清扫 legacy 根 ${lg}（它是另一家 CLI 的安装根；若 Codex 仍读 ~/.codex/skills，其中的 ${NEW_SKILL}* 会再出现一份——Gotcha #28）" >&2
    fi
    return 0
}

resolve_global_install() {
    local touch=0
    resolve_global_sweeps
    if [ "$TARGET_CLAUDE$TARGET_OPENCODE" != "00" ]; then touch=1; fi
    set_canon_roots "$(claude_config_dir)" "$(opencode_config_dir)" "$(codex_config_dir)" "$touch"
    if [ "$TARGET_CLAUDE" = "1" ]; then plan_claude "$(claude_config_dir)"; fi
    if [ "$TARGET_OPENCODE" = "1" ]; then plan_opencode "$(opencode_config_dir)"; fi
    if [ "$TARGET_CODEX" = "1" ]; then plan_codex "$(codex_config_dir)" "$HOME/.codex/skills"; fi
    return 0
}

# --project：只动 <dir> 下的 .claude / .opencode / .agents，全局根一律不碰
resolve_project_install() {
    local p="$PROJECT_ABS" m
    sweep_skills_root "$p/.claude/skills"
    sweep_skills_root "$p/.opencode/skills"
    sweep_skills_root "$p/.agents/skills"
    sweep_commands_root "$p/.claude/commands"
    sweep_commands_root "$p/.opencode/command"
    sweep_commands_root "$p/.opencode/commands"
    m=$(phys_path "$p/${OLD_MISC%/*}")
    add_root "$m/${OLD_MISC##*/}"
    sweep_add "$m" "${OLD_MISC##*/}"
    # 项目级总会装 Claude（plan_claude 无条件），共享 commands 目录照旧拒绝
    set_canon_roots "$p/.claude" "$p/.opencode" "$p/.agents" 1
    plan_claude "$p/.claude"
    if command -v opencode >/dev/null 2>&1; then plan_opencode "$p/.opencode"; fi
    if command -v codex >/dev/null 2>&1; then plan_codex "$p/.agents"; fi
    return 0
}

# 卸载：同一根矩阵，OLD_* 与 NEW_* 全部移除
resolve_uninstall() {
    local oc ag wsl_cl r n
    resolve_global_sweeps
    oc=$(opencode_config_dir); ag=$(codex_config_dir); wsl_cl=$(wsl_claude_dir)
    for r in "$HOME/.claude/skills" "$oc/skills" "$ag/skills" "$HOME/.codex/skills" ${wsl_cl:+"$wsl_cl/skills"}; do
        r=$(phys_path "$r")
        set -f
        for n in $NEW_SKILL $NEW_CODEX_ALIASES; do sweep_add "$r" "$n"; done
        set +f
    done
    for r in "$HOME/.claude/commands" "$oc/command" "$oc/commands" ${wsl_cl:+"$wsl_cl/commands"}; do
        r=$(phys_path "$r")
        set -f
        for n in $NEW_SHIMS $NEW_MAIN_SHIM; do sweep_add "$r" "$n"; done
        set +f
    done
    return 0
}

bak_path() {
    printf '%s/%s\n' "$BAK_DIR" "${1#/}"
}

# --journal-only：按执行顺序打印将发生的 op（与 journal 同格式，另加 root 行）。
# 两家共用物理根时同一目标出现两次：执行时第一次已把它移入 bak，第二次只记 absent，
# 也只拷贝一次（put_skill 认出本次新建），打印须与之一致
print_plan() {
    local p cli kind d made="$NL" seen="$NL" chain
    while IFS= read -r p; do [ -n "$p" ] && echo "root $p"; done <<EOF
$ROOTS
EOF
    while IFS= read -r p; do [ -n "$p" ] && echo "bak $p $(bak_path "$p")"; done <<EOF
$SWEEPS
EOF
    while IFS=' ' read -r cli kind p; do
        [ -n "$p" ] || continue
        case "$seen" in
            *"$NL$p$NL"*) echo "absent $p"; continue ;;
        esac
        seen="$seen$p$NL"
        if [ -e "$p" ] || [ -L "$p" ]; then echo "bak $p $(bak_path "$p")"; else echo "absent $p"; fi
    done <<EOF
$TARGETS
EOF
    while IFS=' ' read -r cli kind p; do
        [ -n "$p" ] || continue
        case "$made" in *"$NL$p$NL"*) continue ;; esac
        chain=""; d=$(dirname "$p")
        while [ ! -e "$d" ] && [ ! -L "$d" ]; do chain="$d$NL$chain"; d=$(dirname "$d"); done
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            case "$made" in *"$NL$d$NL"*) ;; *) made="$made$d$NL"; echo "new $d" ;; esac
        done <<EOF
$chain
EOF
        made="$made$p$NL"
        echo "new $p"
    done <<EOF
$TARGETS
EOF
    return 0
}

# 仅供测试：HANDOFFX_INSTALL_FAIL_AT=<点> 在该点返回 1 → set -e 中止 → EXIT trap 还原
fail_point() {
    if [ "${HANDOFFX_INSTALL_FAIL_AT:-}" = "$1" ]; then
        echo "❌ injected failure at $1 (HANDOFFX_INSTALL_FAIL_AT, test-only)" >&2
        return 1
    fi
    return 0
}

# journal 先写意图再做动作：中途被杀时，还原只认实际存在的 bak / new
jlog() {
    printf '%s\n' "$*" >> "$JOURNAL"
}

txn_begin() {
    local j
    # 事务目录若是链接，bak 会落到链接目标里、提交时随之删除
    if [ -L "$TXN_HOME" ]; then
        echo "❌ 事务目录是符号链接，拒绝使用：$TXN_HOME" >&2
        exit 1
    fi
    # 否则只剩 mkdir 的一句 "File exists"，看不出是哪个路径、该怎么办
    if [ -e "$TXN_HOME" ] && [ ! -d "$TXN_HOME" ]; then
        echo "❌ 事务目录被非目录占用：${TXN_HOME}（请移走后重试）" >&2
        exit 1
    fi
    [ -d "$TXN_HOME" ] || mkdir -m 700 "$TXN_HOME"
    # 遗留 journal = 上次运行被杀、或还原失败；其 bak 里可能是用户唯一的旧副本，
    # 新事务若继续，提交时的 rmdir 会掩盖它的存在
    for j in "$TXN_HOME"/journal.*; do
        if [ -e "$j" ] || [ -L "$j" ]; then
            echo "❌ 发现未完成事务的遗留 journal：$j" >&2
            echo "   对应备份目录：$TXN_HOME/bak.${j##*/journal.}" >&2
            echo "   请按 journal 逐行手工还原（bak 行：<原路径> <备份路径>；new 行：本次新建项），核对无误后删除该 journal 与备份目录再重试" >&2
            exit 1
        fi
    done
    mkdir -p "$BAK_DIR"
    : > "$JOURNAL"
    TXN_ACTIVE=1
}

txn_move_to_bak() {
    local b
    b=$(bak_path "$1")
    mkdir -p "$(dirname "$b")"
    jlog "bak $1 $b"
    mv "$1" "$b"
}

# alias 原地覆盖（不留"alias 不存在"的窗口）：先完整复制到 bak，复制完才改名就位
txn_copy_to_bak() {
    local b
    b=$(bak_path "$1")
    mkdir -p "$(dirname "$b")"
    jlog "bak $1 $b"
    cp -Rp "$1" "$b.partial"
    mv "$b.partial" "$b"
}

# 逐级创建缺失的父目录并记 new，回滚时连本次新建的空目录一起删。只把"不存在"的
# 层级记成 new：已存在但不是目录的路径（用户的文件）绝不能进 journal，否则回滚会删掉它
ensure_dir() {
    local d="$1" chain=""
    while [ ! -e "$d" ] && [ ! -L "$d" ]; do chain="$d$NL$chain"; d=$(dirname "$d"); done
    if [ ! -d "$d" ]; then
        echo "  ❌ 路径被非目录占用：${d}" >&2
        return 1
    fi
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        jlog "new $d"
        mkdir "$d"
    done <<EOF
$chain
EOF
    return 0
}

yaml_single_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/''/g")"
}

alias_body() {   # <cmd_name> <shim-source>
    local cmd_name="$1" cmd_path="$2"
    echo "---"
    printf "name: %s\n" "$(yaml_single_quote "$cmd_name")"
    printf "description: %s\n" "$(yaml_single_quote "Codex \$$cmd_name alias. Use skill: handoffx.")"
    echo "---"
    echo ""
    echo "# /$cmd_name"
    echo ""
    echo "Use skill: handoffx."
    echo ""
    echo "This Codex alias mirrors \`skills/handoffx/command-shims/$cmd_name.md\` so \`\$$cmd_name\` works like \`/$cmd_name\` in Claude Code / OpenCode."
    echo ""
    awk '
        BEGIN { state = "body" }
        NR == 1 && $0 == "---" { state = "frontmatter"; next }
        state == "frontmatter" && $0 == "---" { state = "body"; next }
        state == "body" { print }
    ' "$cmd_path"
}

put_skill() {
    # cp -R 到已存在的目录会拷进其内部（嵌套 handoffx/handoffx/）而非替换
    if [ -e "$1" ] || [ -L "$1" ]; then
        if grep -qxF "new $1" "$JOURNAL"; then
            echo "  ↪ Skill 已由本次事务装入（同一物理目录）：$1/"
            return 0
        fi
        echo "  ❌ 目标已存在，拒绝覆盖：$1" >&2
        return 1
    fi
    ensure_dir "$(dirname "$1")"
    jlog "new $1"
    cp -R "$SKILL_SRC" "$1"
    # command-shims/ 只是 shim 源镜像；留在 skill 目录里 Claude Code 会把它当嵌套命令源
    # 重复登记（Gotcha #5）；commands/ 是 v2.1.2 及更早包的同一目录旧名
    rm -rf "$1/command-shims" "$1/commands"
    chmod +x "$1/scripts/"*.sh 2>/dev/null || true
    echo "  ✅ Skill → $1/"
}

put_shim() {
    local src
    src="$SKILL_SRC/command-shims/$(basename "$1")"
    ensure_dir "$(dirname "$1")"
    jlog "new $1"
    cp "$src" "$1"
    echo "  ✅ Command → $1"
}

put_alias() {
    local name src
    name=$(basename "$1")
    src="$SKILL_SRC/command-shims/$name.md"
    if [ ! -f "$src" ]; then
        echo "  ❌ alias 源缺失：$src" >&2
        return 1
    fi
    # 链接上的 mkdir -p 会成功，SKILL.md 随之写穿到链接目标（txn_stage 已把链接移走）
    if [ -L "$1" ]; then
        echo "  ❌ alias 目标是符号链接，拒绝写入：$1" >&2
        return 1
    fi
    ensure_dir "$(dirname "$1")"
    jlog "new $1"
    mkdir -p "$1"
    alias_body "$name" "$src" > "$1/SKILL.md.new"
    mv -f "$1/SKILL.md.new" "$1/SKILL.md"
    echo "  ✅ Alias → $1/"
}

# 逐项验证本 CLI 的目标；任一不符 → 返回 1（调用方 set -e → 整体还原）
verify_cli() {
    local want="$1" cli kind p bad=0
    while IFS=' ' read -r cli kind p; do
        [ "$cli" = "$want" ] || continue
        case "$kind" in
            skill)
                if [ ! -f "$p/SKILL.md" ] || [ -e "$p/command-shims" ] || [ -e "$p/commands" ] || [ -e "$p/$NEW_SKILL" ]; then
                    echo "  ❌ 验证失败：${p}/SKILL.md 缺失、残留 shim 源目录或嵌套 ${NEW_SKILL}/" >&2; bad=1
                fi ;;
            shim)
                if ! cmp -s "$SKILL_SRC/command-shims/$(basename "$p")" "$p"; then
                    echo "  ❌ 验证失败：${p} 与源 shim 不一致" >&2; bad=1
                fi ;;
            alias)
                if ! grep -qxF 'Use skill: handoffx.' "$p/SKILL.md" 2>/dev/null; then
                    echo "  ❌ 验证失败：${p}/SKILL.md 不是本版 alias" >&2; bad=1
                fi ;;
        esac
    done <<EOF
$TARGETS
EOF
    if [ "$bad" -ne 0 ]; then
        return 1
    fi
    return 0
}

verify_sweeps() {
    local p bad=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -e "$p" ] || [ -L "$p" ]; then
            echo "  ❌ 验证失败：旧物仍在 ${p}" >&2; bad=1
        fi
    done <<EOF
$SWEEPS
EOF
    if [ "$bad" -ne 0 ]; then
        return 1
    fi
    return 0
}

# 阶段 1：所有 OLD_* 命中与将被覆盖的目标先进 bak（alias 复制、其余移动）
txn_stage() {
    local p cli kind n=0
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        txn_move_to_bak "$p"
        echo "  🧹 移除：$p"
        n=$((n+1))
    done <<EOF
$SWEEPS
EOF
    while IFS=' ' read -r cli kind p; do
        [ -n "$p" ] || continue
        if [ -e "$p" ] || [ -L "$p" ]; then
            # 链接若原地复制，只备份了链接本身，随后的写入穿透到链接目标且无法还原
            if [ "$kind" = "alias" ] && [ ! -L "$p" ]; then txn_copy_to_bak "$p"; else txn_move_to_bak "$p"; fi
        else
            jlog "absent $p"
        fi
    done <<EOF
$TARGETS
EOF
    if [ "$n" -gt 0 ]; then
        echo "  🧹 共 $n 项旧物已移入备份（成功后删除）"
    fi
    fail_point cleanup
}

# 阶段 2：按 CLI 顺序拷贝 / 生成，每家装完即验证
install_cli() {
    local want="$1" cli kind p
    echo "── $(cli_label "$want") ──"
    while IFS=' ' read -r cli kind p; do
        [ "$cli" = "$want" ] || continue
        case "$kind" in
            skill) put_skill "$p"; fail_point skill-copy ;;
            shim)  put_shim "$p";  fail_point shim-copy ;;
            alias) put_alias "$p"; fail_point alias-gen ;;
        esac
    done <<EOF
$TARGETS
EOF
    verify_cli "$want"
    echo "  ✅ [$(cli_label "$want")] 安装验证通过"
}

txn_install_all() {
    local cli n=0
    while IFS= read -r cli; do
        [ -n "$cli" ] || continue
        n=$((n+1))
        if [ "$n" -eq 2 ]; then
            fail_point second-cli
        fi
        install_cli "$cli"
    done <<EOF
$CLIS
EOF
    verify_sweeps
}

txn_commit() {
    TXN_ACTIVE=0
    if ! rm -rf "$BAK_DIR" "$JOURNAL"; then
        echo "  ⚠️  安装已成功，但清理备份失败：${BAK_DIR}" >&2
    fi
    rmdir "$TXN_HOME" 2>/dev/null || true
    return 0
}

# 按 journal 逆序还原：new → 删除；bak → 移回原位；absent 仅作记录
txn_rollback() {
    set +e
    TXN_ACTIVE=0
    local line op rest abs b failed=0 restored=0 removed=0
    echo "" >&2
    echo "❌ 安装失败，按 journal 逆序还原：${JOURNAL}" >&2
    if [ ! -f "$JOURNAL" ]; then
        echo "  （journal 不存在，未做任何改动）" >&2
        return 0
    fi
    while IFS= read -r line; do
        op=${line%% *}; rest=${line#* }
        case "$op" in
            new)
                case "$rest" in
                    /?*)
                        rm -rf "$rest"
                        # rm 的退出码不可靠到能代替结果检查；删不净必须记失败，保住 journal/bak
                        if [ -e "$rest" ] || [ -L "$rest" ]; then
                            echo "  ⚠️  无法删除本次新建项：$rest" >&2; failed=1
                        else
                            removed=$((removed+1))
                        fi ;;
                    *) failed=1 ;;
                esac ;;
            bak)
                abs=${rest%" $BAK_DIR/"*}; b=$(bak_path "$abs")
                if [ "$rest" != "$abs $b" ]; then
                    echo "  ⚠️  无法解析的 journal 行：$line" >&2; failed=1; continue
                fi
                if [ -e "$b" ] || [ -L "$b" ]; then
                    rm -rf "$abs"
                    # 原位仍被占用时 mv 会把备份移进该目录（macOS mv 无 -T），造成嵌套却返回 0
                    if [ -e "$abs" ] || [ -L "$abs" ]; then
                        echo "  ⚠️  还原失败：${abs} 无法清空（备份仍在 ${b}）" >&2; failed=1; continue
                    fi
                    if mkdir -p "$(dirname "$abs")" && mv "$b" "$abs"; then
                        echo "  ↩ 已还原：$abs" >&2; restored=$((restored+1))
                    else
                        echo "  ⚠️  还原失败：${abs}（备份仍在 ${b}）" >&2; failed=1
                    fi
                elif [ ! -e "$abs" ] && [ ! -L "$abs" ]; then
                    # 备份缺失而原物仍在 = 被杀在 jlog 与 mv 之间，原物未动；两者都没有则已丢失
                    echo "  ⚠️  备份与原物均不存在：$abs" >&2; failed=1
                fi ;;
        esac
    done <<EOF
$(awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' "$JOURNAL")
EOF
    echo "  ↩ 删除本次新建 $removed 项，移回备份 $restored 项" >&2
    if [ "$failed" -eq 0 ]; then
        rm -rf "$BAK_DIR" "$JOURNAL"
        rmdir "$TXN_HOME" 2>/dev/null
        echo "  ✅ 已还原到安装前状态；journal 与备份已删除" >&2
    else
        echo "  ⚠️  部分还原失败；保留 ${JOURNAL} 与 ${BAK_DIR} 供人工检查" >&2
    fi
    return 0
}

# ── 解析（只读）────────────────────────────────────────────────────────────────

if [ "$UNINSTALL" = "1" ]; then
    resolve_uninstall
elif [ "$MODE" = "project" ]; then
    resolve_project_install
else
    resolve_global_install
fi
warn_nested_all

if [ "$JOURNAL_ONLY" = "1" ]; then
    print_plan
    exit 0
fi

# ── Unified install banner (TKX standard, v2.2.0) ───────────────────────────
# Helper provides install_banner_top / install_checkpoint / install_step_ok /
# install_banner_bottom / install_cli_row + table — same visual as gitx-release
# v1.5.0 / mac-release v0.2.0 / future TKX skills.
HANDOFF_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HANDOFF_SELF_DIR/scripts/lib/install-output-style.sh" ]; then
    # shellcheck source=scripts/lib/install-output-style.sh
    source "$HANDOFF_SELF_DIR/scripts/lib/install-output-style.sh"
elif [ -f "$SKILL_SRC/scripts/lib/install-output-style.sh" ]; then
    # shellcheck source=skills/handoffx/scripts/lib/install-output-style.sh
    source "$SKILL_SRC/scripts/lib/install-output-style.sh"
else
    # Graceful degradation: when bootstrap-mode extracts an older .skill bundle
    # (pre-v2.2.0) that predates the unified install-output-style.sh helper,
    # define no-op stubs so the install proceeds with legacy echo style. The
    # next install (which uses a v2.2.0+ bundle) gets the full unified banner.
    install_style_init()      { :; }
    install_banner_top()      { echo "📦 handoffx installer ${1:-} ${2:-} (legacy mode)"; }
    install_checkpoint()      { echo "── ${2:-step} ──"; }
    install_step_ok()         { echo "  ✅ ${1:-}"; }
    install_step_warn()       { echo "  ⚠️  ${1:-}" >&2; }
    install_step_fail()       { echo "  ❌ ${1:-}" >&2; }
    install_banner_bottom()   { echo "🎉 handoffx installer complete"; }
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
install_banner_top "handoffx" "$_HANDOFF_VERSION" "$_HANDOFF_MODE" "$HANDOFF_SELF_DIR"

if [ "$DRY_RUN" = "1" ]; then
    install_checkpoint "$_TKX_E_SEARCH" "Dry-run preview"
    install_step_ok "Targets parsed successfully; no filesystem changes performed."
    install_banner_bottom "handoffx" "$_HANDOFF_VERSION (dry-run)"
    exit 0
fi
[ "$FORCE" = "1" ] && true

# ── legacy layout warning (D1 → P2.4) ────────────────────────────────────────
# Non-blocking notice when the user's CWD still holds a legacy layout.
# install.sh installs the *skill*; the project layout is upgraded separately.
# Warn-and-continue (rc 0) is the S:60 contract: refusing would block the very
# install that ships the migrators.
warn_if_legacy_layout() {
    local dir="${1:-$PWD}"
    case "$(hx_legacy_layout_kind "$dir")" in
        v1)
            echo ""
            echo "⚠️  Detected legacy v1 $HX_LEGACY_MAIN_FILE at $dir/$HX_LEGACY_MAIN_FILE"
            echo "   v4 keeps the project in $HX_MAIN_FILE + $HX_LOGS_DIR/ + $HX_DEC_DIR/ + $HX_GOTCHAS_FILE."
            echo "   After install: migrate-to-v2.sh --dry-run, then migrate-to-v2.sh --apply."
            echo ""
            ;;
        v3)
            echo ""
            echo "⚠️  Detected legacy four-piece layout at $dir ($HX_LEGACY_MAIN_FILE, $HX_LEGACY_LOGS_DIR/, $HX_LEGACY_DEC_DIR/)"
            echo "   v4 renames it to $HX_MAIN_FILE + $HX_LOGS_DIR/ + $HX_DEC_DIR/."
            echo "   After install: run /handoffx-tidy schema-upgrade in that project."
            echo ""
            ;;
        mixed|unknown)
            echo ""
            echo "⚠️  Detected legacy layout at $dir that is not a clean v1 or four-piece tree ($HX_LEGACY_MAIN_FILE / $HX_LEGACY_LOGS_DIR/ / $HX_LEGACY_DEC_DIR/)"
            echo "   After install: run /handoffx-tidy in that project — it names the exact command for this tree."
            echo ""
            ;;
    esac
    return 0
}

# ── 卸载 ──────────────────────────────────────────────────────────────────────

if [ "$UNINSTALL" = "1" ]; then
    echo "🗑  卸载 HandoffX Skill..."
    echo ""
    txn_begin
    txn_stage
    verify_sweeps
    txn_commit
    echo ""
    echo "✅ 全局卸载完成"
    echo ""
    echo "⚠️  如有项目级安装（--project 模式），请进入各项目目录手动检查："
    echo "   find <project> -name 'handoffx*.md' -path '*/.claude/commands/*' 2>/dev/null"
    exit 0
fi

# ── 安装（项目级 / 全局，同一事务）─────────────────────────────────────────────

install_checkpoint "$_TKX_E_SEARCH" "Preflight: targets detected"
while IFS= read -r _cli; do
    if [ -n "$_cli" ]; then install_step_ok "$(cli_label "$_cli") targeted"; fi
done <<EOF
$CLIS
EOF
[ "${HANDOFF_INSTALL_SKIP_V2_GATE:-0}" = "1" ] || warn_if_legacy_layout

if [ "$MODE" = "project" ]; then
    install_checkpoint "$_TKX_E_DIR" "Project install"
    echo "📦 项目级安装 → ${PROJECT_ABS}/（.claude / .opencode / .agents）"
else
    install_checkpoint "$_TKX_E_DIR" "Global install"
    echo "📦 全局安装 HandoffX Skill"
    echo "   平台: $PLATFORM"
fi
echo ""

txn_begin
txn_stage
txn_install_all
txn_commit

if [ "$MODE" = "project" ]; then
    echo "   → 仅在该项目目录下生效"
fi
# WSL 额外提示：Claude Code 路径是否已正确桥接
if [ "$MODE" != "project" ] && [ "$TARGET_CLAUDE" = "1" ] && [ "$PLATFORM" = "wsl" ]; then
    if [ -n "$(wsl_claude_dir)" ]; then
        echo "  ✅ [WSL] 已写入 Windows Claude Code 路径: $(claude_config_dir)"
    else
        echo "  ⚠️  [WSL] 未找到 Windows AppData/Claude，已写入 WSL 本地 ~/.claude/"
        echo "       如使用 Windows 版 Claude Code，请手动复制到 %APPDATA%\\Claude\\"
    fi
fi
if [ "$MODE" != "project" ] && [ "$TARGET_CODEX" = "1" ]; then
    echo "  ℹ️  Codex 使用 \$handoffx、\$handoffx-recall、\$handoffx-tidy、\$handoffx-memory、\$handoffx-init"
fi
echo ""

# ── 可选：创建主文件 ──────────────────────────────────────────────────────────
# 目标名取 $HX_MAIN_FILE；旧布局目标已在参数校验阶段拒绝。

if [ -n "$TEMPLATE_TARGET" ]; then
    TEMPLATE_ABS="$(cd "$TEMPLATE_TARGET" && pwd)"
    # hx_present, not -f (fix wave 2, m6): a dangling-symlink main is an
    # existing main — cp would write through it (GNU) or fail after the
    # install already landed (BSD).
    if hx_present "$TEMPLATE_ABS/$HX_MAIN_FILE"; then
        echo "⚠️  $TEMPLATE_ABS/$HX_MAIN_FILE 已存在，跳过（保留现有内容）"
    else
        cp "$SKILL_SRC/assets/${HX_MAIN_FILE%.md}.template.md" "$TEMPLATE_ABS/$HX_MAIN_FILE"
        echo "✅ $HX_MAIN_FILE 从模板创建于 $TEMPLATE_ABS/"
    fi
fi

# ── Unified completion banner (TKX standard) ────────────────────────────────

install_checkpoint "$_TKX_E_CHECK" "Validation"
install_step_ok "All targeted CLIs received the handoffx skill"

install_banner_bottom "handoffx" "$_HANDOFF_VERSION"
install_cli_table_begin
[ "$TARGET_CLAUDE" = "1" ]   && install_cli_row "Claude Code" "/handoffx"          "$(claude_config_dir)/skills/handoffx"
[ "$TARGET_OPENCODE" = "1" ] && install_cli_row "OpenCode"    "/handoffx"          "$(opencode_config_dir)/skills/handoffx"
[ "$TARGET_CODEX" = "1" ]    && install_cli_row "Codex CLI"   "\$handoffx"          "$(codex_config_dir)/skills/handoffx"
install_cli_table_end
install_next_block \
    "Run /handoffx-init in a project root to create the v2 four-file scaffold" \
    "Run /handoffx-recall to read an existing $HX_MAIN_FILE and report status" \
    "Sub-commands: \$handoffx-init / \$handoffx-recall / \$handoffx-tidy / \$handoffx-memory"
