#!/bin/bash
# Real-shell finalize integration contract (Bash 3.2 compatible).
# All fixtures, subprocess TMPDIR and per-command evidence stay in wip.
# common.sh is intentionally not sourced: it creates tests/.tmp outside wip.
# Success, budget, credential and xref checks use the actual tools. Only the
# explicitly labelled downstream-failure cases wrap real tools AFTER running
# them; no success-shaped stub can stand in for init/regen/recall/postflight.
set -euo pipefail
unset CDPATH
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SHELL_BIN=${FINALIZE_TEST_BASH:-/bin/bash}
command -v python3 >/dev/null || { echo 'python3 is required for byte-exact test assertions' >&2; exit 2; }
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/handoff-schema.sh"
mkdir -p "$ROOT/wip/reviews/iteration-closeout"
BOX=$(mktemp -d "$ROOT/wip/reviews/iteration-closeout/finalize.XXXXXX")
mkdir "$BOX/tmp" "$BOX/evidence" "$BOX/home" "$BOX/bin"
export TMPDIR="$BOX/tmp" PYTHONDONTWRITEBYTECODE=1
# Do not inherit installer failure hooks or redirect any install into real HOME.
unset CLAUDE_CONFIG_DIR HANDOFFX_INSTALL_FAIL_AT HANDOFF_TEST_PLATFORM BASH_ENV ENV
# Pin PATH-based grandchildren to the real selected Bash, not a shell stub.
SHELL_BIN=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$(command -v "$SHELL_BIN")")
ln -s "$SHELL_BIN" "$BOX/bin/bash"
export PATH="$BOX/bin:$PATH" FINALIZE_SHELL_AUDIT="$BOX/bash-versions.tsv"
# Instrumentation only: BASH_ENV records identity to wip, never changes stdout,
# command behavior, or status. It also observes children invoked via "$BASH".
cat > "$BOX/bash-version-audit.sh" <<'AUDIT'
# Bash 3.2 sets script $0 AFTER reading BASH_ENV. Observe the first real command
# and immediately remove this one-shot hook, before any script-owned trap runs.
trap 'printf "%s\t%s\t%s\t%s\t%s\n" "$BASH" "$BASH_VERSION" "$$" "$PPID" "$0" >> "$FINALIZE_SHELL_AUDIT"; trap - DEBUG' DEBUG
AUDIT
export BASH_ENV="$BOX/bash-version-audit.sh"
printf '%s\t%s\t%s\t%s\t%s\n' "$BASH" "$BASH_VERSION" "$$" "$PPID" "$0" >> "$FINALIZE_SHELL_AUDIT"
# shellcheck disable=SC2016
SELECTED_BASH_VERSION=$("$SHELL_BIN" -c 'printf "%s" "$BASH_VERSION"')
PASS=0 FAIL=0 SEQ=0 PROJECT_SEQ=0 RC=0 OUT='' ERR='' P='' S=''
CONFIRM='✅ 交接已保存；项目定位、声明一致性、索引、召回预检与写后检查通过。'
printf '%s' "$CONFIRM" > "$BOX/expected.stdout"
trap 'printf "finalize evidence: %s\n" "$BOX"' EXIT
printf 'finalize shell: %s\n' "$("$SHELL_BIN" --version | head -n 1)"
# Retain both passes and failures: RED/GREEN logs can point to exact calls.
check() {
    local label=$1; shift
    if "$@"; then PASS=$((PASS+1)); else
        FAIL=$((FAIL+1)); printf 'FAIL: %s (rc=%s; stdout=%s; stderr=%s)\n' "$label" "$RC" "$OUT" "$ERR" >&2
    fi
}
run() {
    local cwd=$1; shift
    SEQ=$((SEQ+1)); OUT="$BOX/evidence/$SEQ.stdout"; ERR="$BOX/evidence/$SEQ.stderr"; RC=0
    # A distributed skill copy without a manifest must name its write root
    # (review #7): the mirror pass supplies the physical cwd explicitly.
    case "$1" in
        "$ROOT/skills/handoffx/scripts/handoff-runtime.sh"|"$ROOT/skills/handoffx/scripts/hx.sh"|"$ROOT/skills/handoffx/scripts/handoff-postflight.sh")
            [ "${2:-}" = --expect-root ] || set -- "$1" --expect-root "$cwd" "${@:2}" ;;
    esac
    printf '%s\n' "$cwd" > "$BOX/evidence/$SEQ.cwd"
    printf '%s\n' "$@" > "$BOX/evidence/$SEQ.argv"
    (cd "$cwd" && "$SHELL_BIN" "$@") > "$OUT" 2> "$ERR" || RC=$?
    printf '%s\n' "$RC" > "$BOX/evidence/$SEQ.rc"
}
must_run() {
    run "$@"
    check 'fixture command succeeds (not a stub)' test "$RC" -eq 0
    if [ "$RC" -ne 0 ]; then cat "$ERR" >&2; exit 1; fi
}
snapshot() {
    python3 - "$1" > "$2" <<'PY'
import hashlib, json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
rows = []
for p in [root] + sorted(root.rglob('*')):
    st = p.lstat()
    content = os.readlink(p) if p.is_symlink() else (hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else '')
    rows.append((str(p.relative_to(root)), stat.S_IMODE(st.st_mode), st.st_mtime_ns, st.st_ino, content))
print(json.dumps(rows, ensure_ascii=True))
PY
}
bad() {
    check "$1: runtime failure is rc2" test "$RC" -eq 2
    check "$1: zero stdout bytes (no success prefix or newline)" test ! -s "$OUT"
    check "$1: diagnostic on stderr" test -s "$ERR"
}
no_write_failure() {
    local label=$1 cwd=$2 before after; shift 2
    before="$BOX/evidence/$((SEQ+1)).before.tree"
    snapshot "$P" "$before"
    run "$cwd" "$@"
    bad "$label"
    after="$BOX/evidence/$SEQ.after.tree"
    snapshot "$P" "$after"
    check "$label: no project writes, including metadata" cmp -s "$before" "$after"
}
success() {
    local label=$1 expected_stderr=${2:-}
    check "$label: rc0" test "$RC" -eq 0
    check "$label: exact fixed confirmation, no extra stdout" cmp -s "$BOX/expected.stdout" "$OUT"
    if [ -n "$expected_stderr" ]; then
        check "$label: exact expected stderr retained" cmp -s "$expected_stderr" "$ERR"
    else
        check "$label: no-warning success stderr is empty" test ! -s "$ERR"
    fi
    check "$label: <=120 Unicode scalars, one line" python3 - "$OUT" <<'PY'
import pathlib, sys
s = pathlib.Path(sys.argv[1]).read_bytes().decode('utf-8')
assert 0 < len(s) <= 120
assert not any(c in s for c in '\n\r\v\f\x85\u2028\u2029')
PY
}
new_project() {
    PROJECT_SEQ=$((PROJECT_SEQ+1)); P="$BOX/project-$PROJECT_SEQ 中文 space"
    mkdir "$P"
    must_run "$P" "$S/handoff-runtime.sh" init
    check 'real init reports initialized' grep -q 'status=initialized' "$OUT"
    check 'real init creates main' test -f "$P/$HX_MAIN_FILE"
    check 'real init creates gotchas' test -f "$P/$HX_GOTCHAS_FILE"
    check 'real init creates logs' test -d "$P/$HX_LOGS_DIR"
    check 'real init creates decisions' test -d "$P/$HX_DEC_DIR"
}
write_log() {
    local number=$1 body=$2
    LOG="$HX_LOGS_DIR/$number-2026-01-02T0304-finalize.md"
    {
        printf '%s\n' '---' 'schema: 2' 'type: dev-log' "number: $number" \
            "title: Finalize integration $number" 'date: 2026-01-02T03:04' '---' \
            '# Finalize integration' '**Trigger**: Integration test.' \
            '**Changes**: Temporary fixture only.' '**Verification**: See declaration, if present.' \
            '**Related**: none.'
        cat "$body"
    } > "$P/$LOG"
}
set_block() { must_run "$P" "$S/hx.sh" block set "$1" --from "$2"; }
late_failure() {
    local label=$1 needle=$2; shift 2
    cp "$P/$HX_MAIN_FILE" "$BOX/late-main.before"
    cp "$P/$LOG" "$BOX/late-log.before"
    run "$P" "$@"
    bad "$label"
    check "$label: expected failing stage" grep -qF -- "$needle" "$ERR"
    check "$label: warns about earlier writes" grep -qF 'earlier writes are not rolled back' "$ERR"
    if cmp -s "$BOX/late-main.before" "$P/$HX_MAIN_FILE"; then
        check "$label: regen must have written before failure" false
    else check "$label: regen wrote before failure" true; fi
    check "$label: updated index names latest log" grep -qF "${LOG##*/}" "$P/$HX_MAIN_FILE"
    check "$label: caller-written log is not rolled back/rewritten" cmp -s "$BOX/late-log.before" "$P/$LOG"
}
printf 'Legacy facts without a verification declaration.\n' > "$BOX/legacy"
printf 'Additional clean document.\n' > "$BOX/additional"
OTHER="$BOX/other"; mkdir "$OTHER"
for S in "$ROOT/scripts" "$ROOT/skills/handoffx/scripts"; do
    printf '\nMirror: %s\n' "$S"
    new_project
    cp "$P/$HX_MAIN_FILE" "$BOX/blank-main"
    # Run a real assertion before rendering a claim; finalize never executes it.
    must_run "$P" -c 'test 1 -eq 1'
    must_run "$P" "$S/handoff-runtime.sh" verification --source runner_report --command 'test 1 -eq 1' --result passed
    cp "$OUT" "$BOX/claim"
    set_block recent "$BOX/claim"
    write_log 0001 "$BOX/claim"
    cp "$P/$LOG" "$BOX/log-before"
    if [ "$S" = "$ROOT/skills/handoffx/scripts" ]; then
        RC=0; (cd "$P" && "$SHELL_BIN" "$S/handoff-runtime.sh" finalize --log "$LOG") >/dev/null 2>&1 || RC=$?
        check 'mirror unbound finalize without --expect-root is refused' test "$RC" -eq 2
    fi
    # Regression: empty optional-root arrays under nounset on /bin/bash 3.2.
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'source/no --expect-root (Bash 3.2 empty-array regression)'
    check 'finalize really regenerates log index' grep -qF "${LOG##*/}" "$P/$HX_MAIN_FILE"
    check 'finalize preserves declared log bytes' cmp -s "$BOX/log-before" "$P/$LOG"
    must_run "$P" "$S/handoff-runtime.sh" verification-check --current --require --match-file "$LOG"
    cp "$BOX/additional" "$P/additional file.md"
    run "$P" "$S/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG" '--files=additional file.md'
    success 'source/explicit expected root and additional target'
    # Expected-root failures may not mutate either the intended or wrong cwd.
    snapshot "$OTHER" "$BOX/other.before"
    no_write_failure 'source wrong cwd' "$OTHER" "$S/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG"
    snapshot "$OTHER" "$BOX/other.after"
    check 'wrong cwd untouched' cmp -s "$BOX/other.before" "$BOX/other.after"
    no_write_failure 'source wrong expected root' "$P" "$S/handoff-runtime.sh" --expect-root "$OTHER" finalize --log "$LOG"
    no_write_failure 'relative expected root' "$P" "$S/handoff-runtime.sh" --expect-root . finalize --log "$LOG"
    no_write_failure 'duplicate expected root' "$P" "$S/handoff-runtime.sh" --expect-root "$P" --expect-root "$P" finalize --log "$LOG"
    no_write_failure 'missing log option' "$P" "$S/handoff-runtime.sh" finalize
    no_write_failure 'missing log value' "$P" "$S/handoff-runtime.sh" finalize --log
    no_write_failure 'empty log value' "$P" "$S/handoff-runtime.sh" finalize --log ''
    no_write_failure 'duplicate log option' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --log "$LOG"
    no_write_failure 'unknown option' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --bogus
    no_write_failure 'custom success text refused' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --text 'invented success'
    no_write_failure 'positional log refused' "$P" "$S/handoff-runtime.sh" finalize "$LOG"
    no_write_failure 'misplaced expected-root refused' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --expect-root "$P"
    no_write_failure 'separate files value refused' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --files 'additional file.md'
    for csv in '' ',x' 'x,' 'x,,y' $'x\ny' $'x\ry' $'x\ty'; do
        no_write_failure 'invalid additional CSV' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" "--files=$csv"
    done
    no_write_failure 'duplicate files option' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG" --files=a --files=b
    for path in "$P/$LOG" "./$LOG" "$HX_LOGS_DIR/../$LOG" "$HX_MAIN_FILE" 'missing.md' "$LOG,other.md"; do
        no_write_failure 'noncanonical or invalid log' "$P" "$S/handoff-runtime.sh" finalize --log "$path"
    done
    OLD_LOG=$LOG
    write_log 0010 "$BOX/claim"
    no_write_failure 'older numbered log refused' "$P" "$S/handoff-runtime.sh" finalize --log "$OLD_LOG"
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'numeric latest log accepted'
    # Only normalized declared fields, not surrounding prose, must match.
    sed 's/result: passed/result: different/' "$BOX/claim" > "$BOX/different"
    write_log 0011 "$BOX/different"
    no_write_failure 'recent/log mismatched result' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'mismatch has its own diagnostic' grep -qF 'declarations differ' "$ERR"
    write_log 0011 "$BOX/legacy"
    no_write_failure 'recent claim but log none' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    set_block recent "$BOX/legacy"
    write_log 0011 "$BOX/claim"
    no_write_failure 'recent none but log claim' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    set_block pending "$BOX/claim"
    no_write_failure 'pending claim cannot stand in for recent' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    set_block recent "$BOX/claim"
    cat "$BOX/claim" "$BOX/claim" > "$BOX/two-claims"
    write_log 0011 "$BOX/two-claims"
    no_write_failure 'different declaration count' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    printf '<!-- verification:v1 -->\nsource: runner_report\n' > "$BOX/malformed"
    write_log 0011 "$BOX/malformed"
    no_write_failure 'malformed log declaration' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    set_block recent "$BOX/malformed"
    write_log 0011 "$BOX/claim"
    no_write_failure 'malformed recent declaration' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    # Legacy compatibility means BOTH absent; not either side absent.
    cp "$BOX/blank-main" "$P/$HX_MAIN_FILE"
    set_block recent "$BOX/legacy"
    write_log 0011 "$BOX/legacy"
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'legacy both-none declarations accepted'
    # Broken pending provenance is current state too: reject before regen, not
    # after refreshing pointers. A new log makes the write boundary observable.
    set_block pending "$BOX/malformed"
    write_log 0012 "$BOX/legacy"
    no_write_failure 'malformed pending declaration before first write' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'pending malformed declaration diagnosed' grep -qF 'unclosed verification stanza' "$ERR"
    # A clean project without numbered logs must fail before regeneration.
    new_project
    no_write_failure 'no numbered log' "$P" "$S/handoff-runtime.sh" finalize --log "$HX_LOGS_DIR/0001-finalize.md"
    write_log 0001 "$BOX/legacy"
    cp "$P/$LOG" "$P/$HX_LOGS_DIR/1-duplicate.md"
    no_write_failure 'duplicate numeric log identity' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    rm "$P/$HX_LOGS_DIR/1-duplicate.md"
    mv "$P/$LOG" "$BOX/symlink-log"
    ln -s "$BOX/symlink-log" "$P/$LOG"
    no_write_failure 'latest log symlink refused' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    rm "$P/$LOG"; mv "$BOX/symlink-log" "$P/$LOG"
    # Decision identities must be checked before regen can update either index.
    for suffix in first second; do
        printf '%s\n' '---' 'schema: 2' 'type: decision' 'number: 0001' \
            'date: 2026-01-02' "title: $suffix" '---' '# Decision fixture' \
            > "$P/$HX_DEC_DIR/0001-2026-01-02-$suffix.md"
    done
    no_write_failure 'duplicate Decision number before first write' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'duplicate Decision identity diagnosed' grep -qF 'number conflict' "$ERR"
    rm "$P/$HX_DEC_DIR/0001-2026-01-02-second.md"
    # State cap is enforced BEFORE regen; total recall cap is checked AFTER.
    python3 -c 'print("s" * 13000)' > "$BOX/oversized-state"
    set_block recent "$BOX/oversized-state"
    no_write_failure 'state exceeds 12288 bytes before first write' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'state budget diagnostic' grep -qF 'limit=12288' "$ERR"
    new_project
    python3 -c 'print("s" * 11000)' > "$BOX/large-state"
    python3 -c 'print("o" * 3500)' > "$BOX/large-continuity"
    python3 -c 'print("<!-- hx:recall -->\n" + "l" * 1900 + "\n<!-- /hx:recall -->")' > "$BOX/large-log"
    set_block recent "$BOX/large-state"
    set_block continuity "$BOX/large-continuity"
    for number in 0001 0002 0003 0004 0005 0006; do write_log "$number" "$BOX/large-log"; done
    # Review #1: old summaries are deferred to metadata instead of failing.
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'total budget overflow defers summaries; finalize succeeds' test "$RC" -eq 0
    new_project
    python3 -c 'print("<!-- hx:recall -->\n" + "l" * 2100 + "\n<!-- /hx:recall -->")' > "$BOX/oversized-summary"
    write_log 0001 "$BOX/oversized-summary"
    # Review #2: the recall preflight runs before regen, so nothing is written.
    no_write_failure 'oversized log summary fails before first write' "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'summary preflight diagnostic' grep -qF 'maximum 2048 bytes' "$ERR"
    check 'preflight reports nothing regenerated' grep -qF 'finalize: recall preflight failed; nothing regenerated' "$ERR"
    # Real credential scanner: synthetic non-secret match, never a user key.
    new_project
    write_log 0001 "$BOX/legacy"
    { printf '\nSynthetic scanner fixture: '; printf 'ghp_'; printf '%036d\n' 123; } >> "$P/$HX_GOTCHAS_FILE"
    late_failure 'real credential scan blocks success' '凭证扫描' "$S/handoff-runtime.sh" finalize --log "$LOG"
    check 'credential failure is postflight stage' grep -qF 'finalize: postflight failed' "$ERR"
    # Actual postflight target/xref validation; no fake failed postflight.
    new_project
    write_log 0001 "$BOX/legacy"
    printf 'Dev Log 7777\n' > "$P/extra.md"
    late_failure 'additional target broken xref' '交叉引用' "$S/handoff-runtime.sh" finalize --log "$LOG" --files=extra.md
    new_project
    write_log 0001 "$BOX/legacy"
    late_failure 'missing additional target' 'postflight failed' "$S/handoff-runtime.sh" finalize --log "$LOG" --files=missing.md
    # Real near-expiry warning: no mocked date, scanner, postflight or archive.
    # Use local today +3 days, matching rotation-reminder's local calendar.
    new_project
    write_log 0001 "$BOX/legacy"
    cp "$P/$HX_MAIN_FILE" "$BOX/pre-warning-main"
    python3 - "$P/$HX_MAIN_FILE" <<'PYWARNING'
import datetime, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
soon = (datetime.date.today() + datetime.timedelta(days=3)).isoformat()
text, count = re.subn(r'^\| <service> \|.*$', '| Rotation fixture | vault://safe | ' + soon + ' |', p.read_text(), flags=re.M)
assert count == 1, 'Expected exactly one credential template row'
p.write_text(text)
PYWARNING
    must_run "$P" "$S/hx.sh" regen
    run "$P" "$S/rotation-reminder.sh" --classify "$HX_MAIN_FILE"
    check 'real rotation classifies fixture as non-blocking warning' test "$RC" -eq 3
    check 'rotation actually saw service row' grep -qF 'Rotation fixture' "$OUT"
    run "$P" "$S/handoff-postflight.sh" --brief "--files=$LOG" "$HX_MAIN_FILE"
    check 'real postflight accepts near-expiry warning' test "$RC" -eq 0
    check 'real postflight emits warning, not normal success' grep -qF '⚠️' "$OUT"
    check 'real postflight identifies near expiry' grep -qF '凭证临近到期（非阻断）' "$OUT"
    cp "$OUT" "$BOX/expected-warning.stderr"
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'real rotation warning preserved without duplicating stdout' "$BOX/expected-warning.stderr"
    check 'finalize warning still visible on stderr' grep -qF '凭证临近到期（非阻断）' "$ERR"
    # Clearing the fixture must restore complete stderr silence, not cached warning.
    cp "$BOX/pre-warning-main" "$P/$HX_MAIN_FILE"
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'normal success after warning is quiet again'
    # Explicit failure injection ONLY after the actual downstream command ran.
    # Wrapped hx still invokes the real regen; wrapped postflight still runs all
    # its real checks. A passive control proves wrappers do not manufacture pass.
    INJECT="$BOX/inject-$PROJECT_SEQ"; mkdir -p "$INJECT/scripts" "$INJECT/assets"
    cp -R "$S/." "$INJECT/scripts/"
    cp -R "$ROOT/skills/handoffx/assets/." "$INJECT/assets/"
    mv "$INJECT/scripts/hx.sh" "$INJECT/scripts/real-hx.sh"
    mv "$INJECT/scripts/handoff-postflight.sh" "$INJECT/scripts/real-postflight.sh"
    cat > "$INJECT/scripts/hx.sh" <<'WRAPPER'
#!/bin/bash
SD=$(cd "$(dirname "$0")" && pwd -P)
bash "$SD/real-hx.sh" "$@" || exit "$?"
if [ "${1:-}" = regen ]; then
    printf 'real-regen-completed\n' >> "$FINALIZE_TRACE"
    if [ "${FINALIZE_FAIL_STAGE:-}" = regen ]; then
        printf 'INJECTED_REGEN_STDOUT\n'; printf 'injected failure AFTER real regen\n' >&2; exit 73
    fi
fi
WRAPPER
    cat > "$INJECT/scripts/handoff-postflight.sh" <<'WRAPPER'
#!/bin/bash
SD=$(cd "$(dirname "$0")" && pwd -P)
bash "$SD/real-postflight.sh" "$@" || exit "$?"
printf 'real-postflight-completed\n' >> "$FINALIZE_TRACE"
if [ "${FINALIZE_FAIL_STAGE:-}" = postflight ]; then
    printf 'INJECTED_POSTFLIGHT_STDOUT\n'; printf 'injected failure AFTER real postflight\n' >&2; exit 73
elif [ "${FINALIZE_FAIL_STAGE:-}" = notice ]; then
    printf 'INJECTED_UNFAMILIAR_SUCCESS_NOTICE\n'
fi
WRAPPER
    export FINALIZE_TRACE="$BOX/injection.trace" FINALIZE_FAIL_STAGE=''
    new_project; write_log 0001 "$BOX/legacy"; : > "$FINALIZE_TRACE"
    run "$P" "$INJECT/scripts/handoff-runtime.sh" finalize --log "$LOG"
    success 'passive wrapper control still runs actual pipeline'
    check 'control ran actual regen' grep -qF real-regen-completed "$FINALIZE_TRACE"
    check 'control ran actual postflight' grep -qF real-postflight-completed "$FINALIZE_TRACE"
    # Extra success diagnostics are simulated explicitly AFTER real postflight.
    # Only the exact normal summary may disappear; unfamiliar output must survive.
    export FINALIZE_FAIL_STAGE=notice
    printf '%s\n' '✅ 交接检查通过，归档检查完成。' 'INJECTED_UNFAMILIAR_SUCCESS_NOTICE' > "$BOX/expected-notice.stderr"
    run "$P" "$INJECT/scripts/handoff-runtime.sh" finalize --log "$LOG"
    success 'unfamiliar successful child output is not suppressed' "$BOX/expected-notice.stderr"
    new_project; write_log 0001 "$BOX/legacy"; : > "$FINALIZE_TRACE"
    export FINALIZE_FAIL_STAGE=regen
    late_failure 'injected failure after real regen' 'finalize: regen failed' "$INJECT/scripts/handoff-runtime.sh" finalize --log "$LOG"
    check 'regen child stdout redirected to stderr' grep -qF INJECTED_REGEN_STDOUT "$ERR"
    check 'injected regen ran real regen' grep -qF real-regen-completed "$FINALIZE_TRACE"
    if grep -qF real-postflight-completed "$FINALIZE_TRACE"; then check 'no postflight after failed regen' false; else check 'no postflight after failed regen' true; fi
    new_project; write_log 0001 "$BOX/legacy"; : > "$FINALIZE_TRACE"
    export FINALIZE_FAIL_STAGE=postflight
    late_failure 'injected failure after real postflight' 'finalize: postflight failed' "$INJECT/scripts/handoff-runtime.sh" finalize --log "$LOG"
    check 'postflight child stdout withheld on failure' grep -qF INJECTED_POSTFLIGHT_STDOUT "$ERR"
    check 'injected postflight ran real postflight' grep -qF real-postflight-completed "$FINALIZE_TRACE"
    unset FINALIZE_TRACE FINALIZE_FAIL_STAGE
    printf 'mirror subtotal: %s passed, %s failed\n' "$PASS" "$FAIL"
done
# Real installer, isolated HOME. Keep the caller HOME for runtime's legacy peer
# classification, as in test_root_proof.sh; no access to real host installations.
INSTALL_HOME="$BOX/home"
# The positional parameters are intentionally expanded by the child shell.
# shellcheck disable=SC2016
must_run "$ROOT" -c 'HOME="$1" XDG_CONFIG_HOME="$1/.config" CODEX_HOME="$1/.codex" HANDOFF_TEST_WSL_HOME="$1/wsl" bash "$2/install.sh" --claude' _ "$INSTALL_HOME" "$ROOT"
G="$INSTALL_HOME/.claude/skills/handoffx/scripts"
S="$ROOT/scripts"; new_project; write_log 0001 "$BOX/legacy"
no_write_failure 'global requires explicit expected root' "$P" "$G/handoff-runtime.sh" finalize --log "$LOG"
no_write_failure 'global wrong expected root' "$P" "$G/handoff-runtime.sh" --expect-root "$OTHER" finalize --log "$LOG"
no_write_failure 'global wrong cwd with intended root' "$OTHER" "$G/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG"
run "$P" "$G/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG"
success 'real global install explicit expected-root success'
# Project installation is a real installation, not a handwritten manifest.
# The positional parameters are intentionally expanded by the child shell.
# shellcheck disable=SC2016
must_run "$ROOT" -c 'HOME="$1" XDG_CONFIG_HOME="$1/.config" CODEX_HOME="$1/.codex" HANDOFF_TEST_WSL_HOME="$1/wsl" bash "$2/install.sh" --project "$3"' _ "$INSTALL_HOME" "$ROOT" "$P"
L="$P/.claude/skills/handoffx/scripts"
run "$P" "$L/handoff-runtime.sh" finalize --log "$LOG"
success 'real project install bound root, no explicit root needed'
run "$P" "$L/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG"
success 'real project install matching expected root'
no_write_failure 'project wrong expected root' "$P" "$L/handoff-runtime.sh" --expect-root "$OTHER" finalize --log "$LOG"
no_write_failure 'project wrong cwd even with matching explicit cwd' "$OTHER" "$L/handoff-runtime.sh" --expect-root "$OTHER" finalize --log "$LOG"
no_write_failure 'project wrong cwd without expected root' "$OTHER" "$L/handoff-runtime.sh" finalize --log "$LOG"
no_write_failure 'global cannot bypass local project install' "$P" "$G/handoff-runtime.sh" --expect-root "$P" finalize --log "$LOG"
# Periodic pending review (wip/plans/2026-11-18-pending-review-design.md): the
# removed pending text is archived as a fenced quote under **Changes** of the
# current log. Field headings inside that fence must not become the log's
# verification field, and finalize must still accept the log unchanged.
for S in "$ROOT/scripts" "$ROOT/skills/handoffx/scripts"; do
    new_project
    must_run "$P" -c 'test 1 -eq 1'
    must_run "$P" "$S/handoff-runtime.sh" verification --source runner_report --command 'test 1 -eq 1' --result passed
    cp "$OUT" "$BOX/review-claim"
    set_block recent "$BOX/review-claim"
    printf -- '- [ ] KEEP_TASK\n' > "$BOX/review-pending"
    set_block pending "$BOX/review-pending"
    LOG="$HX_LOGS_DIR/0001-2026-01-02T0304-review.md"
    {
        printf '%s\n' '---' 'schema: 2' 'type: dev-log' 'number: 0001' \
            'title: Pending review archive' 'date: 2026-01-02T03:04' '---' \
            '# Pending review archive' '**Trigger**: Integration test.' \
            '**Changes**: Pending review (approved in this session) removed 1 item:' \
            '````' '- [ ] OLD_TASK owner=Alice' '**验证**: OLD_FIELD_TEXT' '```' 'old snippet' '```' '````' \
            '**Verification**:'
        cat "$BOX/review-claim"
        printf '%s\n' '**Related**: none.'
    } > "$P/$LOG"
    must_run "$P" "$S/handoff-runtime.sh" review-due --log "$LOG"
    printf 'log_number=1\npending_bytes=16\npending_review_due=0\n' > "$BOX/review-expected"
    check 'review-due on archived-audit log reports exact counters' cmp -s "$BOX/review-expected" "$OUT"
    run "$P" "$S/handoff-runtime.sh" finalize --log "$LOG"
    success 'finalize accepts fenced pending-review archive'
    must_run "$P" "$S/handoff-runtime.sh" verification-check --current --require --match-file "$LOG"
    OLD_LOG=$LOG
    write_log 0002 "$BOX/review-claim"
    run "$P" "$S/handoff-runtime.sh" review-due --log "$OLD_LOG"
    bad 'review-due refuses a log that is no longer latest'
    run "$P" "$S/handoff-runtime.sh" finalize --log "$OLD_LOG"
    bad 'finalize refuses a log that is no longer latest'
done
# Confirm observed parent AND children, including installed copies and PATH bash,
# used the selected real executable/version. A symlink is not a fake interpreter.
check 'actual Bash parent/child versions and executables match selected shell' python3 - "$FINALIZE_SHELL_AUDIT" "$SHELL_BIN" "$SELECTED_BASH_VERSION" <<'PYVERSIONS'
import os, pathlib, sys
rows = [line.split('\t') for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert rows and all(len(row) == 5 for row in rows)
expected_exe, expected_version = os.path.realpath(sys.argv[2]), sys.argv[3]
assert all(os.path.realpath(row[0]) == expected_exe and row[1] == expected_version for row in rows), rows
roles = {pathlib.Path(row[4]).name for row in rows}
assert {'test_finalize.sh', 'handoff-runtime.sh', 'hx.sh', 'handoff-postflight.sh', 'rotation-reminder.sh'} <= roles, roles
runtime_pids = {row[2] for row in rows if pathlib.Path(row[4]).name == 'handoff-runtime.sh'}
assert any(pathlib.Path(row[4]).name == 'hx.sh' and row[3] in runtime_pids for row in rows), 'No runtime -> hx child observed'
assert any(pathlib.Path(row[4]).name == 'handoff-postflight.sh' and row[3] in runtime_pids for row in rows), 'No runtime -> postflight child observed'
PYVERSIONS
printf 'Bash parent/child audit: %s\n' "$FINALIZE_SHELL_AUDIT"
printf '\nfinalize: %s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
