#!/bin/bash
# handoff-v2.sh — shared helpers for v2.0.0 layout
# Source this from scripts that need: slugify / acquire_next_number / verify_v2_layout
#
# Four-piece path constants are centralized in scripts/lib/handoff-schema.sh
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme). This lib sources
# it; do NOT re-hardcode four-piece directory/file literals here — use
# $HX_LOGS_DIR / $HX_DEC_DIR / $HX_MAIN_FILE / $HX_GOTCHAS_FILE instead.
#
# Why bash only, refused before a single function exists (v4.1.1 fix1 I4):
# Claude Code's Bash tool may run zsh, where BASH_SOURCE is empty — the schema
# lib was then looked up in "./", every HX_* stayed empty and regenerate_*
# wrote under the project root itself. Locating the lib under zsh fixed that,
# but zsh reads `exec 200>` as a command, not a redirection, so on a flock
# system acquire_next_number handed out a number with NO lock held, silently.
# Refusing every non-bash shell is what the docs promise; `return` ends a
# source, `exit` covers a shell that cannot return here.
if [ -z "${BASH_VERSION:-}" ]; then
    echo "❌ handoff-v2.sh: 必须在 bash 下 source（当前 shell 不是 bash）；用 bash -c '. <lib>; …'" >&2
    return 1 2>/dev/null || exit 1
fi
_hx_lib_dir="${BASH_SOURCE[0]:-}"
[ -n "$_hx_lib_dir" ] && . "$(dirname "$_hx_lib_dir")/handoff-schema.sh"
unset _hx_lib_dir

# _hx_require_consts <caller> — refuse when the schema constants are empty.
_hx_require_consts() {
    [ -n "${HX_MAIN_FILE:-}" ] && [ -n "${HX_LOGS_DIR:-}" ] && [ -n "${HX_DEC_DIR:-}" ] && return 0
    echo "❌ ${1:-handoff-v2.sh}: schema constants not loaded (source this lib with bash: bash -c '. <lib>; …')" >&2
    return 1
}
_hx_require_consts handoff-v2.sh || return 1 2>/dev/null || exit 1

# slugify <title> → ASCII-only, lowercase, dash-joined, max 40 chars
# Chinese / non-ASCII titles → fallback to "entry-<8-char-hash>"
slugify() {
    local title="$1"
    # Count original bytes vs surviving ASCII chars to detect non-ASCII-dominant titles
    local orig_bytes ascii_chars
    orig_bytes=$(printf '%s' "$title" | wc -c | tr -d ' ')
    ascii_chars=$(printf '%s' "$title" | LC_ALL=C tr -cd '[:alnum:][:space:][:punct:]' | wc -c | tr -d ' ')

    # If less than half the bytes survived the ASCII strip, treat as non-ASCII title
    # Also fall back if fewer than 4 ASCII chars (nearly empty after strip)
    if [ "$ascii_chars" -lt 4 ] || [ "$((ascii_chars * 2))" -lt "$orig_bytes" ]; then
        local hash
        hash=$(printf '%s' "$title" | shasum -a 1 2>/dev/null | cut -c1-8)
        [ -z "$hash" ] && hash=$(printf '%s' "$title" | sha1sum | cut -c1-8)
        printf 'entry-%s\n' "$hash"
    else
        local ascii
        ascii=$(printf '%s' "$title" | LC_ALL=C tr -cd '[:alnum:][:space:][:punct:]' | tr -s '[:space:][:punct:]' '-' | tr '[:upper:]' '[:lower:]' | sed -E 's/^-+|-+$//g')
        # Guard: all-punctuation titles collapse to empty string after stripping dashes
        if [ -z "$ascii" ]; then
            local hash
            hash=$(printf '%s' "$title" | shasum -a 1 2>/dev/null | cut -c1-8)
            [ -z "$hash" ] && hash=$(printf '%s' "$title" | sha1sum | cut -c1-8)
            printf 'entry-%s\n' "$hash"
        else
            # Cut on a word boundary: a hard 40-char cut left slugs ending in
            # "-reminde". Back off to the last dash when the cut lands inside a
            # word, unless the first word alone is longer than 40 chars.
            local cut="${ascii:0:40}"
            case "${ascii:40:1}" in
                ''|-) ;;
                *) case "$cut" in *-*) cut="${cut%-*}" ;; esac ;;
            esac
            printf '%s\n' "$cut" | sed -E 's/-+$//'
        fi
    fi
}

# hx_take_lock <lockdir> [<caller>] / hx_release_lock <lockdir> — the per-project
# mkdir spin-lock (mkdir is atomic on POSIX filesystems). Gives up after ~5 s
# and names the directory: a crashed writer leaves it behind and only a human
# can tell a stale lock from a live one. Shared by acquire_next_number and the
# guided upgrade so a /handoffx write and a layout rename exclude each other.
hx_take_lock() {
    local lockdir="$1" retries=50
    while ! mkdir "$lockdir" 2>/dev/null; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            echo "❌ ${2:-hx_take_lock}: lock held: $lockdir (another write or upgrade is running; if none is, it is stale — rmdir it and retry)" >&2
            return 1
        fi
        sleep 0.1
    done
}
hx_release_lock() { rmdir "$1" 2>/dev/null || true; }

# acquire_next_number <dir> → echoes next 4-digit number; uses flock for single-machine atomicity
#
# Note: The lock protects the directory READ, not the full read-compute-write cycle.
# In single-writer serial use (one /handoffx at a time), this is correct. Cross-machine
# concurrency (e.g., Syncthing) can produce duplicate numbers; those are reconciled by
# /handoffx-tidy's renumber step (see spec section 4 + Task C2).
acquire_next_number() {
    local dir="$1"
    _hx_require_consts acquire_next_number || return 1
    [ -d "$dir" ] || { echo "0001"; return 0; }
    # an unreadable dir globs nothing → "0001" → collides with real entries
    if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
        echo "❌ acquire_next_number: $dir is not readable — cannot pick a safe number" >&2
        return 1
    fi

    local lockfile="$dir/.lock"

    # Use flock if available (Linux); fall back to mkdir-based spin-lock on macOS
    if command -v flock >/dev/null 2>&1; then
        touch "$lockfile"
        exec 200>"$lockfile"
        flock 200
        local max=0 n
        for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] || continue
            n=$(basename "$f" | grep -oE '^[0-9]{4}')
            # Strip leading zeros before arithmetic to avoid octal interpretation
            n=$((10#$n))
            [ -n "$n" ] && [ "$n" -gt "$max" ] && max=$n
        done
        printf '%04d\n' $((max + 1))
        exec 200>&-
    else
        local lockdir="$dir/.lock.d"
        hx_take_lock "$lockdir" acquire_next_number || return 1
        local max=0 n
        for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] || continue
            n=$(basename "$f" | grep -oE '^[0-9]{4}')
            # Strip leading zeros before arithmetic to avoid octal interpretation
            n=$((10#$n))
            [ -n "$n" ] && [ "$n" -gt "$max" ] && max=$n
        done
        printf '%04d\n' $((max + 1))
        hx_release_lock "$lockdir"
    fi
}

# Schema marker constant — used by install gate / tidy / migrate
HANDOFF_V2_MARKER='<!-- HANDOFF v2 schema -->'

# hx_mtime <file> → the file's mtime as epoch seconds; returns 1 if no stat
# variant yields one. Why GNU first and digits-only: on GNU coreutils
# `stat -f` is "file system status" — it prints a multi-line dump (with live
# free-block counters) and exits 1, so the old `stat -f %m || stat -c %Y`
# chain captured dump+epoch, two calls never compared equal, and the
# regenerate_pointers race guard refused on every busy Linux box. An answer
# is accepted only when it is a bare number, whichever stat produced it.
hx_mtime() {
    local out
    out=$(stat -c %Y "$1" 2>/dev/null) || out=""
    case "$out" in ''|*[!0-9]*) out=$(stat -f %m "$1" 2>/dev/null) || out="" ;; esac
    case "$out" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' "$out"
}

# verify_v2_layout <handoff_md_path>
# Exit 0 if v2 layout (or absent — init time OK)
# Exit 1 if v1 layout (single-file with Dev Log entries needing migration)
verify_v2_layout() {
    local main_md="$1"
    [ ! -f "$main_md" ] && return 0   # absent = init flow, OK
    grep -qF -- "$HANDOFF_V2_MARKER" "$main_md" && return 0
    grep -qE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' "$main_md" && return 1   # v1 with entries
    return 0   # empty / unknown, allow
}

# regenerate_pointers <handoff_md_path>
# Re-scan sibling $HX_LOGS_DIR/ $HX_DEC_DIR/ $HX_GOTCHAS_FILE and rewrite the
# in-section pointer stat lines of the main $HX_MAIN_FILE. Idempotent and
# atomic (.new + mv). No-op for v1 layouts.
#
# Stat lines updated:
#   ## 📜 Development Log     →  最近一条 / 最早一条 / 共 N 条
#   ## 🐛 Known Gotchas       →  共 N 条；最新：<title>
#   ## 🧭 Decision Log        →  共 N 条；最新：`<filename>`
regenerate_pointers() {
    local main_md="$1"
    _hx_require_consts regenerate_pointers || return 1
    [ -f "$main_md" ] || return 0
    grep -qF -- "$HANDOFF_V2_MARKER" "$main_md" || return 0

    local root
    root="$(cd "$(dirname "$main_md")" && pwd)"

    # A sibling dir that exists but cannot be listed must not be counted as 0:
    # the `ls … 2>/dev/null | wc -l` below would rewrite the stat line to
    # "共 0 条" and mv it into the main file (Gotcha #24, mutator variant).
    local d
    for d in "$root/$HX_LOGS_DIR" "$root/$HX_DEC_DIR"; do
        if [ -e "$d" ] && { [ ! -d "$d" ] || [ ! -r "$d" ] || [ ! -x "$d" ]; }; then
            echo "❌ regenerate_pointers: $d is not a readable directory — refusing to rewrite stats" >&2
            return 2
        fi
    done
    if [ -e "$root/$HX_GOTCHAS_FILE" ] && [ ! -r "$root/$HX_GOTCHAS_FILE" ]; then
        echo "❌ regenerate_pointers: $root/$HX_GOTCHAS_FILE is not readable — refusing to rewrite stats" >&2
        return 2
    fi

    local latest_log oldest_log log_count
    # sed -n 1p, not head -1: this lib is sourced by pipefail scripts, where a
    # reader that quits early can SIGPIPE the writer (exit 141) on big dirs.
    latest_log=$(ls "$root/$HX_LOGS_DIR/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
    oldest_log=$(ls "$root/$HX_LOGS_DIR/"[0-9]*.md 2>/dev/null | sort | sed -n 1p | sed 's|.*/||' || true)
    log_count=$(ls "$root/$HX_LOGS_DIR/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)
    log_count="${log_count:-0}"

    local latest_dec dec_count
    latest_dec=$(ls "$root/$HX_DEC_DIR/"[0-9]*.md 2>/dev/null | sort | tail -1 | sed 's|.*/||' || true)
    dec_count=$(ls "$root/$HX_DEC_DIR/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ' || true)
    dec_count="${dec_count:-0}"

    local gotcha_count="0" latest_gotcha_title=""
    if [ -f "$root/$HX_GOTCHAS_FILE" ]; then
        gotcha_count=$(grep -cE '^### Gotcha #' "$root/$HX_GOTCHAS_FILE" 2>/dev/null || true)
        gotcha_count="${gotcha_count:-0}"
        latest_gotcha_title=$(grep -E '^### Gotcha #' "$root/$HX_GOTCHAS_FILE" 2>/dev/null | tail -1 | sed 's/^### //' || true)
    fi

    # Codex review #12: snapshot $HX_MAIN_FILE mtime before reading. After the
    # awk transform, we re-check that mtime didn't change — if it did, another
    # writer raced us between read and mv, and our `mv tmp $HX_MAIN_FILE` would
    # silently overwrite their update. Bail out instead. This narrows the race
    # window to the rename(2) syscall itself; full lock-protected sequence is
    # tracked in v2.1.0 backlog (needs a project-level flock/mkdir-spinlock
    # spanning the entire /handoffx write flow, not just regenerate_pointers).
    local mtime_before
    mtime_before=$(hx_mtime "$main_md") || mtime_before=""

    local tmp
    tmp=$(mktemp) || return 1
    awk \
        -v latest_log="$latest_log" \
        -v oldest_log="$oldest_log" \
        -v log_count="$log_count" \
        -v latest_dec="$latest_dec" \
        -v dec_count="$dec_count" \
        -v gotcha_count="$gotcha_count" \
        -v latest_gotcha_title="$latest_gotcha_title" \
        '
        /^## / {
            section = ""
            if ($0 ~ /^## 📜 Development Log/) section = "dev"
            else if ($0 ~ /^## 🐛 Known Gotchas/) section = "got"
            else if ($0 ~ /^## 🧭 Decision Log/) section = "dec"
            print
            next
        }
        section == "dev" && /^最近一条：/ {
            print "最近一条：" (latest_log != "" ? latest_log : "(none)"); next
        }
        section == "dev" && /^最早一条：/ {
            print "最早一条：" (oldest_log != "" ? oldest_log : "(none)"); next
        }
        section == "dev" && /^共 [0-9]+ 条$/ {
            print "共 " log_count " 条"; next
        }
        section == "got" && /^共 [0-9]+ 条；最新：/ {
            print "共 " gotcha_count " 条；最新：" (latest_gotcha_title != "" ? latest_gotcha_title : "(none)"); next
        }
        section == "dec" && /^共 [0-9]+ 条；最新：/ {
            print "共 " dec_count " 条；最新：`" (latest_dec != "" ? latest_dec : "(none)") "`"; next
        }
        { print }
        ' "$main_md" > "$tmp" || { rm -f "$tmp"; return 1; }

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 1
    fi

    # Re-check mtime — if it changed, another writer modified $HX_MAIN_FILE
    # between our read and the impending mv. Refuse rather than clobber.
    if [ -n "$mtime_before" ]; then
        local mtime_after
        mtime_after=$(hx_mtime "$main_md") || mtime_after=""
        if [ "$mtime_before" != "$mtime_after" ]; then
            rm -f "$tmp"
            echo "⚠️  regenerate_pointers: $HX_MAIN_FILE was modified by another process; skipping rewrite" >&2
            return 1
        fi
    fi

    # identical output → leave the file (and its mtime) alone; callers may now
    # refresh unconditionally without churning Syncthing / readers
    if cmp -s "$tmp" "$main_md"; then rm -f "$tmp"; return 0; fi
    mv "$tmp" "$main_md"
}

# B③ (Decision 0019 ③): regenerate $HX_DEC_DIR/INDEX.md from per-file
# frontmatter. recall never auto-reads $HX_DEC_DIR/ ⇒ zero hot-path cost.
# Idempotent + atomic (.new + mv). No-op if dir absent.
regenerate_decision_index() {
    local root="$1" dir="$1/${HX_DEC_DIR:-}" tmp f num date title
    _hx_require_consts regenerate_decision_index || return 1
    [ -d "$dir" ] || return 0
    # unreadable dir would produce an empty (wrong) INDEX.md — refuse instead
    if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
        echo "❌ regenerate_decision_index: $dir is not readable — refusing to write an empty index" >&2
        return 2
    fi
    tmp=$(mktemp) || return 1
    {
        echo "# Decision Index"
        echo
        echo "> 自动生成（regenerate_decision_index）。recall 默认不读，按需查。"
        echo
        echo "| # | 日期 | 标题 |"
        echo "|---|------|------|"
        for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] || continue
            num=$(sed -n 's/^number: *//p' "$f" | sed -n 1p)
            date=$(sed -n 's/^date: *//p' "$f" | sed -n 1p)
            title=$(sed -n 's/^title: *//p' "$f" | sed -n 1p)
            # Sanitize: strip CR/newline AND escape | → \| so a pipe in the
            # title doesn't add spurious table cells (INDEX integrity, F4).
            num=$(printf '%s' "$num" | tr -d '\r\n' | sed 's/|/\\|/g')
            date=$(printf '%s' "$date" | tr -d '\r\n' | sed 's/|/\\|/g')
            title=$(printf '%s' "$title" | tr -d '\r\n' | sed 's/|/\\|/g')
            echo "| $num | $date | $title |"
        done
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$dir/INDEX.md"
}
