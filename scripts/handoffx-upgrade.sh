#!/bin/bash
# handoffx-upgrade.sh — THE standard upgrade flow for a project still on a
# legacy handoff layout: classify → run the one migrator that fits → post-check
# → list the other files that still name the legacy pieces → print what is
# left for the human.
# Usage: handoffx-upgrade.sh (--dry-run|--apply) [--root DIR]   (default root: .)
# Exit:  0 done / nothing to upgrade; 1 migrated but a post-check failed;
#        2 usage error or a layout it refuses (mixed / unknown); else the
#        migrator's own rc (the migrator has already rolled back).
#
# Why a wrapper and not a third migrator: v1 and v3 already have atomic,
# rollback-proven migrators; what the /handoffx* commands lacked was one entry
# point that picks between them by content and finishes the job (checks +
# leftovers), so the skill layer can ask once and run one command.
# Why it never prompts: the ask belongs to the skill layer (the AI asks the
# user); a non-interactive script is what tests and CI can drive.
# Why it never calls git: handoff work is orthogonal to version control (the
# skill's first constraint) — committing the rename is a listed human step.
# Every four-piece name comes from lib/handoff-schema.sh (the only file under
# scripts/ allowed to spell them — tests/test_handoff_schema.sh).
#
# Test-only: HANDOFFX_UPGRADE_FAIL_AT=unreadable-main makes the migrated main
# unreadable before the post-checks (same contract as HANDOFFX_MIGRATE_FAIL_AT),
# so the "migrated but checks failed" path can be proven without a broken tree.
set -euo pipefail

SD="$(cd "$(dirname "$0")" && pwd)"
# Fail closed: without the constants every name below would expand empty.
[ -r "$SD/lib/handoff-schema.sh" ] || { echo "❌ handoffx-upgrade.sh: $SD/lib/handoff-schema.sh missing or unreadable" >&2; exit 2; }
. "$SD/lib/handoff-schema.sh"

usage() { echo "Usage: $0 (--dry-run|--apply) [--root DIR]   (default root: .)"; }
MODE="" ROOT="."
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run|--apply)
            [ -z "$MODE" ] || { echo "❌ choose one of --dry-run / --apply" >&2; usage >&2; exit 2; }
            MODE="${1#--}" ;;
        --root)
            [ -n "${2:-}" ] || { echo "❌ --root requires a directory argument" >&2; usage >&2; exit 2; }
            ROOT="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
[ -n "$MODE" ] || { echo "❌ missing mode: --dry-run or --apply" >&2; usage >&2; exit 2; }
[ -d "$ROOT" ] || { echo "❌ not a directory: $ROOT" >&2; exit 2; }

# leftover_scan — every other text file under ROOT that still names a legacy
# piece. Why: the migrators rewrite references inside the four pieces only; a
# README, CI job or script pointing at the old paths breaks silently after the
# rename. Informational: it never changes the exit status.
# Excluded: VCS / dependency dirs, the four new pieces, the legacy pieces (in a
# dry-run they still exist and naturally name themselves) and the root-level
# main-file family of both layouts (backups, tidy .bak, the v1 overflow archive
# — copies of the main, not references to fix).
leftover_scan() {
    local e='s/[.[\*^$]/\\&/g' re hits errf n
    re="\\b$(printf '%s' "$HX_LEGACY_MAIN_FILE" | sed "$e")\\b|\\b$(printf '%s' "$HX_LEGACY_LOGS_DIR" | sed "$e")\\b|\\b$(printf '%s' "$HX_LEGACY_DEC_DIR" | sed "$e")\\b"
    errf=$(mktemp "${TMPDIR:-/tmp}/hxup.XXXXXX")
    # /dev/null as an extra operand: grep always prints the file name, and an
    # empty file list never makes grep read stdin. rc 1 (no match) is expected,
    # so xargs' status is ignored and read errors are judged from stderr —
    # find's too: an unreadable subdirectory is skipped by find with only a
    # stderr line, and dropping it would turn a partial scan into a clean ✅.
    hits=$(cd "$ROOT" && find . \
            \( -name .git -o -name node_modules \
               -o -path "./$HX_LOGS_DIR" -o -path "./$HX_DEC_DIR" \
               -o -path "./$HX_LEGACY_LOGS_DIR" -o -path "./$HX_LEGACY_DEC_DIR" \) -prune \
            -o -type f ! -path "./$HX_GOTCHAS_FILE" ! -path "./${HX_MAIN_FILE%.md}.*" \
               ! -path "./${HX_LEGACY_MAIN_FILE%.md}.*" ! -name '*.pre-v2-backup' -print0 2>>"$errf" \
        | LC_ALL=C xargs -0 grep -InE -- "$re" /dev/null 2>>"$errf" | sed 's#^\./##') || true
    if [ -s "$errf" ]; then
        echo "⚠️ 扫描不完整：以下路径读不了，残留清单可能缺项:"
        sed 's/^/   /' "$errf"
    fi
    if [ -z "$hits" ]; then
        if [ -s "$errf" ]; then
            echo "⚠️ 可读部分无旧名引用，但扫描不完整——不能确认项目无残留"
        else
            echo "✅ 项目其它文件无旧名引用"
        fi
        rm -f "$errf"
        return 0
    fi
    rm -f "$errf"
    n=$(printf '%s\n' "$hits" | wc -l | tr -d ' ')
    echo "⚠️ 其它文件仍引用旧名（需人工处理）:"
    printf '%s\n' "$hits" | head -n 50 | sed 's/^/   /'
    [ "$n" -le 50 ] || echo "   …共 $n 处，只列出前 50 处"
}

# checklist — the human steps of MIGRATION_GUIDE_v2.md §5.6 this script cannot do.
checklist() {
    echo "📝 后续人工步骤（MIGRATION_GUIDE_v2.md §5.6）:"
    # %q: the line is meant to be copy-pasted, and a root with a space or a
    # quote would otherwise split into wrong arguments.
    [ "$MODE" = "dry-run" ] && echo "   0. 确认上面的清单后执行: bash $(printf '%q' "$0") --apply --root $(printf '%q' "$ROOT")"
    echo "   1. 每台机器、每个 CLI（Claude Code / Codex / OpenCode）都重装 v4 skill"
    echo "   2. 处理上面的旧名残留清单（README / CI / 脚本 / 配置）"
    echo '   3. 提交：git add -A，再 git commit（git 会识别为 rename，历史不断）'
    echo "   4. 有发布链 / 公开镜像时：检查排除表与审计规则里写死的旧名"
    echo "   5. 恢复项目目录同步（Syncthing 等）"
}

KIND=$(hx_legacy_layout_kind "$ROOT")
echo "📋 布局判定: $KIND"
case "$KIND" in
    none)
        if hx_present "$ROOT/$HX_MAIN_FILE"; then
            echo "✅ 已是 handoffx 布局，无需升级"
        else
            echo "ℹ️ 没有任何 handoff 文档，请用 /handoffx-init 初始化"
        fi
        exit 0 ;;
    v1)
        # Braces on every expansion next to CJK text: bash 3.2 reads UTF-8
        # lead bytes as identifier characters, so "$NAME）" is an unbound name.
        echo "   v1 单文件 ${HX_LEGACY_MAIN_FILE} → migrate-to-v2.sh 一步产出新布局（${HX_MAIN_FILE} + ${HX_LOGS_DIR}/ + ${HX_DEC_DIR}/ + ${HX_GOTCHAS_FILE}），原文件保留 .pre-v2-backup"
        MIGRATOR=(bash "$SD/migrate-to-v2.sh") ;;
    v3)
        echo "   旧四件套（${HX_LEGACY_MAIN_FILE} + ${HX_LEGACY_LOGS_DIR}/ + ${HX_LEGACY_DEC_DIR}/ + ${HX_GOTCHAS_FILE}）→ tidy-handoff.sh schema-upgrade 原子改名"
        MIGRATOR=(bash "$SD/tidy-handoff.sh" schema-upgrade) ;;
    *)
        echo "   新旧并存或无法判定——不升级、不写任何文件，见下面的说明"
        hx_refuse_if_legacy_layout "$ROOT" handoffx-upgrade.sh || true
        exit 2 ;;
esac

rc=0; "${MIGRATOR[@]}" "--$MODE" --root "$ROOT" || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "❌ 迁移器失败（rc=${rc}）；迁移器已回滚，项目保持原样" >&2
    exit "$rc"
fi

if [ "$MODE" = "dry-run" ]; then
    leftover_scan
    checklist
    exit 0
fi

[ "${HANDOFFX_UPGRADE_FAIL_AT:-}" = "unreadable-main" ] && chmod 000 "$ROOT/$HX_MAIN_FILE"
checks_ok=1
if bash "$SD/validate-handoff.sh" --readiness "$ROOT"; then
    echo "✅ validate --readiness 通过"
else
    echo "❌ validate --readiness 未通过"; checks_ok=0
fi
bash "$SD/handoff-postflight.sh" --quiet "$ROOT/$HX_MAIN_FILE" || checks_ok=0
leftover_scan
checklist
if [ "$checks_ok" -ne 1 ]; then
    echo "❌ 迁移已完成；后置检查未过，请看上面的输出"
    exit 1
fi
echo "✅ 升级完成"
