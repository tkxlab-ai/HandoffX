#!/bin/bash
# handoff-xref-lint.sh — B① reference-integrity + residual-placeholder lint.
# Operates on the EXPLICIT write-target set passed as args (ADR-0004):
# never git, never mtime. assets/*.template.md is skipped (placeholders are
# legitimate there). Exit 0 clean / 1 finding(s) / 2 usage.
# usage: handoff-xref-lint.sh <file>...   (the write-target set)
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$SCRIPT_DIR/lib/handoff-schema.sh"
# shellcheck source=scripts/lib/handoff-xref-grammar.sh
. "$SCRIPT_DIR/lib/handoff-xref-grammar.sh"

[ $# -ge 1 ] || { echo "usage: handoff-xref-lint.sh <file...>" >&2; exit 2; }

# Walk up from $1 until a dir contains $HX_LOGS_DIR/, $HX_DEC_DIR/, or
# $HX_MAIN_FILE (the four-piece root markers). Stop at filesystem root. Falls
# back to the file's own dir if none found. git-orthogonal: directory/file
# existence only, never git. Uses centralized constants from handoff-schema.sh.
_find_repo_root() {
    local d="$1"
    while [ "$d" != "/" ]; do
        if [ -d "$d/$RL_XREF_LOGS_DIR" ] || [ -d "$d/$RL_XREF_DEC_DIR" ] || [ -f "$d/$HX_MAIN_FILE" ]; then
            echo "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done
    echo "$1"
}

findings=0
processed=0
unprocessable=0
for f in "$@"; do
    # fail-closed:不存在 OR 存在但不可读 = gate 无法检查 → 计 unprocessable,
    # 绝不当作 clean(Decision 0022 / Gotcha #24:假绿比红危险)。grammar 层
    # 仍保留 absent=skip(纯解析器);此处是 gate 策略层的兜底。
    if [ ! -e "$f" ]; then
        echo "❌ xref-lint: 写入目标不存在,无法检查: $f" >&2
        unprocessable=$((unprocessable + 1))
        continue
    fi
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "❌ xref-lint: 写入目标不可读/非常规文件,无法检查: $f" >&2
        unprocessable=$((unprocessable + 1))
        continue
    fi
    # deliberate skip:模板占位合法 — 仅在文件已确认存在且可读后才跳过;
    # 缺失/不可读的 template-shaped 路径必须经过上方 unprocessable 分支
    # (P1.2 fail-closed,Codex stop-time 第3源 / Decision 0022)。
    case "$f" in
        *assets/*.template.md) continue ;;
    esac
    root="$(_find_repo_root "$(cd "$(dirname "$f")" && pwd)")"
    out="$(rl_xref_unresolved "$root" "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
    out="$(rl_residual_placeholders "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
    processed=$((processed + 1))
done

if [ "$unprocessable" -gt 0 ]; then
    echo "❌ xref-lint: $unprocessable 个写入目标无法检查 — gate 拒绝报 clean" >&2
    exit 1
fi
if [ "$processed" -eq 0 ] && [ "$#" -ge 1 ]; then
    echo "✅ xref-lint: write-target set clean(仅 template,无可检目标)"
    exit 0
fi
if [ "$findings" = "0" ]; then
    echo "✅ xref-lint: write-target set clean"
    exit 0
fi
echo "❌ xref-lint: unresolved cross-refs or residual placeholders above" >&2
exit 1
