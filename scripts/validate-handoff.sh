#!/bin/bash
# validate-handoff.sh — structural validation of HANDOFF.md
# usage: validate-handoff.sh [--readiness] [file]    (default: ./HANDOFF.md)
# exit:  0 ok (may warn), 1 required section missing, 2 file not found

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [--readiness] [file|dir]   (default: ./HANDOFF.md)"
        echo "  v2: pass project root → resolves to <dir>/HANDOFF.md plus checks pointer blocks."
        echo "Exit: 0 ok / 1 finding / 2 file not found"
        exit 0
        ;;
esac

READINESS=0
if [ "${1:-}" = "--readiness" ]; then
    READINESS=1
    shift
fi

ARG="${1:-HANDOFF.md}"
if [ -d "$ARG" ]; then
    FILE="$ARG/HANDOFF.md"
else
    FILE="$ARG"
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file|dir]   (default: ./HANDOFF.md)" >&2
    exit 2
fi

REQUIRED=(
    "Project Overview"
    "Architecture"
    "Current State"
    "Development Log"
)
RECOMMENDED=(
    "Coding Conventions"
    "Known Gotchas"
    "Decision Log"
    "References"
    "Milestones"
    "Features"
    "Testing"
)

missing_required=()
missing_recommended=()

has_section() {
    # Match "## [emoji/non-letter prefix] SECTION [终止符]"
    # 终止符合法形式：
    #   - 行尾（可带尾空白）                       e.g. "## 🏗 Architecture"
    #   - 空白后接非字母分隔符（&, —, /, (, 数字…）e.g. "## 📚 References & Docs Map"
    # 仍然拒绝 "## Architecture Notes" 误匹配 "Architecture"——"Notes" 是紧跟的字母词。
    grep -qE "^## [^A-Za-z]*$1([[:space:]]*\$|[[:space:]]+[^A-Za-z[:space:]])" "$FILE"
}

for s in "${REQUIRED[@]}"; do
    has_section "$s" || missing_required+=("$s")
done
for s in "${RECOMMENDED[@]}"; do
    has_section "$s" || missing_recommended+=("$s")
done

# v1 layouts require the inline Dev Log anchor (`<!-- 🚨 AI 注意：... -->`)
# because /handoff inserts new entries above it. v2 layouts have no inline
# Dev Log section — anchor is no longer required.
if ! grep -qF -- '<!-- HANDOFF v2 schema -->' "$FILE"; then
    grep -q "🚨 AI 注意" "$FILE" || missing_required+=("Dev Log anchor comment")
fi

ok=1
for m in "${missing_required[@]}"; do
    echo "❌ REQUIRED missing: $m"
    ok=0
done
for m in "${missing_recommended[@]}"; do
    echo "⚠️  RECOMMENDED missing: $m"
done

[ "$ok" = "1" ] || exit 1

# v2 schema integrity check: if file carries the v2 marker, expect each of the
# three pointer sections (Dev Log / Gotchas / Decision) to contain a `共 N 条`
# stat line — that's how regenerate_pointers and migrate-to-v2 leave them.
# This is a soft warning (does not flip exit code); /handoff-tidy fixes it.
if grep -qF -- '<!-- HANDOFF v2 schema -->' "$FILE"; then
    awk '
        /^## 📜 Development Log/ { dev=1; next }
        /^## 🐛 Known Gotchas/   { got=1; next }
        /^## 🧭 Decision Log/    { dec=1; next }
        /^## /                   { dev=0; got=0; dec=0 }
        dev && /^共 [0-9]+ 条$/                    { dev_stat=1 }
        got && /^共 [0-9]+ 条；最新：/             { got_stat=1 }
        dec && /^共 [0-9]+ 条；最新：/             { dec_stat=1 }
        END {
            exit (dev_stat && got_stat && dec_stat) ? 0 : 1
        }
    ' "$FILE" || {
        echo "⚠️  v2 marker present but pointer stat lines missing in HANDOFF.md"
        echo "    (run regenerate_pointers to refresh, or /handoff-tidy to repair)"
    }
fi

if [ "$READINESS" = "1" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ ! -f "$SCRIPT_DIR/handoff-lint.sh" ]; then
        echo "❌ handoff-lint.sh not found next to validate-handoff.sh" >&2
        exit 2
    fi
    bash "$SCRIPT_DIR/handoff-lint.sh" "$FILE" || exit 1
fi

[ "${#missing_recommended[@]}" = "0" ] && echo "✅ HANDOFF.md structure OK"
exit 0
