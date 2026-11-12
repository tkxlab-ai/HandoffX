#!/bin/bash
# test_handoff_postflight.sh — v2.1.0 UX #3: aggregator script runs all 5
# post-handoff checks (scan / validate / lint / rotation / archive) with
# unified summary.
source "$(dirname "$0")/common.sh"

POSTFLIGHT="$SCRIPTS_DIR/handoff-postflight.sh"
SKILL_TEMPLATES="$ROOT_DIR/skills/handoffx/assets"

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
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_OK/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_OK/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_OK/${HX_LOGS_DIR}" "$SANDBOX_OK/${HX_DEC_DIR}"
out_ok=$(bash "$POSTFLIGHT" "$SANDBOX_OK/${HX_MAIN_FILE}" 2>&1)
ec_ok=$?
assert_exit "T4: valid v2 → exit 0" 0 "$ec_ok"
assert_contains "T4: summary says all passed" "$out_ok" "all checks passed"
rm -rf "$SANDBOX_OK"

# T5: --quiet mode suppresses per-check details, prints only summary
SANDBOX_Q=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_Q/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_Q/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_Q/${HX_LOGS_DIR}" "$SANDBOX_Q/${HX_DEC_DIR}"
out_q=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_Q/${HX_MAIN_FILE}" 2>&1)
ec_q=$?
assert_exit "T5: --quiet on valid → exit 0" 0 "$ec_q"
assert_contains "T5: --quiet still prints summary" "$out_q" "all checks passed"
# --quiet should NOT print per-step "→ 1. scan-credentials" headers
if echo "$out_q" | grep -q "→ 1\."; then
    echo "  ❌ T5: --quiet leaked per-step output"; FAIL=$((FAIL+1))
else
    echo "  ✅ T5: --quiet suppresses per-step output"; PASS=$((PASS+1))
fi
rm -rf "$SANDBOX_Q"

# T6: file path flexibility — flag and positional in any order
SANDBOX_POS=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_POS/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_POS/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_POS/${HX_LOGS_DIR}" "$SANDBOX_POS/${HX_DEC_DIR}"
# file then flag
out_p1=$(bash "$POSTFLIGHT" "$SANDBOX_POS/${HX_MAIN_FILE}" --quiet 2>&1)
ec_p1=$?
assert_exit "T6a: file then --quiet → exit 0" 0 "$ec_p1"
# flag then file
out_p2=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_POS/${HX_MAIN_FILE}" 2>&1)
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
cat > "$SANDBOX_BAD/${HX_MAIN_FILE}" <<'EOF'
# Demo
no sections, no anchor, definitely incomplete
EOF
out_bad=$(bash "$POSTFLIGHT" "$SANDBOX_BAD/${HX_MAIN_FILE}" 2>&1)
ec_bad=$?
assert_exit "T8: bad file → exit 1" 1 "$ec_bad"
assert_contains "T8: summary lists failure count" "$out_bad" "check(s) failed"
rm -rf "$SANDBOX_BAD"

# --- Task 5: postflight --files runs B① xref-lint ---
PF_W="$TMP_DIR/pf-files-$$"; rm -rf "$PF_W"; mkdir -p "$PF_W/${HX_LOGS_DIR}"
printf '<!-- HANDOFF v2 schema -->\n# H\n## 🎯 Current State\n' > "$PF_W/${HX_MAIN_FILE}"
ngf="$PF_W/ng.md"; printf 'dangling Dev Log 7777\n' > "$ngf"
out_files=$(bash "$POSTFLIGHT" --files="$ngf" "$PF_W/${HX_MAIN_FILE}" 2>&1)
ec_files=$?
assert_exit "T9: postflight --files= with dangling ref → exit 1" 1 "$ec_files"
assert_contains "T9: xref-lint runs and reports" "$out_files" "xref-lint"
out_help_files=$(bash "$POSTFLIGHT" --help 2>&1)
assert_contains "T9: --help still works" "$out_help_files" "Usage"
rm -rf "$PF_W"

# --- F3: --files= glob expansion must NOT occur ---
# Without set -f, --files='*.md' expands to all .md files in CWD, causing
# xref-lint to run on files not in the explicit write-target set (ADR-0004
# violation). Fixed behaviour: '*.md' is treated as a literal path; since no
# file literally named '*.md' exists, xref-lint skips it (missing file) →
# no spurious exit 1 from globbed a.md's dangling ref.
# Assertion: xref-lint output must NOT mention a.md's dangling ref (Dev Log 7777).
# We use a valid v2 sandbox so checks 1-5 pass; only check 6 output is inspected.
F3_DIR=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$F3_DIR/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$F3_DIR/${HX_GOTCHAS_FILE}"
mkdir -p "$F3_DIR/${HX_LOGS_DIR}" "$F3_DIR/${HX_DEC_DIR}"
printf 'dangling Dev Log 7777\n' > "$F3_DIR/a.md"
printf 'clean content\n'          > "$F3_DIR/b.md"
# Run from F3_DIR so that '*.md' would glob-expand if set -f is absent.
# With the fix: literal '*.md' path doesn't exist → xref-lint skips it → no "Dev Log 7777" output.
# Without the fix: '*.md' globs to a.md+b.md+${HX_MAIN_FILE} → a.md has dangling ref → output contains it.
f3_out=$(cd "$F3_DIR" && bash "$POSTFLIGHT" --files='*.md' "$HX_MAIN_FILE" 2>&1)
assert_not_contains "F3: glob NOT expanded — Dev Log 7777 not reported" "$f3_out" "Dev Log 7777"
rm -rf "$F3_DIR"

# --- F5: empty --files= is a distinct usage error (exit 2), not silent skip ---
F5W="$TMP_DIR/pf-f5-$$"; rm -rf "$F5W"; mkdir -p "$F5W"
printf '<!-- HANDOFF v2 schema -->\n# H\n## 🎯 Current State\n' > "$F5W/${HX_MAIN_FILE}"
assert_exit "F5: empty --files= -> exit 2 usage error" 2 "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --files= "$F5W/${HX_MAIN_FILE}" >/dev/null 2>&1; echo $?)"
assert_contains "F5: --help still works (no-flag path intact)" "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --help 2>&1)" "Usage"
rm -rf "$F5W"

# --- P2.4 §4b-4 legacy-layout guard: postflight must stop with exit 2 and the
# upgrade command instead of running five checks against a missing main file.
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
ec=0; out=$(cd "$LG" && bash "$POSTFLIGHT" 2>&1) || ec=$?
assert_exit "legacy v3 tree → postflight exit 2" 2 "$ec"
assert_contains "legacy v3 tree → names schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
rm -rf "$LG"
LG=$(mktemp -d); cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$LG/$HX_LEGACY_MAIN_FILE"
ec=0; out=$(bash "$POSTFLIGHT" "$LG/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "legacy v1 file → postflight exit 2" 2 "$ec"
assert_contains "legacy v1 file → names migrate-to-v2 --apply" "$out" "migrate-to-v2.sh --apply"
rm -rf "$LG"
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
cp "$LG/$HX_LEGACY_MAIN_FILE" "$LG/$HX_MAIN_FILE"
ec=0; out=$(bash "$POSTFLIGHT" "$LG/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "mixed legacy+new → postflight exit 2" 2 "$ec"
assert_contains "mixed legacy+new → names the mixed state" "$out" "mixed layout"
assert_contains "mixed legacy+new → names a legacy piece" "$out" "$HX_LEGACY_LOGS_DIR"
rm -rf "$LG"

summary
