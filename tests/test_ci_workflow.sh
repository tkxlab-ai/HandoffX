#!/bin/bash
# test_ci_workflow.sh — CI must enforce local release/test gates
source "$(dirname "$0")/common.sh"

WF="$ROOT_DIR/.github/workflows/ci.yml"
assert_file_exists "CI workflow exists" "$WF"

content=$(cat "$WF" 2>/dev/null || true)
# Anchored as a live `run:` line: a commented-out step still contains the substring (Qwen L0100 #6).
assert_exit "CI runs full test suite" 0 "$(grep -qE '^[[:space:]]+run: .*bash tests/run_all\.sh$' "$WF" && echo 0 || echo 1)"
assert_exit "CI runs release dry-run audit" 0 "$(grep -qE '^[[:space:]]+run: .*bash release\.sh --dry-run-audit' "$WF" && echo 0 || echo 1)"
assert_contains "CI installs shellcheck" "$content" "shellcheck"
assert_contains "CI runs on pull_request" "$content" "pull_request"
assert_contains "CI runs on push" "$content" "push"

# run_all.sh summary must count ➖ skips: the distribution contract ("exactly the
# artifact gate + git-only sections skip") is checked against that number, and a
# green line with an unseen skip is how a gate silently stops running.
# Runs the real run_all.sh copied next to two stub suites, so the loop under test
# is the shipped one, not a re-implementation.
RA=$(mktemp -d); mkdir -p "$RA/tests"
cp "$ROOT_DIR/tests/run_all.sh" "$RA/tests/"
printf '#!/bin/bash\necho "  ✅ fine"\necho "  ➖ something SKIPPED"\necho "  ✅ a label that mentions ➖ in passing"\nexit 0\n' > "$RA/tests/test_a_pass.sh"
printf '#!/bin/bash\necho "  ❌ broken"\nexit 1\n' > "$RA/tests/test_b_fail.sh"
rc=0; ra_out=$(bash "$RA/tests/run_all.sh" 2>&1) || rc=$?
assert_exit "run_all: one failing suite → exit 1" 1 "$rc"
assert_contains "run_all: summary counts the one ➖ line" "$ra_out" "Failing suites: 1 ❌ (skipped: 1)"
assert_contains "run_all: suite output still reaches the log" "$ra_out" "➖ something SKIPPED"
rm -f "$RA/tests/test_b_fail.sh"
rc=0; ra_out=$(bash "$RA/tests/run_all.sh" 2>&1) || rc=$?
assert_exit "run_all: all pass with a skip → still exit 0" 0 "$rc"
assert_contains "run_all: green summary carries the skip count" "$ra_out" "All suites passed ✅ (skipped: 1)"
rm -rf "$RA"

# ── v4.4.0 #14: linux-container.sh --keep-log ────────────────────────────────
# The container is started with --rm and only ❌ lines are echoed, so the full
# log dies with it; diagnosing a Linux-only failure then needs a hand-typed
# docker session. --keep-log copies it out and keeps the runner's exit code.
LC=$(mktemp -d); mkdir -p "$LC/tests" "$LC/Release/v0" "$LC/wip/logs"
ln -s v0 "$LC/Release/latest"
printf 'stub\n' > "$LC/Release/CHANGELOG.md"
cp "$ROOT_DIR/tests/linux-container.sh" "$LC/tests/"
BIN="$LC/bin"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'FAKE'
#!/bin/bash
# fake docker: find "-v HOST:/lclog", write the log the inner script would write
logdir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -v) case "$2" in *:/lclog) logdir="${2%%:*}" ;; esac; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$logdir" ] || exit 9
printf 'FULL-LOG-LINE\n' > "$logdir/run_all.log"
exit 3
FAKE
chmod +x "$BIN/docker"
rc=0; out=$(PATH="$BIN:$PATH" bash "$LC/tests/linux-container.sh" --keep-log 2>&1) || rc=$?
assert_exit "linux-container --keep-log: runner exit code passes through" 3 "$rc"
kept=$(ls "$LC"/wip/logs/linux-container-*.log 2>/dev/null | head -1)
assert_exit "linux-container --keep-log: log kept on the host" 0 "$([ -n "$kept" ] && echo 0 || echo 1)"
assert_contains "linux-container --keep-log: kept log has the full output" "$(cat "$kept" 2>/dev/null)" "FULL-LOG-LINE"
assert_contains "linux-container --keep-log: path printed" "$out" "$kept"
rm -f "$LC"/wip/logs/linux-container-*.log
rc=0; PATH="$BIN:$PATH" bash "$LC/tests/linux-container.sh" >/dev/null 2>&1 || rc=$?
assert_exit "linux-container without --keep-log: no log left behind" 0 \
    "$(ls "$LC"/wip/logs/linux-container-*.log >/dev/null 2>&1 && echo 1 || echo 0)"
rm -rf "$LC"

summary
