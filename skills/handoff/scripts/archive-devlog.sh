#!/bin/bash
# archive-devlog.sh — atomically move older Dev Log entries to HANDOFF.archive.md
# usage: archive-devlog.sh [file] [threshold=50]    (file default: ./HANDOFF.md)
# exit:  0 ok (no-op or archived), 2 file not found, 3 malformed, 4 archive write failed, 5 main write failed
#
# Atomicity guarantee (Dijkstra review v0.7):
#   1. Parse & split into KEEP and MOVE buffers (read-only)
#   2. Build new main to MAIN.tmp (no commit)
#   3. Build new archive to ARCHIVE.tmp with dedup against existing archive (no commit)
#   4. mv ARCHIVE.tmp -> ARCHIVE   (atomic commit of archive first)
#   5. mv MAIN.tmp -> FILE         (atomic commit of main last)
# On interrupt between 4 and 5: main still has all entries, archive has +N extras.
# Retry is safe: archive dedup skips already-migrated entries keyed by full entry body.

set -u

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file|dir] [threshold=50]   (file default: ./HANDOFF.md)"
        echo "  v2: project root with v2 marker → yearly archive of Handoff_Logs/<NNNN>-<YYYY>-*.md."
        echo "Exit: 0 ok (no-op or archived) / 2 file not found / 3 malformed / 4-5 write failed"
        exit 0
        ;;
esac

# v2 yearly archive: when arg is a project root with v2 marker, move
# Handoff_Logs/<NNNN>-<YYYY>-*.md files where YYYY < (current_year - 1) into
# Handoff_Logs.archive/<YYYY>/. Idempotent. Threshold is ignored in v2 mode.
archive_v2_yearly() {
    local root="$1"
    local logs="$root/Handoff_Logs"
    [ -d "$logs" ] || return 0

    local current_year cutoff
    current_year=$(date +%Y)
    cutoff=$((current_year - 1))

    local moved=0 f base year archive_year_dir
    for f in "$logs"/[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$f" ] || continue
        base=$(basename "$f")
        year=$(printf '%s' "$base" | sed -nE 's/^[0-9]{4}-([0-9]{4})-.*/\1/p')
        [ -n "$year" ] || continue
        if [ "$year" -lt "$cutoff" ]; then
            archive_year_dir="$root/Handoff_Logs.archive/$year"
            mkdir -p "$archive_year_dir" || return 4
            mv "$f" "$archive_year_dir/" || return 5
            moved=$((moved + 1))
        fi
    done
    if [ "$moved" -gt 0 ]; then
        echo "📦 archived $moved entries older than $cutoff to Handoff_Logs.archive/"
    fi
    return 0
}

ARG="${1:-HANDOFF.md}"
THRESHOLD="${2:-50}"

# v2 directory mode: dispatch yearly archive and exit early.
if [ -d "$ARG" ]; then
    if grep -qF -- '<!-- HANDOFF v2 schema -->' "$ARG/HANDOFF.md" 2>/dev/null; then
        archive_v2_yearly "$ARG"
        exit $?
    fi
    FILE="$ARG/HANDOFF.md"
else
    FILE="$ARG"
fi

if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file|dir] [threshold=50]   (file default: ./HANDOFF.md)" >&2
    exit 2
fi

# Count entries in Dev Log section
count=$(awk '
    /^## 📜 Development Log/ { in_log=1; next }
    /^## / && in_log         { in_log=0 }
    in_log && /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/ { c++ }
    END { print c+0 }
' "$FILE")

if [ "$count" -le "$THRESHOLD" ]; then
    exit 0
fi

ARCHIVE="${FILE%.md}.archive.md"
TMP_KEEP=$(mktemp) || exit 3
TMP_MOVE=$(mktemp) || { rm -f "$TMP_KEEP"; exit 3; }
MAIN_TMP="${FILE}.tmp.$$"
ARCHIVE_TMP="${ARCHIVE}.tmp.$$"

cleanup() { rm -f "$TMP_KEEP" "$TMP_MOVE" "$MAIN_TMP" "$ARCHIVE_TMP"; }
trap cleanup EXIT

# Step 1: split entries into keep (first N) and move (rest)
awk -v threshold="$THRESHOLD" -v keepf="$TMP_KEEP" -v movef="$TMP_MOVE" '
    BEGIN { in_log=0; entry_idx=0; buf="" }
    /^## 📜 Development Log/ { in_log=1; next }
    /^## / && in_log { in_log=0 }

    in_log {
        if (/^### [0-9]{4}-[0-9]{2}-[0-9]{2}/) {
            if (buf != "") {
                entry_idx++
                out = (entry_idx <= threshold) ? keepf : movef
                print buf >> out
            }
            buf = $0
            next
        }
        if (/^<!-- 🚨/) {
            if (buf != "") {
                entry_idx++
                out = (entry_idx <= threshold) ? keepf : movef
                print buf >> out
                buf = ""
            }
            next
        }
        if (buf != "") {
            buf = buf "\n" $0
        }
    }
    END {
        if (buf != "") {
            entry_idx++
            out = (entry_idx <= threshold) ? keepf : movef
            print buf >> out
        }
    }
' "$FILE"

# Step 2: build new main content to MAIN_TMP (no commit yet)
awk -v keepf="$TMP_KEEP" -v archive="$(basename "$ARCHIVE")" -v threshold="$THRESHOLD" '
    /^## 📜 Development Log/ {
        print
        in_log=1
        hdr_done=0
        next
    }
    in_log && !hdr_done && /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        hdr_done=1
        while ((getline line < keepf) > 0) print line
        close(keepf)
        print ""
        print "> 📦 Older entries archived to `" archive "` (first " threshold+0 " kept here)."
        print ""
        print "<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->"
        in_log=0
        skip_until_anchor=1
        next
    }
    in_log && !hdr_done && /^<!-- 🚨/ {
        print
        in_log=0
        hdr_done=1
        next
    }
    skip_until_anchor {
        if (/^<!-- 🚨/) {
            skip_until_anchor=0
            next
        }
        if (/^## /) {
            # Defensive: source anchor missing but next section reached.
            # Exit skip mode and re-emit this header so the section is preserved.
            skip_until_anchor=0
            print
            next
        }
        next
    }
    { print }
' "$FILE" > "$MAIN_TMP"

# Step 3: build new archive content to ARCHIVE_TMP with dedup
# Dedup key = full entry body. Header-only keys can collapse distinct same-minute entries.
if [ -f "$ARCHIVE" ]; then
    # Existing archive: preserve its header (lines before first ###), then emit
    # new MOVE entries + existing entries, skipping exact duplicate entry bodies.
    awk -v movef="$TMP_MOVE" '
        function flush_existing() {
            if (cur_body == "") return
            if (cur_body in seen) {
                cur_body = ""
                return
            }
            seen[cur_body]=1
            print cur_body
            cur_body = ""
        }
        BEGIN {
            # Load all MOVE entries into memory. Preserve order even when headers match.
            cur=""; n_move=0
            while ((getline line < movef) > 0) {
                if (line ~ /^### [0-9]{4}-/) {
                    if (cur != "") move_buf[++n_move]=cur
                    cur=line
                } else if (cur != "") {
                    cur=cur"\n"line
                }
            }
            if (cur != "") move_buf[++n_move]=cur
            close(movef)
            emit_phase=0  # 0=header, 1=body
        }
        # Phase 0: print existing archive header (everything before first ###)
        !emit_phase && /^### [0-9]{4}-/ {
            emit_phase=1
            # Emit MOVE entries first (newest at top, preserving MOVE-file order)
            for (i=1; i<=n_move; i++) {
                print move_buf[i]
                print ""
                seen[move_buf[i]]=1
            }
        }
        !emit_phase { print; next }
        # Phase 1: existing archive body — dedup by full body
        /^### [0-9]{4}-/ {
            flush_existing()
            cur_body=$0
            next
        }
        emit_phase {
            if (cur_body != "") cur_body=cur_body"\n"$0
            next
        }
        END {
            # If archive had no ### at all (header-only), still emit the moves
            if (!emit_phase) {
                for (i=1; i<=n_move; i++) {
                    print move_buf[i]
                    print ""
                }
            } else {
                flush_existing()
            }
        }
    ' "$ARCHIVE" > "$ARCHIVE_TMP"
else
    {
        echo "# $(basename "$FILE" .md) — Development Log Archive"
        echo ""
        echo "> 从主 \`$(basename "$FILE")\` 归档的旧 Dev Log 条目。最新在最上面。主文件只保留最近 $THRESHOLD 条。"
        echo ""
        cat "$TMP_MOVE"
    } > "$ARCHIVE_TMP"
fi

# Sanity: both tmp files must be non-empty
[ -s "$MAIN_TMP" ]    || { echo "archive-devlog: main tmp empty, abort" >&2; exit 4; }
[ -s "$ARCHIVE_TMP" ] || { echo "archive-devlog: archive tmp empty, abort" >&2; exit 4; }

# Step 4 (atomic commit 1): archive first
mv "$ARCHIVE_TMP" "$ARCHIVE" || { echo "archive-devlog: archive commit failed" >&2; exit 4; }

# Step 5 (atomic commit 2): main last
mv "$MAIN_TMP" "$FILE" || { echo "archive-devlog: main commit failed — archive is at $ARCHIVE, main unchanged" >&2; exit 5; }

echo "📦 Archived $((count - THRESHOLD)) entries to $ARCHIVE (main kept $THRESHOLD)"
exit 0
