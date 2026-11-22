#!/bin/bash
# Caller CDPATH must not redirect relative paths or leak cd output into data.
unset CDPATH
# handoff-postflight.sh — v2.2.0 parallel orchestration: read-only checks run
# concurrently; archive-devlog runs serially after (it mv-s files → no race).
# 只读检查先聚合；有阻断/无法检查时绝不执行归档。
#
# usage: handoff-postflight.sh [--quiet|--brief] [file]   (default: ./$HX_MAIN_FILE)
# exit:  0 all clean / 1 any check failed / 2 file not found or usage error
#
# Checks, numbered in execution order (v4.1.1: the replay used to print
# 1 2 3 4 6 5 because xref-lint was numbered after archive-devlog although it
# runs in the parallel batch before it):
#   1. scan-credentials      — block plaintext API keys / tokens / passwords
#   2. validate-handoff      — structure only (independent lint below)
#   3. handoff-lint          — per-file frontmatter + body field invariants (v2)
#   4. rotation-reminder     — credential rotation warnings
#   5. handoff-xref-lint     — v2 managed anchors + explicit --files=; parallel with 1-4
#   6. archive-devlog        — v2: yearly archive of $HX_LOGS_DIR/ (v1: >50 entries); serial殿后

set -u

# brief 在最外层收口：任何 worker stderr、文件名、甚至前置错误都不能撑爆屏幕。
# 只使用固定中文摘要，不截断原始诊断（也不泄漏凭证）；详查重跑原命令去掉 --brief。
BRIEF=0
for arg in "$@"; do [ "$arg" = "--brief" ] && BRIEF=1; done
BRIEF_MESSAGE="❌ 交接检查无法执行：参数或文件不可用。未执行归档；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"

postflight() {

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
if ! . "$(dirname "$0")/lib/handoff-schema.sh"; then
    BRIEF_MESSAGE="❌ 交接检查无法执行：缺少布局定义。未执行归档；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
    return 2
fi

local context_sd expected_root=''
context_sd=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || return 2
# shellcheck disable=SC1091
. "$context_sd/lib/handoff-context.sh" || return 2
hx_context_take_expect_root 'postflight: ' "$@" || return 2
expected_root=$HX_TAKEN_ROOT; shift "$HX_TAKEN_SHIFT"
hx_context_check_memo "$context_sd" "$expected_root" || return 2

QUIET=0
FILE=""
FILES_CSV=""
FILES_CSV_SET=0
for arg in "$@"; do
    case "$arg" in
        --files=*)
            FILES_CSV="${arg#--files=}"
            FILES_CSV_SET=1
            ;;
        -h|--help)
            # Heredoc body unquoted (<<EOF, not <<'EOF') so $HX_MAIN_FILE
            # expands — the help text follows P2.2 rename, no split-brain
            # with the runtime FILE default (L67 `${FILE:-$HX_MAIN_FILE}`).
            # Body has zero other shell metachars (`$`, backticks, `\`) so
            # unquoting is a no-op for everything else (Tacit#4 Why: prove
            # safe before relaxing quotes — verified line-by-line).
            BRIEF_MESSAGE="用法：bash scripts/handoff-postflight.sh [--brief|--quiet] [--files=a.md,b.md] [file]。详查：去掉 --brief；完整帮助：--help。"
            cat <<EOF
Usage: handoff-postflight.sh [--quiet|--brief] [--files=a.md,b.md] [file]   (default file: ./$HX_MAIN_FILE)
       --brief   ≤200 Unicode 字符聚合摘要；优先于 --quiet，详查去掉 --brief
       --quiet   保留旧摘要契约
       --files=  additional write targets (comma-separated, no empty items)
                 v2 canonical main always includes main + GOTCHAS + existing INDEX
                 no historical-entry scan; ad-hoc/v1 files stay explicit-only

Aggregates the post-handoffx verification checks into a single command
with a unified PASS/FAIL summary. Equivalent to running these in sequence:

  1. scan-credentials      — block plaintext credentials in project tree
  2. validate-handoff      — section structure (lint runs separately once)
  3. handoff-lint          — per-file frontmatter + body fields (v2)
  4. rotation-reminder     — credential rotation warnings
  5. handoff-xref-lint     — v2 managed anchors + explicit --files= (B①)
  6. archive-devlog        — v2: yearly archive of $HX_LOGS_DIR/ (v1: >50 entries)

Options:
  --quiet    suppress per-check output AND failing-tool detail; only the
             summary line is printed. Re-run without --quiet to diagnose.
  -h, --help show this help

Exit: 0 all clean / 1 any check failed / 2 file not found or usage error
EOF
            return 0
            ;;
        --brief) ;;
        --quiet|-q)
            QUIET=1
            ;;
        -*)
            echo "❌ unknown flag: $arg" >&2
            echo "   Run $0 --help for usage." >&2
            return 2
            ;;
        *)
            [ -z "$FILE" ] && FILE="$arg"
            ;;
    esac
done
FILE="${FILE:-$HX_MAIN_FILE}"
# Check BOTH the invocation cwd and selected target on this write operation.
hx_context_write_check "$context_sd" "$expected_root" || return 2
(cd "$(dirname "$FILE")" && hx_context_check "$context_sd" "$expected_root" >/dev/null) || return 2

# Legacy-layout gate (P2.4 design §4b-4) — same rule as tidy-handoff.sh. Why:
# five checks against a missing new main (or against a legacy main whose
# sibling dirs the checks no longer look for) would report noise or a false
# pass; name the exact upgrade command and return 2 before running any check.
# Scoped to main-file basenames so ad-hoc files are never judged by siblings.
_lg_root="$(dirname "$FILE")"; _lg_base="$(basename "$FILE")"
if [ "$_lg_base" = "$HX_MAIN_FILE" ] || [ "$_lg_base" = "$HX_LEGACY_MAIN_FILE" ]; then
    # An explicit v1 single file is left to this tool's own v1 path; every
    # other legacy shape is refused with the command that upgrades it.
    if ! { [ -e "$FILE" ] && [ "$(hx_legacy_layout_kind "$_lg_root")" = "v1" ]; }; then
        if ! hx_refuse_if_legacy_layout "$_lg_root" "handoff-postflight.sh"; then
            BRIEF_MESSAGE="❌ 交接检查无法执行：旧布局或新旧混用，需先升级。未执行归档；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
            return 2
        fi
    fi
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    return 2
fi

# F2: caller-input validation — before any temp infra; fast-fail, no wait needed
if [ "${FILES_CSV_SET:-0}" = "1" ] && [ -z "$FILES_CSV" ]; then
    echo "❌ postflight: --files= given but empty (broken write-target set)" >&2
    return 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$(dirname "$FILE")" && pwd)"

# CSV describes additional write targets, not the complete v2 safety boundary.
# Preserve arrays throughout: an automatically discovered root may contain
# commas/spaces, so it must never be serialized back into the CSV interface.
case "$FILES_CSV" in
    ,*|*,|*,,*|*$'\n'*|*$'\r'*)
        echo "❌ postflight: invalid --files= (empty item or line break)" >&2
        return 2 ;;
esac
local -a XREF_FILES
XREF_FILES=()
XREF_SEEN=$'\n'
AUTO_XREF=0
add_xref_target() {
    local candidate="$1" key
    # %q is a lossless single-line key even for a root containing newlines.
    # Never eval it. Avoid a shell-level scan of every prior array member.
    printf -v key '%q' "$candidate"
    case "$XREF_SEEN" in *$'\n'"$key"$'\n'*) return 0 ;; esac
    XREF_SEEN="$XREF_SEEN$key"$'\n'
    XREF_FILES[${#XREF_FILES[@]}]="$candidate"
}
if [ "$_lg_base" = "$HX_MAIN_FILE" ] && grep -qF '<!-- HANDOFF v2 schema -->' "$FILE"; then
    AUTO_XREF=1
    add_xref_target "$ROOT_DIR/$HX_MAIN_FILE"
    # Required even when missing: the gate must report it, never silently skip.
    add_xref_target "$ROOT_DIR/$HX_GOTCHAS_FILE"
    # INDEX does not exist before first regen; wrong types/dangling links do
    # exist for validation purposes and must not be mistaken for absence.
    if hx_present "$ROOT_DIR/$HX_DEC_DIR/INDEX.md"; then
        add_xref_target "$ROOT_DIR/$HX_DEC_DIR/INDEX.md"
    fi
fi
if [ "$FILES_CSV_SET" = 1 ]; then
    # Pure Bash parsing: a failed producer in process substitution is otherwise
    # invisible and could silently drop explicit files while auto anchors pass.
    _remaining=$FILES_CSV
    while :; do
        case "$_remaining" in
            *,*) _f=${_remaining%%,*}; _remaining=${_remaining#*,}; _more=1 ;;
            *) _f=$_remaining; _more=0 ;;
        esac
        while [[ "$_f" == ./* ]]; do _f=${_f#./}; done
        case "$_f" in /*) ;; *) _f="$ROOT_DIR/$_f" ;; esac
        add_xref_target "$_f"
        [ "$_more" = 1 ] || break
    done
fi
XREF_ENABLED=0
[ "${#XREF_FILES[@]}" -eq 0 ] || XREF_ENABLED=1

PF_TMP=$(mktemp -d) || {
    echo "❌ postflight: mktemp -d failed" >&2
    BRIEF_MESSAGE="❌ 交接检查无法执行：临时目录创建失败。未执行归档；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
    return 2
}
trap 'rm -rf "$PF_TMP"' EXIT

# PARALLEL-ORCHESTRATION: rc/out 落 $PF_TMP，不即删，供 wait 后回放+聚合
run_check() {
    local n="$1" name="$2"
    shift 2
    local ec=0
    "$@" >"$PF_TMP/$n.out" 2>&1 || ec=$?
    echo "$ec" > "$PF_TMP/$n.rc"
    echo "$name" > "$PF_TMP/$n.name"
}

# U04: validate 不带 --readiness，避免其内嵌 lint 与检查 3 重复。
# 只读 check 后台并行（1 scan-credentials / 2 validate / 3 lint / 4 rotation）
run_check 1 "scan-credentials"  bash "$SCRIPT_DIR/scan-credentials.sh"  --include-file "$FILE" "$ROOT_DIR" &
run_check 2 "validate-handoff"  bash "$SCRIPT_DIR/validate-handoff.sh"  "$FILE" &
run_check 3 "handoff-lint"      bash "$SCRIPT_DIR/handoff-lint.sh"      "$FILE" &
run_check 4 "rotation-reminder" bash "$SCRIPT_DIR/rotation-reminder.sh" --classify "$FILE" &

# B① xref-lint remains scoped: managed anchors plus the caller's explicit
# entries, never a recursive walk or an implicit scan of historical logs.
run_xref_check() {
    local guard
    if [ "$AUTO_XREF" = 1 ]; then
        for guard in "$ROOT_DIR/$HX_MAIN_FILE" "$ROOT_DIR/$HX_GOTCHAS_FILE" \
                     "$ROOT_DIR/$HX_DEC_DIR" "$ROOT_DIR/$HX_DEC_DIR/INDEX.md"; do
            if [ -L "$guard" ]; then
                echo "❌ xref-lint: auto target is a symlink, refusing: $guard" >&2
                return 1
            fi
        done
        # Validate every managed dependency BEFORE parsing main-file refs.
        # Otherwise a Gotcha reference could grep a FIFO before xref reaches
        # the GOTCHAS target's own regular-file check, hanging the whole wait.
        for guard in "$ROOT_DIR/$HX_MAIN_FILE" "$ROOT_DIR/$HX_GOTCHAS_FILE" \
                     "$ROOT_DIR/$HX_DEC_DIR/INDEX.md"; do
            if [ "$guard" = "$ROOT_DIR/$HX_DEC_DIR/INDEX.md" ] && ! hx_present "$guard"; then
                continue
            fi
            if [ ! -e "$guard" ]; then
                echo "❌ xref-lint: 写入目标不存在,无法检查: $guard" >&2
                return 1
            fi
            if [ ! -f "$guard" ] || [ ! -r "$guard" ]; then
                echo "❌ xref-lint: 写入目标不可读/非常规文件,无法检查: $guard" >&2
                return 1
            fi
        done
    fi
    bash "$SCRIPT_DIR/handoff-xref-lint.sh" "$@"
}
if [ "$XREF_ENABLED" = 1 ]; then
    run_check 5 "xref-lint(B①)" run_xref_check "${XREF_FILES[@]}" &
fi

wait   # 墙钟 = max(单只读 check)，非 sum

# 先读完所有只读结果，再决定是否维护。缺 rc/异常 rc 均阻断。
readonly_failed=0
for n in 1 2 3 4 5; do
    [ "$n" = "5" ] && [ "$XREF_ENABLED" = 0 ] && continue
    rc=$(cat "$PF_TMP/$n.rc" 2>/dev/null) || rc="missing"
    if [ "$rc" != "0" ] && ! { [ "$n" = "4" ] && [ "$rc" = "3" ]; }; then
        readonly_failed=1
    fi
done
archive_skipped=0
if [ "$readonly_failed" = "0" ]; then
    # Forward caller intent, not a newly inferred cwd requirement. Explicit
    # unbound source callers may select a file outside cwd (legacy CLI API).
    # Global installs already require expected_root above; project installs
    # validate both cwd and target against their manifest in both scripts.
    if [ -n "$expected_root" ]; then
        run_check 6 "archive-devlog" bash "$SCRIPT_DIR/archive-devlog.sh" --expect-root "$expected_root" "$FILE"
    else
        run_check 6 "archive-devlog" bash "$SCRIPT_DIR/archive-devlog.sh" "$FILE"
    fi
else
    archive_skipped=1
fi

[ "$QUIET" = "0" ] && echo
fail_count=0
fail_list=""
warn_count=0
brief_reason=""
for n in 1 2 3 4 5 6; do
    [ "$n" = "5" ] && [ "$XREF_ENABLED" = 0 ] && continue
    if [ "$n" = "6" ] && [ "$archive_skipped" = "1" ]; then
        [ "$QUIET" = "0" ] && echo "→ 6. archive-devlog: skipped（只读检查未通过，未执行归档）"
        continue
    fi
    case "$n" in
        1) label="凭证扫描" ;;
        2) label="文档结构" ;;
        3) label="条目校验" ;;
        4) label="凭证轮换" ;;
        5) label="交叉引用" ;;
        6) label="归档失败（可能已部分执行）" ;;
    esac
    nm=$(cat "$PF_TMP/$n.name" 2>/dev/null) || nm="check#$n"
    rc=$(cat "$PF_TMP/$n.rc" 2>/dev/null) || rc="no-rc"
    status=fail
    if [ "$rc" = "0" ]; then status=pass
    elif [ "$n" = "4" ] && [ "$rc" = "3" ]; then status=warn; fi
    if [ "$QUIET" = "0" ]; then
        echo "→ ${n}. ${nm}"
        case "$status" in
            pass) echo "   ✅" ;;
            warn) echo "   ⚠️ warning（非阻断）" ;;
            fail) echo "   ❌ exit=$rc" ;;
        esac
        if [ "$status" != "pass" ] && [ -s "$PF_TMP/$n.out" ]; then
            sed 's/^/   /' "$PF_TMP/$n.out"
        fi
    fi
    case "$status" in
        warn) warn_count=$((warn_count+1)) ;;
        fail)
            fail_count=$((fail_count+1)); fail_list="$fail_list $nm"
            if [ -z "$brief_reason" ]; then
                brief_reason="$label"
                if [ "$n" != "6" ]; then
                    case "$rc" in 1) ;; *) brief_reason="${label}（无法检查）" ;; esac
                fi
            fi ;;
    esac
done

rm -rf "$PF_TMP"; trap - EXIT
if [ "$fail_count" = "0" ]; then
    if [ "$warn_count" = "0" ]; then
        BRIEF_MESSAGE="✅ 交接检查通过，归档检查完成。"
        echo "✅ postflight: all checks passed"
    else
        BRIEF_MESSAGE="⚠️ 交接检查通过：凭证临近到期（非阻断），归档检查完成；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
        echo "⚠️ postflight: checks passed with rotation warning (non-blocking)"
    fi
    return 0
else
    if [ "$archive_skipped" = "1" ]; then
        BRIEF_MESSAGE="❌ 交接检查未通过：${brief_reason}。未执行归档；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
    else
        BRIEF_MESSAGE="❌ 交接检查未通过：${brief_reason}；运行 bash scripts/handoff-postflight.sh（保留原参数，去掉 --brief）详查。"
    fi
    suffix=""
    [ "$archive_skipped" = "1" ] && suffix="; archive-devlog: skipped（未执行归档）"
    echo "❌ postflight: $fail_count check(s) failed:$fail_list$suffix"
    return 1
fi
}

# 函数不在子 shell 执行，摘要状态得以保留；捕获所有输出，仅 brief 发一行。
if [ "$BRIEF" = "1" ]; then
    postflight "$@" >/dev/null 2>&1
    rc=$?
    printf '%s\n' "$BRIEF_MESSAGE"
else
    postflight "$@"
    rc=$?
fi
exit "$rc"
