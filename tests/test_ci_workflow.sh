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

summary
