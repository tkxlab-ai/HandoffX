#!/bin/bash
# tidy-handoff.sh — tidy & diagnose $HX_MAIN_FILE structure
# usage: tidy-handoff.sh [file]    (default: ./$HX_MAIN_FILE)
# exit:  0 clean or auto-fixed, 1 has findings requiring AI/user attention, 2 file missing
#
# Philosophy: 只动结构、不动内容。AI 和 Nonaka 的默会知识留给用户。
# Auto-fix (safe, deterministic):
#   - 3+ consecutive blank lines → 2
#   - 保证 Dev Log 锚点存在（必要时加到文件末尾）
# Diagnose only (report, let AI/user fix):
#   - REQUIRED / RECOMMENDED 章节缺失
#   - Dev Log 条目按时间戳倒序检测（newest first 应为单调递减）
#   - Dev Log 条目缺必要字段（触发/改动/验证/关联）
#   - Dev Log 条目数 > 50 时提示跑 archive
#
# Backup: 改动前复制到 $FILE.bak

set -u

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "$0")/lib/handoff-schema.sh"

# P2.1 subcommand dispatch：`tidy-handoff.sh schema-upgrade ...` → handoffx schema migrator
# (P2.1, Decision 0019/0020/0025；Boss 2026-05-21 Q1 拍板 subcommand 模式)
if [ "${1:-}" = "schema-upgrade" ]; then
    shift
    . "$(dirname "$0")/lib/handoffx-tidy-migrate.sh"
    handoffx_tidy_main "$@"
    exit $?
fi

# v2.1.0 UX #2: parse --apply CLI flag alongside positional [file] arg.
# Flag position is free (GNU style). ENV var HANDOFF_TIDY_AUTO_MIGRATE=1
# remains supported for backward compat with existing CI / sandbox scripts.
APPLY_FLAG=0
FILE=""
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $0 [--apply] [file]   (default file: ./$HX_MAIN_FILE)"
            echo
            echo "Options:"
            echo "  --apply   auto-apply v1 → v2 migration when v1 layout detected"
            echo "            (CLI alternative to HANDOFF_TIDY_AUTO_MIGRATE=1 env var; preferred)"
            echo
            echo "Exit: 0 clean or auto-fixed / 1 findings / 2 file not found"
            exit 0
            ;;
        --apply)
            APPLY_FLAG=1
            ;;
        -*)
            echo "❌ unknown flag: $arg" >&2
            echo "   Run $0 --help for usage." >&2
            exit 2
            ;;
        *)
            [ -z "$FILE" ] && FILE="$arg"
            ;;
    esac
done
FILE="${FILE:-$HX_MAIN_FILE}"

# Legacy-layout gate (P2.4 design §4b-1/4). Why: since v4 the default file is
# the new main; a project still on a legacy layout would otherwise read as
# "file not found" (or, with the legacy main passed explicitly, get tidied as
# if it were current while its sibling dirs keep the legacy names). Name the
# exact upgrade command and stop. Scoped to main-file basenames so ad-hoc files
# in shared dirs are never judged by unrelated siblings. v1 single files passed
# explicitly fall through to the v1 gate below, which routes to migrate-to-v2.
_lg_root="$(dirname "$FILE")"; _lg_base="$(basename "$FILE")"
if [ "$_lg_base" = "$HX_MAIN_FILE" ] || [ "$_lg_base" = "$HX_LEGACY_MAIN_FILE" ]; then
    # An explicit v1 single file is left to this tool's own v1 path; every
    # other legacy shape is refused with the command that upgrades it.
    if ! { [ -e "$FILE" ] && [ "$(hx_legacy_layout_kind "$_lg_root")" = "v1" ]; }; then
        hx_refuse_if_legacy_layout "$_lg_root" "tidy-handoff.sh" || exit 2
    fi
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file]   (default: ./$HX_MAIN_FILE)" >&2
    exit 2
fi

# ---------- v2 layout helpers (C1 gate + C2 dup recovery) ----------
# Source lib if available; the gate / dup-recovery blocks below check loaded helpers.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_LOADED=0
if [ -f "$SCRIPT_DIR/lib/handoff-v2.sh" ]; then
    # shellcheck source=lib/handoff-v2.sh
    source "$SCRIPT_DIR/lib/handoff-v2.sh"
    LIB_LOADED=1
fi

# C2: detect_dup_numbers — renumber duplicate NNNN entries (Syncthing-merge recovery).
# Sorted basename traversal keeps the earlier filename and bumps subsequent
# duplicates to fresh numbers. Tracks the *original* group number — not the
# previously-seen-or-renamed number — so triples (three files sharing 0001)
# all get caught: first stays as 0001, second renamed, third is still compared
# against 0001 (not against the second's new number) and gets renamed too.
# (Codex review #2 fix.)
detect_dup_numbers() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local current_orig_group="" curr_num rest next new_path renamed=0
    local f
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        curr_num=$(basename "$f" | grep -oE '^[0-9][0-9][0-9][0-9]')
        if [ "$curr_num" = "$current_orig_group" ]; then
            # Same original group as the kept file — renumber to next free.
            next=$(acquire_next_number "$dir")
            rest=$(basename "$f" | sed -E 's/^[0-9][0-9][0-9][0-9]-//')
            new_path="$dir/${next}-${rest}"
            mv "$f" "$new_path"
            echo "   🔧 Renumbered duplicate: $(basename "$f") → ${next}-${rest}"
            renamed=$((renamed + 1))
            # Don't update current_orig_group — we're still tracking the
            # original duplicate group; further files with the same NNNN must
            # also be renumbered.
        else
            # New group — first occurrence keeps its number.
            current_orig_group="$curr_num"
        fi
    done < <(ls "$dir"/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sort)
    return 0
}

# C1: v1 layout gate. Bypass for legacy-layout tests via env var.
# Why the classifier too (fix wave 2): verify_v2_layout calls a file v1 only
# when it holds dated entries, while hx_legacy_layout_kind decides v1 by
# elimination (F1). Without the second clause an entry-less legacy main passed
# with --apply — the fallback every v1 refusal prints — was tidied as if it
# were current and never migrated.
if [ "$LIB_LOADED" = "1" ] && [ "${HANDOFF_TIDY_SKIP_V2_GATE:-0}" != "1" ]; then
    if ! verify_v2_layout "$FILE" \
       || { [ "$_lg_base" = "$HX_LEGACY_MAIN_FILE" ] && [ "$(hx_legacy_layout_kind "$_lg_root")" = v1 ]; }; then
        ROOT_DIR_TIDY="$(cd "$(dirname "$FILE")" && pwd)"
        echo "⚠️  v1 layout detected at $FILE"
        echo "   v2.0.0 stores Dev Log / Decision / Gotchas in sibling files (${HX_LOGS_DIR}/, ${HX_DEC_DIR}/, ${HX_GOTCHAS_FILE})."
        echo

        APPLY=""
        # v2.1.0 UX #2: --apply CLI flag is the preferred non-interactive trigger;
        # ENV var stays as a backward-compat alias (mention both so users see
        # the CLI option exists).
        if [ "$APPLY_FLAG" = "1" ]; then
            APPLY="y"
            echo "   (--apply — auto-applying migration)"
        elif [ "${HANDOFF_TIDY_AUTO_MIGRATE:-0}" = "1" ]; then
            APPLY="y"
            echo "   (HANDOFF_TIDY_AUTO_MIGRATE=1 — auto-applying migration)"
        elif [ -t 0 ]; then
            bash "$SCRIPT_DIR/migrate-to-v2.sh" --dry-run --root "$ROOT_DIR_TIDY"
            echo
            printf "   Apply migration now? (y/N) "
            read -r APPLY
        else
            echo "   non-interactive shell; tidy will NOT migrate automatically."
            echo "   Re-run interactively, pass --apply, or set HANDOFF_TIDY_AUTO_MIGRATE=1."
            exit 0
        fi

        # Normalize answer (bash 3.2 — no ${VAR,,})
        case "$APPLY" in
            [yY]|[yY][eE][sS]) APPLY="y" ;;
            *) APPLY="n" ;;
        esac

        if [ "$APPLY" = "y" ]; then
            bash "$SCRIPT_DIR/migrate-to-v2.sh" --apply --root "$ROOT_DIR_TIDY"
            exit $?
        else
            echo "   skipped — re-run /handoffx-tidy when ready to migrate"
            exit 0
        fi
    fi
fi

# C2: on v2 layouts, renumber any duplicate-NNNN files (Syncthing race recovery).
# Runs whenever the lib is loaded and the file carries the v2 marker.
if [ "$LIB_LOADED" = "1" ] && grep -qF -- "$HANDOFF_V2_MARKER" "$FILE" 2>/dev/null; then
    ROOT_DIR_TIDY="${ROOT_DIR_TIDY:-$(cd "$(dirname "$FILE")" && pwd)}"
    detect_dup_numbers "$ROOT_DIR_TIDY/$HX_LOGS_DIR"
    detect_dup_numbers "$ROOT_DIR_TIDY/$HX_DEC_DIR"
fi

BACKUP_MADE=0
FIX_COUNT=0
FINDINGS=0

# 先记录原始内容 hash 用于判断是否有变动
orig_hash=$(shasum "$FILE" | cut -d' ' -f1)

make_backup_once() {
    if [ "$BACKUP_MADE" = "0" ]; then
        cp "$FILE" "${FILE}.bak"
        BACKUP_MADE=1
    fi
}

# ---------- Auto-fix 2: ensure anchor exists inside Development Log ----------
# Runs before blank-line collapse so any blank line introduced here gets cleaned up in one pass.
if ! grep -q "🚨 AI 注意" "$FILE"; then
    TMP2=$(mktemp)
    awk '
        /^## / {
            if (in_dev_log) {
                in_dev_log = 0
                print ""
                print "<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上，最新记录在最顶部。 -->"
            }
            if ($0 ~ /Development Log[[:space:]]*$/) in_dev_log = 1
            print
            next
        }
        { print }
        END {
            if (in_dev_log) {
                print ""
                print "<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上，最新记录在最顶部。 -->"
            }
        }
    ' "$FILE" > "$TMP2"
    if ! diff -q "$FILE" "$TMP2" >/dev/null 2>&1; then
        make_backup_once
        cp "$TMP2" "$FILE"
        FIX_COUNT=$((FIX_COUNT+1))
        echo "🧹 锚点补齐：Dev Log 内缺锚点，已加"
    fi
    rm -f "$TMP2"
fi

# ---------- Auto-fix 1: collapse 3+ blank lines to 2 ----------
TMP=$(mktemp)
awk '
    /^$/ { blank++; if (blank <= 2) print; next }
    { blank=0; print }
' "$FILE" > "$TMP"
if ! diff -q "$FILE" "$TMP" >/dev/null 2>&1; then
    make_backup_once
    cp "$TMP" "$FILE"
    FIX_COUNT=$((FIX_COUNT+1))
    echo "🧹 空行归一：连续 > 2 个空行压缩为 2 个"
fi
rm -f "$TMP"

# ---------- Diagnose 1: missing sections ----------
REQUIRED=("Project Overview" "Architecture" "Current State" "Development Log")
RECOMMENDED=("Coding Conventions" "Known Gotchas" "Decision Log" "References" "Milestones" "Features" "Testing")

has_section() {
    # 与 validate-handoff.sh 同语义：允许 "## X & Y" / "## X — Z" 复合标题，拒绝 "X Notes" 误匹配
    grep -qE "^## [^A-Za-z]*$1([[:space:]]*\$|[[:space:]]+[^A-Za-z[:space:]])" "$FILE"
}

missing_req=""
for s in "${REQUIRED[@]}"; do
    has_section "$s" || missing_req="$missing_req\n  ❌ $s (REQUIRED)"
done
missing_rec=""
for s in "${RECOMMENDED[@]}"; do
    has_section "$s" || missing_rec="$missing_rec\n  ⚠️  $s (RECOMMENDED)"
done

if [ -n "$missing_req" ] || [ -n "$missing_rec" ]; then
    echo ""
    echo "📐 章节诊断："
    [ -n "$missing_req" ] && printf "缺失 REQUIRED 章节（AI 应从 template 补齐）：$missing_req\n"
    [ -n "$missing_rec" ] && printf "缺失 RECOMMENDED 章节（AI 可选补齐）：$missing_rec\n"
    [ -n "$missing_req" ] && FINDINGS=$((FINDINGS+1))
fi

# ---------- Diagnose 2: Dev Log entry ordering ----------
# 提取所有 Dev Log entry 的 timestamp，期望 newest → oldest 单调递减
timestamps=$(awk '
    /^## 📜 Development Log/ { in_log=1; next }
    /^## / && in_log { in_log=0 }
    in_log && /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        n = split($0, p, " ")
        date = p[2]
        # p[3] might be time "HH:MM" or start of em-dash
        if (n >= 3 && p[3] ~ /^[0-9][0-9]:[0-9][0-9]$/) {
            time = p[3]
        } else {
            time = "00:00"
        }
        gsub(/-/, "", date); gsub(/:/, "", time)
        print date time
    }
' "$FILE")

out_of_order=0
prev_ts=""
for ts in $timestamps; do
    if [ -n "$prev_ts" ] && [ "$ts" -gt "$prev_ts" ] 2>/dev/null; then
        out_of_order=$((out_of_order+1))
    fi
    prev_ts="$ts"
done

entry_count=$(echo "$timestamps" | grep -c "^[0-9]" || true)

anchor_report=$(awk '
    /^## 📜 Development Log/ { in_log=1; next }
    /^## / && in_log { in_log=0 }
    /🚨 AI 注意/ {
        if (in_log) anchor_in_log++
        else anchor_outside++
    }
    END {
        if (anchor_in_log != 1 || anchor_outside > 0) {
            print "  ❌ anchor must be inside Development Log exactly once"
        }
    }
' "$FILE")

if [ -n "$anchor_report" ]; then
    echo ""
    echo "⚓ Dev Log 锚点诊断："
    echo "$anchor_report"
    FINDINGS=$((FINDINGS+1))
fi

if [ "$out_of_order" -gt 0 ]; then
    echo ""
    echo "📅 Dev Log 顺序诊断："
    echo "  ⚠️  $out_of_order 处打乱（应按时间戳严格倒序，最新在最上面）"
    echo "     → AI 应重排条目为倒序"
    FINDINGS=$((FINDINGS+1))
fi

# ---------- Diagnose 3: Dev Log entries missing required fields ----------
missing_fields_report=$(awk '
    /^## 📜 Development Log/ { in_log=1; next }
    /^## / && in_log {
        if (in_log && cur != "") flush_entry()
        in_log=0
    }
    in_log && /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        if (cur != "") flush_entry()
        cur = $0
        delete seen
    }
    in_log && cur != "" {
        # v2.1.0: synonym tolerance — accept Chinese canonical or English
        # alternate (mirror of handoff-lint.sh awk block to keep tidy and
        # lint enforcing the same rule)
        if (match($0, /\*\*触发\*\*:/)   || match($0, /\*\*Trigger\*\*:/))      seen["触发"]=1
        if (match($0, /\*\*改动\*\*:/)   || match($0, /\*\*Changes\*\*:/))      seen["改动"]=1
        if (match($0, /\*\*验证\*\*:/)   || match($0, /\*\*Verification\*\*:/)) seen["验证"]=1
        if (match($0, /\*\*关联\*\*:/)   || match($0, /\*\*Related\*\*:/))      seen["关联"]=1
    }
    END {
        if (cur != "") flush_entry()
    }
    function flush_entry() {
        missing = ""
        if (!seen["触发"]) missing = missing " 触发"
        if (!seen["改动"]) missing = missing " 改动"
        if (!seen["验证"]) missing = missing " 验证"
        if (!seen["关联"]) missing = missing " 关联"
        if (missing != "") {
            # 取条目标题前 80 字符
            title = substr(cur, 1, 80)
            print "  ⚠️  " title " → 缺字段:" missing
        }
    }
' "$FILE")

if [ -n "$missing_fields_report" ]; then
    echo ""
    echo "📝 Dev Log 字段诊断（AI 应补齐缺失字段为 \`—\`）："
    echo "$missing_fields_report"
    FINDINGS=$((FINDINGS+1))
fi

# ---------- Diagnose 4: entry count threshold ----------
if [ "$entry_count" -gt 50 ]; then
    echo ""
    echo "📦 Dev Log 规模：$entry_count 条"
    echo "  ➡️  建议跑 archive-devlog.sh 把最老的 $((entry_count - 50)) 条移到归档"
fi

# ---------- Summary ----------
final_hash=$(shasum "$FILE" | cut -d' ' -f1)
echo ""
echo "═══ tidy summary ═══"
if [ "$orig_hash" != "$final_hash" ]; then
    echo "✏️  自动修复 $FIX_COUNT 项（原文已备份到 ${FILE}.bak）"
fi
if [ "$FINDINGS" -gt 0 ]; then
    echo "⚠️  $FINDINGS 类问题需要 AI / 用户处理（见上方诊断）"
    exit 1
fi
echo "✅ 结构干净"
exit 0
