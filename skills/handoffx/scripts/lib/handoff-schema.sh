#!/bin/bash
# handoff-schema.sh — THE single source of four-piece artifact path constants.
# Sourced, never executed. ⚠ P2 RENAME LOCUS (coupling b/c, Decision 0020):
# the future handoffx mega-program renames ONLY the values here; every consumer
# (xref-grammar lib + coupling-c scripts) sources this — never re-hardcodes.
# One behavioural helper lives here too (legacy-layout classification, below):
# it is the only code that must reason about the legacy names, every gate that
# needs it (tidy / validate / postflight / install) already sources this file,
# and four private copies had already drifted on what "v1" meant.
[ -n "${_HX_SCHEMA_SOURCED:-}" ] && return 0
_HX_SCHEMA_SOURCED=1
HX_LOGS_DIR="Handoffx_Logs"
HX_DEC_DIR="Handoffx_Decisions"
HX_MAIN_FILE="HANDOFFX.md"
HX_GOTCHAS_FILE="GOTCHAS.md"
# Legacy (pre-v4) names. This file is the ONLY place allowed to hold them:
# migrators must recognise the old layout to move it, and a second copy of
# these literals elsewhere would let a consumer silently read the old layout
# (tests/test_handoff_schema.sh guards scripts/**/*.sh against that).
HX_LEGACY_MAIN_FILE="HANDOFF.md"
HX_LEGACY_LOGS_DIR="Handoff_Logs"
HX_LEGACY_DEC_DIR="Handoff_Decisions"

# hx_present <path> — THE presence predicate for four-piece paths. Why `-L`
# too: a dangling symlink fails `-e`, yet a migrator's final mv would replace
# it and a template would be written beside it; every detector, preflight and
# refusal must agree on what "there" means, so they all call this one.
hx_present() { [ -e "$1" ] || [ -L "$1" ]; }

# _hx_present <root> <name>... — print the names that exist under <root>.
_hx_present() {
    local r="$1" p out=""
    shift
    for p in "$@"; do hx_present "$r/$p" && out="$out $p"; done
    printf '%s' "$out"
}

# hx_legacy_layout_kind <root> — classify by content, not by name alone, so the
# refusal can name the one command that actually upgrades this tree:
#   mixed   any legacy piece AND any new piece (upgrading either side would clobber the other)
#   v3      legacy main carries the v2 marker AND both legacy dirs exist (→ schema-upgrade)
#   v1      by elimination: legacy main without the marker, no legacy dir, no
#           new piece (→ migrate-to-v2). Dated entries are NOT required: an
#           entry-less v1 file was "unknown", migrate-to-v2 refused it and the
#           refusal pointed back at migrate-to-v2 — a loop (fix wave 1 F1).
#   unknown anything else with a legacy piece: a marker-bearing main with
#           incomplete dirs, a marker-less main beside a legacy dir (the v1
#           migrator would leave that dir behind), legacy dirs without a
#           legacy main, an unreadable main
#   none    no legacy piece at all
hx_legacy_layout_kind() {
    local r="$1" lm="$1/$HX_LEGACY_MAIN_FILE"
    if [ -n "$(_hx_present "$r" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR")" ] \
       && [ -n "$(_hx_present "$r" "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR")" ]; then
        echo mixed
    elif [ -z "$(_hx_present "$r" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR")" ]; then
        echo none
    elif [ ! -f "$lm" ]; then
        # Why not "none": install --template refuses any legacy piece; calling
        # stray legacy dirs "none" let tidy/validate run on a tree install rejects.
        echo unknown
    elif grep -qF -- '<!-- HANDOFF v2 schema -->' "$lm" 2>/dev/null; then
        if [ -d "$r/$HX_LEGACY_LOGS_DIR" ] && [ -d "$r/$HX_LEGACY_DEC_DIR" ]; then echo v3; else echo unknown; fi
    elif [ ! -r "$lm" ]; then
        # Unreadable: the marker test above could not run, so "no marker" is
        # not established — do not hand the file to the v1 migrator.
        echo unknown
    elif [ -z "$(_hx_present "$r" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR")" ]; then
        echo v1
    else
        echo unknown
    fi
    return 0
}

# hx_refuse_if_legacy_layout <root> <tool-name> — print the content-aware
# upgrade instruction to stderr and return 2 for any legacy layout; 0 for none.
hx_refuse_if_legacy_layout() {
    local r="$1" tool="$2"
    case "$(hx_legacy_layout_kind "$r")" in
        none) return 0 ;;
        mixed)
            echo "❌ $tool: mixed layout in $r: legacy [$(_hx_present "$r" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR") ] and new [$(_hx_present "$r" "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR") ] pieces coexist — inspect both, keep the authoritative set, remove the other, then re-run" >&2 ;;
        v3)
            echo "❌ $tool: detected legacy four-piece layout in $r ($HX_LEGACY_MAIN_FILE, $HX_LEGACY_LOGS_DIR/, $HX_LEGACY_DEC_DIR/) — run \`/handoffx-tidy schema-upgrade\` first (tidy-handoff.sh schema-upgrade --dry-run|--apply --root $r)" >&2 ;;
        v1)
            echo "❌ $tool: detected legacy v1 single-file $HX_LEGACY_MAIN_FILE in $r — run migrate-to-v2.sh --dry-run --root $r, then migrate-to-v2.sh --apply --root $r (or tidy-handoff.sh --apply $r/$HX_LEGACY_MAIN_FILE)" >&2 ;;
        *)
            if [ ! -f "$r/$HX_LEGACY_MAIN_FILE" ]; then
                echo "❌ $tool: legacy [$(_hx_present "$r" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR") ] in $r without $HX_LEGACY_MAIN_FILE as a regular file — restore the legacy main and run \`/handoffx-tidy schema-upgrade\` (tidy-handoff.sh schema-upgrade --dry-run|--apply --root $r), or remove the stray legacy pieces if they are leftovers" >&2
            elif grep -qF -- '<!-- HANDOFF v2 schema -->' "$r/$HX_LEGACY_MAIN_FILE" 2>/dev/null; then
                # Why prefer schema-upgrade: the v2 marker already rules out v1,
                # so naming migrate-to-v2 here would only send the user astray.
                echo "❌ $tool: legacy $HX_LEGACY_MAIN_FILE in $r carries the v2 marker but $HX_LEGACY_LOGS_DIR/ and $HX_LEGACY_DEC_DIR/ are not both present — restore the missing dir (an empty one is fine), then run \`/handoffx-tidy schema-upgrade\` (tidy-handoff.sh schema-upgrade --dry-run|--apply --root $r)" >&2
            else
                echo "❌ $tool: legacy $HX_LEGACY_MAIN_FILE in $r could not be classified (no v2 marker, yet [$(_hx_present "$r" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR") ] sit beside it, or it is unreadable) — inspect it, then run the matching upgrade: v1 single file (move the stray legacy dir aside first) → migrate-to-v2.sh --dry-run --root $r, then migrate-to-v2.sh --apply --root $r; four-piece layout → \`/handoffx-tidy schema-upgrade\` (tidy-handoff.sh schema-upgrade --dry-run|--apply --root $r)" >&2
            fi ;;
    esac
    return 2
}
