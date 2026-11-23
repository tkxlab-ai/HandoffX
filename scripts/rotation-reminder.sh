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

# 默认保持旧契约：0 clean / 1 任一轮换提醒 / 2 无法检查。
# 编排器显式 opt-in 分类：0 pass / 1 expired (阻断) / 2 error / 3 warn。
CLASSIFY=0
ARG=""
for arg in "$@"; do
    case "$arg" in
        --classify) CLASSIFY=1 ;;
        -h|--help)
            echo "Usage: $0 [--classify] [file|dir]   (default: ./$HX_MAIN_FILE)"
            echo "Exit: 0 clean / 1 rotation needed / 2 cannot check"
            echo "--classify: 0 pass / 1 expired / 2 error / 3 warning (due within 30 days)"
            echo "日期仅接受 YYYY-MM-DD；以本地日历日比较，到期当天为 warning。"
            exit 0 ;;
        -*) echo "❌ unknown flag: $arg" >&2; exit 2 ;;
        *)
            if [ -n "$ARG" ]; then echo "❌ expected one file or directory" >&2; exit 2; fi
            ARG="$arg" ;;
    esac
done
ARG="${ARG:-$HX_MAIN_FILE}"
if [ -d "$ARG" ]; then FILE="$ARG/$HX_MAIN_FILE"; else FILE="$ARG"; fi
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    exit 2
fi
if [ ! -r "$FILE" ]; then
    echo "❌ cannot read $FILE — rotation status unknown, refusing to report clean" >&2
    exit 2
fi

# 单次解析：不再每行调用 sed / BSD date / GNU date。严格校验公历日期，
# 不依赖 date 的宽松归一化；用日序比较，避免 DST 和不足 24 小时取整漏报。
TODAY=$(date +%Y-%m-%d) || { echo "❌ cannot determine today's date" >&2; exit 2; }
rc=0
awk -v today="$TODAY" -v classify="$CLASSIFY" '
    function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
    function ordinal(s, a,y,m,d,n,i,md) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
        split(s,a,"-"); y=a[1]+0; m=a[2]+0; d=a[3]+0
        if (y<1 || m<1 || m>12 || d<1) return -1
        split("31 28 31 30 31 30 31 31 30 31 30 31",md," ")
        if (y%4==0 && (y%100!=0 || y%400==0)) md[2]=29
        if (d>md[m]) return -1
        n=365*(y-1)+int((y-1)/4)-int((y-1)/100)+int((y-1)/400)+d
        for (i=1;i<m;i++) n+=md[i]
        return n
    }
    BEGIN {
        now=ordinal(today)
        if (now<0) { print "❌ invalid current date — cannot check rotation"; error=1; exit }
    }
    /^## [^A-Za-z]*Credentials & Access/ { in_sec=1; in_tbl=0; next }
    /^## / && in_sec { in_sec=0 }
    in_sec && !/^[ \t]*\|/ { in_tbl=0 }
    # The expiry column is found by its header, per table: a table without one
    # (e.g. 服务 | 位置 | 状态) has no dates to check. A fixed 3rd column read
    # free text as a date and failed every finalize (MMReviewX, 2026-11-23).
    in_sec && /^[ \t]*\|/ && !in_tbl {
        in_tbl=1; ecol=0; nh=split($0,h,"|")
        for (i=2; i<nh; i++) if (tolower(trim(h[i])) ~ /过期|到期|expir|rotat|轮换/) { ecol=i; break }
        next
    }
    in_sec && /^[ \t]*\|/ {
        if (!ecol) next
        split($0,c,"|"); service=trim(c[2]); expiry=trim(c[ecol])
        if (service=="" || service ~ /^[-:]+$/ || service=="服务" ||
            tolower(service)=="service") next
        if (expiry=="" || expiry=="—" || expiry=="-" || tolower(expiry)=="n/a") next
        # 仓库模板的唯一示例行，不把真实服务的坏日期当占位符。
        if (service=="<service>" && expiry=="YYYY-MM-DD / —") next
        due=ordinal(expiry)
        if (due<0) {
            printf "❌ 日期无法解析 (line %d): %s；仅接受有效 YYYY-MM-DD\n", NR, service
            error=1; next
        }
        days=due-now
        if (days<0) { printf "🔴 已过期 %d 天: %s\n", -days, service; expired=1 }
        else if (days<=7) { printf "🟠 %d 天内过期: %s\n", days, service; warn=1 }
        else if (days<=30) { printf "🟡 %d 天内过期: %s\n", days, service; warn=1 }
    }
    END { exit (error ? 2 : expired ? 1 : warn ? (classify ? 3 : 1) : 0) }
' "$FILE" || rc=$?
case "$rc" in
    0|1|2|3) exit "$rc" ;;
    *) echo "❌ rotation parser failed — cannot check" >&2; exit 2 ;;
esac
