#!/bin/bash
# scan-credentials.sh — detect plaintext credentials.
#
# Usage:
#   scan-credentials.sh                  # default: ./$HX_MAIN_FILE (or stdin if piped)
#   scan-credentials.sh <file>           # scan single file (legacy mode)
#   scan-credentials.sh <project-dir>    # v2: scan $HX_MAIN_FILE + $HX_GOTCHAS_FILE
#                                        #     + $HX_LOGS_DIR/*.md + $HX_DEC_DIR/*.md
#   cat foo | scan-credentials.sh        # stdin
#
# Exit: 0 clean, 1 credential found, 2 usage error / unreadable input (cannot scan ≠ clean)
set -u

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme). Credential
# patterns below are unaffected; this only migrates which paths to scan.
. "$(dirname "$0")/lib/handoff-schema.sh"

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file|dir]   OR   cat file | $0"
        echo "  no arg + no stdin → 默认扫 ./$HX_MAIN_FILE"
        echo "  v2 directory mode scans $HX_MAIN_FILE + $HX_GOTCHAS_FILE + ${HX_LOGS_DIR}/*.md + ${HX_DEC_DIR}/*.md"
        echo "Exit: 0 clean / 1 credential found / 2 usage error or unreadable input"
        exit 0
        ;;
esac

PATTERNS=(
    'sk-proj-[A-Za-z0-9_-]{20,}'
    'sk-ant-(api|admin)[0-9]+-[A-Za-z0-9_-]{20,}'
    'ghp_[A-Za-z0-9]{36,}'
    'gho_[A-Za-z0-9]{36,}'
    'ghs_[A-Za-z0-9]{36,}'
    'github_pat_[A-Za-z0-9_]{36,}'
    'AKIA[0-9A-Z]{16}'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'sbp_[A-Za-z0-9]{32,}'
    'hf_[A-Za-z0-9]{30,}'
    '-----BEGIN [A-Z ]+PRIVATE KEY-----'
)
LABELS=(
    'OpenAI project key'
    'Anthropic API key'
    'GitHub personal token'
    'GitHub OAuth token'
    'GitHub server token'
    'GitHub fine-grained PAT'
    'AWS access key ID'
    'Slack token'
    'Supabase service role key'
    'HuggingFace token'
    'Private key header'
)

# scan_file <path> → exits with 0 clean / 1 credential found / 2 cannot read
scan_file() {
    local f="$1"
    local found=0
    # grep's error exit (2) must not read as "no match": an unreadable file
    # scanned nothing and is not clean (Gotcha #24).
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "❌ $f: not a readable file — cannot scan, refusing to report clean" >&2
        return 2
    fi
    for i in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$i]}"
        local label="${LABELS[$i]}"
        local rc=0
        grep -qE -- "$pattern" "$f" || rc=$?
        if [ "$rc" -eq 0 ]; then
            local line
            line=$(grep -nE -- "$pattern" "$f" | head -1 | cut -d: -f1)
            echo "⚠️  $label detected in $f (line $line)" >&2
            found=1
        elif [ "$rc" -gt 1 ]; then
            # the -f/-r probe above is only a proxy; a read error mid-loop
            # (EIO, revoked permission) still must not read as "no match"
            echo "❌ $f: grep failed (rc=$rc) — cannot scan, refusing to report clean" >&2
            return 2
        fi
    done
    return $found
}

# scan_content_stdin <content> — current legacy stdin path; matches the original
# label format (no file path, since stdin has none).
scan_content_stdin() {
    local content="$1"
    local found=0
    for i in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$i]}"
        local label="${LABELS[$i]}"
        local rc=0
        echo "$content" | grep -qE -- "$pattern" || rc=$?
        if [ "$rc" -eq 0 ]; then
            local line
            line=$(echo "$content" | grep -nE -- "$pattern" | head -1 | cut -d: -f1)
            echo "⚠️  $label detected (line $line)" >&2
            found=1
        elif [ "$rc" -gt 1 ]; then
            # parity with scan_file: a grep error is not "no match"
            echo "❌ stdin: grep failed (rc=$rc) — cannot scan, refusing to report clean" >&2
            return 2
        fi
    done
    return $found
}

# scan_v2_layout <project-dir>
# Walks the v2 four-piece layout PLUS the yearly archive subdirs (Codex
# review #11: archived entries are first-class handoff content; recall reads
# them on demand, so they belong in the same security gate).
scan_v2_layout() {
    local root="$1"
    local hit=0 unreadable=0 rc f d found
    for f in "$root/$HX_MAIN_FILE" "$root/$HX_GOTCHAS_FILE"; do
        # -L: a dangling symlink fails -e but is not "legitimately missing"
        [ -e "$f" ] || [ -L "$f" ] || continue
        rc=0; scan_file "$f" || rc=$?
        case $rc in 1) hit=1 ;; 2) unreadable=1 ;; esac
    done
    # Recursive walk of $HX_LOGS_DIR/ + ${HX_LOGS_DIR}.archive/<year>/
    # + $HX_DEC_DIR/ + ${HX_DEC_DIR}.archive/<year>/ (archive
    # naming reserved for future Decision archiving — included defensively).
    # A missing dir is a legitimate skip; one that exists but cannot be
    # listed/traversed is not — the old `find … 2>/dev/null || true` turned
    # that into "0 files → clean" (Gotcha #24, twin of handoff-lint CRITICAL-B).
    for d in "$root/$HX_LOGS_DIR" "$root/${HX_LOGS_DIR}.archive" \
             "$root/$HX_DEC_DIR" "$root/${HX_DEC_DIR}.archive"; do
        [ -e "$d" ] || [ -L "$d" ] || continue
        if [ ! -d "$d" ] || [ ! -r "$d" ] || [ ! -x "$d" ]; then
            echo "❌ $d: not a readable directory — cannot scan, refusing to report clean" >&2
            unreadable=1
            continue
        fi
        # "$d/" so a symlinked dir is descended (recall's `ls` follows it, the
        # gate must scan at least as much); -o -type l so symlinked entries are
        # handed to scan_file, which follows and judges them.
        if ! found=$(find "$d/" \( -type f -o -type l \) -name '*.md'); then
            echo "❌ $d: find could not walk the whole tree — cannot scan, refusing to report clean" >&2
            unreadable=1
        fi
        [ -n "$found" ] || continue
        while IFS= read -r f; do
            rc=0; scan_file "$f" || rc=$?
            case $rc in 1) hit=1 ;; 2) unreadable=1 ;; esac
        done <<< "$found"
    done
    # A found credential outranks "could not scan everything": both are
    # reported above, but exit 1 is the stronger claim.
    if [ "$hit" -eq 1 ]; then return 1; fi
    if [ "$unreadable" -eq 1 ]; then return 2; fi
    return 0
}

OVERALL=0

if [ $# -ge 1 ]; then
    if [ -d "$1" ]; then
        # v2 directory mode
        scan_v2_layout "$1" || OVERALL=$?
    elif [ -f "$1" ]; then
        scan_file "$1" || OVERALL=$?
    else
        echo "❌ not a file or directory: $1" >&2
        echo "   Usage: $0 [file|dir]   OR   cat file | $0" >&2
        exit 2
    fi
elif [ ! -t 0 ]; then
    CONTENT=$(cat) || { echo "❌ could not read stdin — cannot scan, refusing to report clean" >&2; exit 2; }
    # cron/CI with </dev/null, or `cat missing | scan`: scanning "" and
    # exiting 0 would look like a clean ./$HX_MAIN_FILE that was never opened.
    if [ -z "$CONTENT" ]; then
        echo "❌ stdin is empty — nothing scanned (pipe content, or pass a file/dir)" >&2
        exit 2
    fi
    scan_content_stdin "$CONTENT" || OVERALL=$?
elif [ -f "$HX_MAIN_FILE" ]; then
    scan_file "$HX_MAIN_FILE" || OVERALL=$?
else
    echo "Usage: $0 [file|dir]   OR   cat file | $0" >&2
    echo "  (no arg, no stdin, no ./$HX_MAIN_FILE in cwd)" >&2
    exit 2
fi

exit $OVERALL
