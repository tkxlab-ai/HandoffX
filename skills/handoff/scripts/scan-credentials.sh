#!/bin/bash
# scan-credentials.sh — detect plaintext credentials.
#
# Usage:
#   scan-credentials.sh                  # default: ./HANDOFF.md (or stdin if piped)
#   scan-credentials.sh <file>           # scan single file (legacy mode)
#   scan-credentials.sh <project-dir>    # v2: scan HANDOFF.md + GOTCHAS.md
#                                        #     + Handoff_Logs/*.md + Handoff_Decisions/*.md
#   cat foo | scan-credentials.sh        # stdin
#
# Exit: 0 clean, 1 credential found, 2 usage error
set -u

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file|dir]   OR   cat file | $0"
        echo "  no arg + no stdin → 默认扫 ./HANDOFF.md"
        echo "  v2 directory mode scans HANDOFF.md + GOTCHAS.md + Handoff_Logs/*.md + Handoff_Decisions/*.md"
        echo "Exit: 0 clean / 1 credential found / 2 usage error"
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

# scan_file <path> → exits with 0 clean / 1 credential found
scan_file() {
    local f="$1"
    local found=0
    for i in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$i]}"
        local label="${LABELS[$i]}"
        if grep -qE -- "$pattern" "$f"; then
            local line
            line=$(grep -nE -- "$pattern" "$f" | head -1 | cut -d: -f1)
            echo "⚠️  $label detected in $f (line $line)" >&2
            found=1
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
        if echo "$content" | grep -qE -- "$pattern"; then
            local line
            line=$(echo "$content" | grep -nE -- "$pattern" | head -1 | cut -d: -f1)
            echo "⚠️  $label detected (line $line)" >&2
            found=1
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
    local agg=0 f
    for f in "$root/HANDOFF.md" "$root/GOTCHAS.md"; do
        [ -f "$f" ] || continue
        scan_file "$f" || agg=1
    done
    # Recursive walk of Handoff_Logs/ + Handoff_Logs.archive/<year>/
    # + Handoff_Decisions/ + Handoff_Decisions.archive/<year>/ (archive
    # naming reserved for future Decision archiving — included defensively).
    if command -v find >/dev/null 2>&1; then
        local found
        found=$(find "$root/Handoff_Logs" "$root/Handoff_Logs.archive" \
                     "$root/Handoff_Decisions" "$root/Handoff_Decisions.archive" \
                     -type f -name '*.md' 2>/dev/null || true)
        if [ -n "$found" ]; then
            while IFS= read -r f; do
                scan_file "$f" || agg=1
            done <<< "$found"
        fi
    fi
    return $agg
}

OVERALL=0

if [ $# -ge 1 ]; then
    if [ -d "$1" ]; then
        # v2 directory mode
        scan_v2_layout "$1" || OVERALL=1
    elif [ -f "$1" ]; then
        scan_file "$1" || OVERALL=1
    else
        echo "❌ not a file or directory: $1" >&2
        echo "   Usage: $0 [file|dir]   OR   cat file | $0" >&2
        exit 2
    fi
elif [ ! -t 0 ]; then
    CONTENT=$(cat)
    scan_content_stdin "$CONTENT" || OVERALL=1
elif [ -f "HANDOFF.md" ]; then
    scan_file "HANDOFF.md" || OVERALL=1
else
    echo "Usage: $0 [file|dir]   OR   cat file | $0" >&2
    echo "  (no arg, no stdin, no ./HANDOFF.md in cwd)" >&2
    exit 2
fi

exit $OVERALL
