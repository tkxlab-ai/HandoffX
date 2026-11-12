#!/bin/bash
# validate-handoff.sh — structural validation of $HX_MAIN_FILE
# usage: validate-handoff.sh [--readiness] [file]    (default: ./$HX_MAIN_FILE)
# exit:  0 ok (may warn), 1 required section missing, 2 file not found

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "$0")/lib/handoff-schema.sh"

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [--readiness] [file|dir]   (default: ./$HX_MAIN_FILE)"
        echo "  v2: pass project root → resolves to <dir>/$HX_MAIN_FILE plus checks pointer blocks."
        echo "Exit: 0 ok / 1 finding / 2 file not found"
        exit 0
        ;;
esac

READINESS=0
if [ "${1:-}" = "--readiness" ]; then
    READINESS=1
    shift
fi

ARG="${1:-$HX_MAIN_FILE}"
if [ -d "$ARG" ]; then
    FILE="$ARG/$HX_MAIN_FILE"
else
    FILE="$ARG"
fi
# Legacy-layout gate (P2.4 design §4b-4) — same rule as tidy-handoff.sh. Why:
# since v4 the default file is the new main; a legacy-layout project would
# otherwise read as "file not found" or be validated half-way (legacy sibling
# dirs unseen by --readiness). Name the exact upgrade command, exit 2. Scoped
# to main-file basenames so ad-hoc files in shared dirs are never judged by
# unrelated siblings. An explicit v1 single file is still validated as v1.
_lg_root="$(dirname "$FILE")"; _lg_base="$(basename "$FILE")"
if [ "$_lg_base" = "$HX_MAIN_FILE" ] || [ "$_lg_base" = "$HX_LEGACY_MAIN_FILE" ]; then
    # An explicit v1 single file is left to this tool's own v1 path; every
    # other legacy shape is refused with the command that upgrades it.
    if ! { [ -e "$FILE" ] && [ "$(hx_legacy_layout_kind "$_lg_root")" = "v1" ]; }; then
        hx_refuse_if_legacy_layout "$_lg_root" "validate-handoff.sh" || exit 2
    fi
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file|dir]   (default: ./$HX_MAIN_FILE)" >&2
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
# because /handoffx inserts new entries above it. v2 layouts have no inline
# Dev Log section — anchor is no longer required.
if ! grep -qF -- '<!-- HANDOFF v2 schema -->' "$FILE"; then
    grep -q "🚨 AI 注意" "$FILE" || missing_required+=("Dev Log anchor comment")
fi

ok=1
for m in "${missing_required[@]}"; do
    echo "❌ REQUIRED missing: $m"
    ok=0
done
# One info line, not one warning per section: five warnings per postflight was
# noise on every mature project (v4.2.0).
if [ "${#missing_recommended[@]}" -gt 0 ]; then
    _rec_list=""
    for m in "${missing_recommended[@]}"; do
        _rec_list="${_rec_list:+$_rec_list, }$m"
    done
    echo "ℹ️  RECOMMENDED missing (${#missing_recommended[@]}): $_rec_list — 补骨架: /handoffx-tidy"
fi

[ "$ok" = "1" ] || exit 1

# v2 schema integrity check: if file carries the v2 marker, expect each of the
# three pointer sections (Dev Log / Gotchas / Decision) to contain a `共 N 条`
# stat line — that's how regenerate_pointers and migrate-to-v2 leave them.
# This is a soft warning (does not flip exit code); /handoffx-tidy fixes it.
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
        echo "⚠️  v2 marker present but pointer stat lines missing in $HX_MAIN_FILE"
        echo "    (run regenerate_pointers to refresh, or /handoffx-tidy to repair)"
    }
    # Info only: Current State without any hx: anchor cannot be patched in place.
    # An anchor is a whole line — the same regex tidy and hx.sh use.
    LC_ALL=C awk '/^## .*Current State/{f=1;next} /^## /{f=0} f && /^<!-- \/?hx:[a-z0-9-]+ -->[[:space:]]*$/{found=1} END{exit !found}' "$FILE" ||
        echo "ℹ️  Current State has no hx: anchors — run /handoffx-tidy to add them"
fi

if [ "$READINESS" = "1" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ ! -f "$SCRIPT_DIR/handoff-lint.sh" ]; then
        echo "❌ handoff-lint.sh not found next to validate-handoff.sh" >&2
        exit 2
    fi
    bash "$SCRIPT_DIR/handoff-lint.sh" "$FILE" || exit 1
fi

[ "${#missing_recommended[@]}" = "0" ] && echo "✅ $HX_MAIN_FILE structure OK"
exit 0
