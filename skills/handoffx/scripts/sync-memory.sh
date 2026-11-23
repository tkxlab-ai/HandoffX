#!/bin/bash
# sync-memory.sh — back up this machine's Claude Code project memory and a
# session list into .agent-sessions-sync-hx/machines/<machine>/ (default on).
# usage: sync-memory.sh [--expect-root ABS_DIR] [status|on|off|sync|auto]
#
# The backup is never a client's runtime directory: nothing here changes
# where Claude Code reads or writes. Each machine writes only its own
# subdirectory; /handoffx-recall reads the OTHER machines' backups (Boss
# 2026-11-22). Raw session transcripts are never copied — only metadata.
#
# Subcommands:
#   status   enabled/disabled, machine name, backed-up file and session counts
#   on       remove the .sync-disabled flag and back up once
#   off      create .agent-sessions-sync-hx/.sync-disabled (backups kept)
#   sync     back up once, ignoring the flag
#   auto     back up unless disabled (finalize calls this; silent when there
#            is nothing to back up)
#
# Sources: $HOME/.claude/projects/<encoded cwd>/memory/*.md and the session
# files *.jsonl beside it (start/end timestamps and entrypoint only).
# A legacy ./memory/ that carries this skill's .sync-enabled flag is moved
# into this machine's backup once.
#
# Env:
#   HOME_OVERRIDE    tests: replace $HOME
#   HX_SYNC_MACHINE  override the machine directory name
#
# Exit:
#   0  done, or nothing to back up / disabled
#   1  unknown subcommand / usage error / credential hit before publishing
#   2  I/O or publish failure, or the credential scan could not run

set -e

# Do not let caller CDPATH redirect relative paths or contaminate captured cd output.
unset CDPATH
SCRIPT_DIR="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 2
[ -r "$SCRIPT_DIR/lib/handoff-context.sh" ] || {
    echo "context helper missing or unreadable: $SCRIPT_DIR/lib/handoff-context.sh" >&2; exit 2;
}
. "$SCRIPT_DIR/lib/handoff-context.sh" || exit 2
[ -r "$SCRIPT_DIR/lib/handoff-sync.sh" ] || {
    echo "sync helper missing or unreadable: $SCRIPT_DIR/lib/handoff-sync.sh" >&2; exit 2;
}
. "$SCRIPT_DIR/lib/handoff-sync.sh" || exit 2
hx_context_take_expect_root '' "$@" || exit 2
HX_EXPECT_ROOT=$HX_TAKEN_ROOT; shift "$HX_TAKEN_SHIFT"

CMD="${1:-status}"
case "$CMD" in -h|--help)
    echo "Usage: $0 [--expect-root ABS_DIR] [status|on|off|sync|auto]"
    echo "Back up this machine's Claude Code project memory and session list into"
    echo "$HX_SYNC_DIR/machines/<machine>/ (default on; never a runtime directory)."
    echo ""
    echo "Commands:"
    echo "  status   Show enabled/disabled, machine, backed-up files and sessions (default)"
    echo "  on       Remove $HX_SYNC_DIR/.sync-disabled and back up once"
    echo "  off      Create $HX_SYNC_DIR/.sync-disabled (backups kept)"
    echo "  sync     Back up once regardless of the flag"
    echo "  auto     Back up unless disabled (used by finalize)"
    exit 0
    ;;
esac

hx_context_check_memo "$SCRIPT_DIR" "$HX_EXPECT_ROOT" || exit 2

ENCODE="$SCRIPT_DIR/encode-cc-path.sh"
SCAN="$SCRIPT_DIR/scan-credentials.sh"
[ -x "$ENCODE" ] || [ -f "$ENCODE" ] || {
    echo "❌ encode-cc-path.sh not found at $ENCODE" >&2
    exit 1
}

[ "$#" -le 1 ] || { echo 'sync-memory: unexpected extra argument' >&2; exit 2; }
PROJECT_DIR=$(_hx_context_pwd) || exit 2
MACHINE=$(hx_machine_name) || { echo 'sync-memory: cannot determine this machine name (set HX_SYNC_MACHINE)' >&2; exit 2; }
SYNC_ROOT="$PROJECT_DIR/$HX_SYNC_DIR"
MACHINE_DIR="$SYNC_ROOT/machines/$MACHINE"
MEMORY_DIR="$MACHINE_DIR/claude-code/memory"
SESSIONS_FILE="$MACHINE_DIR/sessions.md"
FLAG_FILE="$SYNC_ROOT/.sync-disabled"
LEGACY_DIR="$PROJECT_DIR/memory"
case "$CMD" in
    on|off|sync|auto)
        hx_context_write_check "$SCRIPT_DIR" "$HX_EXPECT_ROOT" || exit 2
        # Implicit write targets must not redirect through a symlink either.
        for _hx_p in "$SYNC_ROOT" "$SYNC_ROOT/machines" "$MACHINE_DIR" "$MACHINE_DIR/claude-code" \
                     "$MEMORY_DIR" "$SESSIONS_FILE" "$FLAG_FILE"; do
            [ ! -L "$_hx_p" ] || { echo "sync-memory: $_hx_p is a symlink" >&2; exit 2; }
        done
        ;;
esac

# 测试 hook：HOME_OVERRIDE 替换 $HOME
HOME_BASE="${HOME_OVERRIDE:-$HOME}"

encoded=$(bash "$ENCODE" "$PROJECT_DIR")
CC_PROJ="$HOME_BASE/.claude/projects/$encoded"
CC_MEM="$CC_PROJ/memory"

count_md() {
    # 统计本机备份里 *.md 文件数（包括 MEMORY.md 索引，排除 dotfile）
    [ -d "$MEMORY_DIR" ] || { echo 0; return; }
    # 用 find 比 ls 稳（无 matches 不报错）；排除隐藏文件
    find "$MEMORY_DIR" -maxdepth 1 -type f -name "*.md" ! -name ".*" 2>/dev/null | wc -l | tr -d ' '
}

# 子 shell 的 EXIT trap 只清理本次暂存；失败不依赖调用方的 set -e 上下文。
do_sync() (
    # 源不存在 → 友好提示，不作为错误
    if [ ! -d "$CC_MEM" ]; then
        echo "ℹ️  Claude Code 记忆源不存在（${CC_MEM}）"
        echo "   这是正常的——新项目 / 新机器尚未产生记忆"
        return 0
    fi
    if [ ! -r "$CC_MEM" ] || [ ! -x "$CC_MEM" ]; then
        echo "❌ 记忆源无法读取，旧副本保留" >&2
        return 2
    fi

    local has_md=0 m
    for m in "$CC_MEM"/*.md; do
        if [ -f "$m" ] && [ ! -L "$m" ]; then has_md=1; break; fi
    done
    if [ "$has_md" = 0 ] && [ ! -d "$MEMORY_DIR" ]; then
        echo "ℹ️  记忆源里没有 .md 文件：$CC_MEM"
        return 0
    fi
    mkdir -p "$MEMORY_DIR" || { echo "❌ 无法创建备份目录 $MEMORY_DIR" >&2; return 2; }
    local staged
    # 暂存位于目标目录所在文件系统，最后逐文件 rename；旧文件不预先删除。
    staged=$(mktemp -d "$MEMORY_DIR/.sync-memory.XXXXXX") || { echo "❌ 无法创建记忆暂存目录" >&2; return 2; }
    trap 'rm -rf "$staged"' EXIT
    trap 'exit 2' HUP INT TERM
    local copied=0 skipped_symlink=0 f dst rc
    for f in "$CC_MEM"/*.md; do
        [ -f "$f" ] || continue
        # 保持既有隐私策略：不跟随源 symlink，不删除本地多余记忆。
        if [ -L "$f" ]; then
            skipped_symlink=$((skipped_symlink+1))
            continue
        fi
        dst="$MEMORY_DIR/$(basename "$f")"
        if [ -d "$dst" ]; then
            echo "❌ 同步目标是目录：$(basename "$f")，旧副本保留" >&2
            return 2
        fi
        if ! cp "$f" "$staged/$(basename "$f")"; then
            echo "❌ 记忆复制失败：$(basename "$f")，旧副本保留" >&2
            return 2
        fi
        if ! chmod u+w "$staged/$(basename "$f")"; then
            echo "❌ 记忆权限设置失败：$(basename "$f")，旧副本保留" >&2
            return 2
        fi
    done
    # 检查整批待发布文件及不会被替换的本地文件；任一失败均不发布。
    rc=0; scan_synced_files "$staged" || rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    for f in "$staged"/*.md; do
        [ -f "$f" ] || continue
        dst="$MEMORY_DIR/$(basename "$f")"
        if [ -d "$dst" ] || ! mv -f "$f" "$dst"; then
            echo "❌ 记忆发布失败：$(basename "$f")，该文件旧副本保留；此前已发布 $copied 条" >&2
            return 2
        fi
        copied=$((copied+1))
    done
    if [ "$copied" = "0" ]; then
        echo "ℹ️  记忆源里没有 .md 文件：$CC_MEM"
    else
        echo "📦 已备份 $copied 条记忆 → $HX_SYNC_DIR/machines/$MACHINE/claude-code/memory/"
    fi
    [ "$skipped_symlink" -gt "0" ] && echo "⚠️  跳过 $skipped_symlink 个 symlink（防御性策略）"
    return 0
)

# 扫描待发布视图：暂存 .md + 未被替换的本地 .md（忽略 dotfile）。
# 凭证命中返回 1；扫描缺失/IO 错误返回 2；调用方必须在发布前检查结果。
scan_synced_files() {
    [ -d "$MEMORY_DIR" ] || return 0
    if [ ! -f "$SCAN" ]; then
        echo "" >&2
        echo "❌ 凭证扫描器缺失（${SCAN}），无法验证待发布文件——不按 clean 处理" >&2
        return 2
    fi

    local hits=0 unscanned=0 rc
    local f staged="$1"
    for f in "$staged"/*.md "$MEMORY_DIR"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in .*) continue ;; esac
        # 同名旧版本将被覆盖，只扫描暂存的新版本；本地额外文件仍检查。
        if [ "${f%/*}" = "$MEMORY_DIR" ] && [ -f "$staged/$(basename "$f")" ]; then
            continue
        fi
        rc=0; bash "$SCAN" "$f" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 1 ]; then
            if [ "$hits" = "0" ]; then
                echo ""
                echo "🔴 凭证扫描：待同步记忆中检测到疑似凭证！" >&2
            fi
            echo "   • $(basename "$f")" >&2
            hits=$((hits+1))
        elif [ "$rc" -ne 0 ]; then
            # scan-credentials exit 2 = 无法读取；不是「发现凭证」，也不是 clean
            echo "   • $(basename "$f") — 无法扫描（scan-credentials exit ${rc}）" >&2
            unscanned=$((unscanned+1))
        fi
    done

    if [ "$unscanned" -gt "0" ]; then
        echo "" >&2
        echo "❌ $unscanned 个记忆文件无法扫描——凭证状态未知，不按 clean 处理" >&2
        return 2
    fi
    if [ "$hits" -gt "0" ]; then
        echo "" >&2
        echo "   建议：编辑上述文件把明文密钥换成 \$ENV_VAR 或 vault://；" >&2
        echo "   然后重跑 /handoffx-memory sync，或用 /handoffx-memory off 关闭备份。交接不受影响。" >&2
        return 1
    fi
    return 0
}

# 在 .git/ 项目下首次 on 时提示用户考虑 .gitignore（不强制）
maybe_suggest_gitignore() {
    [ -d "$PROJECT_DIR/.git" ] || return 0
    local gi="$PROJECT_DIR/.gitignore"
    # 已在 .gitignore 里 → 不打扰
    if [ -f "$gi" ] && grep -qE "^/?\\$HX_SYNC_DIR/?\$" "$gi"; then
        return 0
    fi
    echo ""
    echo "💡 检测到 .git/ 仓库。本项目的 $HX_SYNC_DIR/ 会随 commit 进入版本管理。"
    echo "   记忆里可能含客户名 / 内部 URL 等敏感内容，建议加入 .gitignore："
    echo ""
    echo "     echo '$HX_SYNC_DIR/' >> $gi"
    echo ""
    echo "   （这只是提醒，不会自动添加——是否入版本由你决定）"
}

# 旧版 ./memory/ 只在带本技能的 .sync-enabled 标志时才视为本技能所建，迁一次。
# 同名同内容直接丢弃旧副本；同名不同内容另存 <名>.legacy.md；都占用就原地保留。
migrate_legacy() {
    [ -d "$LEGACY_DIR" ] && [ ! -L "$LEGACY_DIR" ] && [ -f "$LEGACY_DIR/.sync-enabled" ] || return 0
    local f b dst moved=0 kept=0
    mkdir -p "$MEMORY_DIR" || { echo "❌ 无法创建备份目录 $MEMORY_DIR" >&2; return 2; }
    for f in "$LEGACY_DIR"/*.md; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        b=$(basename "$f"); dst="$MEMORY_DIR/$b"
        if [ -e "$dst" ]; then
            if cmp -s "$f" "$dst"; then rm -f "$f" || return 2; moved=$((moved+1)); continue; fi
            dst="$MEMORY_DIR/${b%.md}.legacy.md"
            if [ -e "$dst" ]; then kept=$((kept+1)); continue; fi
        fi
        mv "$f" "$dst" || { echo "❌ 旧记忆迁移失败：${b}，原件保留在 ./memory/" >&2; return 2; }
        moved=$((moved+1))
    done
    if [ "$kept" -eq 0 ]; then
        rm -f "$LEGACY_DIR/.sync-enabled"
        rmdir "$LEGACY_DIR" 2>/dev/null || true
    fi
    echo "📦 旧 ./memory/ 已迁移 ${moved} 条 → $HX_SYNC_DIR/machines/$MACHINE/claude-code/memory/"
    [ "$kept" -eq 0 ] || echo "⚠️  ${kept} 条与已有备份重名且内容不同，仍留在 ./memory/，请手工合并"
}

# 会话清单：只记元数据（客户端、界面、会话 ID、首尾时间戳），不读对话内容。
# 只看每个会话文件开头和结尾各 64KB 里的 timestamp / entrypoint 字段。
write_sessions() {
    [ -d "$CC_PROJ" ] || return 0
    local f id start end ui rows="" tmp
    for f in "$CC_PROJ"/*.jsonl; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        id=$(basename "$f" .jsonl)
        start=$(head -c 65536 "$f" | LC_ALL=C grep -ao '"timestamp":"[^"]*"' | head -1 | cut -d'"' -f4)
        end=$(tail -c 65536 "$f" | LC_ALL=C grep -ao '"timestamp":"[^"]*"' | tail -1 | cut -d'"' -f4)
        ui=$(head -c 65536 "$f" | LC_ALL=C grep -ao '"entrypoint":"[^"]*"' | head -1 | cut -d'"' -f4)
        rows="$rows${start:-unknown}	| claude-code | ${ui:-unknown} | $id | ${start:-unknown} | ${end:-unknown} |
"
    done
    [ -n "$rows" ] || return 0
    mkdir -p "$MACHINE_DIR" || { echo "❌ 无法创建 $MACHINE_DIR" >&2; return 2; }
    tmp=$(mktemp "$MACHINE_DIR/.sessions.XXXXXX") || return 2
    {
        echo "# 会话清单 — $MACHINE"
        echo
        echo "> 自动生成（sync-memory.sh）。只记元数据，不含对话内容；时间为 UTC。"
        echo
        echo "| 客户端 | 界面 | 会话 ID | 开始 | 结束 |"
        echo "|---|---|---|---|---|"
        printf '%s' "$rows" | LC_ALL=C sort | cut -f2-
    } > "$tmp" || { rm -f "$tmp"; return 2; }
    if [ -f "$SESSIONS_FILE" ] && cmp -s "$tmp" "$SESSIONS_FILE"; then rm -f "$tmp"; return 0; fi
    mv -f "$tmp" "$SESSIONS_FILE" || { rm -f "$tmp"; return 2; }
}

# 一次完整备份：迁移旧目录 → 记忆 → 会话清单。任一步失败返回其退出码，
# 但后面的步骤照样尝试（会话清单不该因为一条记忆扫出凭证就不更新）。
backup_all() {
    local rc=0 r
    r=0; migrate_legacy || r=$?; [ "$r" -eq 0 ] || rc=$r
    r=0; do_sync || r=$?; [ "$r" -eq 0 ] || { [ "$rc" -eq 2 ] || rc=$r; }
    r=0; write_sessions || r=$?; [ "$r" -eq 0 ] || rc=2
    return "$rc"
}

count_sessions() {
    [ -f "$SESSIONS_FILE" ] || { echo 0; return; }
    grep -c '^| claude-code |' "$SESSIONS_FILE" 2>/dev/null || echo 0
}

case "$CMD" in
    status)
        if [ -f "$FLAG_FILE" ]; then echo "disabled"; else echo "enabled"; fi
        echo "machine: $MACHINE"
        echo "files: $(count_md)"
        echo "sessions: $(count_sessions)"
        echo "source: $CC_MEM"
        echo "backup: $HX_SYNC_DIR/machines/$MACHINE/"
        ;;

    on)
        was_present=1
        [ -d "$SYNC_ROOT" ] || was_present=0
        mkdir -p "$SYNC_ROOT" || { echo "❌ 无法创建 $HX_SYNC_DIR/" >&2; exit 2; }
        rm -f "$FLAG_FILE" || { echo "❌ 无法移除关闭标志" >&2; exit 2; }
        sync_ec=0; backup_all || sync_ec=$?
        [ "$was_present" = "0" ] && maybe_suggest_gitignore
        [ "$sync_ec" -eq 0 ] && echo "✅ 跨电脑备份已开启"
        exit "$sync_ec"
        ;;

    off)
        if [ -f "$FLAG_FILE" ]; then
            echo "ℹ️  已经是关闭状态"
        else
            mkdir -p "$SYNC_ROOT" && touch "$FLAG_FILE" || { echo "❌ 无法写入关闭标志" >&2; exit 2; }
            echo "✅ 跨电脑备份已关闭"
            echo "   已有备份保留在 $HX_SYNC_DIR/（要删除请手动 rm -rf $HX_SYNC_DIR/）"
        fi
        ;;

    sync)
        sync_ec=0; backup_all || sync_ec=$?
        exit "$sync_ec"
        ;;

    auto)
        [ ! -f "$FLAG_FILE" ] || exit 0
        sync_ec=0; backup_all || sync_ec=$?
        exit "$sync_ec"
        ;;

    *)
        echo "❌ 未知子命令: $CMD" >&2
        echo "   Usage: $0 [status|on|off|sync|auto]" >&2
        exit 1
        ;;
esac
