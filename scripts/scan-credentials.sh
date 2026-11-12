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
        echo "  识别: sk-proj- / sk-ant- / ghp_ gho_ ghs_ github_pat_ / AKIA / xox?- / sbp_ / hf_ / PEM 私钥头"
        echo "        Authorization: token|Bearer <字面值>；*GIT*_TOKEN / FORGEJO*_TOKEN = 或 : <40 位 hex>（键可带引号，JSON 形态）；"
        echo "        同行出现自建 Git 服务名（Forgejo 等）的 token = 或 : <40 位 hex>"
        echo "  不报: \$VAR / \${VAR} / <占位符> / vault:// 引用 / 整个值都是 x、X、.、_、- 的占位；裸 40 位 hex（commit SHA）"
        echo "  表头启发式: 表头列名含 密码/口令/密钥/令牌/password/pwd/pass/secret/token/api_key/private_key 的列，"
        echo "        单元格非占位、无空白、≥6 字符、全 ASCII 且含字母即报（占位: 空 / - / — / n/a / \$VAR / vault:// / <…> / 全 x*•·._-；"
        echo "        纯数字或含非 ASCII 字符的值不算，如用量、计数、中文说明）"
        echo "  覆盖边界: 只识别上面的模式与表头列；表格外的通用密码语义不检测——exit 0 只说明没命中这些"
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
    # Self-hosted forge tokens have no vendor prefix (report 5 HX-01), so these
    # three key on context. Never a bare hex40 rule: every commit SHA would hit.
    # A `$VAR` / `${VAR}` / `<placeholder>` / `vault://` value cannot match the
    # value class. The header rule is a candidate only: a value of 20+ chars
    # as a whole; cred_grep_n then drops a value made ENTIRELY of x/X . _ -
    # (fix3 N4: one ERE cannot say "20+ total AND not all placeholder" — the
    # old "20 after the first real char" let x+19 / _+19 through). The key may
    # be quoted (`"…_TOKEN": "…"`, a settings.json env block).
    '[Aa]uthorization:[[:space:]]*([Tt]oken|[Bb]earer)[[:space:]]+[A-Za-z0-9._-]{20,}'
    # GIT* covers the GITEA_/GITEE_/GITHUB_ names; the forge's name is spelled
    # in case classes only (rule 3) because the public mirror's privacy gate
    # rejects that word in any shipped non-.md file.
    "(GIT|FORGEJO)[A-Z_]*TOKEN[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Fa-f0-9]{40}"
    "([Gg][Ii][Tt][Ee][Aa]|[Ff][Oo][Rr][Gg][Ee][Jj][Oo]).*[Tt][Oo][Kk][Ee][Nn][\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Fa-f0-9]{40}|[Tt][Oo][Kk][Ee][Nn][\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Fa-f0-9]{40}.*([Gg][Ii][Tt][Ee][Aa]|[Ff][Oo][Rr][Gg][Ee][Jj][Oo])"
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
    'Authorization header token'
    'Forge token variable (40-hex)'
    'Forge-named token assignment (40-hex)'
)

# ── credential placeholder filter (fix3 N4) — byte-identical in
# scan-credentials.sh, release-sanitize-public.sh, release-publish-github.sh
# and release-publish-github-backfill.sh (tests/test_release_sanitize_credscan.sh
# compares the block). cred_grep_n <ERE> [file] = grep -nE, except that for
# the Authorization header rule a header whose WHOLE value is
# placeholder-shaped (only x X . _ -) is blanked first. rc: 0 hit / 1 none /
# 2 unreadable. LC_ALL=C (fix4): the classes are ASCII, and BSD sed under
# UTF-8 dies on a Latin-1 byte. cred_tree_hits <flags> <ERE> <root>
# [grep opts…] runs `grep -rIl<flags>E` and prints each real hit, one per
# line (a newline inside a name shown as \n); rc 2 if grep or any re-check
# could not read. Names travel NUL-separated (fix5 R1: a newline in a name
# split it into two other — clean — names and dropped the hit). With
# <flags> set (case-insensitive privacy rules) there is no second pass.
cred_grep_n() {
    local out
    case "$1" in
        '[Aa]uthorization:'*)
            out=$(LC_ALL=C sed -E 's/[Aa]uthorization:[[:space:]]*([Tt]oken|[Bb]earer)[[:space:]]+[xX._-]+([^A-Za-z0-9._-]|$)/\2/g' ${2+"$2"}) || return 2
            printf '%s\n' "$out" | LC_ALL=C grep -nE -- "$1" ;;
        *) LC_ALL=C grep -nE -- "$1" ${2+"$2"} ;;
    esac
}
cred_tree_hits() {
    local fl="$1" p="$2" root="$3" st
    shift 3
    grep -rIl"${fl}"E --null "$@" -- "$p" "$root" 2>/dev/null | {
        local f grc rc=0 nl='
'
        while IFS= read -r -d '' f; do
            grc=0
            [ -n "$fl" ] || cred_grep_n "$p" "$f" >/dev/null 2>&1 || grc=$?
            case "$grc" in 0) printf '%s\n' "${f//$nl/\\n}" ;; 1) ;; *) rc=2 ;; esac
        done
        exit "$rc"
    }
    st=("${PIPESTATUS[@]}")
    [ "${st[0]}" -le 1 ] && [ "${st[1]}" -eq 0 ] || return 2
}
# ── end credential placeholder filter

# scan_table_secrets <file> [name] → 0 no hit / 1 hit / 2 cannot scan.
# A markdown table whose header (the row above a |---| separator) names a
# password/token/secret column must hold only placeholders there; a cell that
# is not a placeholder, has no whitespace, is 6+ chars, all ASCII and holds an
# ASCII letter is a literal: credentials are ASCII and never purely numeric, so
# a token-usage note ("0（…）") or a count is not one. Being all ASCII, bytes ==
# chars, so length() agrees on mawk and BSD awk. With [name] (stdin) messages
# carry no path.
scan_table_secrets() {
    local f="$1" where=" in $1" who="$1" hits rc=0 line hdr
    if [ $# -ge 2 ]; then where=""; who="$2"; fi
    if [ ! -r "$f" ]; then
        echo "❌ $who: table scan failed — cannot scan, refusing to report clean" >&2
        return 2
    fi
    # Non-ASCII bytes come in through -v (printf), never as \ooo escapes in
    # the awk source: those differ across mawk / gawk / BWK awk (Gotcha #15).
    hits=$(LC_ALL=C awk \
            -v nonascii="$(printf '[\200-\377]')" \
            -v cjk="$(printf '\345\257\206\347\240\201|\345\217\243\344\273\244|\345\257\206\351\222\245|\344\273\244\347\211\214')" \
            -v emd="$(printf '\342\200\224')" -v ens="$(printf '\342\200\223')" \
            -v bul="$(printf '\342\200\242')" -v mid="$(printf '\302\267')" '
        function trim(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
        function placeholder(v,  l, t) {
            l = tolower(v)
            if (v == "" || v == "-" || v == emd || v == ens || l == "n/a") return 1
            if (v ~ /^\$/ || v ~ /^vault:\/\// || v ~ /^<.*>$/) return 1
            t = v; gsub(/[xX*._-]/, "", t); gsub(bul, "", t); gsub(mid, "", t)
            return t == ""
        }
        # No plural: a count column like "tokens used" is not a credential.
        function sensitive(c) {
            c = tolower(c)
            return c ~ /(^|[^a-z0-9])pass([^a-z0-9]|$)/ ||
                   c ~ /(pwd|passw(or)?d|passphrase|secret|token|api[ _-]?key|private[ _-]?key)([^a-z0-9]|$)/ ||
                   c ~ cjk
        }
        # Marks the sensitive columns of the row above; issens[i] == gen means
        # column i is sensitive in the current table block.
        function header_from_prev(  n, i, c) {
            n = split(prev, h, "|")
            for (i = 1; i <= n; i++) {
                c = trim(h[i])
                if (sensitive(c)) { if (issens[i] != gen) nsens++; issens[i] = gen; name[i] = c }
            }
        }
        # Every cell is ---, :---, ---: or :---: (3+ dashes).
        function strict_sep(line,  n, i, c, cells) {
            n = split(line, cell2, "|")
            cells = 0
            for (i = 2; i <= n; i++) {
                c = cell2[i]
                if (i == n && c ~ /^[ \t\r]*$/) continue
                if (c !~ /^[ \t]*:?---+:?[ \t\r]*$/) return 0
                cells++
            }
            return cells > 0
        }
        BEGIN { gen = 1 }
        # CRLF: drop the CR first so header, separator and data rows of a
        # CRLF table parse exactly like the LF one.
        { sub(/\r$/, "") }
        !/^[ \t]*\|/ { nsens = 0; gen++; tblrow = 0; prev = ""; next }
        # The second row of a table is its separator; a `| - | - |` data row
        # must not promote the row above to a header.
        ++tblrow == 2 && /^[ \t]*\|[ \t:|-]*-[ \t:|-]*$/ {
            nsens = 0; gen++
            header_from_prev()
            next
        }
        # A later strict separator is a second table abutting the first: its
        # header columns are added, never removed (sensitivity only grows
        # inside a block, so a placeholder `| --- |` row cannot clear it).
        tblrow > 2 && strict_sep($0) { header_from_prev(); next }
        {
            prev = $0
            if (nsens == 0) next
            n = split($0, cell, "|")
            for (i = 1; i <= n; i++) {
                if (issens[i] != gen) continue
                v = trim(cell[i]); gsub(/`/, "", v); v = trim(v)
                if (placeholder(v) || v ~ /[ \t]/ || v ~ nonascii || v !~ /[A-Za-z]/) continue
                if (length(v) >= 6) print NR "\t" name[i]
            }
        }' "$f") || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "❌ $who: table scan failed — cannot scan, refusing to report clean" >&2
        return 2
    fi
    [ -n "$hits" ] || return 0
    # a pipe, not a here-doc: bash < 5.1 writes here-docs to $TMPDIR (fix3 N3)
    printf '%s\n' "$hits" | while IFS="$(printf '\t')" read -r line hdr; do
        echo "⚠️  table column \"$hdr\" holds a literal value$where (line $line)" >&2
    done
    return 1
}

# scan_file <path> [name] → exits with 0 clean / 1 credential found / 2 cannot
# read. [name] replaces the path in messages (stdin has no path of its own).
scan_file() {
    local f="$1" where=" in $1" who="$1"
    local found=0 trc=0
    if [ $# -ge 2 ]; then where=""; who="$2"; fi
    # grep's error exit (2) must not read as "no match": an unreadable file
    # scanned nothing and is not clean (Gotcha #24).
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "❌ $who: not a readable file — cannot scan, refusing to report clean" >&2
        return 2
    fi
    for i in "${!PATTERNS[@]}"; do
        local pattern="${PATTERNS[$i]}"
        local label="${LABELS[$i]}"
        local rc=0 hits
        hits=$(cred_grep_n "$pattern" "$f") || rc=$?
        if [ "$rc" -eq 0 ]; then
            local line=${hits%%:*}
            echo "⚠️  $label detected$where (line $line)" >&2
            found=1
        elif [ "$rc" -gt 1 ]; then
            # the -f/-r probe above is only a proxy; a read error mid-loop
            # (EIO, revoked permission) still must not read as "no match"
            echo "❌ $who: grep failed (rc=$rc) — cannot scan, refusing to report clean" >&2
            return 2
        fi
    done
    scan_table_secrets "$@" || trc=$?
    [ "$trc" -eq 2 ] && return 2
    [ "$trc" -eq 1 ] && found=1
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
        # fix3 N3: a here-string bash could not write skipped every file and
        # read as clean. A pipe needs no temp file; each scan reports its rc
        # on stdout, and the count must equal the files found.
        # Test-only: HANDOFFX_TEST_SCAN_STOP_AFTER=<n> stops the loop after n
        # files, so the count check below can be proven (fix5 R4).
        local rcs nf
        rcs=$(printf '%s\n' "$found" | { i=0; while IFS= read -r f; do
            if [ -n "${HANDOFFX_TEST_SCAN_STOP_AFTER:-}" ] && [ "$i" -ge "$HANDOFFX_TEST_SCAN_STOP_AFTER" ] 2>/dev/null; then break; fi
            i=$((i+1))
            rc=0; scan_file "$f" || rc=$?
            echo "$rc"
        done; })
        nf=$(printf '%s\n' "$found" | grep -c '')
        if [ "$(printf '%s\n' "$rcs" | grep -c '^[0-2]$')" != "$nf" ]; then
            echo "❌ $d: scanned fewer files than found ($nf) — cannot scan, refusing to report clean" >&2
            unreadable=1
        fi
        case "$rcs" in *1*) hit=1 ;; esac
        case "$rcs" in *2*) unreadable=1 ;; esac
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
    # Explicit template: macOS mktemp silently ignores an unusable $TMPDIR.
    STDIN_TMP=$(mktemp "${TMPDIR:-/tmp}/hx-scan.XXXXXX") || {
        echo "❌ stdin: cannot create a temp file — cannot scan, refusing to report clean" >&2; exit 2; }
    trap 'rm -f "$STDIN_TMP"' EXIT
    trap 'rm -f "$STDIN_TMP"; exit 2' INT TERM HUP
    printf '%s\n' "$CONTENT" > "$STDIN_TMP" || {
        echo "❌ stdin: cannot write a temp file — cannot scan, refusing to report clean" >&2; exit 2; }
    scan_file "$STDIN_TMP" stdin || OVERALL=$?
elif [ -f "$HX_MAIN_FILE" ]; then
    scan_file "$HX_MAIN_FILE" || OVERALL=$?
else
    echo "Usage: $0 [file|dir]   OR   cat file | $0" >&2
    echo "  (no arg, no stdin, no ./$HX_MAIN_FILE in cwd)" >&2
    exit 2
fi

exit $OVERALL
