#!/bin/bash
# test_handoff_postflight.sh — v2.1.0 UX #3: aggregator script runs all 5
# post-handoff checks (scan / validate / lint / rotation / archive) with
# unified summary.
source "$(dirname "$0")/common.sh"

POSTFLIGHT="$SCRIPTS_DIR/handoff-postflight.sh"
SKILL_TEMPLATES="$ROOT_DIR/skills/handoff/assets"

# T1: script exists and is executable
assert_file_exists "postflight.sh exists" "$POSTFLIGHT"
[ -x "$POSTFLIGHT" ] && { echo "  ✅ postflight.sh is executable"; PASS=$((PASS+1)); } || { echo "  ❌ postflight.sh not executable"; FAIL=$((FAIL+1)); }

# T2: -h / --help shows the 5 checks (self-documenting)
out_help=$(bash "$POSTFLIGHT" -h 2>&1)
assert_contains "T2: help mentions scan-credentials" "$out_help" "scan-credentials"
assert_contains "T2: help mentions validate-handoff" "$out_help" "validate-handoff"
assert_contains "T2: help mentions handoff-lint" "$out_help" "handoff-lint"
assert_contains "T2: help mentions rotation-reminder" "$out_help" "rotation-reminder"
assert_contains "T2: help mentions archive-devlog" "$out_help" "archive-devlog"

# T3: missing file → exit 2 + clear error
SANDBOX_MISS=$(mktemp -d)
out_miss=$(bash "$POSTFLIGHT" "$SANDBOX_MISS/nonexistent.md" 2>&1)
ec_miss=$?
assert_exit "T3: missing file → exit 2" 2 "$ec_miss"
assert_contains "T3: missing file error message" "$out_miss" "not found"
rm -rf "$SANDBOX_MISS"

# T4: valid v2 layout → exit 0 + "all 5 checks passed" summary
SANDBOX_OK=$(mktemp -d)
cp "$SKILL_TEMPLATES/HANDOFF.template.md" "$SANDBOX_OK/HANDOFF.md"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_OK/GOTCHAS.md"
mkdir -p "$SANDBOX_OK/Handoff_Logs" "$SANDBOX_OK/Handoff_Decisions"
out_ok=$(bash "$POSTFLIGHT" "$SANDBOX_OK/HANDOFF.md" 2>&1)
ec_ok=$?
assert_exit "T4: valid v2 → exit 0" 0 "$ec_ok"
assert_contains "T4: summary says all passed" "$out_ok" "all 5 checks passed"
rm -rf "$SANDBOX_OK"

# T5: --quiet mode suppresses per-check details, prints only summary
SANDBOX_Q=$(mktemp -d)
cp "$SKILL_TEMPLATES/HANDOFF.template.md" "$SANDBOX_Q/HANDOFF.md"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_Q/GOTCHAS.md"
mkdir -p "$SANDBOX_Q/Handoff_Logs" "$SANDBOX_Q/Handoff_Decisions"
out_q=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_Q/HANDOFF.md" 2>&1)
ec_q=$?
assert_exit "T5: --quiet on valid → exit 0" 0 "$ec_q"
assert_contains "T5: --quiet still prints summary" "$out_q" "all 5 checks passed"
# --quiet should NOT print per-step "→ 1. scan-credentials" headers
if echo "$out_q" | grep -q "→ 1\."; then
    echo "  ❌ T5: --quiet leaked per-step output"; FAIL=$((FAIL+1))
else
    echo "  ✅ T5: --quiet suppresses per-step output"; PASS=$((PASS+1))
fi
rm -rf "$SANDBOX_Q"

# T6: file path flexibility — flag and positional in any order
SANDBOX_POS=$(mktemp -d)
cp "$SKILL_TEMPLATES/HANDOFF.template.md" "$SANDBOX_POS/HANDOFF.md"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_POS/GOTCHAS.md"
mkdir -p "$SANDBOX_POS/Handoff_Logs" "$SANDBOX_POS/Handoff_Decisions"
# file then flag
out_p1=$(bash "$POSTFLIGHT" "$SANDBOX_POS/HANDOFF.md" --quiet 2>&1)
ec_p1=$?
assert_exit "T6a: file then --quiet → exit 0" 0 "$ec_p1"
# flag then file
out_p2=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_POS/HANDOFF.md" 2>&1)
ec_p2=$?
assert_exit "T6b: --quiet then file → exit 0" 0 "$ec_p2"
rm -rf "$SANDBOX_POS"

# T7: unknown flag → exit 2
out_uf=$(bash "$POSTFLIGHT" --bogus 2>&1)
ec_uf=$?
assert_exit "T7: unknown flag → exit 2" 2 "$ec_uf"
assert_contains "T7: unknown flag error" "$out_uf" "unknown flag"

# T8: failing check → exit 1 + summary names which failed
# Use a v1-marker-less file with missing required structure to trip validate
SANDBOX_BAD=$(mktemp -d)
cat > "$SANDBOX_BAD/HANDOFF.md" <<'EOF'
# Demo
no sections, no anchor, definitely incomplete
EOF
out_bad=$(bash "$POSTFLIGHT" "$SANDBOX_BAD/HANDOFF.md" 2>&1)
ec_bad=$?
assert_exit "T8: bad file → exit 1" 1 "$ec_bad"
assert_contains "T8: summary lists failure count" "$out_bad" "checks failed"
rm -rf "$SANDBOX_BAD"

summary
