#!/bin/bash
# Declared verification provenance, not evidence authenticity certification.
# Renderer never reads the clock or runs the supplied command. Bash 3.2+.

# Single awk definition of a Markdown code-fence toggle, prepended to every awk
# program that must ignore fenced examples (runtime sections/log excerpt and
# verification). Uses globals fence/fence_length; returns 1 on a fence line.
# shellcheck disable=SC2016
HX_AWK_FENCE_LINE='
    function fence_line(line, stripped, c, run, suffix) {
        stripped=line; sub(/^[ \t]*/, "", stripped)
        # Conservatively protect indented/list-container code fences too.
        c=substr(stripped,1,1)
        if (c!="`" && c!="~") return 0
        run=stripped
        if (c=="`") sub(/[^`].*$/, "", run); else sub(/[^~].*$/, "", run)
        if (length(run)<3) return 0
        suffix=substr(stripped,length(run)+1)
        if (fence=="") {
            if (c=="`" && index(suffix,"`")) return 0
            fence=c; fence_length=length(run); return 1
        }
        if (c==fence && length(run)>=fence_length && suffix ~ /^[ \t]*$/) {
            fence=""; return 1
        }
        return 0
    }
'

hx_verification_error() { printf 'handoff-verification: %s\n' "$*" >&2; return 2; }

hx_verification_render() {
    local source='' command='' result='' performed_at=unknown time_basis=not_provided time_evidence=not_provided evidence=not_provided
    local key value seen='|' output
    while [ "$#" -gt 0 ]; do
        [ "$#" -ge 2 ] || { hx_verification_error 'every option needs a value'; return 2; }
        key=$1; value=$2; shift 2
        case "$key" in --source|--command|--result|--performed-at|--time-basis|--time-evidence|--evidence) ;; *) hx_verification_error "unknown option: $key"; return 2 ;; esac
        case "$seen" in *"|$key|"*) hx_verification_error "duplicate option: $key"; return 2 ;; esac
        seen="$seen$key|"
        # A field is one non-empty line; never permit an injected stanza/anchor.
        case "$value" in ''|*$'\n'*|*$'\r'*|*$'\t'*) hx_verification_error 'fields must be non-empty single lines without tabs'; return 2 ;; esac
        case "$key" in
            --source) source=$value ;; --command) command=$value ;; --result) result=$value ;;
            --performed-at) performed_at=$value ;; --time-basis) time_basis=$value ;;
            --time-evidence) time_evidence=$value ;; --evidence) evidence=$value ;;
        esac
    done
    [ -n "$source" ] && [ -n "$command" ] && [ -n "$result" ] || { hx_verification_error 'required: --source --command --result'; return 2; }
    output=$(printf '<!-- verification:v1 -->\nsource: %s\ncommand: %s\nresult: %s\nperformed_at: %s\ntime_basis: %s\ntime_evidence: %s\nevidence: %s\n<!-- /verification -->' \
        "$source" "$command" "$result" "$performed_at" "$time_basis" "$time_evidence" "$evidence") || return 2
    # Validate the very representation that will be persisted. No temp file and
    # no partial stdout on failure; a valid shape does not prove a true claim.
    printf '%s\n' "$output" | hx_verification_validate_stream 1 >/dev/null || return 2
    printf '%s\n' "$output"
}

hx_verification_validate_stream() {
    local require="${1:-0}" output_mode="${2:-summary}" summary
    summary=$(LC_ALL=C awk -v require="$require" -v output_mode="$output_mode" "$HX_AWK_FENCE_LINE"'
    function fail(message) { if (!error) error=message; bad=1 }
    function finish( key,n,i,keys) {
        n=split("source command result performed_at time_basis time_evidence evidence",keys," ")
        for (i=1;i<=n;i++) if (!(keys[i] in value)) fail("missing field " keys[i])
        if (value["source"] !~ /^(agent_observed|user_report|runner_report|historical_record|unknown)$/) fail("invalid source")
        if (value["performed_at"]=="unknown") {
            unknown_count++
            if (value["time_basis"]!="not_provided" || value["time_evidence"]!="not_provided") fail("unknown execution time must use not_provided basis/evidence")
        } else {
            if (value["time_basis"] !~ /^(explicit_report|execution_receipt|historical_event)$/) fail("known execution time needs an explicit event-time basis, not the recording clock")
            if (value["time_evidence"]=="not_provided" || value["time_evidence"]=="unknown") fail("known execution time needs a source for that time")
        }
        if (bytes>2048) fail("verification stanza exceeds 2048 UTF-8 bytes")
        # Stable field order: compare only declared facts, never prose, file
        # dates or current clock. Field values stay exact, including unknown.
        records=records "<!-- verification:v1 -->\n"
        for (i=1;i<=n;i++) records=records keys[i] ": " value[keys[i]] "\n"
        records=records "<!-- /verification -->\n"
        for (key in value) delete value[key]
    }
    { sub(/\r$/, "") }
    !active && fence_line($0) { next }
    !active && fence!="" { next }
    $0 ~ /^[ \t]*<!--[ \t]*\/?verification([: >]|$)/ {
        if ($0=="<!-- verification:v1 -->") {
            if (active) fail("nested verification stanza")
            active=1; count++; bytes=length($0)+1
        } else if ($0=="<!-- /verification -->") {
            if (!active) fail("unmatched verification close")
            bytes+=length($0)+1; finish(); active=0
        } else fail("malformed verification marker")
        next
    }
    active {
        bytes+=length($0)+1
        if ($0 ~ /[[:cntrl:]]/ || $0 !~ /^(source|command|result|performed_at|time_basis|time_evidence|evidence): [^\t\r]+$/) { fail("invalid verification field"); next }
        key=$0; sub(/:.*/,"",key)
        if (key in value) fail("duplicate verification field " key)
        val=$0; sub(/^[^:]+: /,"",val)
        if (val !~ /[^[:space:]]/) fail("empty verification field " key)
        value[key]=val
    }
    END {
        if (active) fail("unclosed verification stanza")
        if (require && !count) fail("verification stanza required for this write")
        if (bad) { print "handoff-verification: " error > "/dev/stderr"; exit 2 }
        if (output_mode=="records") { printf "%s",records; exit }
        if (count) {
            print "verification_status=structured_claims_unverified"
            print "verification_count=" count
            print "verification_unknown_event_times=" unknown_count+0
        } else print "verification_status=legacy_unverified"
    }') || return 2
    printf '%s\n' "$summary"
}

hx_verification_check() {
    local file='' require=0
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file)
                [ "$#" -ge 2 ] && [ -n "$2" ] && [ -z "$file" ] || { hx_verification_error '--file requires one path, once'; return 2; }
                file=$2; shift 2 ;;
            --require)
                [ "$require" = 0 ] || { hx_verification_error 'duplicate --require'; return 2; }
                require=1; shift ;;
            *) hx_verification_error "unknown check option: $1"; return 2 ;;
        esac
    done
    [ -n "$file" ] && [ ! -L "$file" ] && [ -f "$file" ] && [ -r "$file" ] || { hx_verification_error '--file must name a readable non-symlink regular file'; return 2; }
    hx_verification_validate_stream "$require" < "$file"
}
