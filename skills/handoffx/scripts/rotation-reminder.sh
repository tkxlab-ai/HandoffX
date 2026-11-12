#!/bin/bash
# rotation-reminder.sh — list credentials expiring soon or already expired
# usage: rotation-reminder.sh [file]   (default: ./$HX_MAIN_FILE)
# exit:
#   0 — no credentials with expiring dates found (clean)
#   1 — found credentials needing rotation (already expired / 7d / 30d)
#   2 — file not found / usage error
#
# Dijkstra review v0.7: consistent exit-code discipline with scan-credentials.sh
# (0 clean, 1 findings) so the handoffx-write pipeline can distinguish
# "ran clean" from "ran with findings" from "script missing".

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "$0")/lib/handoff-schema.sh"

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file|dir]   (default: ./$HX_MAIN_FILE)"
        echo "  v2: pass project root → resolves to <dir>/$HX_MAIN_FILE."
        echo "Exit: 0 clean / 1 rotation needed / 2 file not found"
        exit 0
        ;;
esac

ARG="${1:-$HX_MAIN_FILE}"
if [ -d "$ARG" ]; then
    FILE="$ARG/$HX_MAIN_FILE"
else
    FILE="$ARG"
fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    echo "   Usage: $0 [file|dir]   (default: ./$HX_MAIN_FILE)" >&2
    exit 2
fi
if [ ! -r "$FILE" ]; then
    # awk on an unreadable file yields no findings — that is "could not check",
    # not "nothing due" (Gotcha #24; 2026-10-29 incremental audit)
    echo "❌ cannot read $FILE — rotation status unknown, refusing to report clean" >&2
    exit 2
fi

today_epoch=$(date +%s)
tmpfindings=$(mktemp)
trap 'rm -f "$tmpfindings"' EXIT

parse_date() {
    date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

awk '
    /^## [^A-Za-z]*Credentials & Access/ { in_sec = 1; next }
    /^## / && in_sec                     { in_sec = 0 }
    in_sec && /^\| / && !/^\|[ :-]+\|/ && !/^\| *服务/ { print }
' "$FILE" | while IFS='|' read -r _ service _ expiry _; do
    service=$(echo "$service" | sed 's/^ *//;s/ *$//')
    expiry=$(echo  "$expiry"  | sed 's/^ *//;s/ *$//')
    [ -z "$service" ] && continue
    case "$expiry" in
        ""|"—"|"-"|"N/A"|"n/a") continue ;;
    esac

    exp_epoch=$(parse_date "$expiry")
    [ -z "$exp_epoch" ] && continue

    days=$(( (exp_epoch - today_epoch) / 86400 ))

    if [ "$days" -lt 0 ]; then
        echo "🔴 已过期 $((-days)) 天: $service" >> "$tmpfindings"
    elif [ "$days" -le 7 ]; then
        echo "🟠 ${days} 天内过期: $service" >> "$tmpfindings"
    elif [ "$days" -le 30 ]; then
        echo "🟡 ${days} 天内过期: $service" >> "$tmpfindings"
    fi
done

if [ -s "$tmpfindings" ]; then
    cat "$tmpfindings"
    exit 1
fi
exit 0
