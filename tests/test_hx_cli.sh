#!/bin/bash
# test_hx_cli.sh — scripts/hx.sh, the one bash entry point of the write flow.
# Why a CLI at all: the AI used to `source` the lib from its tool shell, which
# may be zsh — the lib refuses there and every helper silently went missing.
# Also holds the acquire_next_number lock-failure cases (driven through hx.sh,
# since "stdout empty, rc passed through" is the contract callers rely on).
source "$(dirname "$0")/common.sh"
source "$SCRIPTS_DIR/lib/handoff-v2.sh"

HX="$SCRIPTS_DIR/hx.sh"
T=$(mktemp -d) || { echo "  ❌ mktemp -d failed"; exit 1; }
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT

# ─── now ────────────────────────────────────────────────────────────────────
ec=0; out=$(bash "$HX" now 2>/dev/null) || ec=$?
assert_exit "now: exit 0" 0 "$ec"
human=$(printf '%s\n' "$out" | sed -n 's/^human=//p')
fm=$(printf '%s\n' "$out" | sed -n 's/^fm=//p')
fn=$(printf '%s\n' "$out" | sed -n 's/^fn=//p')
assert_exit "now: exactly three lines" 3 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_exit "now: human has YYYY-MM-DD HH:MM shape" 0 \
    "$(printf '%s\n' "$human" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$' && echo 0 || echo 1)"
assert_exit "now: human with space→T equals fm" 0 "$([ -n "$fm" ] && [ "$(printf '%s' "$human" | tr ' ' T)" = "$fm" ] && echo 0 || echo 1)"
assert_exit "now: fm without the colon equals fn" 0 "$([ -n "$fn" ] && [ "$(printf '%s' "$fm" | tr -d :)" = "$fn" ] && echo 0 || echo 1)"
if command -v zsh >/dev/null 2>&1; then
    ec=0; (cd "$ROOT_DIR" && zsh -fc 'bash scripts/hx.sh now') >/dev/null 2>&1 || ec=$?
    assert_exit "now: runs from a zsh tool shell" 0 "$ec"
else
    echo "  ➖ now from zsh SKIPPED (zsh not installed)"
fi

# ─── next-number ────────────────────────────────────────────────────────────
P="$T/proj"; mkdir -p "$P/$HX_LOGS_DIR" "$P/$HX_DEC_DIR"
ec=0; out=$(bash "$HX" next-number logs --root "$P") || ec=$?
assert_exit "next-number logs: exit 0" 0 "$ec"
assert_exit "next-number logs: empty dir → 0001" 0 "$([ "$out" = 0001 ] && echo 0 || echo 1)"
touch "$P/$HX_LOGS_DIR/0001-2026-11-02T1800-first.md"
assert_exit "next-number logs: after 0001 → 0002 with trailing newline" 0 \
    "$([ "$(bash "$HX" next-number logs --root "$P" | od -An -c | tr -s ' ' | sed 's/^ //;s/ $//')" = '0 0 0 2 \n' ] && echo 0 || echo 1)"
assert_exit "next-number decisions: empty dir → 0001" 0 \
    "$([ "$(bash "$HX" next-number decisions --root "$P")" = 0001 ] && echo 0 || echo 1)"
ec=0; out=$(bash "$HX" next-number nope --root "$P" 2>/dev/null) || ec=$?
assert_exit "next-number nope: exit 2" 2 "$ec"
assert_exit "next-number nope: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
ec=0; out=$(bash "$HX" next-number logs --root "$T/absent" 2>/dev/null) || ec=$?
assert_exit "next-number --root absent: exit 2, no number" 2 "$ec$out"

# ─── slug / usage ───────────────────────────────────────────────────────────
assert_exit "slug equals lib slugify" 0 \
    "$([ "$(bash "$HX" slug 'Hello World!')" = "$(slugify 'Hello World!')" ] && echo 0 || echo 1)"
ec=0; bash "$HX" slug >/dev/null 2>&1 || ec=$?
assert_exit "slug without a title: exit 2" 2 "$ec"
# final I2: under set -e a failing shasum killed hx.sh (exit 127, no output)
# before the lib's sha1sum fallback could run. Shims: shasum exits 127; the
# sha1sum shim delegates to the real tool, then a second shim set fails both.
SH1="$T/shim1"; SH2="$T/shim2"; mkdir -p "$SH1" "$SH2"
real_sha1=$(command -v sha1sum || true); real_shasum=$(command -v shasum || true)
printf '#!/bin/sh\nexit 127\n' > "$SH1/shasum"; cp "$SH1/shasum" "$SH2/shasum"; cp "$SH1/shasum" "$SH2/sha1sum"
if [ -n "$real_sha1" ]; then
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_sha1" > "$SH1/sha1sum"
else
    printf '#!/bin/sh\nexec "%s" -a 1 "$@"\n' "$real_shasum" > "$SH1/sha1sum"
fi
chmod 755 "$SH1"/* "$SH2"/*
want=$(slugify '中文标题')
assert_exit "slug control: lib slug of a CJK title is entry-<8 hex>" 0 \
    "$(printf '%s\n' "$want" | grep -qxE 'entry-[0-9a-f]{8}' && echo 0 || echo 1)"
ec=0; out=$(PATH="$SH1:$PATH" bash "$HX" slug '中文标题' 2>/dev/null) || ec=$?
assert_exit "slug: shasum fails (127) → exit 0 via sha1sum" 0 "$ec"
assert_exit "slug: shasum fails → same slug as with shasum" 0 "$([ -n "$out" ] && [ "$out" = "$want" ] && echo 0 || echo 1)"
ec=0; out=$(PATH="$SH2:$PATH" bash "$HX" slug '中文标题' 2>"$T/slug.err") || ec=$?
assert_exit "slug: no hash tool → exit 2 (not 127)" 2 "$ec"
assert_contains "slug: no hash tool → ❌ on stderr" "$(cat "$T/slug.err")" "❌"
assert_exit "slug: no hash tool → stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
# final M4: a failing helper outside the exit-code table is ❌ + exit 2, never
# set -e's raw status. A date that fails only for a bare +%s hits dup-check's
# clock read (the epoch parse passes other arguments and still works).
SH3="$T/shim3"; mkdir -p "$SH3"; real_date=$(command -v date)
printf '#!/bin/sh\n[ "$#" -eq 1 ] && [ "$1" = +%%s ] && exit 5\nexec "%s" "$@"\n' "$real_date" > "$SH3/date"
chmod 755 "$SH3/date"
DC="$T/dc"; mkdir -p "$DC/$HX_LOGS_DIR"
printf -- '---\ndate: 2026-11-02T18:00\ntitle: t\n---\n' > "$DC/$HX_LOGS_DIR/0001-2026-11-02T1800-t.md"
ec=0; out=$(PATH="$SH3:$PATH" bash "$HX" dup-check --files a --root "$DC" 2>"$T/dc.err") || ec=$?
assert_exit "dup-check: date +%s fails → exit 2" 2 "$ec"
assert_contains "dup-check: date +%s fails → ❌ 无法判定" "$(cat "$T/dc.err")" "❌ 无法判定"
assert_exit "dup-check: date +%s fails → stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
printf '#!/bin/sh\nexit 5\n' > "$SH3/date"
ec=0; out=$(PATH="$SH3:$PATH" bash "$HX" now 2>"$T/now.err") || ec=$?
assert_exit "now: date fails → exit 2" 2 "$ec"
assert_contains "now: date fails → ❌ on stderr" "$(cat "$T/now.err")" "❌"
assert_exit "now: date fails → stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
ec=0; err=$(bash "$HX" frobnicate 2>&1 >/dev/null) || ec=$?
assert_exit "unknown subcommand: exit 2" 2 "$ec"
assert_contains "unknown subcommand: usage on stderr" "$err" "Usage:"
ec=0; bash "$HX" >/dev/null 2>&1 || ec=$?
assert_exit "no subcommand: exit 2" 2 "$ec"

# ─── regen ──────────────────────────────────────────────────────────────────
R="$T/regen"; mkdir -p "$R/$HX_LOGS_DIR" "$R/$HX_DEC_DIR"
sed -e 's/<项目负责人>/Boss/g' -e 's/<标题>/Demo/g' \
    "$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md" > "$R/$HX_MAIN_FILE"
printf -- '---\nnumber: 0001\ndate: 2026-11-02T18:00\ntitle: first\n---\n' \
    > "$R/$HX_LOGS_DIR/0001-2026-11-02T1800-first.md"
ec=0; (cd "$R" && bash "$HX" regen) >/dev/null 2>&1 || ec=$?
assert_exit "regen (default root .): exit 0" 0 "$ec"
assert_exit "regen: Dev Log stat line reads 共 1 条" 1 "$(grep -cxF '共 1 条' "$R/$HX_MAIN_FILE")"
assert_file_exists "regen: decision INDEX.md written" "$R/$HX_DEC_DIR/INDEX.md"
mkdir -p "$T/nomain"
ec=0; err=$(bash "$HX" regen --root "$T/nomain" 2>&1) || ec=$?
assert_exit "regen --root without main file: exit 2" 2 "$ec"
assert_contains "regen --root without main file: ❌ on stderr" "$err" "❌"
ec=0; bash "$HX" regen --root "$T/absent" >/dev/null 2>&1 || ec=$?
assert_exit "regen --root absent: exit 2" 2 "$ec"
# Without the v2 marker the lib skips the rewrite and returns 0 — that must
# not read as success.
NM="$T/nomarker"; mkdir -p "$NM/$HX_LOGS_DIR"
grep -vF -- "$HANDOFF_V2_MARKER" "$R/$HX_MAIN_FILE" > "$NM/$HX_MAIN_FILE"
ec=0; err=$(bash "$HX" regen --root "$NM" 2>&1) || ec=$?
assert_exit "regen on a main file without the v2 marker: exit 2" 2 "$ec"
assert_contains "regen without the v2 marker: ❌ names the marker" "$err" "v2 marker"
# final C2: an unreadable Decision used to become an empty INDEX row, rc 0.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ regen unreadable Decision SKIPPED (root bypasses chmod 000)"
else
    printf -- '---\nnumber: 0001\ndate: 2026-11-02\ntitle: d1\n---\n' > "$R/$HX_DEC_DIR/0001-2026-11-02-d1.md"
    printf -- '---\nnumber: 0002\ndate: 2026-11-02\ntitle: d2\n---\n' > "$R/$HX_DEC_DIR/0002-2026-11-02-d2.md"
    ec=0; bash "$HX" regen --root "$R" >/dev/null 2>&1 || ec=$?
    assert_exit "regen control: two readable Decisions → exit 0" 0 "$ec"
    assert_contains "regen control: INDEX lists d2" "$(cat "$R/$HX_DEC_DIR/INDEX.md")" "| 0002 | 2026-11-02 | d2 |"
    cp "$R/$HX_DEC_DIR/INDEX.md" "$T/index.before"
    chmod 000 "$R/$HX_DEC_DIR/0002-2026-11-02-d2.md"
    # A private TMPDIR: the lib builds the new index there, so "nothing left
    # behind" is checked where the temp file really lives.
    RT=$(mktemp -d)
    ec=0; err=$(TMPDIR="$RT" bash "$HX" regen --root "$R" 2>&1) || ec=$?
    chmod 644 "$R/$HX_DEC_DIR/0002-2026-11-02-d2.md"
    assert_exit "regen: unreadable Decision → exit non-zero" 1 "$([ "$ec" -eq 0 ] && echo 0 || echo 1)"
    assert_contains "regen: unreadable Decision → ❌ names it" "$err" "0002-2026-11-02-d2.md"
    assert_exit "regen: unreadable Decision → INDEX.md byte-identical" 0 "$(cmp -s "$R/$HX_DEC_DIR/INDEX.md" "$T/index.before" && echo 0 || echo 1)"
    assert_exit "regen: unreadable Decision → no temp index left in TMPDIR" 0 "$(ls -A "$RT" | wc -l | tr -d ' ')"
    rm -rf "$RT"
fi
# final round 2: -f / -r follow a link and the lib's mv replaced the link
# itself with a regular file. Main file and INDEX.md as links are refused.
LK="$T/regen-link"; mkdir -p "$LK/$HX_LOGS_DIR" "$LK/$HX_DEC_DIR"
cp "$R/$HX_MAIN_FILE" "$T/main.target"; cp "$T/main.target" "$T/main.target.orig"
ln -s "$T/main.target" "$LK/$HX_MAIN_FILE"
cp "$R/$HX_LOGS_DIR/0001-2026-11-02T1800-first.md" "$LK/$HX_LOGS_DIR/"
ec=0; err=$(bash "$HX" regen --root "$LK" 2>&1) || ec=$?
assert_exit "regen: main file is a symlink → exit 2" 2 "$ec"
assert_contains "regen: main file is a symlink → ❌" "$err" "symlink"
assert_exit "regen: main file link still a link" 0 "$([ -L "$LK/$HX_MAIN_FILE" ] && echo 0 || echo 1)"
assert_exit "regen: main file link target byte-identical" 0 "$(cmp -s "$T/main.target" "$T/main.target.orig" && echo 0 || echo 1)"
rm -f "$LK/$HX_MAIN_FILE"; cp "$T/main.target" "$LK/$HX_MAIN_FILE"
printf 'old index\n' > "$T/index.target"
ln -s "$T/index.target" "$LK/$HX_DEC_DIR/INDEX.md"
ec=0; err=$(bash "$HX" regen --root "$LK" 2>&1) || ec=$?
assert_exit "regen: INDEX.md is a symlink → exit non-zero" 1 "$([ "$ec" -eq 0 ] && echo 0 || echo 1)"
assert_exit "regen: INDEX.md link still a link" 0 "$([ -L "$LK/$HX_DEC_DIR/INDEX.md" ] && echo 0 || echo 1)"
assert_exit "regen: INDEX.md link target unchanged" 0 "$([ "$(cat "$T/index.target")" = 'old index' ] && echo 0 || echo 1)"
# The lib guard itself (other callers do not go through hx.sh's precheck).
rm -f "$LK/$HX_DEC_DIR/INDEX.md"; rm -f "$LK/$HX_MAIN_FILE"; ln -s "$T/main.target" "$LK/$HX_MAIN_FILE"
ec=0; bash -c '. "$1"; regenerate_pointers "$2"' _ "$SCRIPTS_DIR/lib/handoff-v2.sh" "$LK/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "lib regenerate_pointers on a symlink → return 1" 1 "$ec"
assert_exit "lib regenerate_pointers: link still a link" 0 "$([ -L "$LK/$HX_MAIN_FILE" ] && echo 0 || echo 1)"

# ─── zero four-piece literals in hx.sh ──────────────────────────────────────
# An unreadable hx.sh must not pass as "no literal found" (Gotcha #24).
n=0; [ -r "$HX" ] || n=unreadable
for lit in "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR" "$HX_GOTCHAS_FILE" \
           "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR"; do
    grep -qF -- "$lit" "$HX" && n=$((n+1))
done
assert_exit "hx.sh holds no four-piece literal" 0 "$n"

# ─── acquire_next_number: no number unless the lock was really taken ────────
# macOS has no flock: a fake one first on PATH drives the flock branch.
FB="$T/fakeflock"; mkdir -p "$FB/fail" "$FB/ok"
printf '#!/bin/sh\nexit 1\n' > "$FB/fail/flock"; printf '#!/bin/sh\nexit 0\n' > "$FB/ok/flock"
chmod +x "$FB/fail/flock" "$FB/ok/flock"
L="$T/lock"; mkdir -p "$L/$HX_LOGS_DIR"
ec=0; out=$(PATH="$FB/fail:$PATH" bash "$HX" next-number logs --root "$L" 2>/dev/null) || ec=$?
assert_exit "flock fails: exit 1" 1 "$ec"
assert_exit "flock fails: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
ec=0; out=$(PATH="$FB/ok:$PATH" bash "$HX" next-number logs --root "$L" 2>/dev/null) || ec=$?
assert_exit "fake flock rc 0: number handed out (fake is the one used)" 0 "$([ "$ec" = 0 ] && [ "$out" = 0001 ] && echo 0 || echo 1)"
L2="$T/lockdir"; mkdir -p "$L2/$HX_LOGS_DIR/.lock"
err="$T/err"
ec=0; out=$(PATH="$FB/ok:$PATH" bash "$HX" next-number logs --root "$L2" 2>"$err") || ec=$?
assert_exit "lock file is a directory (open fails): exit 1" 1 "$ec"
assert_exit "lock file is a directory: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
assert_contains "lock file is a directory: failed at the open step" "$(cat "$err")" "(open)"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ read-only logs dir SKIPPED (root bypasses chmod 555)"
else
    L3="$T/ro"; mkdir -p "$L3/$HX_LOGS_DIR"; chmod 555 "$L3/$HX_LOGS_DIR"
    ec=0; out=$(PATH="$FB/ok:$PATH" bash "$HX" next-number logs --root "$L3" 2>"$err") || ec=$?
    assert_exit "read-only logs dir (touch fails): exit 1" 1 "$ec"
    assert_exit "read-only logs dir: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
    assert_contains "read-only logs dir: failed at the touch step" "$(cat "$err")" "(touch)"
    chmod 755 "$L3/$HX_LOGS_DIR"
fi
# mkdir branch: a PATH holding only what that branch needs, so no flock is
# found on Linux either. hx_take_lock gives up after its fixed ~5 s.
MB="$T/mkdirbin"; mkdir -p "$MB"
for tool in dirname basename grep mkdir rmdir sleep; do
    ln -s "$(command -v "$tool")" "$MB/$tool"
done
L4="$T/mk"; mkdir -p "$L4/$HX_LOGS_DIR/.lock.d"
ec=0; out=$(PATH="$MB" "$BASH" "$HX" next-number logs --root "$L4" 2>/dev/null) || ec=$?
assert_exit "mkdir lock held: exit 1" 1 "$ec"
assert_exit "mkdir lock held: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
rmdir "$L4/$HX_LOGS_DIR/.lock.d"
ec=0; out=$(PATH="$MB" "$BASH" "$HX" next-number logs --root "$L4" 2>/dev/null) || ec=$?
assert_exit "mkdir lock free: number handed out (restricted PATH is usable)" 0 "$([ "$ec" = 0 ] && [ "$out" = 0001 ] && echo 0 || echo 1)"
# A read-only dir is not a held lock: refuse at once and say why, instead of
# spinning ~5 s and blaming a stale lock.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ mkdir branch read-only dir SKIPPED (root bypasses chmod 555)"
else
    L5="$T/mkro"; mkdir -p "$L5/$HX_LOGS_DIR"; chmod 555 "$L5/$HX_LOGS_DIR"
    ec=0; out=$(PATH="$MB" "$BASH" "$HX" next-number logs --root "$L5" 2>"$err") || ec=$?
    assert_exit "mkdir branch, read-only dir: exit 1" 1 "$ec"
    assert_exit "mkdir branch, read-only dir: stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
    assert_contains "mkdir branch, read-only dir: says not writable" "$(cat "$err")" "(not writable)"
    assert_not_contains "mkdir branch, read-only dir: not blamed on a held lock" "$(cat "$err")" "lock held"
    chmod 755 "$L5/$HX_LOGS_DIR"
fi

# ─── block get / set ────────────────────────────────────────────────────────
# Why: a 20-line exact-match Edit of Current State failed too often; the
# write flow now replaces the anchored block from a file instead.
B="$T/block"; mkdir -p "$B"
printf '# Demo\n\n## Current State\n\n> hint\n\n<!-- hx:recent -->\n**a**: one\n**b**: two\n<!-- /hx:recent -->\n\n### tail\nkeep\n' > "$B/$HX_MAIN_FILE"
printf '**a**: one\n**b**: two\n' > "$B/inner.expected"
ec=0; out=$( (cd "$B" && bash "$HX" block get recent) ) || ec=$?
assert_exit "block get (default --file): exit 0" 0 "$ec"
printf '%s\n' "$out" > "$B/inner.got"
assert_exit "block get: exactly the two inner lines" 0 "$(cmp -s "$B/inner.got" "$B/inner.expected" && echo 0 || echo 1)"
printf 'new line 1\nnew line 2\nnew line 3\n' > "$B/new.txt"
ec=0; bash "$HX" block set recent --from "$B/new.txt" --file "$B/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "block set: exit 0" 0 "$ec"
bash "$HX" block get recent --file "$B/$HX_MAIN_FILE" > "$B/after.got" 2>/dev/null
assert_exit "block set then get: equals --from" 0 "$(cmp -s "$B/after.got" "$B/new.txt" && echo 0 || echo 1)"
assert_exit "block set: start anchor still once" 1 "$(grep -cx '<!-- hx:recent -->' "$B/$HX_MAIN_FILE")"
assert_exit "block set: end anchor still once" 1 "$(grep -cx '<!-- /hx:recent -->' "$B/$HX_MAIN_FILE")"
# Outside the block: drop the anchored span from both and compare.
outside() { awk '/^<!-- hx:recent -->$/{skip=1} !skip{print} /^<!-- \/hx:recent -->$/{skip=0}' "$1"; }
printf '# Demo\n\n## Current State\n\n> hint\n\n<!-- hx:recent -->\n**a**: one\n**b**: two\n<!-- /hx:recent -->\n\n### tail\nkeep\n' > "$B/orig.md"
outside "$B/orig.md" > "$B/out.orig"; outside "$B/$HX_MAIN_FILE" > "$B/out.new"
assert_exit "block set: bytes outside the block unchanged" 0 "$(cmp -s "$B/out.orig" "$B/out.new" && echo 0 || echo 1)"

# Failure matrix: every case leaves the target byte-identical.
# block_fail <name> <expected rc> <target> <args…>
block_fail() {
    local label="$1" want="$2" tgt="$3" rc=0; shift 3
    cp "$tgt" "$B/before"
    bash "$HX" block "$@" >/dev/null 2>&1 || rc=$?
    assert_exit "block failure: $label → exit $want" "$want" "$rc"
    assert_exit "block failure: $label → target unchanged" 0 "$(cmp -s "$tgt" "$B/before" && echo 0 || echo 1)"
}
cp "$B/orig.md" "$B/real.md"; ln -s "$B/real.md" "$B/link.md"
block_fail "target is a symlink" 2 "$B/link.md" set recent --from "$B/new.txt" --file "$B/link.md"
assert_exit "block failure: symlink still a symlink" 0 "$([ -L "$B/link.md" ] && echo 0 || echo 1)"
cp "$B/orig.md" "$B/t.md"
block_fail "--from missing" 2 "$B/t.md" set recent --from "$B/absent.txt" --file "$B/t.md"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ block --from unreadable SKIPPED (root bypasses chmod 000)"
else
    cp "$B/new.txt" "$B/noread.txt"; chmod 000 "$B/noread.txt"
    block_fail "--from exists but unreadable" 2 "$B/t.md" set recent --from "$B/noread.txt" --file "$B/t.md"
    chmod 644 "$B/noread.txt"
fi
block_fail "zero anchors (get nope)" 2 "$B/t.md" get nope --file "$B/t.md"
block_fail "zero anchors (set nope)" 2 "$B/t.md" set nope --from "$B/new.txt" --file "$B/t.md"
grep -vx '<!-- /hx:recent -->' "$B/orig.md" > "$B/half.md"
block_fail "start anchor only" 4 "$B/half.md" set recent --from "$B/new.txt" --file "$B/half.md"
cat "$B/orig.md" "$B/orig.md" > "$B/twice.md"
block_fail "anchors twice" 4 "$B/twice.md" set recent --from "$B/new.txt" --file "$B/twice.md"
printf 'x\n<!-- /hx:recent -->\nmid\n<!-- hx:recent -->\ny\n' > "$B/rev.md"
block_fail "end before start" 4 "$B/rev.md" set recent --from "$B/new.txt" --file "$B/rev.md"
block_fail "end before start (get)" 4 "$B/rev.md" get recent --file "$B/rev.md"
ec=0; bash "$HX" block get 'Bad_Name' --file "$B/t.md" >/dev/null 2>&1 || ec=$?
assert_exit "block: name outside [a-z0-9-] → exit 2" 2 "$ec"
ec=0; bash "$HX" block set recent --file "$B/t.md" >/dev/null 2>&1 || ec=$?
assert_exit "block set without --from → exit 2" 2 "$ec"

# Fix round 1. A payload carrying anchor lines would break the structure
# (and once reported success): refuse any hx: anchor line, not only NAME's.
printf 'ok\n<!-- /hx:x -->\n' > "$B/payload-anchor.txt"
block_fail "--from carries an anchor line" 4 "$B/t.md" set recent --from "$B/payload-anchor.txt" --file "$B/t.md"
block_fail "--from is the target itself" 4 "$B/t.md" set recent --from "$B/t.md" --file "$B/t.md"
# A NAME with a newline must not slip past a line-wise check.
ec=0; err=$(bash "$HX" block get "$(printf 'recent\nX')" --file "$B/t.md" 2>&1) || ec=$?
assert_exit "block: NAME with a newline → exit 2" 2 "$ec"
assert_contains "block: NAME with a newline → rejected as a bad name" "$err" "block name must match"
# Bytes outside the block include a missing final newline.
printf 'head\n<!-- hx:recent -->\nold\n<!-- /hx:recent -->\ntail' > "$B/nonl.md"
printf 'head\n<!-- hx:recent -->\nnew line 1\nnew line 2\nnew line 3\n<!-- /hx:recent -->\ntail' > "$B/nonl.expected"
ec=0; bash "$HX" block set recent --from "$B/new.txt" --file "$B/nonl.md" >/dev/null 2>&1 || ec=$?
assert_exit "block set, target without final newline: exit 0" 0 "$ec"
assert_exit "block set, target without final newline: no newline added" 0 \
    "$(cmp -s "$B/nonl.md" "$B/nonl.expected" && echo 0 || echo 1)"
# mktemp makes 0600 files; the rewritten target must keep its own mode.
cp "$B/orig.md" "$B/mode.md"; chmod 664 "$B/mode.md"
bash "$HX" block set recent --from "$B/new.txt" --file "$B/mode.md" >/dev/null 2>&1
mode=$(stat -c %a "$B/mode.md" 2>/dev/null || stat -f %Lp "$B/mode.md")
assert_exit "block set: mode read as three digits" 0 "$(printf '%s' "$mode" | grep -qxE '[0-7][0-7][0-7]' && echo 0 || echo 1)"
assert_exit "block set: target keeps mode 664" 0 "$([ "$mode" = 664 ] && echo 0 || echo 1)"
# [a-z] in a case pattern may collate uppercase in under some locales.
ec=0; LC_ALL=en_US.UTF-8 bash "$HX" block get Recent --file "$B/t.md" >/dev/null 2>&1 || ec=$?
assert_exit "block: uppercase NAME rejected under a UTF-8 locale → exit 2" 2 "$ec"
# final M1: an anchor is the whole line; `<!-- hx:x --> 文字` is none (validate
# and tidy agree), so there is no block x to get.
printf '## Current State\n<!-- hx:x --> 文字\n<!-- /hx:x --> 文字\n' > "$B/textline.md"
ec=0; bash "$HX" block get x --file "$B/textline.md" >/dev/null 2>&1 || ec=$?
assert_exit "block: anchor-shaped comments with trailing text → zero anchors, exit 2" 2 "$ec"

# ─── dup-check ──────────────────────────────────────────────────────────────
# Why: the duplicate check took four manual steps and was being skipped; it is
# now one predicate. Unknown must never read as "ok" (Gotcha #24).
D="$T/dup"; mkdir -p "$D/$HX_LOGS_DIR" "$D/dir"
touch "$D/a.sh" "$D/b.md" "$D/c.sh"
ago() { date -v-"$1"M '+%Y-%m-%dT%H:%M' 2>/dev/null || date -d "-$1 min" '+%Y-%m-%dT%H:%M'; }
d2=$(ago 2); d20=$(ago 20)
assert_exit "dup-check: 'minutes ago' dates have YYYY-MM-DDTHH:MM shape" 0 \
    "$(printf '%s\n%s\n' "$d2" "$d20" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$')"
# dup_entry <date-line> <changes field name> — writes the top entry.
dup_entry() {
    rm -f "$D/$HX_LOGS_DIR"/*.md
    printf -- '---\nschema: 2\ntype: dev-log\n%s\nnumber: 0001\ntitle: prior work\n---\n\n### x — prior work\n\n**触发**: x\n\n**%s**:\n- `a.sh:3` — x\n- `dir/` — y\n- `org/repo` — z\n- `b.md:12` — w\n\n**验证**:\n- `c.sh` ran\n\n**关联**: 无\n' \
        "$1" "$2" > "$D/$HX_LOGS_DIR/0001-2026-11-02T1800-prior.md"
}
# dup_run <files> — sets ec / out / err.
dup_run() { ec=0; out=$(bash "$HX" dup-check --files "$1" --root "$D" 2>"$T/dup.err") || ec=$?; err=$(cat "$T/dup.err"); }
dup_entry "date: $d2" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: same set within 10 min → exit 3" 3 "$ec"
assert_contains "dup-check: ⚠️ header on stderr" "$err" "⚠️ 检测到可能重复："
assert_contains "dup-check: previous set (existing paths only, :NNN and / stripped)" "$err" "改动文件: {a.sh, b.md, dir}"
assert_contains "dup-check: previous title quoted" "$err" '"prior work"'
assert_contains "dup-check: current set marked identical" "$err" "  本次:   改动文件: {a.sh, b.md, dir}  ← 完全相同"
assert_exit "dup-check: exit 3 → stdout empty" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
dup_run a.sh
assert_exit "dup-check: subset → ok, exit 0" 0ok "$ec$out"
dup_run a.sh,b.md,dir,c.sh
assert_exit "dup-check: c.sh is in the verification section, not the changes → ok" 0ok "$ec$out"
dup_entry "date: $d2" Changes
dup_run a.sh,b.md,dir
assert_exit "dup-check: English **Changes** field → exit 3" 3 "$ec"
dup_entry "date: $d20" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: 20 minutes ago → ok, exit 0" 0ok "$ec$out"
dup_entry "type: dev-log" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: no date: line → exit 2" 2 "$ec"
assert_contains "dup-check: no date: line → 无法判定" "$err" "❌ 无法判定"
assert_not_contains "dup-check: no date: line → stdout not ok" "$out" "ok"
dup_entry "date: $(printf '%s' "$d2" | tr -d :)" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: date: in T2144 form → exit 2" 2 "$ec"
assert_contains "dup-check: T2144 form → 无法判定" "$err" "❌ 无法判定"
assert_not_contains "dup-check: T2144 form → stdout not ok" "$out" "ok"
# Fix round 1. Real entries cite line ranges / lists and ./ prefixes; those
# tokens used to be dropped, so the sets never matched.
printf -- '---\ndate: %s\ntitle: ranged\n---\n\n**改动**:\n- `a.sh:12-30` — x\n- `b.md:25,37` — y\n- `./dir/` — z\n' "$d2" \
    > "$D/$HX_LOGS_DIR/0001-2026-11-02T1800-prior.md"
dup_run a.sh,b.md,dir
assert_exit "dup-check: :12-30 / :25,37 / ./ tokens normalised → exit 3" 3 "$ec"
assert_contains "dup-check: normalised previous set" "$err" "改动文件: {a.sh, b.md, dir}"
# A top entry dated in the future is clock skew, not "recent".
later() { date -v+"$1"M '+%Y-%m-%dT%H:%M' 2>/dev/null || date -d "+$1 min" '+%Y-%m-%dT%H:%M'; }
dup_entry "date: $(later 30)" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: date 30 minutes in the future → exit 2" 2 "$ec"
assert_contains "dup-check: future date → 无法判定 names the clock" "$err" "时间在未来"
assert_not_contains "dup-check: future date → stdout not ok" "$out" "ok"
dup_entry "date: $(later 2)" 改动
dup_run a.sh,b.md,dir
assert_exit "dup-check: date 2 minutes ahead, same set → exit 3" 3 "$ec"
assert_not_contains "dup-check: 2 minutes ahead → minutes shown without a minus sign" "$err" "上一条: -"
# Both sets empty: the previous entry names only paths that do not exist.
printf -- '---\ndate: %s\ntitle: t\n---\n\n**改动**:\n- `org/repo` — z\n' "$d2" > "$D/$HX_LOGS_DIR/0001-2026-11-02T1800-prior.md"
dup_run nope.txt
assert_exit "dup-check: both sets empty → ok, exit 0" 0ok "$ec$out"
rm -f "$D/$HX_LOGS_DIR"/*.md
dup_run a.sh
assert_exit "dup-check: empty logs dir → first-entry, exit 0" 0first-entry "$ec$out"
assert_exit "dup-check: empty logs dir → stdout first-entry" 0 "$([ "$out" = first-entry ] && echo 0 || echo 1)"
rmdir "$D/$HX_LOGS_DIR"
dup_run a.sh
assert_exit "dup-check: no logs dir → first-entry, exit 0" 0 "$([ "$ec" = 0 ] && [ "$out" = first-entry ] && echo 0 || echo 1)"
mkdir -p "$D/$HX_LOGS_DIR"
ec=0; bash "$HX" dup-check --root "$D" >/dev/null 2>&1 || ec=$?
assert_exit "dup-check without --files → exit 2" 2 "$ec"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ dup-check unreadable logs dir SKIPPED (root bypasses chmod 000)"
else
    dup_entry "date: $d2" 改动
    chmod 000 "$D/$HX_LOGS_DIR"
    dup_run a.sh,b.md,dir
    chmod 755 "$D/$HX_LOGS_DIR"
    assert_exit "dup-check: unreadable logs dir → exit 2" 2 "$ec"
    assert_contains "dup-check: unreadable logs dir → 无法判定" "$err" "❌ 无法判定"
    assert_not_contains "dup-check: unreadable logs dir → stdout not ok" "$out" "ok"
fi

# ─── instruction layer calls hx.sh only ─────────────────────────────────────
# The template tail used to tell the AI to call lib functions directly, and a
# bare placeholder there reads as a residual one to xref.
TPL="$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md"
n=0; [ -r "$TPL" ] || n=unreadable
[ "$n" = 0 ] && n=$(grep -c 'acquire_next_number\|regenerate_pointers' "$TPL" || true)
assert_exit "template names no lib function directly" 0 "$n"
. "$SCRIPTS_DIR/lib/handoff-xref-grammar.sh"
tail_txt=$(_rl_strip_code_spans "$TPL" | sed -n '/🚨 AI 注意/,$p')
assert_contains "template tail (code spans stripped) is non-empty" "$tail_txt" "AI 注意"
assert_not_contains "template tail: no bare <NNNN> outside code spans" "$tail_txt" "<NNNN>"
assert_contains "template tail: hx.sh next-number logs" "$(cat "$TPL")" "hx.sh next-number logs"
assert_contains "template tail: hx.sh regen" "$(cat "$TPL")" "hx.sh regen"
n=$(grep -rn "bash -c '\\. " "$ROOT_DIR/skills/handoffx/SKILL.md" "$ROOT_DIR/skills/handoffx/command-shims/" | wc -l | tr -d ' ')
assert_exit "SKILL.md and shims carry no bash -c '. lib' line" 0 "$n"

# ─── end to end: the whole write chain on an instantiated template ──────────
# Why: each subcommand was tested alone; nothing proved the chain an AI walks
# ends in a postflight that passes with xref really running.
E="$T/e2e"; mkdir -p "$E/$HX_LOGS_DIR" "$E/$HX_DEC_DIR"
cp "$TEMPLATES_DIR/${HX_GOTCHAS_FILE%.md}.template.md" "$E/$HX_GOTCHAS_FILE"
# Instantiate like /handoffx-init: every <field> outside HTML comments and
# code spans becomes its own text; backticked examples must stay as they are.
awk '
c { print; if (index($0, "-->")) c = 0; next }
index($0, "<!--") && !index($0, "-->") { c = 1; print; next }
{
    n = split($0, s, "`"); o = ""
    for (i = 1; i <= n; i++) {
        if (i % 2 == 1) {
            t = s[i]; r = ""
            while (match(t, /<[^!>][^>]*>/)) {
                r = r substr(t, 1, RSTART - 1) substr(t, RSTART + 1, RLENGTH - 2)
                t = substr(t, RSTART + RLENGTH)
            }
            s[i] = r t
        }
        o = o (i > 1 ? "`" : "") s[i]
    }
    print o
}' "$TPL" > "$E/$HX_MAIN_FILE"
# Control: the raw template must carry these sentinels outside code spans,
# else "none left after instantiation" below is vacuous.
nraw=0
for tok in $RL_PLACEHOLDER_SENTINELS '<任务 1>' '<任务 2>' '<M5>' '<M6>' '<1-3 年的方向>' '<模块 / 文件>' '<item>'; do
    n=$(_rl_strip_code_spans "$TPL" | grep -cF "$tok" || true)
    nraw=$((nraw + n))
done
assert_exit "e2e control: raw template carries sentinels (>0)" 0 "$([ "$nraw" -gt 0 ] && echo 0 || echo 1)"
for tok in $RL_PLACEHOLDER_SENTINELS '<任务 1>' '<任务 2>' '<M5>' '<M6>' '<1-3 年的方向>' '<模块 / 文件>' '<item>'; do
    n=$(_rl_strip_code_spans "$E/$HX_MAIN_FILE" | grep -cF "$tok" || true)
    assert_exit "e2e: instantiated main file has no bare $tok" 0 "$n"
done
assert_contains "e2e: backticked example kept" "$(cat "$E/$HX_MAIN_FILE")" '`<NNNN>-<timestamp>-<slug>.md`'
assert_exit "e2e: anchors kept" 0 "$(grep -qx '<!-- hx:recent -->' "$E/$HX_MAIN_FILE" && grep -qx '<!-- /hx:pending -->' "$E/$HX_MAIN_FILE" && echo 0 || echo 1)"
touch "$E/x.sh"
ec=0; out=$(bash "$HX" now) || ec=$?
efm=$(printf '%s\n' "$out" | sed -n 's/^fm=//p'); efn=$(printf '%s\n' "$out" | sed -n 's/^fn=//p')
assert_exit "e2e: now → fm and fn" 0 "$([ "$ec" = 0 ] && [ -n "$efm" ] && [ -n "$efn" ] && echo 0 || echo 1)"
ec=0; out=$(bash "$HX" dup-check --files x.sh --root "$E" 2>/dev/null) || ec=$?
assert_exit "e2e: dup-check on an empty log → exit 0" 0 "$ec"
assert_exit "e2e: dup-check on an empty log → first-entry" 0 "$([ "$out" = first-entry ] && echo 0 || echo 1)"
ec=0; num=$(bash "$HX" next-number logs --root "$E") || ec=$?
assert_exit "e2e: next-number logs → exit 0" 0 "$ec"
assert_exit "e2e: next-number logs → 0001" 0 "$([ "$num" = 0001 ] && echo 0 || echo 1)"
slug=$(bash "$HX" slug 'e2e chain')
DL="$E/$HX_LOGS_DIR/$num-$efn-$slug.md"
printf -- '---\nschema: 2\ntype: dev-log\ndate: %s\nnumber: %s\ntitle: e2e chain\n---\n\n### %s — e2e chain\n\n**触发**: 端到端测试\n\n**改动**:\n- `x.sh` — 新建\n\n**验证**:\n- 本测试\n\n**关联**: 无\n' \
    "$efm" "$num" "$efm" > "$DL"
assert_file_exists "e2e: dev log named <num>-<fn>-<slug>.md" "$DL"
printf '**最近改动区域**: x.sh\n**验证状态**: ✅\n' > "$E/r.txt"
ec=0; bash "$HX" block set recent --from "$E/r.txt" --file "$E/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "e2e: block set recent: exit 0" 0 "$ec"
bash "$HX" block get recent --file "$E/$HX_MAIN_FILE" > "$E/r.got" 2>/dev/null
assert_exit "e2e: block get recent == r.txt" 0 "$(cmp -s "$E/r.got" "$E/r.txt" && echo 0 || echo 1)"
ec=0; bash "$HX" regen --root "$E" >/dev/null 2>&1 || ec=$?
assert_exit "e2e: regen: exit 0" 0 "$ec"
assert_exit "e2e: main file reads 共 1 条" 1 "$(grep -cxF '共 1 条' "$E/$HX_MAIN_FILE")"
ec=0; pf=$(cd "$E" && bash "$SCRIPTS_DIR/handoff-postflight.sh" --files="$HX_MAIN_FILE,$HX_LOGS_DIR/${DL##*/}" "$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "e2e: postflight with --files: exit 0" 0 "$ec"
assert_contains "e2e: postflight really ran xref-lint" "$pf" "→ 5. xref-lint"
assert_not_contains "e2e: postflight xref-lint not red" "$pf" "❌"
[ "$ec" = 0 ] || printf '%s\n' "$pf" | grep -E '❌|⚠️' | head -20
# Control: the same xref gate on a raw (uninstantiated) copy must flag its
# sentinels, else the green above proves nothing.
mkdir -p "$T/e2e-raw"; cp "$TPL" "$T/e2e-raw/$HX_MAIN_FILE"
ec=0; xo=$(bash "$SCRIPTS_DIR/handoff-xref-lint.sh" "$T/e2e-raw/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "e2e control: xref-lint on an uninstantiated main file → exit 1" 1 "$ec"
assert_contains "e2e control: it names a residual sentinel" "$xo" "<标题>"
ec=0; bash "$HX" dup-check --files x.sh --root "$E" >/dev/null 2>&1 || ec=$?
assert_exit "e2e: second dup-check on the same file within the window → exit 3" 3 "$ec"

summary
