#!/bin/bash
# Run only this suite: bash tests/test_handoff_runtime.sh
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/handoff-v2.sh"
RT="${HRT_TEST_RUNTIME:-$ROOT/scripts/handoff-runtime.sh}"
MIRROR="${HRT_TEST_MIRROR:-$ROOT/skills/handoffx/scripts/handoff-runtime.sh}"
ASSETS="$ROOT/skills/handoffx/assets"
mkdir -p "$ROOT/wip/tmp"
export TMPDIR="$ROOT/wip/tmp"
BOX=$(mktemp -d "$TMPDIR/handoff-runtime.XXXXXX")
trap 'chmod -R u+rwX "$BOX"; rm -rf "$BOX"' EXIT
PASS=0 FAIL=0 RC=0 OUT='' ERR=''

assert_runtime() {
    local label="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); else
        printf '  ❌ %s\n' "$label" >&2
        FAIL=$((FAIL + 1))
    fi
}
hrt_test_has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
hrt_test_lacks() { ! hrt_test_has "$1"; }
hrt_test_err_has() { case "$ERR" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
hrt_test_run() {
    local dir="$1"; shift
    RC=0
    (cd "$dir" && bash "$RT" "$@") > "$BOX/out" 2> "$BOX/err" || RC=$?
    OUT=$(cat "$BOX/out"); ERR=$(cat "$BOX/err")
    if [ "${1:-}" = recall ] && [ "$RC" -eq 0 ]; then
        assert_runtime 'successful recall stdout <= 24576 UTF-8 bytes (including newlines)' \
            test "$(LC_ALL=C wc -c < "$BOX/out")" -le 24576
        assert_runtime 'successful recall is complete UTF-8' \
            iconv -f UTF-8 -t UTF-8 < "$BOX/out" > "$BOX/utf8-validated"
    fi
}
hrt_test_bad() {
    assert_runtime "$1: fails" test "$RC" -ne 0
    assert_runtime "$1: no success output (not even a newline)" test ! -s "$BOX/out"
    assert_runtime "$1: diagnostic" test -n "$ERR"
}
hrt_test_fixture() {
    mkdir -p "$1/$HX_LOGS_DIR" "$1/$HX_DEC_DIR"
    cp "$ASSETS/HANDOFFX.template.md" "$1/$HX_MAIN_FILE"
    cp "$ASSETS/GOTCHAS.template.md" "$1/$HX_GOTCHAS_FILE"
}
hrt_test_stamp() {
    local p
    for p in "$1" "$1/$HX_MAIN_FILE" "$1/$HX_GOTCHAS_FILE" "$1/$HX_LOGS_DIR" "$1/$HX_DEC_DIR" "$1/$HX_LOGS_DIR/"*.md; do
        [ -e "$p" ] || continue
        printf '%s %s\n' "$p" "$(hx_mtime "$p")"
        if [ -f "$p" ]; then cksum "$p"; fi
    done
}

assert_runtime 'mirror byte equality' cmp -s "$RT" "$MIRROR"
assert_runtime 'bash syntax' bash -n "$RT"
assert_runtime 'mirror syntax' bash -n "$MIRROR"
P="$BOX/空格 project 中文"
mkdir "$P"
printf 'untouched\n' > "$P/user.txt"
hrt_test_run "$BOX" init --root "$P"
assert_runtime 'init in spaced Chinese path' test "$RC" -eq 0
assert_runtime 'init status' hrt_test_has 'status=initialized'
assert_runtime 'main exactly template; no invented facts' cmp -s "$P/$HX_MAIN_FILE" "$ASSETS/HANDOFFX.template.md"
assert_runtime 'fresh scaffold has no blocking xref placeholders' bash "$ROOT/scripts/handoff-xref-lint.sh" "$P/$HX_MAIN_FILE" "$P/$HX_GOTCHAS_FILE"
assert_runtime 'gotchas exactly template' cmp -s "$P/$HX_GOTCHAS_FILE" "$ASSETS/GOTCHAS.template.md"
assert_runtime 'empty log directory' test -z "$(ls -A "$P/$HX_LOGS_DIR")"
assert_runtime 'empty decision directory' test -z "$(ls -A "$P/$HX_DEC_DIR")"
assert_runtime 'unrelated file preserved' test "$(cat "$P/user.txt")" = untouched
before=$(hrt_test_stamp "$P")
sleep 1
hrt_test_run "$P" init
assert_runtime 'init idempotent' test "$RC" -eq 0
assert_runtime 'init existing status' hrt_test_has 'status=existing'
assert_runtime 'init existing has no writes' test "$before" = "$(hrt_test_stamp "$P")"
# Pending tasks are not bounded by the requested number of recent logs.
awk '$0=="<!-- /hx:pending -->" { print "- [ ] TODO_ACTIVE"; print "- [ ] TODO_BLOCKED (depends on approval)"; print "- [ ] TODO_DEFERRED (intentionally postponed)" } { print }' "$P/$HX_MAIN_FILE" > "$BOX/pending-main"
cat "$BOX/pending-main" > "$P/$HX_MAIN_FILE"
hrt_test_run "$P" recall
for todo in TODO_ACTIVE TODO_BLOCKED TODO_DEFERRED; do
    assert_runtime "all pending states retained: $todo" hrt_test_has "$todo"
done
assert_runtime 'empty recall succeeds' test "$RC" -eq 0
assert_runtime 'default request' hrt_test_has requested=6
assert_runtime 'zero actual' hrt_test_has actual=0
assert_runtime 'overview retained' hrt_test_has 'Project Overview'
assert_runtime 'fresh template does not masquerade instructions as state' hrt_test_lacks 'Unanchored Current State context'
assert_runtime 'current state retained' hrt_test_has 'Current State'
assert_runtime 'gotchas deferred source retained' hrt_test_has "$HX_GOTCHAS_FILE"
assert_runtime 'unread material is disclosed' hrt_test_has 'deferred_sources='
assert_runtime 'unread decision bodies disclosed' hrt_test_has 'decision bodies'
assert_runtime 'gotchas body is not replayed' hrt_test_lacks "$(cat "$P/$HX_GOTCHAS_FILE")"
for retained in '## 🏗 Architecture' '## 🔑 Coding Conventions' '## 🛠 Build / Run / Test' '## 🔍 Open Questions / Mysteries'; do
    assert_runtime "optional section excluded: $retained" hrt_test_lacks "$retained"
done
assert_runtime 'no log means no invented handoff date' hrt_test_has 'handoff_time_status=no_logs'
for omitted in '## 🚀 Quick Start' '## 🔐 Credentials' '## 🧪 Testing' '## 📚 References' '## ✨ Features'; do
    assert_runtime "layering excludes $omitted" hrt_test_lacks "$omitted"
done

# Lexical timestamps intentionally disagree with sequence; newest is number 8.
for i in 1 2 3 4 5 6 7 8; do
    printf -v number '%04d' "$i"
    printf -- '---\nschema: 2\nnumber: %s\n---\nENTRY_%s 中文正文\nlast_%s\n' "$number" "$i" "$i" > "$P/$HX_LOGS_DIR/$number-2000-01-01-中文 log.md"
done
printf 'DECISION_BODY_MUST_NOT_LEAK\n' > "$P/$HX_DEC_DIR/0001-choice.md"
mkdir "$P/unrelated-directory"
printf 'UNRELATED_CONTENT_MUST_NOT_LEAK\n' > "$P/unrelated-directory/secret"
for arg in '3。说明' '3 说明' '0003 中文尾注' '3？' '  3。说明' $'\t3。说明' $' \t\r\n\v\f3。说明'; do
    hrt_test_run "$P" recall "$arg"
    assert_runtime "raw argument $arg" test "$RC" -eq 0
    assert_runtime "requested 3: $arg" hrt_test_has requested=3
    assert_runtime "actual 3: $arg" hrt_test_has actual=3
    assert_runtime 'newest whole log' hrt_test_has last_8
    assert_runtime 'third newest included' hrt_test_has ENTRY_6
    assert_runtime 'older logs excluded' hrt_test_lacks ENTRY_5
done
assert_runtime 'newest first' test "$(printf '%s\n' "$OUT" | grep '^ENTRY_' | sed -n '1p')" = 'ENTRY_8 中文正文'
assert_runtime 'decision bodies not read' hrt_test_lacks DECISION_BODY_MUST_NOT_LEAK
assert_runtime 'unrelated file not read' hrt_test_lacks UNRELATED_CONTENT_MUST_NOT_LEAK
for arg in '' '说明' '中文 3' '  说明' $' \t'; do
    hrt_test_run "$P" recall "$arg"
    assert_runtime "non-numeric prefix defaults: $arg" test "$RC" -eq 0
    assert_runtime 'default six logs' hrt_test_has actual=6
done
for arg in 0 '000。说明' -1 '-3 说明' +3 '  0。说明' $'\t-3 说明' $' \t+3' ' 2147483648' '2147483648' '9999999999999999999999999999999999999'; do
    hrt_test_run "$P" recall "$arg"
    hrt_test_bad "invalid count $arg"
done
hrt_test_run "$P" recall '2147483647 尾注'
assert_runtime 'maximum accepted' test "$RC" -eq 0
assert_runtime 'requested differs from actual' hrt_test_has requested=2147483647
assert_runtime 'actual limited to existing entries' hrt_test_has actual=8
hrt_test_run "$P" recall 3 extra
hrt_test_bad 'extra argv rejected (one raw string only)'

before=$(hrt_test_stamp "$P")
mkdir "$BOX/forbidden"
for tool in git find tree mkdir mktemp touch cp mv rm; do
    printf '#!/bin/bash\necho forbidden-%s >&2\nexit 99\n' "$tool" > "$BOX/forbidden/$tool"
    chmod +x "$BOX/forbidden/$tool"
done
saved_path=$PATH
PATH="$BOX/forbidden:$PATH"
sleep 1
hrt_test_run "$P" recall 3
PATH=$saved_path
assert_runtime 'recall no git/tree/find/write commands' test "$RC" -eq 0
assert_runtime 'recall content and mtimes unchanged' test "$before" = "$(hrt_test_stamp "$P")"

# Recency comes from the newest numbered log metadata, never file mtime.
TIMEP="$BOX/time-context"; mkdir "$TIMEP"; hrt_test_fixture "$TIMEP"
mkdir "$BOX/clock-bin"
REAL_DATE=$(command -v date); export REAL_DATE
cat > "$BOX/clock-bin/date" <<'CLOCK'
#!/bin/bash
if [ "$*" = '+%Y-%m-%d %H:%M|%s' ]; then
    [ "$HX_FIXTURE_CLOCK" != fail ] || exit 1
    printf '2000-01-05 03:04|%s\n' "$HX_FIXTURE_CLOCK"
else
    exec "$REAL_DATE" "$@"
fi
CLOCK
chmod +x "$BOX/clock-bin/date"
export HX_FIXTURE_CLOCK=947041440
saved_path=$PATH; PATH="$BOX/clock-bin:$PATH"
for scenario in elapsed elapsed_utc same_day future missing invalid duplicate clock_failure; do
    epoch=946684800
    case "$scenario" in
        same_day) epoch=947030400 ;;
        future) epoch=947041500 ;;
        missing) epoch='' ;;
        invalid) epoch='not-a-time' ;;
        clock_failure) HX_FIXTURE_CLOCK=fail ;;
    esac
    { printf -- '---\ndate: 2000-01-01T00:00\n';
      [ -z "$epoch" ] || printf 'epoch: %s\n' "$epoch"
      [ "$scenario" != duplicate ] || printf 'epoch: 946684800\n'
      printf -- '---\nLATEST_HANDOFF_CONTENT\n';
    } > "$TIMEP/$HX_LOGS_DIR/0002-2000-01-01T0000-latest.md"
    printf -- '---\nepoch: 9999999999\n---\nOLDER_RECORD\n' > "$TIMEP/$HX_LOGS_DIR/0001-2099-01-01T0000-older.md"
    before=$(hrt_test_stamp "$TIMEP")
    if [ "$scenario" = elapsed_utc ]; then TZ=UTC hrt_test_run "$TIMEP" recall 1
    else hrt_test_run "$TIMEP" recall 1; fi
    assert_runtime "$scenario: context remains available" test "$RC" -eq 0
    assert_runtime "$scenario: newest log is still read" hrt_test_has LATEST_HANDOFF_CONTENT
    assert_runtime "$scenario: no filesystem mutations" test "$before" = "$(hrt_test_stamp "$TIMEP")"
    case "$scenario" in
        elapsed|elapsed_utc)
            assert_runtime 'timestamp is explicit UTC, independent of file name/mtime' hrt_test_has 'last_handoff_at=2000-01-01T00:00:00Z'
            assert_runtime 'current clock is reported' hrt_test_has 'recall_now=2000-01-05T03:04:00Z'
            assert_runtime 'four complete 24-hour days elapsed' hrt_test_has 'elapsed_days=4'
            assert_runtime 'remaining hours after full days' hrt_test_has 'elapsed_hours=3'
            assert_runtime 'remaining minutes after hours' hrt_test_has 'elapsed_minutes=4' ;;
        same_day)
            assert_runtime 'less than a day is zero complete days' hrt_test_has 'elapsed_days=0'
            assert_runtime 'same-day hours still reported' hrt_test_has 'elapsed_hours=3' ;;
        future)
            assert_runtime 'future timestamp is flagged, not clamped to zero' hrt_test_has 'handoff_time_status=future'
            assert_runtime 'future timestamp has no fabricated days' hrt_test_lacks 'elapsed_days=' ;;
        missing)
            assert_runtime 'old date without timezone stays visible' hrt_test_has 'last_handoff_recorded=2000-01-01T00:00'
            assert_runtime 'missing epoch explicitly unknown' hrt_test_has 'handoff_time_status=date_only'
            assert_runtime 'no mtime fallback for missing epoch' hrt_test_lacks 'elapsed_days=' ;;
        invalid|duplicate)
            assert_runtime 'bad epoch metadata explicitly flagged' hrt_test_has 'handoff_time_status=invalid_epoch' ;;
        clock_failure)
            assert_runtime 'unavailable clock does not invent elapsed time' hrt_test_has 'handoff_time_status=clock_unavailable' ;;
    esac
done
PATH=$saved_path; unset HX_FIXTURE_CLOCK REAL_DATE

cp "$P/$HX_LOGS_DIR/0008-2000-01-01-中文 log.md" "$P/$HX_LOGS_DIR/8-conflict.md"
for cmd in recall init; do
    hrt_test_run "$P" "$cmd"
    hrt_test_bad "$cmd duplicate numeric identity (0008 vs 8)"
done
rm "$P/$HX_LOGS_DIR/8-conflict.md"
for key in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR"; do
    mv "$P/$key" "$P/saved"
    for target in "$P/saved" "$P/nonexistent"; do
        ln -s "$target" "$P/$key"
        for cmd in recall init; do
            hrt_test_run "$P" "$cmd"
            hrt_test_bad "$cmd rejects $key link to $target"
        done
        rm "$P/$key"
    done
    hrt_test_run "$P" recall
    hrt_test_bad "recall missing $key"
    mv "$P/saved" "$P/$key"
done
ln -s "$P/$HX_GOTCHAS_FILE" "$P/$HX_LOGS_DIR/0099-linked.md"
hrt_test_run "$P" recall 1
hrt_test_bad 'numbered log symlink even beyond requested scope'
rm "$P/$HX_LOGS_DIR/0099-linked.md"
ln -s "$P" "$BOX/root-link"
hrt_test_run "$BOX" init --root "$BOX/root-link/"
hrt_test_bad 'root symlink with trailing slash'
hrt_test_run "$BOX" init --root "$BOX/root-link/../空格 project 中文"
hrt_test_bad 'symlink ancestor before dotdot'
hrt_test_run "$BOX" init --root "$BOX/does-not-exist"
hrt_test_bad 'missing root is not created'
hrt_test_run "$BOX" init --root "$P/user.txt"
hrt_test_bad 'file is not root directory'

Q="$BOX/partial"
mkdir "$Q"
cp "$P/$HX_MAIN_FILE" "$Q/$HX_MAIN_FILE"
printf '\nUSER_MAIN_CONTENT\n' >> "$Q/$HX_MAIN_FILE"
before=$(cksum "$Q/$HX_MAIN_FILE")
hrt_test_run "$Q" init
assert_runtime 'fill missing pieces' test "$RC" -eq 0
assert_runtime 'existing main never changed' test "$before" = "$(cksum "$Q/$HX_MAIN_FILE")"
printf '\nUSER_GOTCHA\n' >> "$Q/$HX_GOTCHAS_FILE"
rm "$Q/$HX_MAIN_FILE"
before=$(cksum "$Q/$HX_GOTCHAS_FILE")
hrt_test_run "$Q" init
assert_runtime 'missing main filled around user gotchas' test "$RC" -eq 0
assert_runtime 'user gotchas preserved' test "$before" = "$(cksum "$Q/$HX_GOTCHAS_FILE")"

for kind in legacy mixed invalid-main wrong-dir duplicate; do
    Q="$BOX/$kind"; mkdir "$Q"
    case "$kind" in
        legacy) printf 'legacy\n' > "$Q/$HX_LEGACY_MAIN_FILE" ;;
        mixed) hrt_test_fixture "$Q"; mkdir "$Q/$HX_LEGACY_LOGS_DIR" ;;
        invalid-main) printf 'USER UNKNOWN DOCUMENT\n' > "$Q/$HX_MAIN_FILE" ;;
        wrong-dir) printf 'not a directory\n' > "$Q/$HX_DEC_DIR" ;;
        duplicate) mkdir "$Q/$HX_LOGS_DIR"; touch "$Q/$HX_LOGS_DIR/0001-a.md" "$Q/$HX_LOGS_DIR/0001-b.md" ;;
    esac
    before=$(ls -a "$Q")
    for cmd in recall init; do
        hrt_test_run "$Q" "$cmd"
        hrt_test_bad "$kind: $cmd"
    done
    assert_runtime "$kind: preflight creates nothing" test "$before" = "$(ls -a "$Q")"
done
if [ "$(id -u)" -ne 0 ]; then
    for key in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR" "$HX_LOGS_DIR/0008-2000-01-01-中文 log.md"; do
        chmod 000 "$P/$key"
        for cmd in recall init; do
            hrt_test_run "$P" "$cmd"; hrt_test_bad "$cmd unreadable $key"
        done
        chmod u+rwX "$P/$key"
    done
else
    printf '  ➖ SKIPPED: unreadable permission tests require non-root\n'
fi

# reply counts Unicode code points, not UTF-8 bytes or grapheme clusters.
text120=''
for ((i=0; i<120; i++)); do text120="${text120}中"; done
for text in ' 中文 reply -- 100% ' "$text120" '😀é'; do
    hrt_test_run "$BOX" reply --text "$text"
    assert_runtime 'reply accepted' test "$RC" -eq 0
    printf '%s' "$text" > "$BOX/expected"
    assert_runtime 'reply exact bytes, no newline/prefix' cmp -s "$BOX/expected" "$BOX/out"
    assert_runtime 'reply no extra diagnostic' test -z "$ERR"
done
for text in '' "${text120}中" $'one\ntwo' $'one\rtwo' $'one\n' 'one two' $'\xff' $'\xc0\xaf' $'\xed\xa0\x80' $'\xf4\x90\x80\x80'; do
    hrt_test_run "$BOX" reply --text "$text"
    hrt_test_bad 'reply invalid/empty/multiline/121/UTF-8'
done
emoji120=''; for ((i=0; i<120; i++)); do emoji120="${emoji120}😀"; done
hrt_test_run "$BOX" reply --text "$emoji120"
assert_runtime '120 supplementary code points' test "$RC" -eq 0
hrt_test_run "$BOX" reply --text "${emoji120}x"
hrt_test_bad '121 supplementary code points'
hrt_test_run "$BOX" reply --text x extra
hrt_test_bad 'reply extra arguments'
hrt_test_run "$BOX" reply --wrong x
hrt_test_bad 'reply wrong flag'
hrt_test_run "$BOX" init --root
hrt_test_bad 'init missing root argument'
hrt_test_run "$BOX" unknown
hrt_test_bad 'unknown command'
hrt_test_run "$BOX"
hrt_test_bad 'missing command'

# A late missing template must not leave either directory or a main behind.
REAL_RT=$RT
PKG="$BOX/isolated skill"
mkdir -p "$PKG/scripts" "$PKG/assets"
cp "$RT" "$PKG/scripts/handoff-runtime.sh"
cp -R "$ROOT/scripts/lib" "$PKG/scripts/lib"
cp "$ASSETS/HANDOFFX.template.md" "$PKG/assets/HANDOFFX.template.md"
RT="$PKG/scripts/handoff-runtime.sh"
Q="$BOX/template failure"; mkdir "$Q"
hrt_test_run "$Q" init
hrt_test_bad 'missing second template'
assert_runtime 'all templates checked before writes' test -z "$(ls -A "$Q")"
RT=$REAL_RT

Q="$BOX/section validation"; hrt_test_fixture "$Q"
printf '\n## 🎯 Current State\nDUPLICATE\n' >> "$Q/$HX_MAIN_FILE"
hrt_test_run "$Q" recall
hrt_test_bad 'duplicate required section'
cp "$ASSETS/HANDOFFX.template.md" "$Q/$HX_MAIN_FILE"
sed '/^## .*Current State$/d' "$Q/$HX_MAIN_FILE" > "$BOX/reduced"
cp "$BOX/reduced" "$Q/$HX_MAIN_FILE"
hrt_test_run "$Q" recall
hrt_test_bad 'missing required section'
cp "$ASSETS/HANDOFFX.template.md" "$Q/$HX_MAIN_FILE"
printf 'private decision one\n' > "$Q/$HX_DEC_DIR/0001-a.md"
printf 'private decision two\n' > "$Q/$HX_DEC_DIR/0001-b.md"
for cmd in recall init; do
    hrt_test_run "$Q" "$cmd"; hrt_test_bad "$cmd conflicting decisions"
done
rm "$Q/$HX_DEC_DIR/0001-b.md"
if [ "$(id -u)" -ne 0 ]; then
    chmod a-w "$Q" "$Q/$HX_MAIN_FILE" "$Q/$HX_GOTCHAS_FILE" "$Q/$HX_LOGS_DIR" "$Q/$HX_DEC_DIR"
    hrt_test_run "$Q" init
    assert_runtime 'complete read-only layout init succeeds' test "$RC" -eq 0
    hrt_test_run "$Q" recall
    assert_runtime 'read-only layout recall succeeds' test "$RC" -eq 0
    chmod u+w "$Q" "$Q/$HX_MAIN_FILE" "$Q/$HX_GOTCHAS_FILE" "$Q/$HX_LOGS_DIR" "$Q/$HX_DEC_DIR"
else
    printf '  ➖ SKIPPED: read-only mode-bit layout tests require non-root\n'
fi

# Installed mirror resolves its own ../assets, independent of checkout entry.
Q="$BOX/mirror project"; mkdir "$Q"
RT=$MIRROR
# A distributed skill copy without a manifest must name its write root (#7).
hrt_test_run "$Q" init
assert_runtime 'mirror unbound init without --expect-root is refused' test "$RC" -eq 2
hrt_test_run "$Q" --expect-root "$(cd "$Q" && pwd -P)" init
assert_runtime 'mirror init assets resolution' test "$RC" -eq 0
hrt_test_run "$Q" recall
assert_runtime 'mirror recall' test "$RC" -eq 0
hrt_test_run "$Q" reply --text 中文
assert_runtime 'mirror reply' test "$OUT" = 中文
# Deny all filesystem writes, not just writes to the fixture. Bash 3.2
# heredocs previously failed here even though content/mtime tests were green.
if command -v sandbox-exec >/dev/null 2>&1; then
    policy='(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))'
    RC=0
    # Expand the probe path only inside the sandboxed child shell.
    # shellcheck disable=SC2016
    sandbox-exec -p "$policy" /bin/bash -c 'printf denied > "$1"' _ "$BOX/denied-write" > "$BOX/out" 2> "$BOX/err" || RC=$?
    assert_runtime 'sandbox really denies file writes' test "$RC" -ne 0
    assert_runtime 'sandbox write probe created nothing' test ! -e "$BOX/denied-write"
    EMPTY="$BOX/sandbox empty 中文"; hrt_test_fixture "$EMPTY"
    for runtime in "$REAL_RT" "$MIRROR"; do
        for project in "$P" "$EMPTY"; do
            before=$(hrt_test_stamp "$project")
            RC=0
            (cd "$project" && sandbox-exec -p "$policy" /bin/bash "$runtime" recall $' \t3。只读') > "$BOX/out" 2> "$BOX/err" || RC=$?
            OUT=$(cat "$BOX/out"); ERR=$(cat "$BOX/err")
            assert_runtime 'Bash strict sandbox recall succeeds' test "$RC" -eq 0
            assert_runtime 'sandbox recall has no stderr' test -z "$ERR"
            assert_runtime 'sandbox whitespace-tail request parsed' hrt_test_has requested=3
            if [ "$project" = "$P" ]; then
                assert_runtime 'sandbox latest three entries' hrt_test_has actual=3
                assert_runtime 'sandbox outputs complete latest log' hrt_test_has last_8
                assert_runtime 'sandbox excludes fourth latest' hrt_test_lacks ENTRY_5
            else
                assert_runtime 'sandbox empty log is normal' hrt_test_has actual=0
            fi
            assert_runtime 'sandbox preserves files and mtimes' test "$before" = "$(hrt_test_stamp "$project")"
        done
    done
else
    printf '  ➖ SKIPPED: strict deny-write regression requires macOS sandbox-exec\n'
fi

# Bounded recall contract: use deliberately small, deterministic state instead
# of depending on prose or placeholders in the evolving initialization template.
hrt_test_compact_fixture() {
    hrt_test_fixture "$1"
    cat > "$1/$HX_MAIN_FILE" <<'MAIN'
<!-- HANDOFF v2 schema -->
# Bounded recall fixture
## Project Overview
OVERVIEW_KEEP
## Current State
<!-- hx:recent -->
STOP_POINT_KEEP
NEXT_STEP_KEEP
CONSTRAINT_KEEP_USER_APPROVAL
<!-- /hx:recent -->
<!-- hx:pending -->
- [ ] OLD_OPEN_FROM_LOG_0001 owner=Alice blocked=approval dependency=external
  OLD_OPEN_CONTEXT_KEEP
- [ ] DEFERRED_KEEP intentionally postponed
<!-- /hx:pending -->
<!-- hx:done -->
DONE_BODY_MUST_NOT_LEAK
<!-- /hx:done -->
## Known Gotchas
GOTCHAS_POINTER_ONLY GOTCHAS.md
## Decision Log
DECISION_POINTER_ONLY Handoffx_Decisions/
## Development Log
LOG_POINTER_ONLY Handoffx_Logs/
## Architecture
OPTIONAL_ARCHITECTURE_MUST_NOT_LEAK
## Coding Conventions
OPTIONAL_CONVENTIONS_MUST_NOT_LEAK
## Build / Run / Test
OPTIONAL_BUILD_MUST_NOT_LEAK
## Open Questions / Mysteries
OPTIONAL_QUESTIONS_MUST_NOT_LEAK
MAIN
    printf 'GOTCHAS_BODY_MUST_NOT_LEAK\n' > "$1/$HX_GOTCHAS_FILE"
}
hrt_test_replace_section() {
    local project="$1" heading="$2" body="$3"
    awk -v heading="$heading" -v body="$body" '
        /^## / { skip=0 }
        $0=="## " heading {
            print; while ((getline line < body)>0) print line
            close(body); skip=1; next
        }
        !skip { print }
    ' "$project/$HX_MAIN_FILE" > "$BOX/replaced-main"
    cat "$BOX/replaced-main" > "$project/$HX_MAIN_FILE"
}
hrt_test_repeat() {
    # Explicit UTF-8 strings allow byte-limit tests independent of LC_CTYPE.
    awk -v count="$1" -v text="$2" 'BEGIN { for(i=0;i<count;i++) printf "%s",text; printf "\n" }'
}
hrt_test_bounded_suite() {
    local tag="$1" q file before i number variant baseline_bytes reader real_reader saved_reader_path text
    q="$BOX/bounded-$tag"; hrt_test_compact_fixture "$q"
    for i in 1 2 3 4 5 6 7 8; do
        printf -v number '%04d' "$i"
        printf 'ENTRY_%s\n' "$number" > "$q/$HX_LOGS_DIR/$number-old.md"
    done
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall
    assert_runtime "$tag compact mode metadata" hrt_test_has recall_mode=compact
    assert_runtime "$tag budget metadata" hrt_test_has budget_bytes=24576
    assert_runtime "$tag payload byte metadata" hrt_test_has payload_bytes=
    assert_runtime "$tag loaded log count" hrt_test_has loaded_logs=6
    assert_runtime "$tag default newest six" test "$(printf '%s\n' "$OUT" | grep '^ENTRY_' || :)" = \
        $'ENTRY_0008\nENTRY_0007\nENTRY_0006\nENTRY_0005\nENTRY_0004\nENTRY_0003'
    for text in OLD_OPEN_FROM_LOG_0001 OLD_OPEN_CONTEXT_KEEP DEFERRED_KEEP STOP_POINT_KEEP NEXT_STEP_KEEP CONSTRAINT_KEEP_USER_APPROVAL; do
        assert_runtime "$tag old or gated current context survives: $text" hrt_test_has "$text"
    done
    for text in GOTCHAS_BODY_MUST_NOT_LEAK DONE_BODY_MUST_NOT_LEAK OPTIONAL_ARCHITECTURE_MUST_NOT_LEAK OPTIONAL_CONVENTIONS_MUST_NOT_LEAK OPTIONAL_BUILD_MUST_NOT_LEAK OPTIONAL_QUESTIONS_MUST_NOT_LEAK; do
        assert_runtime "$tag excluded body: $text" hrt_test_lacks "$text"
    done
    assert_runtime "$tag compact recall never rewrites files" test "$before" = "$(hrt_test_stamp "$q")"

    # A completed item with descendant prose retains context; independent
    # prose/bold group headings and open children must not be swallowed.
    cat > "$BOX/state" <<'STATE'
<!-- hx:recent -->
RECENT_KEEP
<!-- /hx:recent -->
<!-- hx:pending -->
- [x] CHECKED_LOWER_HIDE
  CHECKED_CONTINUATION_HIDE
    CHECKED_DEEP_CONTINUATION_HIDE
INDEPENDENT_PROSE_KEEP
- [X] CHECKED_UPPER_HIDE
  CHECKED_UPPER_CONTINUATION_HIDE
**BOLD_GROUP_KEEP**
- [x] CHECKED_PARENT_HIDE
  CHECKED_PARENT_DETAIL_HIDE
  - [ ] NESTED_OPEN_KEEP owner=Bob dependency=review
    NESTED_OPEN_DETAIL_KEEP
- [ ] OPEN_AFTER_CHECKED_KEEP
  OPEN_AFTER_DETAIL_KEEP
- [x] CHECKED_BEFORE_HEADING_HIDE
  CHECKED_BEFORE_HEADING_DETAIL_HIDE
### NEXT_GROUP_KEEP
UNRESOLVED_PROSE_KEEP (the word completed is not a checkbox)
<!-- /hx:pending -->
<!-- hx:done -->
DONE_BODY_MUST_NOT_LEAK
<!-- /hx:done -->
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall 1
    assert_runtime "$tag pending filtering succeeds" test "$RC" -eq 0
    for text in INDEPENDENT_PROSE_KEEP BOLD_GROUP_KEEP NESTED_OPEN_KEEP NESTED_OPEN_DETAIL_KEEP OPEN_AFTER_CHECKED_KEEP OPEN_AFTER_DETAIL_KEEP NEXT_GROUP_KEEP UNRESOLVED_PROSE_KEEP; do
        assert_runtime "$tag pending preserves $text" hrt_test_has "$text"
    done
    for text in CHECKED_LOWER_HIDE CHECKED_CONTINUATION_HIDE CHECKED_DEEP_CONTINUATION_HIDE CHECKED_UPPER_HIDE CHECKED_UPPER_CONTINUATION_HIDE CHECKED_PARENT_HIDE CHECKED_PARENT_DETAIL_HIDE CHECKED_BEFORE_HEADING_HIDE CHECKED_BEFORE_HEADING_DETAIL_HIDE; do
        assert_runtime "$tag pending keeps checked-parent context $text" hrt_test_has "$text"
    done
    assert_runtime "$tag historical done block still excluded" hrt_test_lacks DONE_BODY_MUST_NOT_LEAK

    # Large excluded sections and old histories do not consume the payload.
    q="$BOX/large-$tag"; hrt_test_compact_fixture "$q"
    awk -v dir="$q/$HX_LOGS_DIR" 'BEGIN {
        for (i=1;i<=200;i++) {
            path=sprintf("%s/%04d-old.md",dir,i)
            if(i<=194) for(j=0;j<400;j++) print "ANCIENT_BODY_MUST_NOT_LEAK" > path
            else print "RECENT_ENTRY_" i > path
            close(path)
        }
    }'
    hrt_test_run "$q" recall
    assert_runtime "$tag 200-log fixture succeeds" test "$RC" -eq 0
    baseline_bytes=$(LC_ALL=C wc -c < "$BOX/out")
    { printf '<!-- hx:recent -->\nSTOP_POINT_KEEP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n- [ ] OLD_OPEN_FROM_LOG_0001\n<!-- /hx:pending -->\n<!-- hx:done -->\n'
      hrt_test_repeat 20000 'HUGE_DONE_HIDE '
      printf '<!-- /hx:done -->\n'; } > "$BOX/state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_repeat 20000 'GOTCHAS_BODY_MUST_NOT_LEAK ' > "$q/$HX_GOTCHAS_FILE"
    hrt_test_repeat 20000 'OPTIONAL_ARCHITECTURE_MUST_NOT_LEAK ' > "$BOX/optional"
    hrt_test_replace_section "$q" Architecture "$BOX/optional"
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall
    assert_runtime "$tag huge done/gotchas/optional sections succeed" test "$RC" -eq 0
    assert_runtime "$tag excluded growth does not grow output" test "$(LC_ALL=C wc -c < "$BOX/out")" -le "$baseline_bytes"
    assert_runtime "$tag old open task survives 200 histories" hrt_test_has OLD_OPEN_FROM_LOG_0001
    assert_runtime "$tag last sixth included" hrt_test_has RECENT_ENTRY_195
    for text in ANCIENT_BODY_MUST_NOT_LEAK HUGE_DONE_HIDE GOTCHAS_BODY_MUST_NOT_LEAK OPTIONAL_ARCHITECTURE_MUST_NOT_LEAK; do
        assert_runtime "$tag large excluded body stays excluded: $text" hrt_test_lacks "$text"
    done
    assert_runtime "$tag huge files are immutable" test "$before" = "$(hrt_test_stamp "$q")"

    # Intercept common external content readers, not access(2): a macOS
    # file-read-data denial also makes the required -r preflight fail, so that
    # sandbox cannot distinguish stat/readability checks from opening content.
    # This probe covers these readers; strict deny-write tests above are separate.
    mkdir "$BOX/read-guard-$tag"
    for reader in cat awk sed grep head tail dd iconv cut sort wc; do
        real_reader=$(command -v "$reader")
        { printf '#!/bin/bash\nfor arg in "$@"; do\n'
          printf 'case "$arg" in GOTCHAS.md|*/GOTCHAS.md) echo forbidden-gotchas-content-read >&2; exit 99 ;; esac\ndone\n'
          printf 'exec %q "$@"\n' "$real_reader"
        } > "$BOX/read-guard-$tag/$reader"
        chmod +x "$BOX/read-guard-$tag/$reader"
    done
    saved_reader_path=$PATH
    PATH="$BOX/read-guard-$tag:$PATH"
    RC=0; cat "$q/$HX_GOTCHAS_FILE" > "$BOX/out" 2> "$BOX/err" || RC=$?
    assert_runtime "$tag content-reader guard rejects GOTCHAS reads" test "$RC" -eq 99
    hrt_test_run "$q" recall
    PATH=$saved_reader_path
    assert_runtime "$tag recall uses no guarded GOTCHAS content reader" test "$RC" -eq 0
    assert_runtime "$tag guarded recall has no ignored read error" test -z "$ERR"

    q="$BOX/log-bounds-$tag"; hrt_test_compact_fixture "$q"
    file="$q/$HX_LOGS_DIR/0001-detail.md"
    { printf -- '---\nschema: 2\nnumber: 0001\ndate: 2000-01-01T00:00\nepoch: 946684800\ntitle: METADATA_TITLE_KEEP\n---\nOUTSIDE_BEFORE_HIDE\n<!-- hx:recall -->\nSUMMARY_KEEP 中文😀\n<!-- /hx:recall -->\n'
      hrt_test_repeat 5000 'OUTSIDE_AFTER_HIDE '; } > "$file"
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall
    assert_runtime "$tag valid summary succeeds" test "$RC" -eq 0
    for text in log_status=summary SUMMARY_KEEP METADATA_TITLE_KEEP 'date: 2000-01-01T00:00' 'last_handoff_at=2000-01-01T00:00:00Z'; do
        assert_runtime "$tag summary and metadata retained: $text" hrt_test_has "$text"
    done
    assert_runtime "$tag text before summary is not replayed" hrt_test_lacks OUTSIDE_BEFORE_HIDE
    assert_runtime "$tag text after summary is not replayed" hrt_test_lacks OUTSIDE_AFTER_HIDE
    assert_runtime "$tag summary recall immutable" test "$before" = "$(hrt_test_stamp "$q")"

    # 2048 is an inclusive byte cap, not a character cap.
    { printf '<!-- hx:recall -->\n'; hrt_test_repeat 2047 s; printf '<!-- /hx:recall -->\n'; } > "$file"
    hrt_test_run "$q" recall
    assert_runtime "$tag exactly 2048-byte summary accepted" test "$RC" -eq 0
    assert_runtime "$tag exact summary kept whole" hrt_test_has "$(hrt_test_repeat 2047 s)"
    hrt_test_repeat 2047 l > "$file"
    hrt_test_run "$q" recall
    assert_runtime "$tag exactly 2048-byte legacy log accepted" test "$RC" -eq 0
    assert_runtime "$tag short legacy full status" hrt_test_has log_status=legacy_short_full
    assert_runtime "$tag short legacy last byte retained" hrt_test_has "$(hrt_test_repeat 2047 l)"
    { printf -- '---\ndate: 2000-01-01T00:00\ntitle: LEGACY_TITLE_KEEP\n---\n'; hrt_test_repeat 700 中; printf 'LONG_LEGACY_BODY_HIDE\n'; } > "$file"
    hrt_test_run "$q" recall
    assert_runtime "$tag long UTF-8 legacy degrades successfully" test "$RC" -eq 0
    assert_runtime "$tag legacy degradation explicit" hrt_test_has log_status=legacy_metadata_only
    assert_runtime "$tag long legacy title retained" hrt_test_has LEGACY_TITLE_KEEP
    assert_runtime "$tag long legacy path retained" hrt_test_has 0001-detail.md
    assert_runtime "$tag long legacy body excluded" hrt_test_lacks LONG_LEGACY_BODY_HIDE
    assert_runtime "$tag UTF-8 length is bytes not characters" hrt_test_lacks '中中中'

    # A malformed OLDER selected log must not leak an already valid newer one.
    printf 'VALID_NEWER_MUST_NOT_PARTIALLY_ESCAPE\n' > "$q/$HX_LOGS_DIR/0002-valid.md"
    for variant in missing_close orphan_close duplicate nested reversed empty whitespace oversized_ascii oversized_utf8; do
        case "$variant" in
            missing_close) printf '<!-- hx:recall -->\nBROKEN\n' > "$file" ;;
            orphan_close) printf 'BROKEN\n<!-- /hx:recall -->\n' > "$file" ;;
            duplicate) printf '<!-- hx:recall -->\na\n<!-- /hx:recall -->\n<!-- hx:recall -->\nb\n<!-- /hx:recall -->\n' > "$file" ;;
            nested) printf '<!-- hx:recall -->\na\n<!-- hx:recall -->\nb\n<!-- /hx:recall -->\n<!-- /hx:recall -->\n' > "$file" ;;
            reversed) printf '<!-- /hx:recall -->\na\n<!-- hx:recall -->\n' > "$file" ;;
            empty) printf '<!-- hx:recall -->\n<!-- /hx:recall -->\n' > "$file" ;;
            whitespace) printf '<!-- hx:recall -->\n \t\n<!-- /hx:recall -->\n' > "$file" ;;
            oversized_ascii) { printf '<!-- hx:recall -->\n'; hrt_test_repeat 2048 a; printf '<!-- /hx:recall -->\n'; } > "$file" ;;
            oversized_utf8) { printf '<!-- hx:recall -->\n'; hrt_test_repeat 700 中; printf '<!-- /hx:recall -->\n'; } > "$file" ;;
        esac
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        hrt_test_bad "$tag malformed summary $variant"
        assert_runtime "$tag rejected summary $variant not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
    done

    q="$BOX/state-bounds-$tag"; hrt_test_compact_fixture "$q"
    for variant in anchored_ascii anchored_utf8 legacy_ascii legacy_utf8; do
        { case "$variant" in anchored_*) printf '<!-- hx:recent -->\nRECENT_KEEP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n' ;; esac
          printf -- '- [ ] REQUIRED_OPEN_TASK '
          case "$variant" in *_ascii) hrt_test_repeat 12300 a ;; *_utf8) hrt_test_repeat 4200 中 ;; esac
          case "$variant" in anchored_*) printf '<!-- /hx:pending -->\n' ;; esac
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        hrt_test_bad "$tag over-budget state $variant"
        assert_runtime "$tag over-budget state unchanged: $variant" test "$before" = "$(hrt_test_stamp "$q")"
    done
    printf 'LEGACY_STATE_CONTEXT_KEEP\n- [ ] LEGACY_OPEN_KEEP\n- [x] LEGACY_DONE_NOT_INFERRED\n' > "$BOX/state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag bounded unanchored legacy state succeeds" test "$RC" -eq 0
    for text in LEGACY_STATE_CONTEXT_KEEP LEGACY_OPEN_KEEP LEGACY_DONE_NOT_INFERRED; do
        assert_runtime "$tag unanchored state kept conservatively: $text" hrt_test_has "$text"
    done
    for variant in missing_end duplicate nested partial; do
        case "$variant" in
            missing_end) printf '<!-- hx:recent -->\nRECENT\n' > "$BOX/state" ;;
            duplicate) printf '<!-- hx:recent -->\na\n<!-- /hx:recent -->\n<!-- hx:recent -->\nb\n<!-- /hx:recent -->\n<!-- hx:pending -->\nc\n<!-- /hx:pending -->\n' > "$BOX/state" ;;
            nested) printf '<!-- hx:recent -->\n<!-- hx:pending -->\nx\n<!-- /hx:pending -->\n<!-- /hx:recent -->\n' > "$BOX/state" ;;
            partial) printf '<!-- hx:pending -->\n- [ ] OPEN\n<!-- /hx:pending -->\n' > "$BOX/state" ;;
        esac
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        hrt_test_run "$q" recall
        hrt_test_bad "$tag malformed state anchors $variant"
    done

    # Anchors must not silently hide an open task outside pending, including
    # one mislabeled as done. Fenced examples are data, not active tasks.
    for variant in recent "done" outside; do
        q="$BOX/misplaced-$tag-$variant"; hrt_test_compact_fixture "$q"
        { printf '<!-- hx:recent -->\nRECENT_KEEP\n'
          [ "$variant" != recent ] || printf -- '- [ ] MISPLACED_OPEN_MUST_NOT_VANISH\n'
          printf '<!-- /hx:recent -->\n<!-- hx:pending -->\n- [ ] VALID_PENDING\n<!-- /hx:pending -->\n<!-- hx:done -->\n'
          [ "$variant" != "done" ] || printf -- '- [ ] MISPLACED_OPEN_MUST_NOT_VANISH\n'
          printf '<!-- /hx:done -->\n'
          [ "$variant" != outside ] || printf -- '- [ ] MISPLACED_OPEN_MUST_NOT_VANISH\n'
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        hrt_test_bad "$tag open task outside pending: $variant"
        assert_runtime "$tag misplaced task is not moved automatically: $variant" test "$before" = "$(hrt_test_stamp "$q")"
    done
    q="$BOX/fenced-task-$tag"; hrt_test_compact_fixture "$q"
    cat > "$BOX/state" <<'STATE'
<!-- hx:recent -->
RECENT_KEEP
```markdown
- [ ] EXAMPLE_NOT_AN_ACTIVE_TASK
```
<!-- /hx:recent -->
<!-- hx:pending -->
- [ ] ACTUAL_OPEN_KEEP
<!-- /hx:pending -->
<!-- hx:done -->
~~~markdown
- [ ] DONE_EXAMPLE_HIDE
~~~
<!-- /hx:done -->
```markdown
- [ ] OUTSIDE_EXAMPLE_HIDE
```
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag fenced unchecked examples do not fail closed" test "$RC" -eq 0
    assert_runtime "$tag real pending remains with fenced examples" hrt_test_has ACTUAL_OPEN_KEEP

    q="$BOX/overview-bounds-$tag"; hrt_test_compact_fixture "$q"
    hrt_test_repeat 700 中 > "$BOX/overview"
    printf 'LEGACY_GOAL_MUST_SURVIVE\n' >> "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    assert_runtime "$tag legacy overview above old 2KiB cap is retained" test "$RC" -eq 0
    assert_runtime "$tag legacy not claimed semantically complete" hrt_test_has continuity_status=legacy_unverified
    assert_runtime "$tag legacy goal not deferred" hrt_test_has LEGACY_GOAL_MUST_SURVIVE
    hrt_test_repeat 1400 中 > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag oversized mandatory legacy overview fails atomically"

    # Huge optional background with explicit, single-source direction capsule.
    {
        hrt_test_repeat 8000 背景
        printf '<!-- hx:continuity -->\n'
        printf 'GOAL=help maintainers resume safely\nSUCCESS=no omitted open tasks\nNON_GOAL=chat replay\nCONSTRAINT=Bash3.2\nDECISION=Markdown for portability; source=Decision001\n'
        printf '<!-- /hx:continuity -->\nOPTIONAL_BACKGROUND_HIDE\n'
    } > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall 1
    assert_runtime "$tag explicit continuity survives enormous overview" test "$RC" -eq 0
    assert_runtime "$tag explicit structure not semantic proof" hrt_test_has continuity_status=explicit_unverified
    for fact in 'GOAL=help maintainers resume safely' 'SUCCESS=no omitted open tasks' 'NON_GOAL=chat replay' 'CONSTRAINT=Bash3.2' 'DECISION=Markdown for portability; source=Decision001' OLD_OPEN_FROM_LOG_0001; do
        assert_runtime "$tag direction/task retained: $fact" hrt_test_has "$fact"
    done
    assert_runtime "$tag background not replayed" hrt_test_lacks OPTIONAL_BACKGROUND_HIDE
    assert_runtime "$tag excluded overview content is disclosed" hrt_test_has overview_outside_continuity_bytes=
    assert_runtime "$tag continuity recall never repairs source" test "$before" = "$(hrt_test_stamp "$q")"

    # Inclusive byte boundaries: no UTF-8 slicing, no mandatory-data deferral.
    for variant in exact over unicode_exact unicode_over; do
        case "$variant" in
            exact) size=4095; prefix=a ;;
            over) size=4096; prefix=a ;;
            unicode_exact) size=1365; prefix=中 ;;
            unicode_over) size=1366; prefix=中 ;;
        esac
        { printf '<!-- hx:continuity -->\n'; hrt_test_repeat "$size" "$prefix"; printf '<!-- /hx:continuity -->\n'; } > "$BOX/overview"
        hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
        hrt_test_run "$q" recall
        case "$variant" in
            *over) hrt_test_bad "$tag $variant required continuity cap" ;;
            *) assert_runtime "$tag $variant 4096-byte continuity accepted" test "$RC" -eq 0 ;;
        esac
    done

    for variant in duplicate nested unclosed stray_close typo indented crossed misplaced; do
        hrt_test_compact_fixture "$q"
        case "$variant" in
            duplicate) printf '<!-- hx:continuity -->\nA\n<!-- /hx:continuity -->\n<!-- hx:continuity -->\nB\n<!-- /hx:continuity -->\n' ;;
            nested) printf '<!-- hx:continuity -->\n<!-- hx:continuity -->\nA\n<!-- /hx:continuity -->\n' ;;
            unclosed) printf '<!-- hx:continuity -->\nA\n' ;;
            stray_close) printf 'A\n<!-- /hx:continuity -->\n' ;;
            typo) printf '<!- hx:continuity -->\nA\n<!-- /hx:continuity -->\n' ;;
            indented) printf '  <!-- hx:continuity -->\nA\n<!-- /hx:continuity -->\n' ;;
            crossed) printf '<!-- hx:continuity -->\n## Unrelated\nA\n<!-- /hx:continuity -->\n' ;;
            misplaced) printf 'A\n## Unrelated\n<!-- hx:continuity -->\nB\n<!-- /hx:continuity -->\n' ;;
        esac > "$BOX/overview"
        hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
        hrt_test_run "$q" recall
        hrt_test_bad "$tag $variant continuity rejected"
    done
    hrt_test_compact_fixture "$q"
    for variant in '```' '~~~~' '    ```' $'\t~~~'; do
        {
            printf '%smarkdown\n<!-- hx:continuity -->\nFAKE_DIRECTION\n<!-- /hx:continuity -->\n%s\n' "$variant" "$variant"
            printf '<!-- hx:continuity -->\nREAL_GOAL\n```text\n<!-- /hx:continuity -->\nLITERAL_INSIDE\n```\n<!-- /hx:continuity -->\n'
        } > "$BOX/overview"
        hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
        hrt_test_run "$q" recall
        assert_runtime "$tag $variant fenced markers ignored" test "$RC" -eq 0
        assert_runtime "$tag $variant actual direction retained" hrt_test_has REAL_GOAL
        assert_runtime "$tag $variant code inside capsule retained" hrt_test_has LITERAL_INSIDE
        assert_runtime "$tag $variant fake direction excluded" hrt_test_lacks FAKE_DIRECTION
    done
    printf '<!-- hx:continuity -->\n<!-- /hx:continuity -->\n' > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag empty capsule cannot discard legacy direction"
    printf '<!-- hx:continuity -->\n  \t\n<!-- /hx:continuity -->\n' > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag whitespace capsule cannot discard direction"
    size=$((4096 - $(printf '## Project Overview\n' | LC_ALL=C wc -c) - 1))
    hrt_test_repeat "$size" a > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    assert_runtime "$tag exactly 4096-byte legacy overview accepted" test "$RC" -eq 0
    hrt_test_repeat "$((size+1))" a > "$BOX/overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag legacy overview 4097 bytes rejected"

    # Prose citations and actual Markdown links do not become orphan tasks.
    hrt_test_compact_fixture "$q"
    cat > "$BOX/state" <<'STATE'
<!-- hx:recent -->
- [设计文档](docs/design.md)
1. [验证证据][proof]
详见 [1]
结果 [OK]
<!-- /hx:recent -->
<!-- hx:pending -->
- [ ] ACTIVE_TASK
<!-- /hx:pending -->
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag Markdown links/citations are not orphan checkboxes" test "$RC" -eq 0
    assert_runtime "$tag work reference retained" hrt_test_has '[设计文档](docs/design.md)'
    assert_runtime "$tag verification reference retained" hrt_test_has '[验证证据][proof]'

    q="$BOX/continuity-outside-$tag"; hrt_test_compact_fixture "$q"
    cat > "$BOX/state" <<'STATE'
CRITICAL_CONTEXT_BEFORE_ANCHORS
<!-- hx:recent -->
STOP
<!-- /hx:recent -->
<!-- hx:pending -->
- [x] Completed migration
  - RESIDUAL_INDEX_NOT_REBUILT must be handled before release
- [x] STANDALONE_DONE_HIDE
- [ ] RELEASE_WAIT_FOR_APPROVAL
<!-- /hx:pending -->
IMPORTANT_APPROVAL_AFTER_ANCHORS
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag unanchored required context retained" test "$RC" -eq 0
    for fact in CRITICAL_CONTEXT_BEFORE_ANCHORS IMPORTANT_APPROVAL_AFTER_ANCHORS RESIDUAL_INDEX_NOT_REBUILT 'Completed migration'; do
        assert_runtime "$tag no inferred completion/lost context: $fact" hrt_test_has "$fact"
    done
    assert_runtime "$tag standalone checked task retained as context" hrt_test_has STANDALONE_DONE_HIDE
    for variant in backlog overview; do
        hrt_test_compact_fixture "$q"
        if [ "$variant" = backlog ]; then
            printf '\n## Backlog\n- [ ] OUTSIDE_PENDING_TASK\n' >> "$q/$HX_MAIN_FILE"
        else
            printf -- '- [ ] OUTSIDE_PENDING_TASK\n' > "$BOX/overview"
            hrt_test_replace_section "$q" 'Project Overview' "$BOX/overview"
        fi
        hrt_test_run "$q" recall
        hrt_test_bad "$tag external task in $variant cannot silently disappear"
    done
    hrt_test_compact_fixture "$q"
    { cat "$BOX/state"; hrt_test_repeat 12300 x; } > "$BOX/oversized-extra"
    hrt_test_replace_section "$q" 'Current State' "$BOX/oversized-extra"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag unanchored context counts toward state budget"
    hrt_test_compact_fixture "$q"
    for variant in short long; do
        {
            printf '```markdown\n<!-- hx:recall -->\nSUMMARY_CANNOT_HIDE_IN_UNCLOSED_FENCE\n<!-- /hx:recall -->\n'
            [ "$variant" != long ] || hrt_test_repeat 3000 x
        } > "$q/$HX_LOGS_DIR/0001-broken-fence.md"
        hrt_test_run "$q" recall
        hrt_test_bad "$tag $variant unclosed log fence is not legacy degradation"
    done

    q="$BOX/continuity-ancestry-$tag"; hrt_test_compact_fixture "$q"
    for variant in link unknown child lazy mixed_tabs; do
        case "$variant" in
            link) prefix='  Residual backfill see [#123](https://example.invalid/123), still pending' ;;
            unknown) prefix='  - [custom] RESIDUAL_PENDING' ;;
            child) prefix='  - [ ] RESIDUAL_PENDING' ;;
            lazy) prefix='Residual: still pending with no indentation' ;;
            mixed_tabs) prefix=$'\tResidual: tab-indented child' ;;
        esac
        printf '<!-- hx:recent -->\nSTOP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n- [ ] PREVIOUS_UNRELATED_TASK\n- [x] CHECKED_PARENT_WITH_RESIDUAL\n%s\n- [x] STANDALONE_OMITTED\n<!-- /hx:pending -->\n' "$prefix" > "$BOX/state"
        if [ "$variant" = mixed_tabs ]; then
            sed 's/^- \[x\] CHECKED_PARENT_WITH_RESIDUAL/  - [x] CHECKED_PARENT_WITH_RESIDUAL/' "$BOX/state" > "$BOX/mixed-state"
            cat "$BOX/mixed-state" > "$BOX/state"
        fi
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        hrt_test_run "$q" recall
        assert_runtime "$tag $variant ancestry preserved successfully" test "$RC" -eq 0
        assert_runtime "$tag $variant residual stays with checked parent" hrt_test_has "$(printf -- '- [x] CHECKED_PARENT_WITH_RESIDUAL\n%s' "$prefix")"
        assert_runtime "$tag $variant pending omits no checked items" hrt_test_has pending_completed_items_omitted=0
        assert_runtime "$tag $variant standalone checked context retained" hrt_test_has STANDALONE_OMITTED
    done
    printf -- '---\ntitle: OLD_LOG_WITH_BROKEN_FENCE\n---\n```bash\nUNREAD_OLD_CODE\n' > "$q/$HX_LOGS_DIR/0001-old.md"
    hrt_test_run "$q" recall
    assert_runtime "$tag unmarked legacy fence problem permits warned metadata" test "$RC" -eq 0
    assert_runtime "$tag unmarked legacy fence is not ordinary successful summary" hrt_test_has log_status=legacy_unclosed_fence_metadata_only
    assert_runtime "$tag unmarked legacy code is not claimed loaded" hrt_test_lacks UNREAD_OLD_CODE

    hrt_test_compact_fixture "$q"
    cat >> "$BOX/state" <<'STATE'
```text
## IMPORTANT_FENCED_HEADING_CONTEXT
FENCED_BODY_CONTEXT
```
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag unanchored fenced headings stay intact" hrt_test_has $'```text\n## IMPORTANT_FENCED_HEADING_CONTEXT\nFENCED_BODY_CONTEXT\n```'

    q="$BOX/total-budget-$tag"; hrt_test_compact_fixture "$q"
    for ((i=1;i<=20;i++)); do
        printf -v number '%04d' "$i"
        { printf '<!-- hx:recall -->\nSUMMARY_%s\n' "$number"; hrt_test_repeat 1800 t; printf '<!-- /hx:recall -->\n'; } > "$q/$HX_LOGS_DIR/$number-summary.md"
    done
    hrt_test_run "$q" recall
    assert_runtime "$tag default six summaries fit budget" test "$RC" -eq 0
    assert_runtime "$tag default six not silently reduced" hrt_test_has loaded_logs=6
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall 20
    assert_runtime "$tag explicit N stays within total budget" test "$RC" -eq 0
    assert_runtime "$tag explicit N output capped at 24576 bytes" test "$(LC_ALL=C wc -c < "$BOX/out")" -le 24576
    assert_runtime "$tag summaries beyond budget are explicitly deferred" hrt_test_has 'log_status=summary_deferred_budget'
    assert_runtime "$tag failed total budget leaves files unchanged" test "$before" = "$(hrt_test_stamp "$q")"

    # The advertised total limit is inclusive, including protocol headers.
    q="$BOX/total-exact-$tag"; hrt_test_compact_fixture "$q"
    for ((i=1;i<=7;i++)); do
        printf -v number '%04d' "$i"
        { printf '<!-- hx:recall -->\n'; hrt_test_repeat 1900 t; printf '<!-- /hx:recall -->\n'; } > "$q/$HX_LOGS_DIR/$number-summary.md"
    done
    hrt_test_run "$q" recall 7
    assert_runtime "$tag total-boundary base succeeds" test "$RC" -eq 0
    size=$((24576 - $(LC_ALL=C wc -c < "$BOX/out") - 1))
    hrt_test_repeat "$size" z > "$BOX/padding"
    awk -v padding="$BOX/padding" '{ print } $0=="STOP_POINT_KEEP" { while((getline line < padding)>0) print line; close(padding) }' "$q/$HX_MAIN_FILE" > "$BOX/exact-main"
    cat "$BOX/exact-main" > "$q/$HX_MAIN_FILE"
    hrt_test_run "$q" recall 7
    assert_runtime "$tag exactly 24576 total bytes accepted" test "$RC" -eq 0
    assert_runtime "$tag advertised total byte cap is inclusive" test "$(LC_ALL=C wc -c < "$BOX/out")" -eq 24576
    sed 's/STOP_POINT_KEEP/STOP_POINT_KEEPz/' "$q/$HX_MAIN_FILE" > "$BOX/exact-main"
    cat "$BOX/exact-main" > "$q/$HX_MAIN_FILE"
    hrt_test_run "$q" recall 7
    assert_runtime "$tag one byte over defers the oldest summary" test "$RC" -eq 0
    assert_runtime "$tag deferred output still within 24576 bytes" test "$(LC_ALL=C wc -c < "$BOX/out")" -le 24576
    assert_runtime "$tag deferral is explicit, not a sliced summary" hrt_test_has 'log_status=summary_deferred_budget'
}
# Independent review regressions H1/M1/M2. Keep these in this suite so both
# checkout and installed-mirror entry points exercise exactly the same fixtures.
hrt_test_review_suite() {
    local tag="$1" q file before variant prefix location size opener fake_close closer bad_open bad_close state_key
    # H1: legal ordered/unordered list spacing must not hide an open child,
    # and completed-item and orphan recognition must use the same grammar.
    for variant in ordered_dot ordered_paren multi_space star_space plus_tab dash_tab ordered_tab paren_space; do
        case "$variant" in
            ordered_dot) prefix='1. ' ;;
            ordered_paren) prefix='2) ' ;;
            multi_space) prefix='-  ' ;;
            star_space) prefix='*   ' ;;
            plus_tab) prefix=$'+\t' ;;
            dash_tab) prefix=$'-\t' ;;
            ordered_tab) prefix=$'3.\t' ;;
            paren_space) prefix='4)  ' ;;
        esac
        q="$BOX/review-h1-$tag-$variant"; hrt_test_compact_fixture "$q"
        {
            printf '<!-- hx:recent -->\nRECENT_KEEP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n'
            printf -- '- [x] COMPLETED_PARENT_HIDE\n  COMPLETED_PARENT_DETAIL_HIDE\n'
            printf '  %s[ ] REVIEW_OPEN_CHILD owner=Alice blocked=approval\n     REVIEW_CHILD_DEPENDENCY=security-review\n' "$prefix"
            printf '%s[X] REVIEW_COMPLETED_VARIANT_HIDE\n    REVIEW_COMPLETED_DETAIL_HIDE\n' "$prefix"
            printf '**INDEPENDENT_GROUP_KEEP**\n- [ ] FOLLOWING_OPEN_KEEP\n<!-- /hx:pending -->\n'
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        assert_runtime "$tag H1 $variant: nested task recall succeeds" test "$RC" -eq 0
        assert_runtime "$tag H1 $variant: entire open child retained" hrt_test_has "${prefix}[ ] REVIEW_OPEN_CHILD owner=Alice blocked=approval"
        assert_runtime "$tag H1 $variant: child dependency retained" hrt_test_has REVIEW_CHILD_DEPENDENCY=security-review
        assert_runtime "$tag H1 $variant: completed parent context retained" hrt_test_has COMPLETED_PARENT_HIDE
        assert_runtime "$tag H1 $variant: completed variant context retained" hrt_test_has REVIEW_COMPLETED_VARIANT_HIDE
        assert_runtime "$tag H1 $variant: completed variant continuation preserved" hrt_test_has REVIEW_COMPLETED_DETAIL_HIDE
        assert_runtime "$tag H1 $variant: independent group survives" hrt_test_has INDEPENDENT_GROUP_KEEP
        assert_runtime "$tag H1 $variant: following task survives" hrt_test_has FOLLOWING_OPEN_KEEP
        assert_runtime "$tag H1 $variant: files unchanged" test "$before" = "$(hrt_test_stamp "$q")"
        for location in recent "done" outside; do
            {
                printf '<!-- hx:recent -->\nRECENT_KEEP\n'
                [ "$location" != recent ] || printf '%s[ ] REVIEW_ORPHAN owner=Alice dependency=approval\n' "$prefix"
                printf '<!-- /hx:recent -->\n<!-- hx:pending -->\n- [ ] VALID_PENDING\n<!-- /hx:pending -->\n<!-- hx:done -->\n'
                [ "$location" != "done" ] || printf '%s[ ] REVIEW_ORPHAN owner=Alice dependency=approval\n' "$prefix"
                printf '<!-- /hx:done -->\n'
                [ "$location" != outside ] || printf '%s[ ] REVIEW_ORPHAN owner=Alice dependency=approval\n' "$prefix"
            } > "$BOX/state"
            hrt_test_replace_section "$q" 'Current State' "$BOX/state"
            before=$(hrt_test_stamp "$q")
            hrt_test_run "$q" recall
            hrt_test_bad "$tag H1 $variant: orphan in $location"
            assert_runtime "$tag H1 $variant: orphan in $location not moved" test "$before" = "$(hrt_test_stamp "$q")"
        done
    done

    # M1: an opening fence keeps its character and full length. A shorter run,
    # another character, or a run with info text cannot close it. Longer same-
    # character runs with trailing whitespace CAN close it.
    for variant in four_ticks four_tildes tick_info tilde_info mixed_chars longer_closer; do
        case "$variant" in
            four_ticks) opener='````markdown'; fake_close='```'; closer='````' ;;
            four_tildes) opener='~~~~markdown'; fake_close='~~~'; closer='~~~~' ;;
            tick_info) opener='```markdown'; fake_close='```python'; closer='```' ;;
            tilde_info) opener='~~~markdown'; fake_close='~~~python'; closer='~~~' ;;
            mixed_chars) opener='```markdown'; fake_close='~~~'; closer='```' ;;
            longer_closer) opener='````markdown'; fake_close='```'; closer=$'````` \t' ;;
        esac
        q="$BOX/review-m1-$tag-$variant"; hrt_test_compact_fixture "$q"
        file="$q/$HX_LOGS_DIR/0001-fence.md"
        {
            printf 'UNVERIFIED_REAL_STATUS_KEEP\n%s\n%s\n' "$opener" "$fake_close"
            printf '<!-- hx:recall -->\nEXAMPLE_NOT_REAL_STATUS\n<!-- /hx:recall -->\n%s\nREAL_BODY_AFTER_FENCE_KEEP\n' "$closer"
        } > "$file"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        assert_runtime "$tag M1 $variant: fenced literal succeeds" test "$RC" -eq 0
        assert_runtime "$tag M1 $variant: literal markers are not a summary" hrt_test_has log_status=legacy_short_full
        assert_runtime "$tag M1 $variant: real status is not discarded" hrt_test_has UNVERIFIED_REAL_STATUS_KEEP
        assert_runtime "$tag M1 $variant: whole short log preserved" hrt_test_has "$(cat "$file")"
        assert_runtime "$tag M1 $variant: no summary status" hrt_test_lacks log_status=summary
        assert_runtime "$tag M1 $variant: log not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
        printf '<!-- hx:recall -->\nGENUINE_SUMMARY_AFTER_FENCE\n<!-- /hx:recall -->\n' >> "$file"
        hrt_test_run "$q" recall
        assert_runtime "$tag M1 $variant: genuine summary after valid closure succeeds" test "$RC" -eq 0
        assert_runtime "$tag M1 $variant: genuine summary selected" hrt_test_has GENUINE_SUMMARY_AFTER_FENCE
        assert_runtime "$tag M1 $variant: genuine summary status" hrt_test_has log_status=summary
        assert_runtime "$tag M1 $variant: example not promoted into genuine summary" hrt_test_lacks EXAMPLE_NOT_REAL_STATUS

        # The same fence semantics protect state anchors, headings and orphan
        # checks. These fake pending markers/tasks belong to a code sample.
        {
            printf '<!-- hx:recent -->\nRECENT_KEEP\n<!-- /hx:recent -->\n%s\n%s\n' "$opener" "$fake_close"
            printf '## Current State\n<!-- hx:pending -->\n1. [ ] FENCED_ORPHAN_EXAMPLE\n<!-- /hx:pending -->\n%s\n' "$closer"
            printf '<!-- hx:pending -->\n- [ ] REAL_PENDING_AFTER_FENCE owner=Bob\n<!-- /hx:pending -->\n'
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        assert_runtime "$tag M1 $variant: fenced state syntax does not corrupt anchors" test "$RC" -eq 0
        assert_runtime "$tag M1 $variant: task after real fence closure survives" hrt_test_has REAL_PENDING_AFTER_FENCE
        assert_runtime "$tag M1 $variant: state code sample retained as fenced context" hrt_test_has FENCED_ORPHAN_EXAMPLE
        assert_runtime "$tag M1 $variant: state not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
    done

    # M2: BOTH sides are damaged, so merely counting exact markers is not
    # enough. Test short and long logs: neither legacy fallback is legitimate.
    for variant in no_close_space no_open_space extra_space tab_space indented trailing_space missing_gt missing_dash unfinished_comment duplicate_damaged; do
        case "$variant" in
            no_close_space|duplicate_damaged) bad_open='<!-- hx:recall-->'; bad_close='<!-- /hx:recall-->' ;;
            no_open_space) bad_open='<!--hx:recall -->'; bad_close='<!--/hx:recall -->' ;;
            extra_space) bad_open='<!--  hx:recall  -->'; bad_close='<!--  /hx:recall  -->' ;;
            tab_space) bad_open=$'<!--\thx:recall\t-->'; bad_close=$'<!--\t/hx:recall\t-->' ;;
            indented) bad_open='  <!-- hx:recall -->'; bad_close='  <!-- /hx:recall -->' ;;
            trailing_space) bad_open='<!-- hx:recall --> '; bad_close='<!-- /hx:recall --> ' ;;
            missing_gt) bad_open='<!-- hx:recall --'; bad_close='<!-- /hx:recall --' ;;
            missing_dash) bad_open='<!- hx:recall -->'; bad_close='<!- /hx:recall -->' ;;
            unfinished_comment) bad_open='<!-- hx:recall'; bad_close='<!-- /hx:recall' ;;
        esac
        q="$BOX/review-m2-$tag-$variant"; hrt_test_compact_fixture "$q"
        file="$q/$HX_LOGS_DIR/0001-damaged.md"
        printf 'VALID_NEWER_LOG_MUST_NOT_ESCAPE\n' > "$q/$HX_LOGS_DIR/0002-valid.md"
        for size in short long; do
            {
                printf '%s\nIMPORTANT_NEW_SUMMARY\n%s\n' "$bad_open" "$bad_close"
                [ "$variant" != duplicate_damaged ] || printf '%s\nDUPLICATE_DAMAGED_SUMMARY\n%s\n' "$bad_open" "$bad_close"
                [ "$size" != long ] || hrt_test_repeat 500 'detail '
            } > "$file"
            before=$(hrt_test_stamp "$q")
            hrt_test_run "$q" recall
            hrt_test_bad "$tag M2 $variant $size: damaged pair cannot fall back"
            assert_runtime "$tag M2 $variant $size: malformed file unchanged" test "$before" = "$(hrt_test_stamp "$q")"
        done
        # Negative control: identical damaged-looking text inside a genuine
        # fence is an example, not a broken summary. No automatic rewriting.
        {
            printf 'REAL_SHORT_LOG_KEEP\n````markdown\n%s\nFENCED_DAMAGED_EXAMPLE\n%s\n````\n' "$bad_open" "$bad_close"
        } > "$file"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        assert_runtime "$tag M2 $variant: fenced literal is accepted" test "$RC" -eq 0
        assert_runtime "$tag M2 $variant: fenced literal uses legacy short path" hrt_test_has log_status=legacy_short_full
        assert_runtime "$tag M2 $variant: fenced literal retained verbatim" hrt_test_has "$(cat "$file")"
        assert_runtime "$tag M2 $variant: fenced literal not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
        printf '<!-- hx:recall -->\nREAL_SUMMARY_NOT_FENCED\n<!-- /hx:recall -->\n' >> "$file"
        hrt_test_run "$q" recall
        assert_runtime "$tag M2 $variant: valid summary with fenced malformed example succeeds" test "$RC" -eq 0
        assert_runtime "$tag M2 $variant: real non-fenced summary selected" hrt_test_has REAL_SUMMARY_NOT_FENCED
        assert_runtime "$tag M2 $variant: fenced malformed example not output as summary" hrt_test_lacks FENCED_DAMAGED_EXAMPLE

        # Both delimiters of EVERY state block are damaged. With no exact
        # anchors left, a parser must not misclassify this as unanchored legacy.
        q="$BOX/review-m2-state-$tag-$variant"; hrt_test_compact_fixture "$q"
        {
            for state_key in recent pending "done"; do
                printf '%s\n' "${bad_open/hx:recall/hx:$state_key}"
                if [ "$state_key" = pending ]; then printf -- '- [ ] STATE_TASK_MUST_NOT_BE_SILENTLY_RECLASSIFIED\n'
                else printf 'STATE_BODY_%s\n' "$state_key"; fi
                printf '%s\n' "${bad_close/hx:recall/hx:$state_key}"
            done
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        hrt_test_bad "$tag M2 state $variant: damaged pairs cannot fall back to legacy"
        assert_runtime "$tag M2 state $variant: broken state not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
        # Identical broken markers and valid-looking state markers stay literal
        # inside FOUR ticks, including an interior THREE-tick fake closure.
        {
            printf '<!-- hx:recent -->\nRECENT_KEEP\n<!-- /hx:recent -->\n````markdown\n```\n'
            for state_key in recent pending "done"; do
                printf '%s\nFENCED_STATE_EXAMPLE\n%s\n' \
                    "${bad_open/hx:recall/hx:$state_key}" "${bad_close/hx:recall/hx:$state_key}"
            done
            printf '<!-- hx:pending -->\n1. [ ] FENCED_STATE_ORPHAN\n<!-- /hx:pending -->\n````\n'
            printf '<!-- hx:pending -->\n- [ ] REAL_PENDING_AFTER_DAMAGED_EXAMPLE\n<!-- /hx:pending -->\n'
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        assert_runtime "$tag M2 state $variant: fenced damaged markers are literal" test "$RC" -eq 0
        assert_runtime "$tag M2 state $variant: real pending after fence preserved" hrt_test_has REAL_PENDING_AFTER_DAMAGED_EXAMPLE
        assert_runtime "$tag M2 state $variant: fenced fake pending retained as code context" hrt_test_has FENCED_STATE_ORPHAN
        assert_runtime "$tag M2 state $variant: fenced example not rewritten" test "$before" = "$(hrt_test_stamp "$q")"
    done
}
# Follow-up review: uncertain checkbox states are not completion evidence;
# protect whole code blocks, including list-container fences.
hrt_test_conservative_suite() {
    local tag="$1" q mark fence_mark
    q="$BOX/conservative-$tag"; hrt_test_compact_fixture "$q"
    for mark in '[/]' '[-]' '[  ]' '[ ]nospace'; do
        printf '<!-- hx:recent -->\nSTOP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n- [x] DONE\n  - %s UNKNOWN_TASK owner=Alice\n    dependency=approval\n<!-- /hx:pending -->\n' "$mark" > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        hrt_test_run "$q" recall
        assert_runtime "$tag unknown status is preserved: $mark" test "$RC" -eq 0
        assert_runtime "$tag unknown task is not discarded: $mark" hrt_test_has UNKNOWN_TASK
        assert_runtime "$tag unknown task dependencies retained: $mark" hrt_test_has dependency=approval
        printf '<!-- hx:recent -->\nSTOP\n<!-- /hx:recent -->\n- %s UNKNOWN_ORPHAN\n<!-- hx:pending -->\n- [ ] ACTIVE\n<!-- /hx:pending -->\n' "$mark" > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        hrt_test_run "$q" recall
        hrt_test_bad "$tag ambiguous orphan is refused: $mark"
    done
    cat > "$BOX/state" <<'STATE'
<!-- hx:recent -->
STOP
<!-- /hx:recent -->
<!-- hx:pending -->
- [x] DONE
```text
IMPORTANT_CODE_CONTEXT
```
- [ ] ACTIVE
    ```markdown
    - [x] LITERAL_CHECKED_EXAMPLE
      REQUIRED_LITERAL_CONTEXT
    ```
<!-- /hx:pending -->
STATE
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    hrt_test_run "$q" recall
    assert_runtime "$tag independent and nested fences succeed" test "$RC" -eq 0
    assert_runtime "$tag independent opening fence retained" hrt_test_has $'```text\nIMPORTANT_CODE_CONTEXT\n```'
    assert_runtime "$tag nested code not filtered as completed tasks" hrt_test_has $'    ```markdown\n    - [x] LITERAL_CHECKED_EXAMPLE\n      REQUIRED_LITERAL_CONTEXT\n    ```'
    for mark in "\t" "  \t"; do
        for fence_mark in '```' '~~~'; do
            printf '<!-- hx:recent -->\nSTOP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n- [ ] ACTIVE\n%b%smarkdown\n%b- [x] TAB_LITERAL_KEEP\n%b  TAB_DEPENDENCY_KEEP\n%b%s\n<!-- /hx:pending -->\n' "$mark" "$fence_mark" "$mark" "$mark" "$mark" "$fence_mark" > "$BOX/state"
            hrt_test_replace_section "$q" 'Current State' "$BOX/state"
            hrt_test_run "$q" recall
            assert_runtime "$tag tab/container code fence succeeds" test "$RC" -eq 0
            assert_runtime "$tag tab code checkbox retained" hrt_test_has TAB_LITERAL_KEEP
            assert_runtime "$tag tab code context retained" hrt_test_has TAB_DEPENDENCY_KEEP
        done
    done
    printf '%s\n' '---' 'title: unclosed frontmatter' '<!-- hx:recall -->' 'NOT_VALID' '<!-- /hx:recall -->' > "$q/$HX_LOGS_DIR/0001-unclosed.md"
    hrt_test_run "$q" recall
    hrt_test_bad "$tag unclosed frontmatter does not hide summary as metadata"
}
# Generalized from legacy mixed checked-context evidence kept under wip.
# Closed work still carries push gates, accepted risks and a backup decision.
# Compare the ENTIRE block, not keywords; no private infrastructure/identifiers.
hrt_test_pending_preservation_suite() {
    local tag="$1" q="$BOX/pending-verbatim-$1" before variant
    hrt_test_compact_fixture "$q"
    cat > "$BOX/pending" <<'PENDING'
- [ ] OPEN_FIRST owner=Alice dependency=approval

- [x] ~~**git/SSH**：公钥未登记代码托管服务~~ ✅ 闭（管理员登记用户示例的开发机公钥；认证通过；经授权推送分支与标签，远端一致）。**后续 push 仍逐次等 Boss 明文**（已推至已发布提交；当前待发布提交起若干提交本地未推）。
- [x] ~~**review-loop（dev-only）收敛缺陷**~~ ✅ 闭（修复提交；沙箱复现并修复，审查通过）。已接受的残留（maintainer-only）：账本截断与"无轮次"不可区分；两个 `start` 同 cwd 并发的清理竞争不加锁。
- [x] ~~**技能跨目录重复**~~ ✅ probe完成：多个安装目录扫描存在同名覆盖；隐藏旧备份仍含旧技能。**处置 ✅ 已落地**：安装时仅警告旧备份，不自动删除；**该备份目录是否删除仍待 Boss**。
- [x] FINISHED_PLAIN_NO_RESIDUAL
- [X] FINISHED_UPPERCASE
  - [ ] NESTED_OPEN owner=Bob
    original nested context
- [custom] UNKNOWN_STATE_KEEP
- [ ] OPEN_LAST owner=Carol
PENDING
    {
        printf '<!-- hx:recent -->
STOP
<!-- /hx:recent -->
<!-- hx:pending -->
'
        cat "$BOX/pending"
        printf '<!-- /hx:pending -->
<!-- hx:done -->
- [x] EXPLICIT_DONE_EXCLUDED
<!-- /hx:done -->
'
    } > "$BOX/state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall
    assert_runtime "$tag mixed real checked constraints recall succeeds" test "$RC" -eq 0
    assert_runtime "$tag entire mixed pending block preserved verbatim and in order" hrt_test_has "$(cat "$BOX/pending")"
    assert_runtime "$tag no invented omitted count" hrt_test_has pending_completed_items_omitted=0
    assert_runtime "$tag explicit done block alone excluded" hrt_test_lacks EXPLICIT_DONE_EXCLUDED
    assert_runtime "$tag preserving pending does not rewrite checkbox/source" test "$before" = "$(hrt_test_stamp "$q")"

    # Previously these large standalone checked lines vanished before budget
    # accounting. Full retention must fail closed; do not raise the limit.
    for variant in ascii utf8; do
        {
            printf '<!-- hx:recent -->
STOP
<!-- /hx:recent -->
<!-- hx:pending -->
- [x] '
            if [ "$variant" = ascii ]; then hrt_test_repeat 13000 x; else hrt_test_repeat 4200 中; fi
            printf '<!-- /hx:pending -->
'
        } > "$BOX/state"
        hrt_test_replace_section "$q" 'Current State' "$BOX/state"
        before=$(hrt_test_stamp "$q")
        hrt_test_run "$q" recall
        hrt_test_bad "$tag oversized checked pending $variant fails closed"
        assert_runtime "$tag oversized checked pending $variant retains 12288-byte limit"             test "${ERR#*limit=12288}" != "$ERR"
        assert_runtime "$tag oversized checked pending $variant requests explicit organization"             test "${ERR#*explicitly organize current context}" != "$ERR"
        assert_runtime "$tag oversized checked pending $variant leaves source intact" test "$before" = "$(hrt_test_stamp "$q")"
    done
}

# No headings in either source block: output must identify their origin while
# keeping every source byte contiguous. Output headings are metadata, not anchors.
hrt_test_section_labels_suite() {
    local tag="$1" q="$BOX/section-labels-$1" before reported actual
    hrt_test_compact_fixture "$q"
    printf '停在：X\n\n- [x] 已完成A\n' > "$BOX/recent-no-heading"
    printf '约束：B 需用户授权\n- [ ] C\n  原关联上下文\n\n- [x] 已关闭但每次操作仍需授权\n' > "$BOX/pending-no-heading"
    {
        printf '<!-- hx:recent -->\n'
        cat "$BOX/recent-no-heading"
        printf '<!-- /hx:recent -->\n<!-- hx:pending -->\n'
        cat "$BOX/pending-no-heading"
        printf '<!-- /hx:pending -->\n'
    } > "$BOX/state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/state"
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" recall
    assert_runtime "$tag unlabeled source blocks recall succeeds" test "$RC" -eq 0
    {
        printf '### hx:recent\n'
        cat "$BOX/recent-no-heading"
        printf '\n### hx:pending\n'
        cat "$BOX/pending-no-heading"
    } > "$BOX/expected-labeled-state"
    assert_runtime "$tag explicit source labels enclose both complete blocks in order" hrt_test_has "$(cat "$BOX/expected-labeled-state")"
    assert_runtime "$tag recent boundary occurs once" test "$(grep -c '^### hx:recent$' "$BOX/out" || :)" -eq 1
    assert_runtime "$tag pending boundary occurs once" test "$(grep -c '^### hx:pending$' "$BOX/out" || :)" -eq 1
    assert_runtime "$tag output does not reinsert parseable recent anchor" hrt_test_lacks '<!-- hx:recent -->'
    assert_runtime "$tag output does not reinsert parseable pending anchor" hrt_test_lacks '<!-- hx:pending -->'
    reported=$(sed -n 's/^payload_bytes=//p' "$BOX/out")
    # payload_bytes excludes its two metadata header lines and the final LF;
    # the existing runtime total-budget guard covers the complete stdout.
    actual=$(tail -n +3 "$BOX/out" | LC_ALL=C wc -c | tr -d ' ')
    assert_runtime "$tag payload byte count includes source headings" test "$reported" -eq "$((actual - 1))"
    assert_runtime "$tag labeling does not modify source" test "$before" = "$(hrt_test_stamp "$q")"
}

# review-due: deterministic trigger for the periodic pending review. The log
# being finalized is the one counted, so it must be the latest direct entry.
hrt_test_review_state() {
    # $1 project, $2 file holding the exact pending block content
    {
        printf '<!-- hx:recent -->\nRECENT_KEEP\n<!-- /hx:recent -->\n<!-- hx:pending -->\n'
        cat "$2"
        printf '<!-- /hx:pending -->\n'
    } > "$BOX/review-state"
    hrt_test_replace_section "$1" 'Current State' "$BOX/review-state"
}
hrt_test_review_logs() {
    local i number
    for i in $(seq 1 "$2"); do
        printf -v number '%04d' "$i"
        printf 'ENTRY_%s\n' "$number" > "$1/$HX_LOGS_DIR/$number-review.md"
    done
}
hrt_test_review_due_suite() {
    local tag="$1" q="$BOX/review-due-$1" before policy runtime_sb
    hrt_test_compact_fixture "$q"
    hrt_test_repeat 3071 a > "$BOX/pending-3072"
    hrt_test_review_state "$q" "$BOX/pending-3072"
    hrt_test_review_logs "$q" 5
    before=$(hrt_test_stamp "$q")
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0005-review.md"
    assert_runtime "$tag review-due 0005 rc0" test "$RC" -eq 0
    assert_runtime "$tag review-due 0005 not due" hrt_test_has $'log_number=5\npending_bytes=3072\npending_review_due=0'
    assert_runtime "$tag review-due is read-only" test "$before" = "$(hrt_test_stamp "$q")"
    hrt_test_review_logs "$q" 6
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due 0006 due at 3072" test "$OUT" = $'log_number=6\npending_bytes=3072\npending_review_due=1'
    assert_runtime "$tag review-due success has no stderr" test -z "$ERR"
    hrt_test_repeat 3070 a > "$BOX/pending-3071"
    hrt_test_review_state "$q" "$BOX/pending-3071"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due 3071 not due" test "$OUT" = $'log_number=6\npending_bytes=3071\npending_review_due=0'
    # Multi-byte text plus a trailing blank line: 1023*3 + 1 + 1 + 1 = 3072.
    { hrt_test_repeat 1023 '中' | tr -d '\n'; printf 'a\n\n'; } > "$BOX/pending-zh"
    hrt_test_review_state "$q" "$BOX/pending-zh"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due counts UTF-8 bytes and blank lines" test "$OUT" = $'log_number=6\npending_bytes=3072\npending_review_due=1'
    # The review is most needed exactly when recall's state budget is exceeded.
    hrt_test_repeat 12999 a > "$BOX/pending-big"
    hrt_test_review_state "$q" "$BOX/pending-big"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due ignores recall budget" test "$OUT" = $'log_number=6\npending_bytes=13000\npending_review_due=1'
    printf '%s\n' '- [ ] FENCED_KEEP' '```' '<!-- hx:pending -->' '```' > "$BOX/pending-fence"
    hrt_test_review_state "$q" "$BOX/pending-fence"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due fenced fake anchor is content" test "$OUT" = $'log_number=6\npending_bytes=46\npending_review_due=0'
    mkdir -p "$q/${HX_LOGS_DIR}.archive/2026"
    printf 'ARCHIVED\n' > "$q/${HX_LOGS_DIR}.archive/2026/0012-review.md"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"
    assert_runtime "$tag review-due ignores archive numbers" hrt_test_has log_number=6
    if command -v sandbox-exec >/dev/null 2>&1; then
        policy='(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null"))'
        runtime_sb=$RT
        before=$(hrt_test_stamp "$q")
        RC=0
        (cd "$q" && sandbox-exec -p "$policy" /bin/bash "$runtime_sb" review-due --log "$HX_LOGS_DIR/0006-review.md") > "$BOX/out" 2> "$BOX/err" || RC=$?
        assert_runtime "$tag review-due under deny-write sandbox" test "$RC" -eq 0
        assert_runtime "$tag review-due sandbox no stderr" test ! -s "$BOX/err"
        assert_runtime "$tag review-due sandbox preserves files" test "$before" = "$(hrt_test_stamp "$q")"
    fi
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0005-review.md"; hrt_test_bad "$tag review-due non-latest log"
    hrt_test_run "$q" review-due --log "./$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due aliased log path"
    hrt_test_run "$q" review-due --log "${HX_LOGS_DIR}.archive/2026/0012-review.md"; hrt_test_bad "$tag review-due archived log"
    hrt_test_run "$q" review-due; hrt_test_bad "$tag review-due missing --log"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md" --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due duplicate --log"
    printf '%s\n' '<!-- hx:recent -->' 'R' '<!-- /hx:recent -->' '<!-- hx:pending -->' '- [ ] X' > "$BOX/review-state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/review-state"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due unclosed pending"; assert_runtime "$tag review-due unclosed: names state failure" hrt_test_err_has 'invalid current state or no hx:pending block'
    printf '%s\n' '<!-- hx:recent -->' 'R' '<!-- /hx:recent -->' '<!-- hx:pending -->' '- [ ] X' '<!-- /hx:pending -->' '<!-- hx:pending -->' '- [ ] Y' '<!-- /hx:pending -->' > "$BOX/review-state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/review-state"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due duplicate pending"; assert_runtime "$tag review-due duplicate: names state failure" hrt_test_err_has 'invalid current state or no hx:pending block'
    # Continuity structure errors must stop review-due exactly as they stop recall
    # and finalize: otherwise the AI would remove pending items, then fail late.
    hrt_test_review_state "$q" "$BOX/pending-3072"
    printf '%s\n' '<!-- hx:continuity -->' '<!-- /hx:continuity -->' > "$BOX/review-overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/review-overview"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due empty continuity"; assert_runtime "$tag review-due empty continuity: names state failure" hrt_test_err_has 'invalid current state or no hx:pending block'
    printf '%s\n' '<!-- hx:continuity -->' 'A' '<!-- /hx:continuity -->' '<!-- hx:continuity -->' 'B' '<!-- /hx:continuity -->' > "$BOX/review-overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/review-overview"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due duplicate continuity"; assert_runtime "$tag review-due duplicate continuity: names state failure" hrt_test_err_has 'invalid current state or no hx:pending block'
    printf '%s\n' 'OVERVIEW_KEEP' > "$BOX/review-overview"
    hrt_test_replace_section "$q" 'Project Overview' "$BOX/review-overview"
    printf '%s\n' 'LEGACY_STATE_ONLY' > "$BOX/review-state"
    hrt_test_replace_section "$q" 'Current State' "$BOX/review-state"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0006-review.md"; hrt_test_bad "$tag review-due legacy state without anchors"; assert_runtime "$tag review-due legacy: names state failure" hrt_test_err_has 'invalid current state or no hx:pending block'
    q="$BOX/review-due-empty-$tag"; hrt_test_compact_fixture "$q"
    hrt_test_run "$q" review-due --log "$HX_LOGS_DIR/0001-review.md"; hrt_test_bad "$tag review-due without logs"; assert_runtime "$tag review-due without logs: names missing log" hrt_test_err_has 'requires a numbered log'
}

for bounded_runtime in "$REAL_RT" "$MIRROR"; do
    RT=$bounded_runtime
    if [ "$bounded_runtime" = "$REAL_RT" ]; then bounded_tag=source; else bounded_tag=mirror; fi
    hrt_test_review_due_suite "$bounded_tag"
done

for bounded_runtime in "$REAL_RT" "$MIRROR"; do
    RT=$bounded_runtime
    if [ "$bounded_runtime" = "$REAL_RT" ]; then bounded_tag=source; else bounded_tag=mirror; fi
    hrt_test_section_labels_suite "$bounded_tag"
    hrt_test_pending_preservation_suite "$bounded_tag"
    hrt_test_bounded_suite "$bounded_tag"
    hrt_test_review_suite "$bounded_tag"
    hrt_test_conservative_suite "$bounded_tag"
done
RT=$REAL_RT

# v4.4.1: one rule for an anchor line across runtime / hx.sh / tidy. The
# marker grammar is exact (M1/M2 above: trailing blanks are a damaged marker),
# but hx.sh and tidy accepted trailing whitespace (CR included), so tidy and
# lint called a file clean that recall then refused at finalize, and on a CRLF
# file tidy added a fresh pair on every run. All three must refuse alike.
HX="$ROOT/scripts/hx.sh"; TIDY="$ROOT/scripts/tidy-handoff.sh"
W="$BOX/anchor-ws"; mkdir -p "$W"; hrt_test_fixture "$W"
sed 's/^<!-- hx:recent -->$/<!-- hx:recent -->  /' "$W/$HX_MAIN_FILE" > "$BOX/ws-main"; cat "$BOX/ws-main" > "$W/$HX_MAIN_FILE"
assert_runtime 'anchor-ws: trailing blanks really planted' grep -q '^<!-- hx:recent -->  $' "$W/$HX_MAIN_FILE"
hrt_test_run "$W" recall ''
assert_runtime 'anchor-ws: recall refuses the damaged anchor' test "$RC" -ne 0
rc=0; bash "$HX" block get recent --file "$W/$HX_MAIN_FILE" >/dev/null 2>&1 || rc=$?
assert_runtime 'anchor-ws: block get refuses it too (exit 4)' test "$rc" -eq 4
cp "$W/$HX_MAIN_FILE" "$BOX/ws-before"
rc=0; bash "$TIDY" "$W/$HX_MAIN_FILE" </dev/null >"$BOX/ws-tidy" 2>&1 || rc=$?
assert_runtime 'anchor-ws: tidy refuses (exit 1)' test "$rc" -eq 1
assert_runtime 'anchor-ws: tidy names the damaged anchor' grep -q 'hx:recent' "$BOX/ws-tidy"
assert_runtime 'anchor-ws: tidy wrote nothing' cmp -s "$W/$HX_MAIN_FILE" "$BOX/ws-before"
C="$BOX/anchor-crlf"; mkdir -p "$C"; hrt_test_fixture "$C"
sed 's/$/\r/' "$C/$HX_MAIN_FILE" > "$BOX/crlf-main"; cat "$BOX/crlf-main" > "$C/$HX_MAIN_FILE"
hrt_test_run "$C" recall ''
assert_runtime 'anchor-crlf: recall refuses CRLF anchors' test "$RC" -ne 0
rc=0; bash "$HX" block get recent --file "$C/$HX_MAIN_FILE" >/dev/null 2>&1 || rc=$?
assert_runtime 'anchor-crlf: block get says damaged (4), not "no anchors" (2)' test "$rc" -eq 4
cp "$C/$HX_MAIN_FILE" "$BOX/crlf-before"
bash "$TIDY" "$C/$HX_MAIN_FILE" </dev/null >/dev/null 2>&1 || true
bash "$TIDY" "$C/$HX_MAIN_FILE" </dev/null >/dev/null 2>&1 || true
assert_runtime 'anchor-crlf: tidy refuses instead of adding pairs (file unchanged)' cmp -s "$C/$HX_MAIN_FILE" "$BOX/crlf-before"

# v4.4.1: the release notes' "skill only" option (bare unzip of the .skill)
# leaves no install binding, and context refuses it. The refusal must say how
# to recover, not just "reinstall" — the user followed the published steps.
U="$BOX/bare-unzip/.claude/skills/handoffx"; mkdir -p "$(dirname "$U")" "$BOX/bare-proj"
cp -R "$ROOT/skills/handoffx" "$U"; rm -rf "$U/command-shims" "$U/.handoffx-install-context"
rc=0; (cd "$BOX/bare-proj" && bash "$U/scripts/handoff-runtime.sh" context --root "$BOX/bare-proj" --skill-root "$U") >/dev/null 2>"$BOX/bare-err" || rc=$?
assert_runtime 'bare-unzip: context refuses an install without a binding' test "$rc" -ne 0
assert_runtime 'bare-unzip: refusal names install.sh as the fix' grep -q 'install.sh' "$BOX/bare-err"

printf '  ─── %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
