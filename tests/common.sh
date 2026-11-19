#!/bin/bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
# Why: tests derive four-piece names from the schema lib so a rename never
# needs a test-side literal sweep (only fixtures/ input data may hold names).
. "$SCRIPTS_DIR/lib/handoff-schema.sh"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures"
TEMPLATES_DIR="$ROOT_DIR/skills/handoffx/assets"
TMP_DIR="$ROOT_DIR/tests/.tmp"
mkdir -p "$TMP_DIR"

PASS=0
FAIL=0

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: expected exit $expected, got $actual"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    # `-- "$needle"` 必须保留：Gotcha #1——grep pattern 以 `-` 开头会被当成选项
    local name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: missing '$needle'"
        FAIL=$((FAIL+1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  ❌ $name: unexpectedly contains '$needle'"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ $name"
        PASS=$((PASS+1))
    fi
}

assert_file_exists() {
    local name="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: file missing: $path"
        FAIL=$((FAIL+1))
    fi
}

summary() {
    echo "  ─── $PASS passed, $FAIL failed"
    [ "$FAIL" = "0" ]
}

# hx_git_worktree_state <root> — print exactly one of:
#   worktree  <root> is the top of its own git work tree
#   none      structurally not a checkout: no .git entry at <root>, and git
#             says "not a git repository" (rc 128) or resolves to some OTHER
#             top level (an extracted package placed inside another checkout)
#   error     anything else: git missing from PATH, dubious ownership, a bogus
#             GIT_DIR, a .git that git cannot use, or a top level elsewhere
#             although <root> has its own .git
# Why three states: suites ➖-skip only on `none`. Treating every rev-parse
# failure as "not a checkout" let a broken git silently turn a whole gate into
# a skip (exit 0) in a real checkout. git's own message goes to stderr.
hx_git_worktree_state() {
    local root="$1" here out rc=0
    here=$(cd "$root" 2>/dev/null && pwd -P) || { echo "hx_git_worktree_state: cannot enter $root" >&2; echo error; return 0; }
    # rc 127 counts as "no git" too: a shell that already hashed git keeps
    # answering `command -v git` after PATH loses it.
    if command -v git >/dev/null 2>&1; then
        out=$(LC_ALL=C git -C "$root" rev-parse --show-toplevel 2>&1) || rc=$?
    else
        rc=127
    fi
    if [ "$rc" -eq 127 ]; then
        # No git AND no .git: an extracted package on a machine without git —
        # structurally not a checkout (fix wave 2, m3). With .git it is ❌.
        hx_present "$root/.git" || { echo none; return 0; }
        echo "hx_git_worktree_state: git not found on PATH" >&2; echo error; return 0
    fi
    if [ "$rc" -eq 0 ]; then
        if [ "$out" = "$here" ]; then echo worktree
        elif ! hx_present "$root/.git"; then echo none
        else echo "hx_git_worktree_state: $root has .git but git resolves to $out" >&2; echo error
        fi
    elif [ "$rc" -eq 128 ] && ! hx_present "$root/.git" && printf '%s' "$out" | grep -q 'not a git repository'; then
        echo none
    else
        echo "hx_git_worktree_state: git rev-parse rc $rc: $out" >&2; echo error
    fi
    return 0
}

# p21_materialize <dst> [<src>] — lay the synthetic v2-era corpus out under the
# legacy four-piece names in <dst>. Why the fixture is stored under neutral
# names (legacy-main.md, legacy-gotchas.md, legacy-logs/, legacy-decisions/):
# gitx-release's deep audit rejects a legacy main / gotchas / legacy dir at ANY
# depth of the source tarball, so the fixture cannot ship under those names;
# the names exist only in the sandbox each test builds. Fail-closed: a missing
# source piece returns 1 and says which — a half-built corpus would turn every
# migration assertion that follows into a statement about the wrong tree.
p21_materialize() {
    local dst="$1" src="${2:-$FIXTURES_DIR/p2-1-synthetic-v2}" p
    for p in legacy-main.md legacy-gotchas.md legacy-logs legacy-decisions; do
        [ -e "$src/$p" ] || { echo "❌ p21_materialize: fixture piece missing: $src/$p" >&2; return 1; }
    done
    [ -d "$dst" ] || { echo "❌ p21_materialize: destination is not a directory: $dst" >&2; return 1; }
    cp "$src/legacy-main.md" "$dst/$HX_LEGACY_MAIN_FILE" \
        && cp "$src/legacy-gotchas.md" "$dst/$HX_GOTCHAS_FILE" \
        && cp -R "$src/legacy-logs" "$dst/$HX_LEGACY_LOGS_DIR" \
        && cp -R "$src/legacy-decisions" "$dst/$HX_LEGACY_DEC_DIR" \
        || { echo "❌ p21_materialize: copy into $dst failed" >&2; return 1; }
}

# hx_gitx_nested_re <prefix> — the ERE gitx-release's deep audit applies to the
# source tarball listing (release-audit.sh, "不含 private local state dotdirs",
# nested-name branch): a legacy main, the gotchas file or a legacy dir anywhere
# BELOW the top level fails the cut. Mirrored here, built from the schema
# constants, so the release contract catches it before gitx does.
hx_gitx_nested_re() {
    local e='s/[.[\*^$]/\\&/g'
    printf '^%s/(.*/)+(%s|%s|%s/|%s/)' \
        "$(printf '%s' "$1" | sed "$e")" \
        "$(printf '%s' "$HX_LEGACY_MAIN_FILE" | sed "$e")" \
        "$(printf '%s' "$HX_GOTCHAS_FILE" | sed "$e")" \
        "$(printf '%s' "$HX_LEGACY_LOGS_DIR" | sed "$e")" \
        "$(printf '%s' "$HX_LEGACY_DEC_DIR" | sed "$e")"
}

# hx_tar_list_raw <tgz> — every member name, AppleDouble `._*` entries included.
# Why not plain `tar tzf`: macOS bsdtar folds `._x` into x's metadata and hides
# it from the listing (report 5 HX-08: Python saw 52 of 104 members as `._*`,
# `tar tzf` printed the other 52 and nothing else). `--options '!mac-ext'` turns
# that folding off; GNU tar never folds and does not know the option.
hx_tar_list_raw() {
    if tar --version 2>/dev/null | grep -q bsdtar; then
        tar --options '!mac-ext' -tzf "$1"
    else
        tar -tzf "$1"
    fi
}

# hx_ad_members <tgz> — prints the AppleDouble (`._*` / __MACOSX/) members.
# rc 0 = listed (output may be empty: none found); rc 2 = the archive could
# not be listed (missing, truncated, unsupported option) — callers must say
# 无法列出归档, never ✅ (fix1 M-a: `2>/dev/null … || true` read a lister
# error as "no AppleDouble"). An archive with no members at all counts as
# unlisted too.
hx_ad_members() {
    local raw
    raw=$(hx_tar_list_raw "$1" 2>/dev/null) || return 2
    [ -n "$raw" ] || return 2
    printf '%s\n' "$raw" | grep -E '(^|/)\._|__MACOSX/' || true
}
