#!/usr/bin/env bash
# hx.sh — the one entry point of the /handoffx write flow. Non-interactive;
# stdout carries data only, diagnostics go to stderr.
# Usage: hx.sh (now | next-number logs|decisions [--root DIR] | slug "<title>" | regen [--root DIR]
#              | dup-check --files a,b,c [--root DIR] | block get|set <name> [--from FILE] [--file F])
#
# Why a script and not "source the lib": the AI's tool shell may be zsh, where
# the lib refuses to load (bash-only) and every helper silently went missing.
# This file always runs under bash (shebang / `bash hx.sh …`).
# Every helper / lib call is captured as `x=$(…) || rc=$?`: set -e is off
# inside `||`, so lib fallbacks still run, and a failure becomes ❌ + exit 2
# instead of set -e's raw status (the usage line documents 0 / 2 / 3 / 4).
set -euo pipefail

SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -r "$SD/lib/handoff-schema.sh" ] || { echo "❌ hx.sh: $SD/lib/handoff-schema.sh missing or unreadable" >&2; exit 2; }
. "$SD/lib/handoff-schema.sh"
[ -r "$SD/lib/handoff-v2.sh" ] || { echo "❌ hx.sh: $SD/lib/handoff-v2.sh missing or unreadable" >&2; exit 2; }
. "$SD/lib/handoff-v2.sh"

usage() {
    cat <<'EOF'
Usage: hx.sh <subcommand> [args]
  now                                       human= / fm= / fn= timestamps
  next-number (logs|decisions) [--root DIR] next 4-digit entry number
  slug "<title>"                            filename slug for a title
  regen [--root DIR]                        refresh main-file stat lines + decision index
  dup-check --files a,b,c [--root DIR]      first-entry / ok (0), likely duplicate (3), undecidable (2)
  block get NAME [--file F]                 print what sits between the hx:NAME anchors
  block set NAME --from PATH [--file F]     replace it with PATH's content (anchors kept)
(default root: .; default --file: ./<main file>)
EOF
}

die_usage() { echo "❌ hx.sh: $1" >&2; usage >&2; exit 2; }

# parse_root <args…> — sets ROOT from an optional `--root DIR`; anything else is a usage error.
parse_root() {
    ROOT="."
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --root)
                [ -n "${2:-}" ] || die_usage "--root requires a directory argument"
                ROOT="$2"; shift ;;
            *) die_usage "unknown argument: $1" ;;
        esac
        shift
    done
    [ -d "$ROOT" ] || { echo "❌ hx.sh: not a directory: $ROOT" >&2; exit 2; }
}

cmd_now() {
    [ "$#" -eq 0 ] || die_usage "now takes no arguments"
    # One clock read: three separate `date` calls can straddle a minute.
    local human fm
    human=$(date "+%Y-%m-%d %H:%M") && [ -n "$human" ] || { echo "❌ hx.sh now: date failed" >&2; exit 2; }
    fm="${human/ /T}"
    printf 'human=%s\nfm=%s\nfn=%s\n' "$human" "$fm" "${fm/:/}"
}

cmd_next_number() {
    local kind="${1:-}" dir n rc=0
    [ "$#" -gt 0 ] && shift
    parse_root "$@"
    case "$kind" in
        logs) dir="$ROOT/$HX_LOGS_DIR" ;;
        decisions) dir="$ROOT/$HX_DEC_DIR" ;;
        *) die_usage "next-number needs logs or decisions" ;;
    esac
    # Captured, not streamed: on failure nothing may reach stdout, and the
    # lib's return code is the exit code (set -e is off inside `||`).
    n=$(acquire_next_number "$dir") || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    printf '%s\n' "$n"
}

cmd_slug() {
    local out rc=0
    [ "$#" -eq 1 ] && [ -n "$1" ] || die_usage "slug needs exactly one non-empty title"
    out=$(slugify "$1") || rc=$?
    # A bare "entry-" is slugify's output when neither shasum nor sha1sum ran.
    if [ "$rc" -ne 0 ] || [ -z "$out" ] || [ "$out" = entry- ]; then
        echo "❌ hx.sh slug: cannot compute a slug (rc $rc; non-ASCII titles need shasum or sha1sum)" >&2
        exit 2
    fi
    printf '%s\n' "$out"
}

cmd_regen() {
    local rc=0
    parse_root "$@"
    # The lib helpers are success no-ops on a missing file or a file without
    # the v2 marker, so check here. -f / -r follow a link, and the lib's mv
    # would replace the link itself with a regular file.
    if [ -L "$ROOT/$HX_MAIN_FILE" ]; then
        echo "❌ hx.sh regen: $ROOT/$HX_MAIN_FILE is a symlink — refusing" >&2
        exit 2
    fi
    if [ ! -f "$ROOT/$HX_MAIN_FILE" ] || [ ! -r "$ROOT/$HX_MAIN_FILE" ]; then
        echo "❌ hx.sh regen: $ROOT/$HX_MAIN_FILE is not a readable regular file" >&2
        exit 2
    fi
    if ! grep -qF -- "$HANDOFF_V2_MARKER" "$ROOT/$HX_MAIN_FILE"; then
        echo "❌ hx.sh regen: $ROOT/$HX_MAIN_FILE has no v2 marker — nothing would be refreshed" >&2
        exit 2
    fi
    regenerate_pointers "$ROOT/$HX_MAIN_FILE" || rc=$?
    [ "$rc" -eq 0 ] || exit "$rc"
    regenerate_decision_index "$ROOT" || rc=$?
    exit "$rc"
}

# block get|set NAME — read or replace the lines strictly between
# `<!-- hx:NAME -->` and `<!-- /hx:NAME -->`. Exit 2: target or --from not
# readable, target a symlink / not a regular file, or no anchor at all.
# Exit 4: an anchor twice, only one of the pair, end before start, or (set)
# a --from payload that carries an hx: anchor line.
# Every failure leaves the target byte-identical.
cmd_block() {
    local action="${1:-}" name="${2:-}" file="" from="" counts ns ne s e dir tmp rc nonl
    [ "$#" -ge 2 ] || die_usage "block needs get|set and a block name"
    shift 2
    case "$action" in get|set) ;; *) die_usage "block needs get or set, not: $action" ;; esac
    # Some locales collate uppercase into [a-z]; C keeps the range ASCII lowercase.
    local LC_ALL=C
    case "$name" in ''|*[!a-z0-9-]*) die_usage "block name must match [a-z0-9-]+: $name" ;; esac
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --file) [ -n "${2:-}" ] || die_usage "--file requires a path"; file="$2"; shift ;;
            --from)
                [ "$action" = set ] || die_usage "--from is for block set only"
                [ -n "${2:-}" ] || die_usage "--from requires a path"
                from="$2"; shift ;;
            *) die_usage "unknown argument: $1" ;;
        esac
        shift
    done
    [ "$action" = get ] || [ -n "$from" ] || die_usage "block set needs --from PATH"
    file="${file:-./$HX_MAIN_FILE}"

    # mv over a symlink would replace the link, not what it points at.
    if [ -L "$file" ]; then
        echo "❌ hx.sh block: $file is a symlink — refusing" >&2; exit 2
    fi
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo "❌ hx.sh block: $file is not a readable regular file" >&2; exit 2
    fi
    if [ "$action" = set ] && { [ -d "$from" ] || [ ! -r "$from" ]; }; then
        echo "❌ hx.sh block: --from $from is missing or unreadable" >&2; exit 2
    fi
    # Any anchor line in the payload (any block's, not just NAME's) would break
    # the structure once written — including --from pointing at the target.
    if [ "$action" = set ]; then
        rc=0; LC_ALL=C grep -qE '^<!-- /?hx:[a-z0-9-]+ -->[[:space:]]*$' "$from" || rc=$?
        if [ "$rc" -eq 0 ]; then
            echo "❌ hx.sh block: --from $from carries an hx: anchor line — refusing" >&2; exit 4
        elif [ "$rc" -ne 1 ]; then
            echo "❌ hx.sh block: cannot read --from $from" >&2; exit 2
        fi
    fi

    # Same anchor-line regex as validate and tidy (NAME is [a-z0-9-]+, so it
    # is regex-safe).
    counts=$(LC_ALL=C awk -v n="$name" '
        $0 ~ ("^<!-- hx:" n " -->[[:space:]]*$")  { s++; sl = NR }
        $0 ~ ("^<!-- /hx:" n " -->[[:space:]]*$") { e++; el = NR }
        END { printf "%d %d %d %d\n", s, e, sl, el }
    ' "$file") || { echo "❌ hx.sh block: cannot read $file" >&2; exit 2; }
    # Word split, not a here-doc: bash < 5.1 writes here-docs to $TMPDIR.
    # shellcheck disable=SC2086
    set -- $counts
    [ "$#" -eq 4 ] || { echo "❌ hx.sh block: cannot read $file" >&2; exit 2; }
    ns=$1; ne=$2; s=$3; e=$4
    if [ "$ns" -eq 0 ] && [ "$ne" -eq 0 ]; then
        echo "❌ hx.sh block: no hx:$name anchors in $file" >&2; exit 2
    fi
    if [ "$ns" -ne 1 ] || [ "$ne" -ne 1 ]; then
        echo "❌ hx.sh block: hx:$name anchors must appear exactly once each (start $ns, end $ne) in $file" >&2; exit 4
    fi
    if [ "$e" -le "$s" ]; then
        echo "❌ hx.sh block: /hx:$name (line $e) comes before hx:$name (line $s) in $file" >&2; exit 4
    fi

    if [ "$action" = get ]; then
        awk -v s="$s" -v e="$e" 'NR > s && NR < e' "$file" || { echo "❌ hx.sh block: cannot read $file" >&2; exit 2; }
        return 0
    fi

    dir=$(dirname "$file")
    # A target without a final newline must stay that way (bytes outside the
    # block are untouched), so lines are joined and the last "\n" is optional.
    nonl=$(tail -c1 "$file") || { echo "❌ hx.sh block: cannot read $file" >&2; exit 2; }
    if [ -n "$nonl" ]; then nonl=1; else nonl=0; fi
    tmp=$(mktemp "$dir/.hx-block.XXXXXX") || { echo "❌ hx.sh block: cannot create a temp file in $dir" >&2; exit 2; }
    # cp -p first so the rewritten file keeps the target's mode (mktemp gives 0600).
    # The path goes in via ENVIRON: -v would expand backslash escapes in it.
    # Lines s and e are re-checked here because the file may have changed since
    # the counting pass. No lock: the write flow has one writer per project, so
    # this only catches a file that shifted underneath, it does not serialize.
    rc=0
    cp -p "$file" "$tmp" || rc=2
    if [ "$rc" -eq 0 ]; then
        HX_BLOCK_SRC="$from" LC_ALL=C awk -v s="$s" -v e="$e" -v nm="$name" -v nonl="$nonl" '
            function out(x) { printf "%s%s", (n++ ? "\n" : ""), x }
            NR == s {
                if ($0 !~ ("^<!-- hx:" nm " -->[[:space:]]*$")) { code = 4; exit code }
                out($0)
                src = ENVIRON["HX_BLOCK_SRC"]
                while ((r = (getline line < src)) > 0) out(line)
                if (r < 0) { code = 3; exit code }
                next
            }
            NR == e {
                if ($0 !~ ("^<!-- /hx:" nm " -->[[:space:]]*$")) { code = 4; exit code }
                out($0); next
            }
            NR > s && NR < e { next }
            { out($0) }
            END {
                if (!code && NR < e) code = 4
                if (code) exit code
                if (!nonl) printf "\n"
            }
        ' "$file" > "$tmp" || rc=$?
    fi
    [ "$rc" -eq 0 ] && { mv -f "$tmp" "$file" || rc=2; }
    if [ "$rc" -ne 0 ]; then
        rm -f "$tmp"
        if [ "$rc" -eq 4 ]; then
            echo "❌ hx.sh block: hx:$name anchors moved while writing $file — left unchanged" >&2
            exit 4
        fi
        echo "❌ hx.sh block: writing $file failed — left unchanged" >&2
        exit 2
    fi
}

# norm_paths ROOT — stdin: candidate paths, one per line. stdout: those that
# exist under ROOT (file or dir) after dropping a ":NNN" suffix and trailing
# "/", sorted unique. Existence is what filters repo names, SHAs and branches
# out of backtick tokens.
norm_paths() {
    local p
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/:[0-9][0-9,-]*$//' -e 's:/*$::' -e 's:^\./::' |
        while IFS= read -r p; do
            if [ -n "$p" ] && [ -e "$1/$p" ]; then printf '%s\n' "$p"; fi
        done | LC_ALL=C sort -u
}

# join_set — stdin lines → "{a, b}".
join_set() { awk 'BEGIN { printf "{" } NR > 1 { printf ", " } { printf "%s", $0 } END { printf "}" }'; }

undecidable() { echo "❌ 无法判定：$1" >&2; exit 2; }

# fm_field KEY FILE — value of KEY: in FILE's leading --- frontmatter block.
fm_field() {
    awk -v k="$1" '
        NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
        /^---[[:space:]]*$/ { exit }
        index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v); print v; exit }
    ' "$2"
}

# dup-check --files a,b,c [--root DIR] — the write flow's duplicate predicate.
# Exit 0 + "first-entry" / "ok", exit 3 + warning on stderr, exit 2 when it
# cannot be decided (never "ok" then: an unknown is not a pass).
cmd_dup_check() {
    local files="" have_files=0 logs names top d epoch now diff title prev cur
    ROOT="."
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --files) [ "$#" -ge 2 ] || die_usage "--files requires a comma-separated list"; files="$2"; have_files=1; shift ;;
            --root) [ -n "${2:-}" ] || die_usage "--root requires a directory argument"; ROOT="$2"; shift ;;
            *) die_usage "unknown argument: $1" ;;
        esac
        shift
    done
    [ "$have_files" -eq 1 ] || die_usage "dup-check needs --files a,b,c"
    [ -d "$ROOT" ] || { echo "❌ hx.sh: not a directory: $ROOT" >&2; exit 2; }

    logs="$ROOT/$HX_LOGS_DIR"
    if [ ! -e "$logs" ] && [ ! -L "$logs" ]; then echo first-entry; return 0; fi
    [ -d "$logs" ] || undecidable "$logs is not a directory"
    names=$(ls -1 "$logs") || undecidable "cannot list $logs"
    top=$(printf '%s\n' "$names" | awk '/^[0-9].*\.md$/' | LC_ALL=C sort | tail -1) || undecidable "cannot list $logs"
    if [ -z "$top" ]; then echo first-entry; return 0; fi
    top="$logs/$top"
    if [ ! -f "$top" ] || [ ! -r "$top" ]; then undecidable "$top is not a readable file"; fi

    d=$(fm_field date "$top") || undecidable "cannot read $top"
    title=$(fm_field title "$top") || undecidable "cannot read $top"
    # Shape first: GNU date reads "2026-11-02 2144" as 21:44, and BSD date
    # accepts trailing extras with a warning.
    # Seconds pinned to :00 — BSD date -j fills unparsed fields from the clock.
    epoch=""
    if printf '%s\n' "$d" | grep -qxE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}'; then
        epoch=$(date -j -f '%Y-%m-%dT%H:%M:%S' "$d:00" +%s 2>/dev/null) ||
            epoch=$(date -d "${d/T/ }:00" +%s 2>/dev/null) || epoch=""
    fi
    case "$epoch" in
        ''|*[!0-9]*) undecidable "date: '${d}' in $top is not YYYY-MM-DDTHH:MM" ;;
    esac
    now=$(date +%s) || undecidable "cannot read the clock (date +%s failed)"
    case "$now" in ''|*[!0-9]*) undecidable "cannot read the clock (date +%s: '$now')" ;; esac
    diff=$((now - epoch))
    if [ "$diff" -lt -600 ]; then undecidable "顶部条目的时间在未来（时钟偏差？）: $top"; fi
    [ "$diff" -ge 0 ] || diff=$((-diff))
    if [ "$diff" -ge 600 ]; then echo ok; return 0; fi

    # Previous entry: backtick tokens of the **改动** / **Changes** field, up to
    # the next **field** line. The CJK name goes in via -v (mawk).
    prev=$(awk -v cn="改动" '
        {
            if ($0 ~ ("^\\*\\*(" cn "|Changes)\\*\\*")) on = 1
            else if ($0 ~ /^\*\*[^*]+\*\*/) on = 0
        }
        on {
            s = $0
            while (match(s, /`[^`]*`/)) {
                print substr(s, RSTART + 1, RLENGTH - 2)
                s = substr(s, RSTART + RLENGTH)
            }
        }
    ' "$top") || undecidable "cannot read $top"
    prev=$(printf '%s\n' "$prev" | norm_paths "$ROOT") || undecidable "cannot normalise the previous entry's paths"
    cur=$(printf '%s\n' "$files" | tr ',' '\n' | norm_paths "$ROOT") || undecidable "cannot normalise --files"

    if [ -n "$prev" ] && [ "$prev" = "$cur" ]; then
        {
            echo "⚠️ 检测到可能重复："
            echo "  上一条: $((diff / 60)) 分钟前 \"${title:-$(basename "$top")}\" 改动文件: $(printf '%s\n' "$prev" | join_set)"
            echo "  本次:   改动文件: $(printf '%s\n' "$cur" | join_set)  ← 完全相同"
        } >&2
        exit 3
    fi
    echo ok
}

[ "$#" -gt 0 ] || die_usage "missing subcommand"
sub="$1"; shift
case "$sub" in
    now) cmd_now "$@" ;;
    next-number) cmd_next_number "$@" ;;
    slug) cmd_slug "$@" ;;
    regen) cmd_regen "$@" ;;
    block) cmd_block "$@" ;;
    dup-check) cmd_dup_check "$@" ;;
    -h|--help) usage ;;
    *) die_usage "unknown subcommand: $sub" ;;
esac
