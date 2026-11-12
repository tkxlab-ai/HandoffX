#!/bin/bash
# sync-memory.sh — Experimental: sync Claude Code auto-memory into project ./memory/
# usage: sync-memory.sh [status|on|off|sync]
# so that记忆跟着项目文件夹走（跨机器便携）。
#
# Subcommands:
#   status                 显示 enabled/disabled + ./memory/*.md 文件数（默认）
#   on                     启用实验性同步：创建 ./memory/.sync-enabled 并立即跑一次 sync
#   off                    删除标志（保留已同步的 .md 文件）
#   sync                   无视标志，强制跑一次同步（供 on 和 /handoffx 写入流程复用）
#
# 源路径推导：
#   CC 把 $PWD 编码进 ~/.claude/projects/<encoded>/memory/
#   编码规则由 encode-cc-path.sh 定义（/_. → -）
#
# Env:
#   HOME_OVERRIDE          测试用：替换 $HOME，指到临时 fake home
#
# Exit:
#   0  成功（含"源不存在也友好退出"）
#   1  未知子命令 / 参数错误 / 同步后凭证扫描命中
#   2  凭证扫描无法进行（扫描器缺失或已同步文件读不到）——不按 clean 处理

set -e

CMD="${1:-status}"
case "$CMD" in -h|--help)
    echo "Usage: $0 [status|on|off|sync]"
    echo "Experimental: sync Claude Code auto-memory into project ./memory/."
    echo ""
    echo "Commands:"
    echo "  status   Show enabled/disabled and .md file count (default)"
    echo "  on       Enable sync (creates ./memory/.sync-enabled) and run once"
    echo "  off      Disable (remove flag; keep synced files)"
    echo "  sync     Run one-shot sync regardless of flag"
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENCODE="$SCRIPT_DIR/encode-cc-path.sh"
SCAN="$SCRIPT_DIR/scan-credentials.sh"
[ -x "$ENCODE" ] || [ -f "$ENCODE" ] || {
    echo "❌ encode-cc-path.sh not found at $ENCODE" >&2
    exit 1
}

PROJECT_DIR="$(pwd)"
MEMORY_DIR="$PROJECT_DIR/memory"
FLAG_FILE="$MEMORY_DIR/.sync-enabled"

# 测试 hook：HOME_OVERRIDE 替换 $HOME
HOME_BASE="${HOME_OVERRIDE:-$HOME}"

encoded=$(bash "$ENCODE" "$PROJECT_DIR")
CC_MEM="$HOME_BASE/.claude/projects/$encoded/memory"

count_md() {
    # 统计 ./memory/ 下 *.md 文件数（包括 .md 索引，排除 dotfile）
    [ -d "$MEMORY_DIR" ] || { echo 0; return; }
    # 用 find 比 ls 稳（无 matches 不报错）；排除隐藏文件
    find "$MEMORY_DIR" -maxdepth 1 -type f -name "*.md" ! -name ".*" 2>/dev/null | wc -l | tr -d ' '
}

do_sync() {
    # 源不存在 → 友好提示，不作为错误
    if [ ! -d "$CC_MEM" ]; then
        echo "ℹ️  Claude Code 记忆源不存在（${CC_MEM}）"
        echo "   这是正常的——新项目 / 新机器尚未产生记忆"
        return 0
    fi

    mkdir -p "$MEMORY_DIR"
    local copied=0
    local skipped_symlink=0
    # 逐文件拷贝（覆盖式，不删除本地多余文件）
    # 为避免 "no matches" 下 for-loop 误拿字面量，先做 nullglob 判断
    local f
    for f in "$CC_MEM"/*.md; do
        [ -f "$f" ] || continue
        # R6.2 防御：拒绝同步 symlink——CC 本身从不创建 symlink，
        # 若存在即可能是攻击者植入用于读取任意文件（cp 默认 follow）。
        # 本地合法 symlink 会被跳过但不影响主流程。
        if [ -L "$f" ]; then
            skipped_symlink=$((skipped_symlink+1))
            continue
        fi
        local dst
        dst="$MEMORY_DIR/$(basename "$f")"
        # R6.4 防御：先 rm 再 cp，避免 CC 源文件为只读模式时 cp 覆盖失败；
        # 再显式 chmod u+w 保证后续 sync 可重复执行。
        rm -f "$dst"
        cp "$f" "$dst"
        chmod u+w "$dst" 2>/dev/null || true
        copied=$((copied+1))
    done

    if [ "$copied" = "0" ]; then
        echo "ℹ️  源目录存在但无 .md 文件：$CC_MEM"
    else
        echo "📦 已同步 $copied 条记忆 → ./memory/"
    fi
    [ "$skipped_symlink" -gt "0" ] && echo "⚠️  跳过 $skipped_symlink 个 symlink（防御性策略）"

    # 同步后扫描凭证（防止 CC memory 里的客户名 / API key 跟着项目泄漏）
    scan_synced_files
    return $?
}

# 扫描 ./memory/ 下所有 .md（忽略 dotfile）。发现凭证 → 打印警告 + 返回 1；
# 扫描器缺失 / 文件读不到 → 无法验证，返回 2（不能当 clean，Gotcha #24）。
# 不撤销已同步的文件——决策权交给用户（见 /handoffx-memory off + rm）。
scan_synced_files() {
    [ -d "$MEMORY_DIR" ] || return 0
    if [ ! -f "$SCAN" ]; then
        echo "" >&2
        echo "❌ 凭证扫描器缺失（${SCAN}），无法验证已同步文件——不按 clean 处理" >&2
        return 2
    fi

    local hits=0 unscanned=0 rc
    local f
    for f in "$MEMORY_DIR"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in .*) continue ;; esac
        rc=0; bash "$SCAN" "$f" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 1 ]; then
            if [ "$hits" = "0" ]; then
                echo ""
                echo "🔴 凭证扫描：./memory/ 中检测到疑似凭证！" >&2
            fi
            echo "   • $(basename "$f")" >&2
            hits=$((hits+1))
        elif [ "$rc" -ne 0 ]; then
            # scan-credentials exit 2 = 无法读取；不是「发现凭证」，也不是 clean
            echo "   • $(basename "$f") — 无法扫描（scan-credentials exit ${rc}）" >&2
            unscanned=$((unscanned+1))
        fi
    done

    if [ "$hits" -gt "0" ]; then
        echo "" >&2
        echo "   建议：编辑上述文件把明文密钥换成 \$ENV_VAR 或 vault://；" >&2
        echo "   然后重跑 /handoffx-memory sync。或 /handoffx-memory off 关闭同步。" >&2
        return 1
    fi
    if [ "$unscanned" -gt "0" ]; then
        echo "" >&2
        echo "❌ $unscanned 个已同步文件无法扫描——凭证状态未知，不按 clean 处理" >&2
        return 2
    fi
    return 0
}

# 在 .git/ 项目下首次 on 时提示用户考虑 .gitignore（不强制）
maybe_suggest_gitignore() {
    [ -d "$PROJECT_DIR/.git" ] || return 0
    local gi="$PROJECT_DIR/.gitignore"
    # 已在 .gitignore 里 → 不打扰
    if [ -f "$gi" ] && grep -qE '^/?memory/?$' "$gi"; then
        return 0
    fi
    echo ""
    echo "💡 检测到 .git/ 仓库。本项目的 ./memory/ 即将随 commit 进入版本管理。"
    echo "   如果记忆里可能含客户名 / 内部 URL / token 等敏感内容，建议加入 .gitignore："
    echo ""
    echo "     echo 'memory/' >> $gi"
    echo ""
    echo "   （这只是提醒，不会自动添加——记忆是否入版本由你决定）"
}

case "$CMD" in
    status)
        if [ -f "$FLAG_FILE" ]; then
            echo "enabled"
        else
            echo "disabled"
        fi
        echo "files: $(count_md)"
        echo "source: $CC_MEM"
        ;;

    on)
        was_enabled=0
        [ -f "$FLAG_FILE" ] && was_enabled=1
        mkdir -p "$MEMORY_DIR"
        touch "$FLAG_FILE"
        echo "✅ Experimental memory sync enabled"
        # 用 if 形式调用避免 set -e 在 do_sync 返回 1（如凭证扫描命中）时
        # 中断脚本——那样 .gitignore 提示就不会打印。
        if do_sync; then sync_ec=0; else sync_ec=$?; fi
        # 仅在首次 on（标志文件本来不存在）时打印 .gitignore 提示
        [ "$was_enabled" = "0" ] && maybe_suggest_gitignore
        exit $sync_ec
        ;;

    off)
        if [ -f "$FLAG_FILE" ]; then
            rm -f "$FLAG_FILE"
            echo "✅ Experimental memory sync disabled"
            echo "   已同步的文件保留在 ./memory/（手动删除：rm -rf ./memory/）"
        else
            echo "ℹ️  已经是 disabled 状态"
        fi
        ;;

    sync)
        do_sync
        ;;

    *)
        echo "❌ 未知子命令: $CMD" >&2
        echo "   Usage: $0 [status|on|off|sync]" >&2
        exit 1
        ;;
esac
