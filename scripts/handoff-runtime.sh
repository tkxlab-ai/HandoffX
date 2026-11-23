#!/bin/bash
# Caller CDPATH must not redirect relative paths or leak cd output into data.
unset CDPATH
# Usage: handoff-runtime.sh [--expect-root ABS_DIR] context [--root DIR --skill-root DIR] | verification OPTIONS | verification-check OPTIONS | recall [RAW] | init [--root DIR] | finalize --log LOG [--files=CSV] | review-due --log LOG | reply --text TEXT
# Standalone runtime, Bash 3.2+. Data on stdout; errors on stderr, exit 2.
# recall [ONE raw argument string]: trim leading ASCII whitespace, then digits; trailing
# notes ("3。说明" / "3 说明"); no leading digits => 6. Leading +/- rejected.
# Positive decimal range: 1..2147483647 (leading zeros accepted).
# init [--root DIR]: explicit, additive template initialization; never overwrite.
# reply --text TEXT: 1..120 Unicode code points, one line, no truncation.
# The 80-code-point host reserve is a convention, NOT control over host/model.
# No snapshot/whole-batch transaction or concurrent-writer safety is promised.
set -euo pipefail
export LC_ALL=C
RUNTIME_SD=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck disable=SC1091
. "$RUNTIME_SD/lib/handoff-v2.sh"
# shellcheck disable=SC1091
. "$RUNTIME_SD/lib/handoff-context.sh"
# shellcheck disable=SC1091
. "$RUNTIME_SD/lib/handoff-verification.sh"
# shellcheck disable=SC1091
. "$RUNTIME_SD/lib/handoff-sync.sh"

hrt_error() { printf 'handoff-runtime: %s\n' "$*" >&2; exit 2; }

# Context is a pure function of (physical cwd, expected root) within one
# process; hx_context_check_memo computes it once per cwd (init --root
# recomputes). Never shared across processes.
HRT_CTX=''
hrt_ctx() { hx_context_check_memo "$RUNTIME_SD" "$HRT_EXPECT_ROOT" || return 2; HRT_CTX=$HX_CTX_MEMO; }
hrt_write_ctx() { hrt_ctx || return 2; hx_context_write_policy "$HRT_CTX" "$HRT_EXPECT_ROOT" || return 2; }

hrt_context() {
    local root='' skill=''
    while [ "$#" -gt 0 ]; do
        [ "$#" -ge 2 ] && [ -n "$2" ] || hrt_error 'context expects --root DIR and/or --skill-root DIR'
        case "$1" in
            --root) [ -z "$root" ] || hrt_error 'duplicate --root'; root=$2 ;;
            --skill-root) [ -z "$skill" ] || hrt_error 'duplicate --skill-root'; skill=$2 ;;
            *) hrt_error "unknown context option: $1" ;;
        esac
        shift 2
    done
    hx_context_check "$RUNTIME_SD" "$root" "$skill" || return 2
}

hrt_verification_check() {
    hrt_ctx || return 2
    if [ "${1:-}" = --current ]; then
        shift
        local require=0 match='' sections recent summary current_records log_records match_dir log_dir entries latest
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --require) [ "$require" = 0 ] || hrt_error 'duplicate --require'; require=1; shift ;;
                --match-file)
                    [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$match" ] || hrt_error '--match-file requires one log path, once'
                    match=$2; shift 2 ;;
                *) hrt_error 'verification-check --current [--require] [--match-file LOG]' ;;
            esac
        done
        hrt_preflight recall || return 2
        # Validate the whole selected current context first, but a declaration
        # elsewhere must NEVER satisfy the recent-only requirement.
        sections=$(hrt_sections) || hrt_error 'invalid current sections'
        printf '%s\n' "$sections" | hx_verification_validate_stream >/dev/null || return 2
        recent=$(hrt_sections recent) || hrt_error 'invalid recent section'
        [ -z "$match" ] || require=1
        summary=$(printf '%s\n' "$recent" | hx_verification_validate_stream "$require") || return 2
        if [ -n "$match" ]; then
            hrt_file "$match"
            match_dir=$(_hx_context_dir "$(dirname "$match")") || hrt_error 'invalid log directory'
            log_dir=$(_hx_context_dir "$HX_LOGS_DIR") || hrt_error 'invalid current log directory'
            [ "$match_dir" = "$log_dir" ] || hrt_error '--match-file must be a direct current-project log, not the main file or an external copy'
            entries=$(hrt_entries "$HX_LOGS_DIR") || return 2
            [ -n "$entries" ] || hrt_error '--match-file requires a numbered log'
            latest=${entries%%$'\n'*}; latest=${latest#*$'\t'}
            [ "${match##*/}" = "${latest##*/}" ] || hrt_error '--match-file must be the latest numbered main log'
            current_records=$(printf '%s\n' "$recent" | hx_verification_validate_stream 1 records) || return 2
            log_records=$(hrt_log_verification_field "$match" | hx_verification_validate_stream 1 records) || return 2
            [ "$current_records" = "$log_records" ] || hrt_error 'recent verification declarations differ from the supplied log; no successful-write confirmation'
            summary="$summary"$'\n''verification_match=declared_fields_equal'
        fi
        printf '%s\n' "$summary"
    else
        hx_verification_check "$@"
    fi
}

hrt_positive() {
    local n="$1"
    while [ "${n#0}" != "$n" ]; do n=${n#0}; done
    [ -n "$n" ] || hrt_error 'count must be positive (not zero)'
    [ "${#n}" -le 10 ] || hrt_error 'integer overflow: maximum 2147483647'
    # Equal-length decimal strings compare lexically without integer overflow.
    # shellcheck disable=SC2071
    if [ "${#n}" -eq 10 ] && [[ "$n" > 2147483647 ]]; then
        hrt_error 'integer overflow: maximum 2147483647'
    fi
    printf '%s' "$n"
}

hrt_root() {
    local physical
    physical=$(_hx_context_dir "$1") || hrt_error 'invalid root directory'
    cd "$physical" || hrt_error "cannot enter: $physical"
}

hrt_file() {
    [ ! -L "$1" ] && [ -f "$1" ] && [ -r "$1" ] || hrt_error "missing, symlink, wrong type or unreadable file: $1"
}

hrt_preflight() {
    local mode="$1" p
    hrt_ctx || return 2
    # Refuse links before the shared detector can follow a legacy main link.
    for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR" \
             "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR"; do
        [ ! -L "$p" ] || hrt_error "symlink: $p"
    done
    hx_refuse_if_legacy_layout . handoff-runtime || exit 2
    for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE"; do
        if hx_present "$p"; then hrt_file "$p"
        elif [ "$mode" = recall ]; then hrt_error "missing file: $p"; fi
    done
    for p in "$HX_LOGS_DIR" "$HX_DEC_DIR"; do
        if hx_present "$p"; then
            [ -d "$p" ] && [ -r "$p" ] && [ -x "$p" ] || hrt_error "wrong type or inaccessible directory: $p"
        elif [ "$mode" = recall ]; then hrt_error "missing directory: $p"; fi
    done
    if [ -f "$HX_MAIN_FILE" ]; then
        verify_v2_layout "$HX_MAIN_FILE" || hrt_error 'not v2 layout'
        # Existing verifier intentionally accepts unknown/empty main files;
        # runtime is stricter, never initialize around an ambiguous main.
        grep -qF -- "$HANDOFF_V2_MARKER" "$HX_MAIN_FILE" || hrt_error 'main has no v2 schema marker'
    fi
}

hrt_entries() {
    local dir="$1" f base prefix n seen='|' rows=''
    [ -d "$dir" ] || return 0
    # Only direct numbered Markdown entries; no recursive traversal or archive.
    for f in "$dir"/[0-9]*.md; do
        hx_present "$f" || continue
        hrt_file "$f"
        base=${f##*/}
        case "$base" in *$'\n'*|*$'\r'*|*$'\t'*) hrt_error "invalid entry name: $f" ;; esac
        prefix=${base%%-*}
        case "$prefix" in ''|*[!0-9]*) hrt_error "invalid numbered entry: $f" ;; esac
        [ "$prefix" != "$base" ] || hrt_error "invalid numbered entry: $f"
        n=$(hrt_positive "$prefix") || return 2
        case "$seen" in *"|$n|"*) hrt_error "number conflict in $dir: $prefix" ;; esac
        seen="$seen$n|"
        rows="$rows$n"$'\t'"$f"$'\n'
    done
    [ -n "$rows" ] || return 0
    printf '%s' "$rows" | sort -rn
}

hrt_sections() {
    # Bound stored/output context, not just the final model answer. Historical
    # done blocks and optional background never enter the default payload.
    awk -v state_limit=12288 -v overview_limit=4096 -v selection="${1:-recall}" "$HX_AWK_FENCE_LINE"'
    function save(which, line) {
        if (which=="continuity" && line ~ /[^[:space:]]/) continuity_content=1
        size[which]+=length(line)+1
        if (size[which]<=state_limit) text[which]=text[which] line "\n"
    }
    function task_state(line) {
        if (line !~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ xX]\]([ \t]|$)/) {
            # Ordinary prose citations and Markdown list links are not tasks.
            if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[^]]+\](\(|\[)/) return ""
            # Only checkbox-like brackets (empty, blank or one symbol such as
            # [-] [~] [/]) are ambiguous; [P0] [security] [2026-11] are labels.
            if (line ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[[ \t]*[^][:alnum:][:space:]]?[ \t]*\]/) return "unknown"
            return ""
        }
        sub(/^[ \t]*([-*+]|[0-9]+[.)])[ \t]+\[/, "", line)
        return substr(line,1,1)==" " ? "open" : "done"
    }
    {
        if (fence_line($0)) {
            if (section=="state") {
                save("legacy",$0)
                if (block=="recent" || block=="pending") save(block,$0)
                else if (block=="") save("extra",$0)
            }
            if (section=="overview") save("overview",$0)
            if (continuity) save("continuity",$0)
            next
        }
    }
    # Direction is mandatory context, never a deferred optional overview.
    # Markers are only valid once, inside Overview, outside fenced examples.
    fence=="" && $0 ~ /^[ \t]*<!-+[ \t]*\/?hx:continuity([ \t>-]|$)/ {
        if ($0!="<!-- hx:continuity -->" && $0!="<!-- /hx:continuity -->") bad=1
        else if ($0=="<!-- hx:continuity -->") {
            if (section!="overview" || continuity) bad=1
            continuity_starts++; continuity=1
        } else {
            if (section!="overview" || !continuity) bad=1
            continuity_ends++; continuity=0
        }
        next
    }
    continuity { save("continuity",$0) }
    fence=="" && (/^# / || /^## /) {
        if (block!="" || continuity) bad=1
        section=""
        if ($0 ~ /(^| )Project Overview[[:space:]]*$/) section="overview"
        if ($0 ~ /(^| )Current State[[:space:]]*$/) section="state"
        if ($0 ~ /(^| )Known Gotchas[[:space:]]*$/) section="gotchas"
        if ($0 ~ /(^| )Decision Log[[:space:]]*$/) section="decisions"
        if ($0 ~ /(^| )Development Log[[:space:]]*$/) section="logs"
        if (section!="") seen[section]++
    }
    fence=="" && section!="state" && task_state($0)!="" && task_state($0)!="done" { if (!external_task) external_task_line=NR; external_task=1 }
    section=="overview" { save("overview",$0) }
    section=="state" {
        save("legacy",$0)
        if (fence=="" && $0 ~ /^[ \t]*<!-+[ \t]*\/?hx:(recent|pending|done)([ \t>-]|$)/ &&
            $0 !~ /^<!-- \/?hx:(recent|pending|done) -->$/) bad=1
        if (fence=="" && $0 ~ /^<!-- \/?hx:(recent|pending|done) -->$/) {
            key=$0; sub(/^<!-- \/?hx:/,"",key); sub(/ -->$/,"",key)
            if ($0 ~ /^<!-- \/hx:/) {
                if (block!=key) bad=1
                closed[key]++; block=""
            } else {
                if (block!="") bad=1
                opened[key]++; block=key
            }
            next
        }
        if (fence=="" && block!="pending" && task_state($0)!="" && task_state($0)!="done") orphan_task=1
        # A checked line can still carry constraints, gates or accepted risks.
        # Keep pending verbatim; only the explicit done block is excluded.
        if (block=="pending") save("pending",$0)
        else if (block=="recent") save("recent",$0)
        else if (block=="" && (fence!="" || $0 !~ /^## /)) save("extra",$0)
    }
    END {
        if (external_task) {
            print "handoff-runtime: unchecked or ambiguous task outside Current State/pending at " FILENAME ":" external_task_line "; reconcile scattered tasks explicitly, do not mark them completed by inference" > "/dev/stderr"
            exit 2
        }
        if (bad || fence!="" || block!="" || seen["overview"]!=1 || seen["state"]!=1 ||
            seen["gotchas"]!=1 || seen["decisions"]!=1 || seen["logs"]!=1) exit 2
        anchors=opened["recent"]+opened["pending"]+opened["done"]
        if (anchors) {
            if (orphan_task) exit 2
            if (opened["recent"]!=1 || opened["pending"]!=1 ||
                closed["recent"]!=1 || closed["pending"]!=1 ||
                opened["done"]>1 || opened["done"]!=closed["done"]) exit 2
            state_bytes=size["recent"]+size["pending"]+size["extra"]
        } else state_bytes=size["legacy"]
        # Pending review counts the real block even past the recall budget
        # (exactly when it is needed), but only after every structure check
        # recall/finalize apply. Legacy (no anchors) has no block.
        review=(selection=="pending_bytes")
        if (review && !anchors) exit 2
        if (!review && state_bytes>state_limit) {
            print "handoff-runtime: Current State is " state_bytes " bytes; limit=" state_limit > "/dev/stderr"; exit 3
        }
        if (continuity_starts || continuity_ends) {
            if (continuity || continuity_starts!=1 || continuity_ends!=1 || !continuity_content) exit 2
            if (review) { print size["pending"]+0; exit }
            if (size["continuity"]>overview_limit) {
                print "handoff-runtime: continuity block is " size["continuity"] " bytes; limit=" overview_limit > "/dev/stderr"; exit 3
            }
            # Structural validity is not proof that goals/constraints exist.
            if (selection!="recent") printf "continuity_status=explicit_unverified\noverview_outside_continuity_bytes=%d\n## Project Overview — Continuity\n%s",size["overview"]-size["continuity"],text["continuity"]
        } else {
            if (review) { print size["pending"]+0; exit }
            if (size["overview"]>overview_limit) {
                print "handoff-runtime: legacy Project Overview is " size["overview"] " bytes; limit=" overview_limit > "/dev/stderr"; exit 3
            }
            if (selection!="recent") printf "continuity_status=legacy_unverified\n%s",text["overview"]
        }
        if (selection=="recent") { printf "%s",text["recent"]; exit }
        if (anchors) {
            printf "\npending_completed_items_omitted=0\n## Current State\n### hx:recent\n%s\n### hx:pending\n%s",text["recent"],text["pending"]
            if (text["extra"] ~ /[^[:space:]]/) printf "\n### Unanchored Current State context\n%s",text["extra"]
        }
        else printf "\nstate_status=legacy_unfiltered\n%s",text["legacy"]
    }' "$HX_MAIN_FILE"
}

hrt_log_excerpt() {
    # Additive summary marker: old logs remain immutable. Never synthesize a
    # summary from a title, and never fall back to full text for a large log.
    awk -v cap=2048 "$HX_AWK_FENCE_LINE"'
    {
        bytes+=length($0)+1
        if (bytes<=cap) full=full $0 "\n"
    }
    NR==1 && $0=="---" { front=1; next }
    front {
        if ($0 ~ /^---[[:space:]]*$/) { front=0; next }
        if ($0 ~ /^title:/ && length($0)<=512) title=$0
        if ($0 ~ /^date:/ && length($0)<=128) date=$0
        next
    }
    $0 ~ /hx:recall/ { raw_marker=1 }
    { fence_line($0) }
    fence=="" && $0 ~ /^[ \t]*<!-+[ \t]*\/?hx:recall([ \t>-]|$)/ &&
        $0!="<!-- hx:recall -->" && $0!="<!-- /hx:recall -->" { bad=1 }
    fence=="" && $0=="<!-- hx:recall -->" { starts++; active=1; next }
    fence=="" && $0=="<!-- /hx:recall -->" {
        ends++; if (!active) bad=1; active=0; next
    }
    active {
        summary_bytes+=length($0)+1
        if (summary_bytes<=cap) summary=summary $0 "\n"
        if ($0 ~ /[^[:space:]]/) content=1
    }
    END {
        if (bad || front) exit 2
        if (fence!="") {
            if (raw_marker) exit 2
            print "log_status=legacy_unclosed_fence_metadata_only (warning: incomplete code fence; details not loaded)"
            if (title!="") print title
            if (date!="") print date
            exit
        }
        if (starts || ends) {
            if (bad || active || starts!=1 || ends!=1 || !content || summary_bytes>cap) exit 2
            print "log_status=summary"
            if (title!="") print title
            if (date!="") print date
            printf "%s",summary
        } else if (bytes<=cap) {
            print "log_status=legacy_short_full"
            printf "%s",full
        } else {
            print "log_status=legacy_metadata_only (details not loaded; no summary)"
            if (title!="") print title
            if (date!="") print date
        }
    }' "$1"
}

# Read one scalar only from frontmatter; duplicate fields are ambiguous.
hrt_metadata() {
    awk -v key="$1" '
        NR==1 { if ($0!="---") exit; next }
        /^---[[:space:]]*$/ { exit }
        index($0,key ":")==1 {
            count++; if (length($0)>1024) { oversized=1; exit }; value=substr($0,length(key)+2)
            sub(/^[[:space:]]*/,"",value); sub(/[[:space:]]*$/, "",value)
        }
        END { if (count>1 || oversized) exit 2; print value }
    ' "$2"
}

hrt_utc() {
    # Do not try GNU date -r: it means file mtime, not seconds since epoch.
    case "$(uname -s)" in
        Darwin|FreeBSD|OpenBSD|NetBSD) date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' ;;
        *) date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' ;;
    esac
}

hrt_recency() {
    local file="$1" recorded epoch stamp clock now current delta
    if [ -z "$file" ]; then printf 'handoff_time_status=no_logs\n'; return; fi
    printf 'last_handoff_log=%s\n' "$file"
    # A log timestamp proves recording, not successful postflight completion.
    printf 'handoff_time_basis=recorded_metadata\n'
    recorded=$(hrt_metadata date "$file") || recorded=''
    [ -z "$recorded" ] || printf 'last_handoff_recorded=%s\n' "$recorded"
    if ! epoch=$(hrt_metadata epoch "$file"); then
        printf 'handoff_time_status=invalid_epoch\n'; return
    fi
    if [ -z "$epoch" ]; then
        if [ -n "$recorded" ]; then printf 'handoff_time_status=date_only\n'
        else printf 'handoff_time_status=unknown\n'; fi
        return
    fi
    case "$epoch" in *[!0-9]*|?????????????*) printf 'handoff_time_status=invalid_epoch\n'; return ;; esac
    epoch=$((10#$epoch))
    stamp=$(hrt_utc "$epoch" 2>/dev/null) || { printf 'handoff_time_status=invalid_epoch\n'; return; }
    printf 'last_handoff_at=%s\n' "$stamp"
    clock=$("$BASH" "$RUNTIME_SD/hx.sh" now --epoch 2>/dev/null) || {
        printf 'handoff_time_status=clock_unavailable\n'; return;
    }
    now=$(printf '%s\n' "$clock" | sed -n 's/^epoch=//p')
    case "$now" in ''|*[!0-9]*|?????????????*) printf 'handoff_time_status=clock_unavailable\n'; return ;; esac
    now=$((10#$now))
    current=$(hrt_utc "$now" 2>/dev/null) || { printf 'handoff_time_status=clock_unavailable\n'; return; }
    printf 'recall_now=%s\n' "$current"
    delta=$((now - epoch))
    if [ "$delta" -lt 0 ]; then printf 'handoff_time_status=future\n'; return; fi
    printf 'handoff_time_status=known\nelapsed_days=%s\nelapsed_hours=%s\nelapsed_minutes=%s\n' \
        "$((delta / 86400))" "$((delta % 86400 / 3600))" "$((delta % 3600 / 60))"
}

# Would a payload of LEN bytes fit? Same arithmetic as the final check below.
hrt_fits_len() {
    local header
    header=$(printf 'payload_bytes=%s\nloaded_logs=%s\n' "$1" "$actual")
    [ $((${#header} + $1 + 2)) -le 24576 ]
}

hrt_deferred() {
    # Computed for EVERY selected log (as its reserved floor), so unreadable
    # title/date metadata (duplicate or >1024 bytes) must not fail a recall
    # that fits; say so instead (GLM review A). Excerpts tolerate it too.
    local title date note=''
    title=$(hrt_metadata title "$1") || { title=''; note=' title/date metadata unreadable;'; }
    date=$(hrt_metadata date "$1") || { date=''; note=' title/date metadata unreadable;'; }
    printf 'log_status=summary_deferred_budget (recall budget reached;%s details not loaded, read this log explicitly)\n' "$note"
    [ -z "$title" ] || printf 'title: %s\n' "$title"
    [ -z "$date" ] || printf 'date: %s\n' "$date"
}

# When the log's own **验证** field carries a declaration, it is the only
# comparison source: a summary copy or a quoted historical declaration elsewhere
# must not count. Logs whose declaration sits outside that field keep the
# original whole-log comparison.
hrt_log_verification_field() {
    # Field headings and declarations inside code fences are examples, never
    # the field itself (2nd review N1).
    awk "$HX_AWK_FENCE_LINE"'
        { all[NR]=$0 }
        fence_line($0) { if (on) field=field $0 "\n"; next }
        fence=="" && /^\*\*(验证|Verification)\*\*/ { on=1; next }
        fence=="" && on && /^\*\*[^*]+\*\*/ { on=0 }
        on { field=field $0 "\n"; if (fence=="" && $0 ~ /^<!-- verification:v1 -->$/) has=1 }
        END { if (has) printf "%s", field; else for (i=1;i<=NR;i++) print all[i] }
    ' "$1"
}

# hrt_cross_machine full|short — the other machines' backups in
# .agent-sessions-sync-hx/machines/ (Boss 2026-11-22: finalize exports this
# machine's, recall reads the others'; nothing is imported into ~/.claude, so
# what is read here only reaches this session). Pure reader. Prints nothing
# when no other machine has a backup. 'full' inlines memory this machine does
# not already have (deduplicated by content, MEMORY.md index never read) within
# 4096 bytes and names the rest; 'short' gives the per-machine lines only.
# Symlinks and unreadable files are skipped, never fatal: a backup synced from
# elsewhere must not be able to break or redirect this machine's recall.
hrt_cross_machine() {
    local mode=$1 base="$HX_SYNC_DIR/machines" me enc local_dir sums='' seen='' cands='' mlines=''
    local d m f sum sess last files shown name label body block out
    [ -d "$base" ] && [ ! -L "$HX_SYNC_DIR" ] && [ ! -L "$base" ] || return 0
    me=$(hx_machine_name) || me=''
    enc=$(bash "$RUNTIME_SD/encode-cc-path.sh" "$(pwd -P)" 2>/dev/null) || enc=''
    local_dir="${HOME_OVERRIDE:-${HOME:-}}/.claude/projects/$enc/memory"
    if [ -n "$enc" ] && [ -d "$local_dir" ]; then
        for f in "$local_dir"/*.md; do
            [ -f "$f" ] && [ -r "$f" ] || continue
            sum=$(cksum < "$f") || continue
            sums="$sums$sum"$'\n'
        done
    fi
    for d in "$base"/*/; do
        d=${d%/}; m=${d##*/}
        [ -d "$d" ] && [ ! -L "$d" ] || continue
        case "$m" in ''|*[!a-z0-9-]*) continue ;; esac
        [ "$m" != "$me" ] || continue
        sess=0; last=unknown
        if [ -f "$d/sessions.md" ] && [ ! -L "$d/sessions.md" ] && [ -r "$d/sessions.md" ]; then
            # Data rows only: the header (客户端) and the |---| separator are not sessions.
            read -r sess last < <(awk -F'|' 'NF >= 7 && $2 ~ /^ *[a-z]/ {
                n++; e = $6; gsub(/ /, "", e); if (e > max) max = e }
                END { printf "%d %s\n", n, (max == "" ? "unknown" : max) }' "$d/sessions.md") || { sess=0; last=unknown; }
        fi
        files=0; shown=0
        if [ ! -L "$d/claude-code" ] && [ ! -L "$d/claude-code/memory" ]; then
            for f in "$d/claude-code/memory"/*.md; do
                [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ] || continue
                [ "${f##*/}" != MEMORY.md ] || continue
                files=$((files + 1))
                sum=$(cksum < "$f") || continue
                case $'\n'"$sums$seen" in *$'\n'"$sum"$'\n'*) continue ;; esac
                seen="$seen$sum"$'\n'; shown=$((shown + 1))
                cands="$cands$m"$'\t'"$f"$'\n'
            done
        fi
        mlines="$mlines"$'\n'"machine=$m last_session_end=$last sessions=$sess memory_files=$files new_or_changed=$shown"
    done
    [ -n "$mlines" ] || return 0
    out="--- cross-machine backups ($HX_SYNC_DIR, read-only) ---"$'\n'"current_machine=${me:-unknown}$mlines"
    if [ "$mode" = short ]; then
        [ -z "$cands" ] || out="$out"$'\n'"memory_bodies=omitted (recall budget; read $base/<machine>/claude-code/memory/ explicitly)"
        printf '%s\n' "$out"; return 0
    fi
    [ "${#out}" -le 4096 ] || return 0
    while IFS=$'\t' read -r m f; do
        [ -n "$m" ] || continue
        name=${f##*/}
        if [ -f "$local_dir/$name" ]; then label="differs from this machine"; else label="not on this machine"; fi
        body=$(cat "$f" 2>/dev/null) || continue
        block=$'\n'"--- $m/claude-code/memory/$name ($label) ---"$'\n'"$body"
        if [ $((${#out} + ${#block})) -le 4096 ]; then out="$out$block"; continue; fi
        block=$'\n'"$m/claude-code/memory/$name (omitted: budget)"
        [ $((${#out} + ${#block})) -gt 4096 ] || out="$out$block"
    done < <(printf '%s' "$cands")
    printf '%s\n' "$out"
}

hrt_recall() {
    [ "$#" -le 1 ] || hrt_error 'recall accepts one raw argument string'
    local raw="${1:-}" digits n=6 entries selected sections recency latest='' actual=0 line f excerpt payload header bytes total context verification
    while [[ "$raw" == [$' \t\r\n\v\f']* ]]; do raw=${raw:1}; done
    case "$raw" in
        +*|-*) hrt_error 'signed counts are not accepted; use 1..2147483647' ;;
        [0-9]*) digits=${raw%%[!0-9]*}; n=$(hrt_positive "$digits") || exit 2 ;;
    esac
    hrt_root .
    hrt_ctx || return 2
    context=$HRT_CTX
    hrt_preflight recall || return 2
    entries=$(hrt_entries "$HX_LOGS_DIR") || exit 2
    hrt_entries "$HX_DEC_DIR" >/dev/null || exit 2
    sections=$(hrt_sections) || hrt_error 'invalid recall sections/anchors/continuity, unchecked tasks outside pending, state exceeds 12288 bytes, or required continuity/legacy overview exceeds 4096 bytes; explicitly organize current context; no goals or tasks were silently omitted'
    verification=$(printf '%s\n' "$sections" | hx_verification_validate_stream) || hrt_error 'invalid current verification provenance'
    selected=''
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        [ "$actual" -lt "$n" ] || break
        f=${line#*$'\t'}
        [ -n "$latest" ] || latest="$f"
        selected="$selected$f"$'\n'
        actual=$((actual + 1))
    done < <(printf '%s\n' "$entries")
    recency=$(hrt_recency "$latest") || hrt_error 'cannot read handoff time'
    payload=$(printf 'requested=%s\nactual=%s\nrecall_mode=compact\nbudget_bytes=24576\n%s\n%s\n%s\n\n%s\n\ndeferred_sources=%s, optional background, decision bodies, log details (read only on explicit need)\n' \
        "$n" "$actual" "$context" "$verification" "$recency" "$sections" "$HX_GOTCHAS_FILE")
    # Direction/state/TODO are already in the payload and still fail closed.
    # Every selected log first reserves its smallest form (explicit deferral
    # or its own shorter excerpt); then newest-first upgrades to the summary
    # while the WHOLE output still fits. A greedy single pass could spend the
    # budget on new summaries and leave no room for older logs' metadata.
    # C locale makes Bash string length a UTF-8 byte count; nothing is sliced.
    local -a log_file log_full log_floor log_pick
    local count=0 j sep cur deferred
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        hrt_file "$f"
        hx_verification_check --file "$f" >/dev/null || hrt_error "invalid verification provenance: $f"
        excerpt=$(hrt_log_excerpt "$f") || hrt_error "invalid or oversized recall summary (maximum 2048 bytes): $f"
        deferred=$(hrt_deferred "$f") || hrt_error "cannot read log metadata: $f"
        log_file[count]=$f; log_full[count]=$excerpt; log_floor[count]=$deferred
        [ "${#excerpt}" -gt "${#deferred}" ] || log_floor[count]=$excerpt
        count=$((count + 1))
    done < <(printf '%s\n' "$selected")
    cur=${#payload}
    for ((j = 0; j < count; j++)); do
        sep=$'\n\n'"--- ${log_file[j]} ---"$'\n'
        cur=$((cur + ${#sep} + ${#log_floor[j]}))
        log_pick[j]=floor
    done
    # Other machines' backups come after the logs and only reserve one line;
    # they get room only after every log summary that fits has its room.
    local xm_full='' xm_short xm_floor='' xm='' xm_cand
    xm_short=$(hrt_cross_machine short) || xm_short=''
    if [ -n "$xm_short" ]; then
        xm_full=$(hrt_cross_machine full) || xm_full=''
        xm_floor="cross_machine=deferred_budget (read $HX_SYNC_DIR/machines/ explicitly)"
        cur=$((cur + 2 + ${#xm_floor}))
    fi
    hrt_fits_len "$cur" || hrt_error 'recall budget exceeded (24576 bytes) even with older logs as metadata; explicitly compact current state; no partial output'
    for ((j = 0; j < count; j++)); do
        if hrt_fits_len $((cur + ${#log_full[j]} - ${#log_floor[j]})); then
            cur=$((cur + ${#log_full[j]} - ${#log_floor[j]})); log_pick[j]=full
        fi
    done
    if [ -n "$xm_floor" ]; then
        xm=$xm_floor
        for xm_cand in "$xm_full" "$xm_short"; do
            [ -n "$xm_cand" ] || continue
            if hrt_fits_len $((cur + ${#xm_cand} - ${#xm_floor})); then xm=$xm_cand; break; fi
        done
    fi
    for ((j = 0; j < count; j++)); do
        if [ "${log_pick[j]}" = full ]; then excerpt=${log_full[j]}; else excerpt=${log_floor[j]}; fi
        payload="$payload"$'\n\n'"--- ${log_file[j]} ---"$'\n'"$excerpt"
    done
    [ -z "$xm" ] || payload="$payload"$'\n\n'"$xm"
    bytes=${#payload}
    header=$(printf 'payload_bytes=%s\nloaded_logs=%s\n' "$bytes" "$actual")
    total=$((${#header} + bytes + 2))
    [ "$total" -le 24576 ] || hrt_error 'recall budget exceeded (24576 bytes); no partial output'
    printf '%s\n%s\n' "$header" "$payload"
}

hrt_init() {
    # Do not repair a host-selected wrong cwd by silently changing to --root.
    hrt_write_ctx || return 2
    local root=. p assets missing=0
    if [ "$#" -ne 0 ]; then
        [ "$#" -eq 2 ] && [ "$1" = --root ] && [ -n "$2" ] || hrt_error 'init [--root DIR]'
        root=$2
    fi
    hrt_root "$root"
    hrt_preflight init
    hrt_entries "$HX_LOGS_DIR" >/dev/null || exit 2
    hrt_entries "$HX_DEC_DIR" >/dev/null || exit 2
    for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR"; do
        if ! hx_present "$p"; then missing=1; fi
    done
    if [ "$missing" -eq 0 ]; then printf 'status=existing\n'; return 0; fi
    assets="$RUNTIME_SD/../assets"
    if [ ! -d "$assets" ]; then assets="$RUNTIME_SD/../skills/handoffx/assets"; fi
    # Preflight every needed template and target BEFORE the first write.
    for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE"; do
        if ! hx_present "$p"; then hrt_file "$assets/${p%.md}.template.md"; fi
    done
    [ -w . ] || hrt_error 'root is not writable'
    for p in "$HX_LOGS_DIR" "$HX_DEC_DIR"; do
        if ! hx_present "$p"; then mkdir "$p" || hrt_error "cannot create directory: $p (partial init possible)"; fi
    done
    for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE"; do
        if ! hx_present "$p"; then
            # noclobber refuses a target appearing since preflight; no /tmp,
            # no user-file replacement, no false claim of batch atomicity.
            (set -C; cat "$assets/${p%.md}.template.md" > "$p") || hrt_error "cannot create $p (partial init possible)"
        fi
    done
    printf 'status=initialized\n'
}

# One auditable finalization call; not a transaction or proof of test execution.
# Validate caller intent and declarations BEFORE regenerating any files. All
# success output is withheld until every stage completes; failures may still
# leave earlier writes in place. No caller-provided shell or success text.
hrt_finalize() {
    local log='' files='' entries latest recent sections current_records log_records result
    local regen_args=("$BASH" "$RUNTIME_SD/hx.sh")
    local postflight_args=("$BASH" "$RUNTIME_SD/handoff-postflight.sh")
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --log)
                [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$log" ] || hrt_error 'finalize requires --log PATH once'
                log=$2; shift 2 ;;
            --files=*)
                [ -z "$files" ] || hrt_error 'duplicate --files'
                files=${1#--files=}
                case "$files" in ''|,*|*,|*,,*) hrt_error 'empty additional write target' ;; esac
                shift ;;
            *) hrt_error 'finalize --log LATEST_LOG [--files=ADDITIONAL_CSV]' ;;
        esac
    done
    [ -n "$log" ] || hrt_error 'finalize requires --log LATEST_LOG'
    hrt_write_ctx || return 2
    hrt_preflight recall || return 2
    entries=$(hrt_entries "$HX_LOGS_DIR") || return 2
    [ -n "$entries" ] || hrt_error 'finalize requires a numbered log'
    hrt_entries "$HX_DEC_DIR" >/dev/null || return 2
    sections=$(hrt_sections) || hrt_error 'invalid current state'
    printf '%s\n' "$sections" | hx_verification_validate_stream >/dev/null || return 2
    latest=${entries%%$'\n'*}; latest=${latest#*$'\t'}
    # Canonical relative path only: also prevents CSV injection / parent alias.
    [ "$log" = "$latest" ] || hrt_error 'finalize --log must name the latest direct log by canonical relative path'
    case "$log$files" in *$'\n'*|*$'\r'*|*$'\t'*) hrt_error 'invalid finalize path' ;; esac
    case "$log" in *,*) hrt_error 'log path cannot contain a CSV separator' ;; esac
    recent=$(hrt_sections recent) || hrt_error 'invalid current state'
    current_records=$(printf '%s\n' "$recent" | hx_verification_validate_stream 0 records) || return 2
    log_records=$(hrt_log_verification_field "$log" | hx_verification_validate_stream 0 records) || return 2
    [ "$current_records" = "$log_records" ] || hrt_error 'recent verification declarations differ from latest log; no successful-write confirmation'
    if [ -n "$HRT_EXPECT_ROOT" ]; then
        regen_args+=(--expect-root "$HRT_EXPECT_ROOT")
        postflight_args+=(--expect-root "$HRT_EXPECT_ROOT")
    fi
    # Recall output does not depend on regenerated pointer/index lines, so the
    # budget/structure preflight runs BEFORE the first finalize write.
    ( hrt_recall '' ) >/dev/null || { printf 'finalize: recall preflight failed; nothing regenerated\n' >&2; return 2; }
    "${regen_args[@]}" regen >&2 || { printf 'finalize: regen failed; earlier writes are not rolled back\n' >&2; return 2; }
    if result=$("${postflight_args[@]}" --brief "--files=$log${files:+,$files}" "$HX_MAIN_FILE"); then
        # Hosts often merge stdout/stderr in their tool cards. Emit exactly one
        # normal confirmation, but never suppress warnings or unfamiliar output.
        case "$result" in
            '✅ 交接检查通过，归档检查完成。') ;;
            *) printf '%s\n' "$result" >&2 ;;
        esac
    else
        printf '%s\nfinalize: postflight failed; earlier writes are not rolled back\n' "$result" >&2; return 2
    fi
    # Cross-machine backup (Boss 2026-11-22): default on, run here so it no
    # longer depends on the agent remembering a separate step. Auxiliary: a
    # failure is one stderr warning; the handoff is already saved and confirmed.
    local sync_args=("$BASH" "$RUNTIME_SD/sync-memory.sh") sync_out
    [ -z "$HRT_EXPECT_ROOT" ] || sync_args+=(--expect-root "$HRT_EXPECT_ROOT")
    if ! sync_out=$("${sync_args[@]}" auto 2>&1); then
        printf '⚠️ 跨电脑备份未更新（交接已保存）：%s\n' \
            "$(printf '%s\n' "$sync_out" | grep -v '^[[:space:]]*$' | tail -n 3 | tr '\n' ' ')" >&2
    fi
    hrt_reply --text '✅ 交接已保存；项目定位、声明一致性、索引、召回预检与写后检查通过。'
}

# Periodic pending review trigger (read-only). The log being finalized is the
# one counted, so a stale or aliased --log could fire the review off-cycle.
# Log numbers are not a count of successful handoffs (accepted limitation).
HRT_REVIEW_EVERY=6
HRT_REVIEW_MIN_BYTES=3072
hrt_review_due() {
    local log='' entries latest number bytes due=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --log)
                [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$log" ] || hrt_error 'review-due requires --log PATH once'
                log=$2; shift 2 ;;
            *) hrt_error 'review-due --log LATEST_LOG' ;;
        esac
    done
    [ -n "$log" ] || hrt_error 'review-due requires --log LATEST_LOG'
    hrt_ctx || return 2
    hrt_preflight recall || return 2
    entries=$(hrt_entries "$HX_LOGS_DIR") || return 2
    [ -n "$entries" ] || hrt_error 'review-due requires a numbered log'
    latest=${entries%%$'\n'*}; number=${latest%%$'\t'*}; latest=${latest#*$'\t'}
    [ "$log" = "$latest" ] || hrt_error 'review-due --log must name the latest direct log by canonical relative path'
    bytes=$(hrt_sections pending_bytes) || hrt_error 'invalid current state or no hx:pending block'
    if [ $((number % HRT_REVIEW_EVERY)) -eq 0 ] && [ "$bytes" -ge "$HRT_REVIEW_MIN_BYTES" ]; then due=1; fi
    printf 'log_number=%s\npending_bytes=%s\npending_review_due=%s\n' "$number" "$bytes" "$due"
}

hrt_reply() {
    [ "$#" -eq 2 ] && [ "$1" = --text ] || hrt_error 'reply --text TEXT'
    local text="$2" count
    [ -n "$text" ] || hrt_error 'reply must not be empty'
    case "$text" in *$'\n'*|*$'\r'*|*$'\v'*|*$'\f'*|*$'\xe2\x80\xa8'*|*$'\xe2\x80\xa9'*|*$'\xc2\x85'*) hrt_error 'reply must be one line' ;; esac
    # Validate/count UTF-8 scalars without depending on an installed locale,
    # Python, or grapheme counting (combining marks count individually).
    count=$(printf '%s' "$text" | od -An -v -tu1 | awk '
    { for (i=1;i<=NF;i++) {
        b=$i
        if (need) {
            if (b<lo || b>hi) exit 2
            need--; lo=128; hi=191
        } else {
            count++; lo=128; hi=191
            if (b<=127) continue
            if (b>=194 && b<=223) need=1
            else if (b>=224 && b<=239) {
                need=2; if (b==224) lo=160; if (b==237) hi=159
            } else if (b>=240 && b<=244) {
                need=3; if (b==240) lo=144; if (b==244) hi=143
            } else exit 2
        }
    }}
    END { if (need) exit 2; print count+0 }') || hrt_error 'reply is not valid UTF-8'
    [ "$count" -le 120 ] || hrt_error "reply exceeds 120 Unicode code points: $count"
    printf '%s' "$text"
}

hx_context_take_expect_root 'handoff-runtime: ' "$@" || exit 2
HRT_EXPECT_ROOT=$HX_TAKEN_ROOT; shift "$HX_TAKEN_SHIFT"
if [ -n "$HRT_EXPECT_ROOT" ]; then hrt_ctx || exit 2; fi
[ "$#" -gt 0 ] || hrt_error 'expected context | verification | verification-check | recall | init | finalize | review-due | reply'
hrt_command=$1; shift
case "$hrt_command" in
    context) hrt_context "$@" ;;
    verification) hrt_ctx || exit 2; hx_verification_render "$@" ;;
    verification-check) hrt_verification_check "$@" ;;
    recall) hrt_recall "$@" ;;
    init) hrt_init "$@" ;;
    finalize) hrt_finalize "$@" ;;
    review-due) hrt_review_due "$@" ;;
    reply) hrt_reply "$@" ;;
    *) hrt_error "unknown command: $hrt_command" ;;
esac
