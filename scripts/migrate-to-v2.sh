#!/bin/bash
# migrate-to-v2.sh — atomic migration of a v1 single-file $HX_LEGACY_MAIN_FILE
# straight to the v4 four-piece layout ($HX_MAIN_FILE + $HX_LOGS_DIR/ +
# $HX_DEC_DIR/ + $HX_GOTCHAS_FILE). The name is historical (v1 → v2 schema).
# Usage: migrate-to-v2.sh --dry-run|--apply [--root <project-dir>]
#
# Why one step to v4: a v1 user would otherwise need this script and then
# schema-upgrade; reading the legacy name and writing the new names here makes
# the rename part of the same atomic run.
#
# Retiring the legacy main file is the LAST step before MIGRATE_DONE=1: only
# after all four new pieces are finalized (the new main is registered in
# FINALIZED_PATHS) is $HX_LEGACY_MAIN_FILE removed; its bytes stay in the
# retained ${HX_LEGACY_MAIN_FILE}.pre-v2-backup. Any failure up to and
# including that removal rolls everything back: finalized pieces are removed
# and the legacy main is restored from the backup.
#
# Test-only: HANDOFFX_MIGRATE_FAIL_AT=<new-main|final-mv|retire-legacy> fails
# the apply flow at that point (same contract as install.sh's
# HANDOFFX_INSTALL_FAIL_AT) so the rollback can be proven after preflight.
set -euo pipefail

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme). Input uses the
# HX_LEGACY_* names, output the HX_* names.
. "$(dirname "$0")/lib/handoff-schema.sh"

ROOT="$PWD"
MODE="dry-run"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) MODE="dry-run" ;;
        --apply)   MODE="apply" ;;
        --root)
            [ -n "${2:-}" ] || { echo "❌ --root requires a directory argument" >&2; exit 1; }
            ROOT="$2"; shift ;;
        *) echo "❌ Unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

HANDOFF="$ROOT/$HX_LEGACY_MAIN_FILE"
NEW_MAIN="$ROOT/$HX_MAIN_FILE"
# v1 yearly-overflow archive next to the legacy main (see Step 4 for why it is
# derived from the legacy constant).
ARCHIVE="$ROOT/${HX_LEGACY_MAIN_FILE%.md}.archive.md"
# A1 (fix wave 1): classify the tree before anything else, dry-run included,
# and proceed ONLY for a v1 single file. Why: reading the legacy name and
# writing the new ones removed the old implicit guard (a four-piece tree used
# to collide with its own targets), so a v3 tree "succeeded" — real entries
# left in the legacy dirs, empty new dirs, legacy main deleted: a mixed tree
# every tool refuses. The shared refusal names the command that fits (v3 →
# schema-upgrade, mixed → both sides, unknown → both commands).
case "$(hx_legacy_layout_kind "$ROOT")" in
    v1)   ;;
    none) echo "❌ $HANDOFF not found" >&2; exit 1 ;;
    *)    hx_refuse_if_legacy_layout "$ROOT" migrate-to-v2.sh || exit 1 ;;
esac

# Parse counts (no side effects)
DEV_LOG_COUNT=$(awk '
    /^## 📜 Development Log/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section
' "$HANDOFF" | grep -cE '^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || true)
DECISION_COUNT=$(awk '
    /^## 🧭 Decision Log/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section
' "$HANDOFF" | grep -cE '^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || true)
GOTCHA_COUNT=$(awk '
    /^## 🐛 Known Gotchas/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section
' "$HANDOFF" | grep -cE '^### Gotcha #' || true)

echo "📊 Migration plan for $HANDOFF"
echo "   Main file: $HX_LEGACY_MAIN_FILE → $HX_MAIN_FILE (original kept as ${HX_LEGACY_MAIN_FILE}.pre-v2-backup)"
echo "   Dev Log: $DEV_LOG_COUNT entries → ${HX_LOGS_DIR}/"
echo "   Decision Log: $DECISION_COUNT entries → ${HX_DEC_DIR}/"
echo "   Gotchas: $GOTCHA_COUNT entries → ${HX_GOTCHAS_FILE}"

if [ "$MODE" = "dry-run" ]; then
    # v4.1.1 U7: unfilled template placeholders survive the migration and only
    # surface later as xref-lint failures — name them before anything moves.
    # Template-token shaped = <…> with 1–40 characters inside, not an HTML
    # comment / closing tag, URL, mail address or common inline HTML tag.
    # Inline code spans and fenced blocks are skipped: there <dir> is literal
    # syntax, not a field. Informational only — the exit status is unchanged.
    # LC_ALL=C with the continuation-byte class: characters = bytes minus
    # UTF-8 continuation bytes, the same under mawk, BWK awk and gawk.
    PH=$(LC_ALL=C awk -v c="$(printf '[\200-\277]')" '
        /^```/ { fence = !fence; next }
        fence { next }
        {
            s = $0; gsub(/`[^`]*`/, "", s); toks = ""
            while (match(s, /<[^<>]+>/)) {
                t = substr(s, RSTART, RLENGTH); len = RLENGTH; s = substr(s, RSTART + RLENGTH)
                u = t; nc = gsub(c, "", u)
                if (len - 2 - nc > 40) continue
                if (t ~ /^<[!\/?]/ || t ~ /:\/\// || t ~ /@/) continue
                if (tolower(t) ~ /^<(a|b|i|p|u|s|br|hr|em|img|sub|sup|kbd|code|pre|div|span|small|details|summary|table|thead|tbody|tr|td|th|ul|ol|li)([ \/][^>]*)?>$/) continue
                toks = toks " " t
            }
            if (toks != "") printf "   L%d:%s\n", NR, toks
        }' "$HANDOFF") || PH=""
    if [ -n "$PH" ]; then
        PH_N=$(printf '%s\n' "$PH" | wc -l | tr -d ' ')
        echo "⚠️ 模板占位符未填（迁移后 xref-lint 会报）：${PH_N} 行"
        printf '%s\n' "$PH" | awk 'NR <= 20'
        [ "$PH_N" -le 20 ] || echo "   …只列出前 20 行"
    fi
    echo "🔍 dry-run only; no files modified"
    exit 0
fi

# Apply mode: atomic migration with .partial staging + EXIT-trap rollback (B7).
# All output goes to *.partial / .new paths first; on success they are renamed
# to final names, the legacy main is retired and MIGRATE_DONE flips to 1. The
# EXIT trap cleans staging, removes finalized pieces and restores
# $HX_LEGACY_MAIN_FILE from the validated backup if MIGRATE_DONE=0 at exit.

MIGRATE_DONE=0
BACKUP_VALIDATED=0
ARCHIVE_BACKUP_VALIDATED=0
DEVLOG_TMP=""
DECLOG_TMP=""
TMPRAW=""
TMPRAW_DEC=""
HANDOFF_NEW="$ROOT/${HX_MAIN_FILE}.new"
LOGS_DIR_PARTIAL="$ROOT/${HX_LOGS_DIR}.partial"
DEC_DIR_PARTIAL="$ROOT/${HX_DEC_DIR}.partial"
GOTCHAS_PARTIAL="$ROOT/${HX_GOTCHAS_FILE}.partial"
# Track final destinations as they're successfully renamed so the trap can
# undo them if a *later* mv fails (Codex review #1: previously, a failure
# between mv #2 and mv #4 left earlier finalized dirs in place).
FINALIZED_PATHS=()

# Test-only failure injection (see header). Returning 1 lets set -e abort the
# apply flow exactly as a real failure at that point would.
fail_point() {
    if [ "${HANDOFFX_MIGRATE_FAIL_AT:-}" = "$1" ]; then
        echo "❌ injected failure at $1 (HANDOFFX_MIGRATE_FAIL_AT, test-only)" >&2
        return 1
    fi
    return 0
}

cleanup_and_maybe_rollback() {
    # A5 (fix wave 1): the handler must not inherit `set -e`. It used to start
    # with a bare rm; one failing removal aborted it before the finalized pieces
    # were removed and the legacy main restored — the one moment the user needs
    # it most. Every op below is attempted, each failure is counted, and the
    # script still exits with the status that fired the trap.
    local status=$?
    set +e
    rm -f "${DEVLOG_TMP:-}" "${DECLOG_TMP:-}"
    rm -rf "${TMPRAW:-}" "${TMPRAW_DEC:-}"

    local verb=rollback
    [ "$MIGRATE_DONE" = "1" ] && verb=cleanup
    local n_finalized="${#FINALIZED_PATHS[@]}"
    if [ "$MIGRATE_DONE" != "1" ] && { hx_present "$LOGS_DIR_PARTIAL" || hx_present "$DEC_DIR_PARTIAL" || hx_present "$GOTCHAS_PARTIAL" || hx_present "$HANDOFF_NEW" || [ "$n_finalized" -gt 0 ]; }; then
        echo "❌ Migration failed; rolling back partial output" >&2
    fi

    # Staging paths: preflight proved none pre-existed, so all of them are ours.
    # rm runs unconditionally (a no-op when absent); presence afterwards is the
    # verdict, so a removal that fails is residue, never swallowed.
    local i p residue=0
    for p in "$HANDOFF_NEW" "$LOGS_DIR_PARTIAL" "$DEC_DIR_PARTIAL" "$GOTCHAS_PARTIAL"; do
        rm -rf "$p"
        if hx_present "$p"; then
            echo "  ⚠️  $verb could not remove $p" >&2
            residue=$((residue + 1))
        fi
    done

    if [ "$MIGRATE_DONE" = "1" ]; then
        [ "$residue" = "0" ] || echo "  ⚠️  migration succeeded, but the staging path(s) above remain — remove them by hand" >&2
        exit "$status"
    fi

    # Reverse-order undo of any destinations that finalized before failure,
    # the new main file included. Each entry was an empty target before the
    # mv, so `rm -rf` returns the tree to that state. set -u + bash 3.2 quirk:
    # don't expand an empty array via `${arr[@]}`; iterate by index.
    # A removal that fails is counted: a new main left beside the restored
    # legacy main is a mixed tree, and the backups must then stay (same residue
    # rule as the schema-upgrade lib).
    for ((i = n_finalized - 1; i >= 0; i--)); do
        p="${FINALIZED_PATHS[$i]}"
        rm -rf "$p"
        if hx_present "$p"; then
            echo "  ⚠️  rollback could not remove $p" >&2
            residue=$((residue + 1))
        fi
    done

    local unrestored=0
    restore_from_backup "$HANDOFF" "$BACKUP_VALIDATED" "$residue" || unrestored=$((unrestored + 1))
    restore_from_backup "$ARCHIVE" "$ARCHIVE_BACKUP_VALIDATED" "$residue" || unrestored=$((unrestored + 1))
    if [ "$residue" != "0" ] || [ "$unrestored" != "0" ]; then
        echo "  ⚠️  rollback incomplete ($residue path(s) left, $unrestored original(s) not restored); backups kept — clean up by hand before re-running" >&2
    fi
    exit "$status"
}

# restore_from_backup <orig> <validated> <residue> — put <orig> back from
# <orig>.pre-v2-backup when it is missing (a failure after its retirement) or
# differs. The backup is dropped only once <orig> provably matches it and the
# rollback left no residue — otherwise it is the last copy of the v1 bytes.
# Returns 1 when <orig> could not be restored (the caller reports it).
restore_from_backup() {
    local orig="$1" validated="$2" residue="$3" backup="$1.pre-v2-backup"
    if [ "$validated" = "1" ] && [ -f "$backup" ]; then
        if [ ! -f "$orig" ] || ! cmp -s "$backup" "$orig"; then
            # cp's own error stays visible: EACCES / ENOSPC is what the user must fix.
            cp "$backup" "$orig" && echo "  ↩️  ${orig##*/} restored from backup" >&2
        fi
        if cmp -s "$backup" "$orig"; then
            [ "$residue" = "0" ] && rm -f "$backup"
            return 0
        fi
        echo "  ⚠️  could not restore ${orig##*/}; original kept at $backup" >&2
        return 1
    fi
    # Unvalidated (or never taken): the original was never touched; a partial
    # copy is junk.
    rm -f "$backup"
    return 0
}

# Preflight: abort before any modification if any final destination OR stale
# staging path exists. Two categories:
#   - Final destinations (Codex review #1): typical when re-running --apply on
#     an already-migrated project, or when user has hand-created sibling files.
#     The new main file is one of them: v1 → v4 renames the main file.
#   - Stale .partial / .new paths (Codex review #6): from a previous run that
#     was killed before the EXIT trap could clean up (kill -9, machine crash).
#     Without this check, mkdir -p succeeds on the existing dir, new entries
#     mix into stale content, and the final mv promotes the merged tree as
#     real v2 entries. Refuse with explicit guidance instead.
#   - Backup names: a pre-existing backup would be overwritten by Step 1 and
#     then deleted on rollback — someone's only copy, gone. Refuse instead.
for fp in \
    "$NEW_MAIN" "$HANDOFF.pre-v2-backup" "$ARCHIVE.pre-v2-backup" \
    "$ROOT/$HX_LOGS_DIR"           "$ROOT/$HX_DEC_DIR"           "$ROOT/$HX_GOTCHAS_FILE" \
    "$ROOT/${HX_LOGS_DIR}.partial" "$ROOT/${HX_DEC_DIR}.partial" "$ROOT/${HX_GOTCHAS_FILE}.partial" \
    "$HANDOFF_NEW"; do
    # -L too: a dangling symlink fails -e yet the final mv would replace it.
    if hx_present "$fp"; then
        echo "❌ Migration target already exists: $fp" >&2
        case "$fp" in
            *.partial|*.new)
                echo "   Stale staging path from a prior interrupted run." >&2
                echo "   Inspect contents, then remove with: rm -rf $(printf '%q' "$fp")" >&2
                ;;
            "$ROOT/$HX_GOTCHAS_FILE")
                # It may be the project's real gotchas log — never tell the user
                # to delete it; route instead (A1, fix wave 1).
                echo "   It may hold real gotchas. If this project already uses the four-piece layout, run \`/handoffx-tidy schema-upgrade\` (tidy-handoff.sh schema-upgrade --dry-run|--apply --root $ROOT) instead of this script." >&2
                echo "   Otherwise merge its entries into the Known Gotchas section of $HX_LEGACY_MAIN_FILE, move it aside (keep a copy), then re-run migrate-to-v2.sh --apply." >&2
                ;;
            *)
                echo "   Remove or rename it before running migrate-to-v2.sh --apply." >&2
                ;;
        esac
        exit 1
    fi
done

# Install trap *after* preflight so a preflight-only abort doesn't fire the
# rollback (which would rm -rf user-visible stale .partial dirs the user is
# being asked to preserve and inspect).
trap cleanup_and_maybe_rollback EXIT

# Step 1: Back up the legacy main — and its overflow archive, which is deleted
# on success — as the rollback source of truth. Both backups are retained on
# success so the printed Restore line can rebuild the exact v1 tree.
cp "$HANDOFF" "$HANDOFF.pre-v2-backup"
if cmp -s "$HANDOFF" "$HANDOFF.pre-v2-backup"; then
    BACKUP_VALIDATED=1
else
    echo "❌ Backup verification failed; aborting before any modification" >&2
    exit 1
fi
if [ -f "$ARCHIVE" ]; then
    cp "$ARCHIVE" "$ARCHIVE.pre-v2-backup"
    if cmp -s "$ARCHIVE" "$ARCHIVE.pre-v2-backup"; then
        ARCHIVE_BACKUP_VALIDATED=1
    else
        echo "❌ Archive backup verification failed; aborting before any modification" >&2
        exit 1
    fi
fi

# Step 2: Source lib for slugify
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/handoff-v2.sh
source "$SCRIPT_DIR/lib/handoff-v2.sh"

# Step 3: Create staging directory (renamed to final name on success)
mkdir -p "$LOGS_DIR_PARTIAL"

# Step 4: Extract Dev Log section to temp file
DEVLOG_TMP=$(mktemp)
awk '
    /^## 📜 Development Log/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section { print }
' "$HANDOFF" > "$DEVLOG_TMP"

# Codex review #4 fix: ${HX_LEGACY_MAIN_FILE%.md}.archive.md (v1 yearly-overflow
# archive) contains additional Dev Log entries that the original code
# unconditionally deleted. Append its content to DEVLOG_TMP so its entries flow
# into the per-file split, get sorted by timestamp alongside main entries, and
# assigned NNNN naturally. Archive file format: `# Title` heading + blockquote
# intro + sequence of `### YYYY-MM-DD HH:MM — title` entries; the splitter
# ignores non-entry lines so the heading/blockquote are inert.
#
# Codex 3rd-source [high] fix (Gotcha #25 母题 recursion in archive-name class):
# derive ARCHIVE from the main-file constant rather than a literal. It is the
# LEGACY constant because a v1 overflow archive sits next to the v1 main file;
# deriving it from the new name would silently skip it — pure data loss.
# Precedent: scripts/archive-devlog.sh uses the same `${FILE%.md}.archive.md`
# derivation. (ARCHIVE is assigned next to HANDOFF at the top.)
if [ -f "$ARCHIVE" ]; then
    cat "$ARCHIVE" >> "$DEVLOG_TMP"
fi

# Step 5: Split into per-entry temp files in a temp subdirectory
# Each entry starts with ### YYYY-MM-DD HH:MM — title
# Content continues until next ### or --- separator or EOF
TMPRAW=$(mktemp -d)
awk -v outdir="$TMPRAW" '
    /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        # Save previous entry if we have one
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
        }
        # Start new entry
        header = $0
        entry_n++
        body_n = 0
        delete body
        next
    }
    /^---$/ {
        # Horizontal rule = entry separator; commit current entry and reset
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
            header = ""
            body_n = 0
            delete body
        }
        next
    }
    header != "" {
        body_n++
        body[body_n] = $0
    }
    END {
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
        }
    }
' "$DEVLOG_TMP"
rm -f "$DEVLOG_TMP"

# Step 6: Sort raw entries by timestamp ascending; assign 0001..NNNN; write final files
# Build a sortable list: "<timestamp-digits>|<raw-file-path>"
sortlist=$(
    for raw in "$TMPRAW"/raw-*.md; do
        [ -f "$raw" ] || continue
        first_line=$(head -1 "$raw")
        date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sed -n 1p || true)
        time_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9]:[0-9][0-9]' | sed -n 1p || true)
        [ -z "$time_part" ] && time_part="00:00"
        # Strip colons and dashes for numeric sort key: 20260430T1000
        sort_key="${date_part}${time_part//:}"
        sort_key="${sort_key//-}"
        printf '%s|%s\n' "$sort_key" "$raw"
    done | sort
)

n=0
while IFS='|' read -r _key raw; do
    [ -f "$raw" ] || continue
    n=$((n + 1))
    nnnn=$(printf '%04d' "$n")

    # Parse first line: "### YYYY-MM-DD [HH:MM] — title"
    # `|| true` swallows grep's no-match exit so pipefail doesn't abort on
    # legacy entries that omit HH:MM (date-only headers). `sed -n 1p` instead
    # of `head -1` here and in the other pipelines of this script: a reader
    # that keeps reading can never SIGPIPE its writer into a pipefail 141.
    first_line=$(head -1 "$raw")
    date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sed -n 1p || true)
    time_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9]:[0-9][0-9]' | sed -n 1p || true)
    [ -z "$time_part" ] && time_part="00:00"

    # Compact timestamp for filename: 2026-04-30T1000
    time_compact="${time_part//:}"
    timestamp="${date_part}T${time_compact}"

    # Extract title: strip "### YYYY-MM-DD [HH:MM] —/–/- " prefix; HH:MM optional.
    title=$(printf '%s' "$first_line" | sed -E 's/^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]([[:space:]]+[0-9][0-9]:[0-9][0-9])?[[:space:]]*[—–-]+[[:space:]]*//')

    slug=$(slugify "$title")
    out="$LOGS_DIR_PARTIAL/${nnnn}-${timestamp}-${slug}.md"

    {
        printf -- '---\n'
        printf -- 'schema: 2\n'
        printf -- 'type: dev-log\n'
        printf -- 'date: %sT%s\n' "$date_part" "$time_part"
        printf -- 'number: %s\n' "$nnnn"
        printf -- 'title: %s\n' "$title"
        printf -- '---\n'
        printf -- '\n'
        cat "$raw"
    } > "$out"
done <<< "$sortlist"

rm -rf "$TMPRAW"

echo "   ✅ Dev Log: staged $n files in ${HX_LOGS_DIR}.partial/"

# Apply mode: migrate Decision Log entries to per-file in ${HX_DEC_DIR}.partial/

# Step D1: Create staging directory
mkdir -p "$DEC_DIR_PARTIAL"

# Step D2: Extract Decision Log section to temp file
DECLOG_TMP=$(mktemp)

awk '
    /^## 🧭 Decision Log/ { in_section=1; next }
    /^## / && in_section { in_section=0 }
    in_section { print }
' "$HANDOFF" > "$DECLOG_TMP"

# Step D3: Split into per-entry temp files
# Each entry starts with ### YYYY-MM-DD — title (date only, no time)
TMPRAW_DEC=$(mktemp -d)
awk -v outdir="$TMPRAW_DEC" '
    /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
        # Save previous entry if we have one
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
        }
        # Start new entry
        header = $0
        entry_n++
        body_n = 0
        delete body
        next
    }
    /^---$/ {
        # Horizontal rule = entry separator; commit current entry and reset
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
            header = ""
            body_n = 0
            delete body
        }
        next
    }
    header != "" {
        body_n++
        body[body_n] = $0
    }
    END {
        if (header != "") {
            fname = outdir "/raw-" entry_n ".md"
            print header > fname
            for (i = 1; i <= body_n; i++) printf "%s\n", body[i] > fname
            close(fname)
        }
    }
' "$DECLOG_TMP"
rm -f "$DECLOG_TMP"

# Step D4: Sort raw entries by date ascending; assign 0001..NNNN; write final files
sortlist_dec=$(
    for raw in "$TMPRAW_DEC"/raw-*.md; do
        [ -f "$raw" ] || continue
        first_line=$(head -1 "$raw")
        date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sed -n 1p || true)
        # Sort key: numeric date digits only (no time component)
        sort_key="${date_part//-}"
        printf '%s|%s\n' "$sort_key" "$raw"
    done | sort
)

nd=0
while IFS='|' read -r _key raw; do
    [ -f "$raw" ] || continue
    nd=$((nd + 1))
    nnnn=$(printf '%04d' "$nd")

    # Parse first line: "### YYYY-MM-DD — title"
    first_line=$(head -1 "$raw")
    date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | sed -n 1p || true)

    # Extract title: everything after the em-dash (—)
    title=$(printf '%s' "$first_line" | sed -E 's/^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*[—–-]+[[:space:]]*//')

    slug=$(slugify "$title")
    out="$DEC_DIR_PARTIAL/${nnnn}-${date_part}-${slug}.md"

    {
        printf -- '---\n'
        printf -- 'schema: 2\n'
        printf -- 'type: decision\n'
        printf -- 'date: %s\n' "$date_part"
        printf -- 'number: %s\n' "$nnnn"
        printf -- 'title: %s\n' "$title"
        printf -- '---\n'
        printf -- '\n'
        cat "$raw"
    } > "$out"
done <<< "$sortlist_dec"

rm -rf "$TMPRAW_DEC"

echo "   ✅ Decision Log: staged $nd files in ${HX_DEC_DIR}.partial/"

# Phase 2c: Gotchas → ${HX_GOTCHAS_FILE}.partial (single file, no per-Gotcha split)
GOTCHAS_BODY=$(awk '
    /^## 🐛 Known Gotchas/ { in_section=1; next }
    /^## / && in_section { exit }
    in_section
' "$HANDOFF")

cat > "$GOTCHAS_PARTIAL" <<EOF
# Known Gotchas

> All gotchas accumulated during the project lifetime. Each entry: 症状 / 根因 / 方案 / 教训 / 关联.
> Read by /handoffx-recall by default. Add new entries to the bottom; keep \`### Gotcha #N\` header pattern.

$GOTCHAS_BODY
EOF

echo "   ✅ Gotchas: staged in ${HX_GOTCHAS_FILE}.partial"

# Phase B6: build the new $HX_MAIN_FILE (v2 pointer layout) from the legacy main
# Generate stats for pointer blocks from staged partial dirs (renamed at finalization)

LATEST_LOG=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
OLDEST_LOG=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | sed -n 1p | sed 's|.*/||' || true)
LOG_COUNT=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)

LATEST_DEC=$(ls "$DEC_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
DEC_COUNT=$(ls "$DEC_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)

LATEST_GOTCHA_TITLE=$(grep -E '^### Gotcha #' "$GOTCHAS_PARTIAL" | tail -1 | sed 's/^### //' || true)

MIGRATE_TS=$(date -u +%Y-%m-%dT%H:%MZ)

# Build the new main file in $HANDOFF_NEW (already declared at apply-mode setup)
awk \
    -v latest_log="$LATEST_LOG" \
    -v oldest_log="$OLDEST_LOG" \
    -v log_count="$LOG_COUNT" \
    -v latest_dec="$LATEST_DEC" \
    -v dec_count="$DEC_COUNT" \
    -v gotcha_count="$GOTCHA_COUNT" \
    -v latest_gotcha_title="$LATEST_GOTCHA_TITLE" \
    -v migrate_ts="$MIGRATE_TS" \
    -v logs_dir="$HX_LOGS_DIR" \
    -v dec_dir="$HX_DEC_DIR" \
    -v gotchas_file="$HX_GOTCHAS_FILE" \
    '
    BEGIN {
        # Prepend v2 marker before any content
        print "<!-- HANDOFF v2 schema -->"
        print "<!-- Migrated: " migrate_ts " -->"
        print ""
        skip_section = 0
    }

    # Detect section headers
    /^## / {
        # Close any active skip section
        skip_section = 0

        # Dev Log section: replace content with pointer block
        if ($0 ~ /^## 📜 Development Log/) {
            print $0
            print ""
            print "> 所有 Dev Log 条目储存在 `" logs_dir "/`，每条一文件，按 `<NNNN>-<timestamp>-<slug>.md` 命名。"
            print "> 接手 → `/handoffx-recall`（读最近 6 条）；翻多条 → `/handoffx-recall 20`。"
            print "> 直接查询 → `ls -1 " logs_dir "/ | sort -r | head -6`"
            print ""
            print "最近一条：" (latest_log != "" ? latest_log : "(none)")
            print "最早一条：" (oldest_log != "" ? oldest_log : "(none)")
            print "共 " log_count " 条"
            print ""
            skip_section = 1
            next
        }

        # Gotchas section: replace content with pointer block
        if ($0 ~ /^## 🐛 Known Gotchas/) {
            print $0
            print ""
            print "> 全部 Known Gotchas 储存在 `" gotchas_file "`，按踩坑序号 `Gotcha #N` 累积保留。"
            print "> recall 默认会读 `" gotchas_file "`。直接查询 → `cat " gotchas_file "` 或"
            print "> `grep -n '\''^### Gotcha'\'' " gotchas_file "` 看全部标题列表"
            print ""
            print "共 " gotcha_count " 条；最新：" (latest_gotcha_title != "" ? latest_gotcha_title : "(none)")
            print ""
            skip_section = 1
            next
        }

        # Decision Log section: replace content with pointer block
        if ($0 ~ /^## 🧭 Decision Log/) {
            print $0
            print ""
            print "> 全部 Decision 储存在 `" dec_dir "/`，每个权衡一文件。recall 默认不读，"
            print "> 按需 → `ls " dec_dir "/` 看标题，`cat " dec_dir "/<NNNN>-*.md` 读 body。"
            print "> 全读（约 10 文件 ~10K，安全区） → `cat " dec_dir "/*.md`"
            print ""
            print "共 " dec_count " 条；最新：`" (latest_dec != "" ? latest_dec : "(none)") "`"
            print ""
            skip_section = 1
            next
        }

        # Any other ## header: pass through normally
        skip_section = 0
        print $0
        next
    }

    # Skip lines inside replaced sections
    skip_section { next }

    # All other lines pass through verbatim
    { print }
    ' "$HANDOFF" > "$HANDOFF_NEW"

# Verify the .new file is non-empty and contains v2 marker.
# These exit-1 paths leave $HANDOFF_NEW in place; the EXIT trap will rm it.
[ -s "$HANDOFF_NEW" ] || { echo "❌ ${HANDOFF_NEW##*/} is empty, aborting" >&2; exit 1; }
grep -q '<!-- HANDOFF v2 schema -->' "$HANDOFF_NEW" || { echo "❌ v2 marker missing from ${HANDOFF_NEW##*/}, aborting" >&2; exit 1; }
fail_point new-main

# Finalization: atomic renames in dependency order. Each individual mv is atomic
# on the same filesystem; the at-risk window is between renames. Each successful
# mv is recorded in FINALIZED_PATHS so the EXIT trap can roll them back if a
# *later* mv fails — the new main file included, so a failure while retiring
# the legacy main still takes it back out. MIGRATE_DONE flips only after the
# four mvs and the legacy-main removal all succeeded.
#
# Each mv is preceded by a re-check of its destination (Codex review #8: the
# preflight at the top of apply mode runs before backup/staging, so a TOCTOU
# race window exists between preflight and finalization where a concurrent
# process could create one of our targets. Without a re-check, `mv srcdir
# existing-dst-dir` would move srcdir *into* existing-dst-dir — corrupting the
# user's concurrent data and burying our partial. The re-check shrinks the
# window to a single syscall and fails fast on collision.) Full racefree
# coverage requires a flock/mkdir-spinlock around the whole apply phase; that
# is tracked as v2.1.0 backlog.

assert_dest_clear() {
    local dst="$1"
    if hx_present "$dst"; then
        echo "❌ Race: '$dst' appeared between preflight and finalization" >&2
        echo "   Aborting; rollback will clean partials." >&2
        exit 1
    fi
}

assert_dest_clear "$ROOT/$HX_LOGS_DIR"
mv "$LOGS_DIR_PARTIAL" "$ROOT/$HX_LOGS_DIR"
FINALIZED_PATHS+=("$ROOT/$HX_LOGS_DIR")

assert_dest_clear "$ROOT/$HX_DEC_DIR"
mv "$DEC_DIR_PARTIAL" "$ROOT/$HX_DEC_DIR"
FINALIZED_PATHS+=("$ROOT/$HX_DEC_DIR")

assert_dest_clear "$ROOT/$HX_GOTCHAS_FILE"
mv "$GOTCHAS_PARTIAL" "$ROOT/$HX_GOTCHAS_FILE"
FINALIZED_PATHS+=("$ROOT/$HX_GOTCHAS_FILE")

fail_point final-mv

assert_dest_clear "$NEW_MAIN"
mv "$HANDOFF_NEW" "$NEW_MAIN"
FINALIZED_PATHS+=("$NEW_MAIN")

# Retire the legacy main (and its overflow archive, whose entries now live in
# ${HX_LOGS_DIR}/) last: a v1 main left beside the new one would read as a
# legacy layout to every guard (and MIXED to schema-upgrade). Their bytes live
# in the retained backups; a failure up to MIGRATE_DONE=1 — including the
# retire-legacy point, which fires with the legacy main already gone — still
# rolls everything back and restores both from the backups.
rm -f "$HANDOFF"
ARCHIVE_NOTE=""
if [ -f "$ARCHIVE" ]; then
    rm -f "$ARCHIVE"
    ARCHIVE_NOTE=" && mv $(printf '%q' "$ARCHIVE.pre-v2-backup") $(printf '%q' "$ARCHIVE")"
fi
fail_point retire-legacy

MIGRATE_DONE=1

[ -n "$ARCHIVE_NOTE" ] && echo "   ✅ Deleted ${ARCHIVE##*/} (content migrated to ${HX_LOGS_DIR}/; backup kept)"
echo "   ✅ $HX_LEGACY_MAIN_FILE → $HX_MAIN_FILE (v2 pointer layout)"
echo ""
echo "✅ Migration complete. Backup at: $HANDOFF.pre-v2-backup"
# The Restore line is a single command that rebuilds the exact pre-migration
# tree (backups moved back, every new piece removed); tests execute it as-is.
# Every operand goes through %q (A6, fix wave 1): single quotes broke on a root
# whose path holds an apostrophe.
echo "   Restore: mv $(printf '%q' "$HANDOFF.pre-v2-backup") $(printf '%q' "$HANDOFF")${ARCHIVE_NOTE} && rm -rf $(printf '%q' "$NEW_MAIN") $(printf '%q' "$ROOT/$HX_LOGS_DIR") $(printf '%q' "$ROOT/$HX_DEC_DIR") $(printf '%q' "$ROOT/$HX_GOTCHAS_FILE")"
exit 0
