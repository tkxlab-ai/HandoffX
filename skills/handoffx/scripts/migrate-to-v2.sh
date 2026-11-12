#!/bin/bash
# migrate-to-v2.sh — atomic migration of v1 $HX_MAIN_FILE to v2 layout
# Usage: migrate-to-v2.sh --dry-run|--apply [--root <project-dir>]
set -euo pipefail

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme). This script is
# the v1→v2 migrator; the four-piece refs here are the v2 target schema.
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

HANDOFF="$ROOT/$HX_MAIN_FILE"
[ -f "$HANDOFF" ] || { echo "❌ $HANDOFF not found" >&2; exit 1; }

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
echo "   Dev Log: $DEV_LOG_COUNT entries → ${HX_LOGS_DIR}/"
echo "   Decision Log: $DECISION_COUNT entries → ${HX_DEC_DIR}/"
echo "   Gotchas: $GOTCHA_COUNT entries → ${HX_GOTCHAS_FILE}"

if [ "$MODE" = "dry-run" ]; then
    echo "🔍 dry-run only; no files modified"
    exit 0
fi

# Apply mode: atomic migration with .partial staging + EXIT-trap rollback (B7).
# All output goes to *.partial paths first; on success they are renamed to final
# names and MIGRATE_DONE flips to 1. The EXIT trap cleans partials and restores
# $HX_MAIN_FILE from the validated backup if MIGRATE_DONE=0 at exit.

MIGRATE_DONE=0
BACKUP_VALIDATED=0
DEVLOG_TMP=""
DECLOG_TMP=""
TMPRAW=""
TMPRAW_DEC=""
HANDOFF_NEW="$HANDOFF.new"
LOGS_DIR_PARTIAL="$ROOT/${HX_LOGS_DIR}.partial"
DEC_DIR_PARTIAL="$ROOT/${HX_DEC_DIR}.partial"
GOTCHAS_PARTIAL="$ROOT/${HX_GOTCHAS_FILE}.partial"
# Track final destinations as they're successfully renamed so the trap can
# undo them if a *later* mv fails (Codex review #1: previously, a failure
# between mv #2 and mv #4 left earlier finalized dirs in place).
FINALIZED_PATHS=()

cleanup_and_maybe_rollback() {
    rm -f "${DEVLOG_TMP:-}" "${DECLOG_TMP:-}" "${HANDOFF_NEW:-}"
    rm -rf "${TMPRAW:-}" "${TMPRAW_DEC:-}"

    if [ "$MIGRATE_DONE" = "1" ]; then
        return 0
    fi

    local n_finalized="${#FINALIZED_PATHS[@]}"
    if [ -d "$LOGS_DIR_PARTIAL" ] || [ -d "$DEC_DIR_PARTIAL" ] || [ -f "$GOTCHAS_PARTIAL" ] || [ "$n_finalized" -gt 0 ]; then
        echo "❌ Migration failed; rolling back partial output" >&2
    fi
    rm -rf "$LOGS_DIR_PARTIAL" "$DEC_DIR_PARTIAL"
    rm -f "$GOTCHAS_PARTIAL"

    # Reverse-order undo of any destinations that finalized before failure.
    # Each entry was an empty target before the mv, so `rm -rf` returns the
    # tree to that state. set -u + bash 3.2 quirk: don't expand an empty array
    # via `${arr[@]}`; iterate by index.
    local i
    for ((i = n_finalized - 1; i >= 0; i--)); do
        rm -rf "${FINALIZED_PATHS[$i]}" 2>/dev/null || true
    done

    if [ "$BACKUP_VALIDATED" = "1" ] && [ -f "$HANDOFF.pre-v2-backup" ] && [ -f "$HANDOFF" ]; then
        if ! diff -q "$HANDOFF.pre-v2-backup" "$HANDOFF" >/dev/null 2>&1; then
            cp "$HANDOFF.pre-v2-backup" "$HANDOFF" 2>/dev/null || true
            echo "  ↩️  $HX_MAIN_FILE restored from backup" >&2
        fi
    fi
    rm -f "$HANDOFF.pre-v2-backup"
}

# Preflight: abort before any modification if any final destination OR stale
# staging path exists. Two categories:
#   - Final destinations (Codex review #1): typical when re-running --apply on
#     an already-migrated project, or when user has hand-created sibling files.
#   - Stale .partial / .new paths (Codex review #6): from a previous run that
#     was killed before the EXIT trap could clean up (kill -9, machine crash).
#     Without this check, mkdir -p succeeds on the existing dir, new entries
#     mix into stale content, and the final mv promotes the merged tree as
#     real v2 entries. Refuse with explicit guidance instead.
for fp in \
    "$ROOT/$HX_LOGS_DIR"           "$ROOT/$HX_DEC_DIR"           "$ROOT/$HX_GOTCHAS_FILE" \
    "$ROOT/${HX_LOGS_DIR}.partial" "$ROOT/${HX_DEC_DIR}.partial" "$ROOT/${HX_GOTCHAS_FILE}.partial" \
    "$ROOT/${HX_MAIN_FILE}.new"; do
    if [ -e "$fp" ]; then
        echo "❌ Migration target already exists: $fp" >&2
        case "$fp" in
            *.partial|*.new)
                echo "   Stale staging path from a prior interrupted run." >&2
                echo "   Inspect contents, then remove with: rm -rf '$fp'" >&2
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

# Step 1: Backup $HX_MAIN_FILE (rollback source-of-truth)
cp "$HANDOFF" "$HANDOFF.pre-v2-backup"
if diff -q "$HANDOFF" "$HANDOFF.pre-v2-backup" >/dev/null 2>&1; then
    BACKUP_VALIDATED=1
else
    echo "❌ Backup verification failed; aborting before any modification" >&2
    exit 1
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

# Codex review #4 fix: ${HX_MAIN_FILE%.md}.archive.md (v1 yearly-overflow
# archive) contains additional Dev Log entries that the original code
# unconditionally deleted. Append its content to DEVLOG_TMP so its entries flow
# into the per-file split, get sorted by timestamp alongside main entries, and
# assigned NNNN naturally. Archive file format: `# Title` heading + blockquote
# intro + sequence of `### YYYY-MM-DD HH:MM — title` entries; the splitter
# ignores non-entry lines so the heading/blockquote are inert.
#
# Codex 3rd-source [high] fix (Gotcha #25 母题 recursion in archive-name class):
# derive ARCHIVE from $HX_MAIN_FILE so a future P2.2 rename of the main file
# also catches its sibling overflow archive. Hardcoding the v1 archive literal
# here meant the v1 overflow archive was silently skipped under rename — pure
# data loss. Precedent: scripts/archive-devlog.sh:93 uses the same
# `${FILE%.md}.archive.md` derivation.
ARCHIVE="$ROOT/${HX_MAIN_FILE%.md}.archive.md"
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
        date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | head -1 || true)
        time_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9]:[0-9][0-9]' | head -1 || true)
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
    # legacy entries that omit HH:MM (date-only headers).
    first_line=$(head -1 "$raw")
    date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | head -1 || true)
    time_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9]:[0-9][0-9]' | head -1 || true)
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
        date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | head -1 || true)
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
    date_part=$(printf '%s' "$first_line" | grep -oE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' | head -1 || true)

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

# Phase B6: Atomic rewrite of $HX_MAIN_FILE to v2 layout
# Generate stats for pointer blocks from staged partial dirs (renamed at finalization)

LATEST_LOG=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
OLDEST_LOG=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | head -1 | sed 's|.*/||' || true)
LOG_COUNT=$(ls "$LOGS_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)

LATEST_DEC=$(ls "$DEC_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
DEC_COUNT=$(ls "$DEC_DIR_PARTIAL/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)

LATEST_GOTCHA_TITLE=$(grep -E '^### Gotcha #' "$GOTCHAS_PARTIAL" | tail -1 | sed 's/^### //' || true)

MIGRATE_TS=$(date -u +%Y-%m-%dT%H:%MZ)

# Build the new $HX_MAIN_FILE in $HANDOFF_NEW (already declared at apply-mode setup)
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
            print "> 接手 → `/handoffx-recall`（读最近 5 条）；翻多条 → `/handoffx-recall 20`。"
            print "> 直接查询 → `ls -1 " logs_dir "/ | sort -r | head -5`"
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
[ -s "$HANDOFF_NEW" ] || { echo "❌ HANDOFF.new is empty, aborting" >&2; exit 1; }
grep -q '<!-- HANDOFF v2 schema -->' "$HANDOFF_NEW" || { echo "❌ v2 marker missing from HANDOFF.new, aborting" >&2; exit 1; }

# Finalization: atomic renames in dependency order. Each individual mv is atomic
# on the same filesystem; the at-risk window is between renames. Each successful
# mv is recorded in FINALIZED_PATHS so the EXIT trap can roll them back if a
# *later* mv fails. MIGRATE_DONE flips only after the four mvs all succeeded.
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
    if [ -e "$dst" ]; then
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

mv "$HANDOFF_NEW" "$HANDOFF"

MIGRATE_DONE=1

# Delete v1 overflow archive if present (its content was migrated to
# ${HX_LOGS_DIR}/). Derived from $HX_MAIN_FILE per Codex 3rd-source [high] —
# matches the ARCHIVE assignment at the read site above so rename follows.
if [ -f "$ARCHIVE" ]; then
    rm -f "$ARCHIVE"
    echo "   ✅ Deleted ${ARCHIVE##*/} (content migrated to ${HX_LOGS_DIR}/)"
fi

echo "   ✅ $HX_MAIN_FILE rewritten to v2 layout"
echo ""
echo "✅ Migration complete. Backup at: $HANDOFF.pre-v2-backup"
echo "   Restore: cp '$HANDOFF.pre-v2-backup' '$HANDOFF'"
exit 0
