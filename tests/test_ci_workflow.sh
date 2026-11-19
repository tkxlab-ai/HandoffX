#!/bin/bash
# test_ci_workflow.sh — CI must enforce local release/test gates
source "$(dirname "$0")/common.sh"

WF="$ROOT_DIR/.github/workflows/ci.yml"
assert_file_exists "CI workflow exists" "$WF"

content=$(cat "$WF" 2>/dev/null || true)
assert_contains "CI runs full test suite" "$content" "bash tests/run_all.sh"
assert_contains "CI runs release dry-run audit" "$content" "bash release.sh --dry-run-audit"
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

summary
