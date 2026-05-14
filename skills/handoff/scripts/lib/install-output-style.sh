#!/bin/bash
# install-output-style.sh — unified install.sh runtime output helper.
#
# Sourced by every TKX skill's install.sh to render the same banner /
# checkpoint / summary visual across gitx-release / mac-release / handoff /
# 1by1 / ClaudeMeX. Master copy lives in Git_Release_Skill/scripts/lib/;
# downstream skills vendor a byte-identical copy in their own scripts/lib/.
# Enforced by release-audit.sh §0b (must `source` this file when shipped).
#
# Public API:
#   install_style_init      <total_checkpoints>
#   install_banner_top      <skill_name> <version> <mode> [source_dir]
#   install_checkpoint      <icon> <title>            # auto increments
#   install_step_ok         <msg>
#   install_step_warn       <msg>
#   install_step_fail       <msg>
#   install_banner_bottom   <skill_name> <version>
#   install_cli_row         <cli_name> <invocation> <path>
#   install_cli_table_begin
#   install_cli_table_end
#   install_next_hint       <msg>
#   install_next_block      "hint1" "hint2" ...
#
# Design rules:
#   - ASCII-portable. Emoji are intentional but optional (TKX_INSTALL_NO_EMOJI=1
#     replaces them with ASCII markers). Box-drawing is plain `=` lines.
#   - No color when not on a TTY (CI / pipe / non-interactive). When on a TTY
#     and `tput` is available, use minimal bold/dim only — never background
#     color.
#   - State (checkpoint counter, total) is module-scoped via shell vars; safe
#     to `source` multiple times — `install_style_init` resets state.
#   - Exit codes: this helper never exits the parent script. Callers decide.

# Guard against double-source (idempotent).
if [ "${_TKX_INSTALL_STYLE_LOADED:-0}" = "1" ]; then
    return 0 2>/dev/null || true
fi
_TKX_INSTALL_STYLE_LOADED=1

# --- Visual constants (overridable via env) ---
_TKX_BAR_CHAR="${TKX_INSTALL_BAR_CHAR:-=}"
_TKX_BAR_WIDTH="${TKX_INSTALL_BAR_WIDTH:-63}"
_TKX_BAR_LINE=""
_i=0
while [ "$_i" -lt "$_TKX_BAR_WIDTH" ]; do
    _TKX_BAR_LINE="${_TKX_BAR_LINE}${_TKX_BAR_CHAR}"
    _i=$((_i + 1))
done
unset _i

# Emoji + Unicode set (override with TKX_INSTALL_NO_EMOJI=1 for ASCII-only output).
# In ASCII mode, the em-dash separator and bullet also fall back to plain ASCII
# so the entire helper output is single-byte safe for non-UTF-8 terminals / logs.
if [ "${TKX_INSTALL_NO_EMOJI:-0}" = "1" ]; then
    _TKX_E_PKG="[*]"
    _TKX_E_LOCK="[lock]"
    _TKX_E_SEARCH="[?]"
    _TKX_E_DIR="[dir]"
    _TKX_E_LINK="[ln]"
    _TKX_E_BROOM="[rm]"
    _TKX_E_CHECK="[ok]"
    _TKX_E_OK="[OK]"
    _TKX_E_WARN="[!]"
    _TKX_E_FAIL="[X]"
    _TKX_E_PARTY="[done]"
    _TKX_DASH="-"
    _TKX_BULLET="*"
else
    _TKX_E_PKG="📦"
    _TKX_E_LOCK="🔐"
    _TKX_E_SEARCH="🔍"
    _TKX_E_DIR="📂"
    _TKX_E_LINK="🔗"
    _TKX_E_BROOM="🧹"
    _TKX_E_CHECK="✓"
    _TKX_E_OK="✅"
    _TKX_E_WARN="⚠️"
    _TKX_E_FAIL="❌"
    _TKX_E_PARTY="🎉"
    _TKX_DASH="—"
    _TKX_BULLET="•"
fi

# Export emoji constants for downstream callers that need direct access
# (e.g. dry-run preview lines that don't fit checkpoint shape).
export _TKX_E_PKG _TKX_E_LOCK _TKX_E_SEARCH _TKX_E_DIR _TKX_E_LINK
export _TKX_E_BROOM _TKX_E_CHECK _TKX_E_OK _TKX_E_WARN _TKX_E_FAIL _TKX_E_PARTY

# --- Counter state (reset by install_style_init) ---
_TKX_CHECKPOINT_N=0
_TKX_CHECKPOINT_TOTAL=0

install_style_init() {
    _TKX_CHECKPOINT_N=0
    # Coerce to integer: empty / non-numeric → 0 (means "no n/total in
    # checkpoint header"). Prevents `[: abc: integer expected` noise when
    # a downstream skill passes an unset / mistyped total.
    local arg="${1:-0}"
    case "$arg" in
        ''|*[!0-9]*) _TKX_CHECKPOINT_TOTAL=0 ;;
        *)           _TKX_CHECKPOINT_TOTAL="$arg" ;;
    esac
}

# --- Banner top: skill name + version + mode + source dir ---
install_banner_top() {
    local skill="${1:-unknown}"
    local version="${2:-unknown}"
    local mode="${3:-install}"
    local src="${4:-}"
    printf '\n%s\n' "$_TKX_BAR_LINE"
    printf '  %s  %s Installation  %s\n' "$_TKX_E_PKG" "$skill" "$version"
    printf '%s\n' "$_TKX_BAR_LINE"
    [ -n "$src" ] && printf '  Source : %s\n' "$src"
    printf '  Mode   : %s\n\n' "$mode"
}

# --- Checkpoint: increments counter, prints "icon  Checkpoint n/total — title" ---
install_checkpoint() {
    local icon="${1:-$_TKX_E_CHECK}"
    local title="${2:-step}"
    _TKX_CHECKPOINT_N=$((_TKX_CHECKPOINT_N + 1))
    if [ "$_TKX_CHECKPOINT_TOTAL" -gt 0 ]; then
        printf '%s  Checkpoint %d/%d %s %s\n' \
            "$icon" "$_TKX_CHECKPOINT_N" "$_TKX_CHECKPOINT_TOTAL" "$_TKX_DASH" "$title"
    else
        printf '%s  Checkpoint %d %s %s\n' \
            "$icon" "$_TKX_CHECKPOINT_N" "$_TKX_DASH" "$title"
    fi
}

# --- Step indicators (under a checkpoint) ---
install_step_ok()   { printf '    %s %s\n' "$_TKX_E_OK"   "${1:-}"; }
install_step_warn() { printf '    %s %s\n' "$_TKX_E_WARN" "${1:-}"; }
install_step_fail() { printf '    %s %s\n' "$_TKX_E_FAIL" "${1:-}" >&2; }

# --- Banner bottom: success summary ---
install_banner_bottom() {
    local skill="${1:-unknown}"
    local version="${2:-unknown}"
    printf '\n%s\n' "$_TKX_BAR_LINE"
    printf '  %s  %s %s installed\n' "$_TKX_E_PARTY" "$skill" "$version"
    printf '%s\n\n' "$_TKX_BAR_LINE"
}

# --- CLI table: per-CLI invocation + skill path ---
install_cli_table_begin() {
    printf '  Installed CLI commands:\n\n'
}

install_cli_row() {
    local cli="${1:-CLI}"
    local invocation="${2:-}"
    local path="${3:-}"
    # 12-char left column for CLI name (padded via %-12s), 22-char invocation, then path.
    printf '    [%-12s] %-22s %s\n' "$cli" "$invocation" "$path"
}

install_cli_table_end() {
    printf '\n'
}

# --- Next steps hints ---
install_next_block() {
    [ "$#" -eq 0 ] && return 0
    printf '  Next:\n'
    local hint
    for hint in "$@"; do
        printf '    %s %s\n' "$_TKX_BULLET" "$hint"
    done
    printf '\n'
}

install_next_hint() {
    printf '    %s %s\n' "$_TKX_BULLET" "${1:-}"
}
