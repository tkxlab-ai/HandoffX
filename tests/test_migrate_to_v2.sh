#!/bin/bash
source "$(dirname "$0")/common.sh"

# Setup: copy fixture into a sandbox
SANDBOX=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX/${HX_LEGACY_MAIN_FILE}"

# Run dry-run
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --dry-run --root "$SANDBOX" 2>&1)
ec=$?

assert_exit "B2: dry-run exit 0" 0 "$ec"
assert_contains "B2: dry-run mentions Dev Log count" "$out" "Dev Log: 2"
assert_contains "B2: dry-run mentions Decision count" "$out" "Decision Log: 2"
assert_contains "B2: dry-run mentions Gotchas count" "$out" "Gotcha"
# v1 → v4: the plan must say the main file is renamed, not rewritten in place
assert_contains "B2: dry-run names the main-file rename" "$out" "${HX_LEGACY_MAIN_FILE} → ${HX_MAIN_FILE}"

# No files should have been created (dry-run is no-op)
[ -d "$SANDBOX/${HX_LOGS_DIR}" ] && { echo "  ❌ B2: dry-run created ${HX_LOGS_DIR}/"; FAIL=$((FAIL+1)); } || { echo "  ✅ B2: dry-run no side effect"; PASS=$((PASS+1)); }

rm -rf "$SANDBOX"

# B2.6: --root without value should fail gracefully
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --root 2>&1)
ec=$?
assert_exit "B2.6: --root without value exits 1" 1 "$ec"
assert_contains "B2.6: --root error message clear" "$out" "requires"

# B2.7: Dev Log count should not include entries from sections after Dev Log
SANDBOX3=$(mktemp -d)
cat > "$SANDBOX3/${HX_LEGACY_MAIN_FILE}" <<'EOF'
# Handoff
## 📜 Development Log
### 2026-05-01 14:00 — entry 1
content
### 2026-04-30 10:00 — entry 2
content
## 📌 PostScript
### 2026-05-02 — should NOT be counted
This section is after Dev Log
EOF
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --dry-run --root "$SANDBOX3" 2>&1)
assert_contains "B2.7: Dev Log count stops at section boundary (=2 not 3)" "$out" "Dev Log: 2"
rm -rf "$SANDBOX3"

# B3: --apply creates ${HX_LOGS_DIR}/ with per-file entries from fixture
SANDBOX_B3=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B3/${HX_LEGACY_MAIN_FILE}"

bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B3" >/dev/null 2>&1
ec=$?

assert_exit "B3: --apply exits 0 (Dev Log only)" 0 "$ec"
[ -d "$SANDBOX_B3/${HX_LOGS_DIR}" ] && { echo "  ✅ B3: ${HX_LOGS_DIR}/ created"; PASS=$((PASS+1)); } || { echo "  ❌ B3: ${HX_LOGS_DIR}/ missing"; FAIL=$((FAIL+1)); }

# Should have 2 Dev Log entry files (fixture has 2)
n=$(ls "$SANDBOX_B3/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B3: 2 Dev Log files created" "$n" "2"

# Filename pattern check
[ -f "$SANDBOX_B3/${HX_LOGS_DIR}/0001-2026-04-30T1000-"*.md ] && { echo "  ✅ B3: 0001 oldest entry"; PASS=$((PASS+1)); } || { echo "  ❌ B3: 0001 file pattern wrong"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_B3/${HX_LOGS_DIR}/0002-2026-05-01T1400-"*.md ] && { echo "  ✅ B3: 0002 newest entry"; PASS=$((PASS+1)); } || { echo "  ❌ B3: 0002 file pattern wrong"; FAIL=$((FAIL+1)); }

# Frontmatter check
first_entry=$(ls "$SANDBOX_B3/${HX_LOGS_DIR}/0001-"*.md | head -1)
head -1 "$first_entry" | grep -q '^---$' && { echo "  ✅ B3: entry frontmatter starts with ---"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing frontmatter"; FAIL=$((FAIL+1)); }
grep -q '^schema: 2$' "$first_entry" && { echo "  ✅ B3: frontmatter schema:2"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing schema"; FAIL=$((FAIL+1)); }
grep -q '^type: dev-log$' "$first_entry" && { echo "  ✅ B3: frontmatter type:dev-log"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing type"; FAIL=$((FAIL+1)); }
grep -q '^number: 0001$' "$first_entry" && { echo "  ✅ B3: frontmatter number:0001"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing number"; FAIL=$((FAIL+1)); }

# Backup created
[ -f "$SANDBOX_B3/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] && { echo "  ✅ B3: backup file created"; PASS=$((PASS+1)); } || { echo "  ❌ B3: no backup"; FAIL=$((FAIL+1)); }

# B6 builds the new ${HX_MAIN_FILE} (v2 pointer layout) from the legacy main; the backup keeps the v1 original
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B3/${HX_MAIN_FILE}" && { echo "  ✅ B3: ${HX_MAIN_FILE} now has v2 marker (B6 ran)"; PASS=$((PASS+1)); } || { echo "  ❌ B3: ${HX_MAIN_FILE} missing v2 marker"; FAIL=$((FAIL+1)); }
diff -q "$SANDBOX_B3/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" >/dev/null 2>&1 && { echo "  ✅ B3: backup is original v1 content"; PASS=$((PASS+1)); } || { echo "  ❌ B3: backup mismatch"; FAIL=$((FAIL+1)); }

# B3-v4: success-state contract of the v1 → v4 rename. Why each clause: a stale
# legacy main beside the new one would trip every legacy-layout guard (and read
# as MIXED to schema-upgrade); the backup is the only copy of the v1 bytes.
[ ! -e "$SANDBOX_B3/${HX_LEGACY_MAIN_FILE}" ] && { echo "  ✅ B3-v4: legacy main retired on success"; PASS=$((PASS+1)); } || { echo "  ❌ B3-v4: legacy main still present after success"; FAIL=$((FAIL+1)); }
{ [ -f "$SANDBOX_B3/${HX_MAIN_FILE}" ] && [ -d "$SANDBOX_B3/${HX_LOGS_DIR}" ] && [ -d "$SANDBOX_B3/${HX_DEC_DIR}" ] && [ -f "$SANDBOX_B3/${HX_GOTCHAS_FILE}" ]; } \
    && { echo "  ✅ B3-v4: all four new-name pieces present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B3-v4: a new-name piece is missing"; FAIL=$((FAIL+1)); }
state_b3=$( . "$SCRIPTS_DIR/lib/handoffx-tidy-migrate.sh" && detect_schema_state "$SANDBOX_B3" )
assert_exit "B3-v4: result detects as ALREADY-HANDOFFX (never MIXED) [got: $state_b3]" 0 "$([ "$state_b3" = "ALREADY-HANDOFFX" ] && echo 0 || echo 1)"

rm -rf "$SANDBOX_B3"

# B4: --apply also creates ${HX_DEC_DIR}/ with per-file entries
SANDBOX_B4=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B4/${HX_LEGACY_MAIN_FILE}"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B4" >/dev/null 2>&1

[ -d "$SANDBOX_B4/${HX_DEC_DIR}" ] && { echo "  ✅ B4: ${HX_DEC_DIR}/ created"; PASS=$((PASS+1)); } || { echo "  ❌ B4: missing"; FAIL=$((FAIL+1)); }

n=$(ls "$SANDBOX_B4/${HX_DEC_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B4: 2 Decision files created" "$n" "2"

[ -f "$SANDBOX_B4/${HX_DEC_DIR}/0001-2026-04-30-"*.md ] && { echo "  ✅ B4: 0001 oldest"; PASS=$((PASS+1)); } || { echo "  ❌ B4: 0001 wrong"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_B4/${HX_DEC_DIR}/0002-2026-05-01-"*.md ] && { echo "  ✅ B4: 0002 newest"; PASS=$((PASS+1)); } || { echo "  ❌ B4: 0002 wrong"; FAIL=$((FAIL+1)); }

first=$(ls "$SANDBOX_B4/${HX_DEC_DIR}/0001-"*.md | head -1)
grep -q '^type: decision$' "$first" && { echo "  ✅ B4: type:decision"; PASS=$((PASS+1)); } || { echo "  ❌ B4: missing type"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B4"

# B5: --apply also creates ${HX_GOTCHAS_FILE} (single file)
SANDBOX_B5=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B5/${HX_LEGACY_MAIN_FILE}"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B5" >/dev/null 2>&1

[ -f "$SANDBOX_B5/${HX_GOTCHAS_FILE}" ] && { echo "  ✅ B5: ${HX_GOTCHAS_FILE} created"; PASS=$((PASS+1)); } || { echo "  ❌ B5: ${HX_GOTCHAS_FILE} missing"; FAIL=$((FAIL+1)); }
grep -q '^# Known Gotchas$' "$SANDBOX_B5/${HX_GOTCHAS_FILE}" && { echo "  ✅ B5: ${HX_GOTCHAS_FILE} has top header"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing # Known Gotchas"; FAIL=$((FAIL+1)); }
n=$(grep -cE '^### Gotcha #' "$SANDBOX_B5/${HX_GOTCHAS_FILE}" || true)
assert_contains "B5: 2 Gotcha entries in ${HX_GOTCHAS_FILE}" "$n" "2"

# Original Gotcha content preserved
grep -q '示例坑' "$SANDBOX_B5/${HX_GOTCHAS_FILE}" && { echo "  ✅ B5: Gotcha #1 content preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing Gotcha #1"; FAIL=$((FAIL+1)); }
grep -q '另一个示例' "$SANDBOX_B5/${HX_GOTCHAS_FILE}" && { echo "  ✅ B5: Gotcha #2 content preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing Gotcha #2"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B5"

# B6: --apply rewrites ${HX_LEGACY_MAIN_FILE} to v2 layout
SANDBOX_B6=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B6/${HX_LEGACY_MAIN_FILE}"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B6" >/dev/null 2>&1

# v2 marker present
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B6/${HX_MAIN_FILE}" && { echo "  ✅ B6: v2 marker inserted"; PASS=$((PASS+1)); } || { echo "  ❌ B6: marker missing"; FAIL=$((FAIL+1)); }

# Dev Log section is pointer (no ### YYYY-MM-DD entries inside)
# Use awk to extract section content excluding the terminating ## header (macOS-safe)
devlog_section=$(awk '/^## 📜 Development Log/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/${HX_MAIN_FILE}")
echo "$devlog_section" | grep -qE '^### [0-9]{4}-[0-9]{2}' && { echo "  ❌ B6: Dev Log still has entries"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Dev Log section is pointer"; PASS=$((PASS+1)); }
echo "$devlog_section" | grep -q "储存在 .${HX_LOGS_DIR}/." && { echo "  ✅ B6: Dev Log pointer mentions ${HX_LOGS_DIR}"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing ${HX_LOGS_DIR} pointer"; FAIL=$((FAIL+1)); }
echo "$devlog_section" | grep -qE '共 [0-9]+ 条' && { echo "  ✅ B6: Dev Log shows count"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing count"; FAIL=$((FAIL+1)); }

# Gotchas section is pointer
gotchas_section=$(awk '/^## 🐛 Known Gotchas/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/${HX_MAIN_FILE}")
echo "$gotchas_section" | grep -qE '^### Gotcha #' && { echo "  ❌ B6: Gotchas still inline"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Gotchas section is pointer"; PASS=$((PASS+1)); }
echo "$gotchas_section" | grep -qF "${HX_GOTCHAS_FILE}" && { echo "  ✅ B6: Gotchas pointer mentions ${HX_GOTCHAS_FILE}"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing ${HX_GOTCHAS_FILE} pointer"; FAIL=$((FAIL+1)); }

# Decision Log section is pointer
dec_section=$(awk '/^## 🧭 Decision Log/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/${HX_MAIN_FILE}")
echo "$dec_section" | grep -qE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' && { echo "  ❌ B6: Decision Log still inline"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Decision Log section is pointer"; PASS=$((PASS+1)); }
echo "$dec_section" | grep -qF "${HX_DEC_DIR}" && { echo "  ✅ B6: Decision pointer mentions dir"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing ${HX_DEC_DIR} pointer"; FAIL=$((FAIL+1)); }

# Backup is original v1 content (unchanged, has full Dev Log entries)
diff -q "$SANDBOX_B6/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" >/dev/null 2>&1 && { echo "  ✅ B6: backup is original v1 content"; PASS=$((PASS+1)); } || { echo "  ❌ B6: backup mismatch"; FAIL=$((FAIL+1)); }

# Other sections preserved (Project Overview, Current State unchanged)
grep -q '## 📦 Project Overview' "$SANDBOX_B6/${HX_MAIN_FILE}" && { echo "  ✅ B6: Project Overview preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B6: Project Overview lost"; FAIL=$((FAIL+1)); }
grep -q '## 🎯 Current State' "$SANDBOX_B6/${HX_MAIN_FILE}" && { echo "  ✅ B6: Current State preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B6: Current State lost"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B6"

# B6.fix-A: --apply works when v1 ${HX_LEGACY_MAIN_FILE} lacks Decision Log section
SANDBOX_NO_DEC=$(mktemp -d)
cat > "$SANDBOX_NO_DEC/${HX_LEGACY_MAIN_FILE}" <<'EOF'
# Handoff
## 📦 Project Overview
test
## 🐛 Known Gotchas
### Gotcha #1 — `[build]` x
- foo
## 📜 Development Log
### 2026-05-01 14:00 — entry
content
EOF
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_NO_DEC" >/dev/null 2>&1
ec=$?
assert_exit "B6.fix-A: --apply succeeds with no Decision Log" 0 "$ec"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_NO_DEC/${HX_MAIN_FILE}" && { echo "  ✅ B6.fix-A: v2 marker inserted even without Decision Log"; PASS=$((PASS+1)); } || { echo "  ❌ B6.fix-A: marker missing"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_NO_DEC"

# B7-a: chmod 555 sandbox → backup creation fails before any write → exit 1, ${HX_LEGACY_MAIN_FILE} untouched.
# Skipped when running as root: CAP_DAC_OVERRIDE bypasses chmod-based denial (Linux container
# default user is root; bare-metal Linux/macOS dev users hit the assertions). B7-b below covers
# the rollback contract via a root-immune path-collision mechanism (mkdir on existing file).
SANDBOX_B7a=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7a/${HX_LEGACY_MAIN_FILE}"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ B7-a: read-only sandbox SKIPPED (root bypasses chmod 555; B7-b covers rollback contract via path-collision)"
else
    chmod 555 "$SANDBOX_B7a"
    bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7a" >/dev/null 2>&1
    ec=$?
    chmod 755 "$SANDBOX_B7a"
    assert_exit "B7-a: read-only sandbox → exit non-zero" 1 "$ec"
    grep -q '## 📜 Development Log' "$SANDBOX_B7a/${HX_LEGACY_MAIN_FILE}" && { echo "  ✅ B7-a: ${HX_LEGACY_MAIN_FILE} still v1"; PASS=$((PASS+1)); } || { echo "  ❌ B7-a: ${HX_LEGACY_MAIN_FILE} modified"; FAIL=$((FAIL+1)); }
    [ ! -d "$SANDBOX_B7a/${HX_LOGS_DIR}" ] && [ ! -d "$SANDBOX_B7a/${HX_LOGS_DIR}.partial" ] && { echo "  ✅ B7-a: no ${HX_LOGS_DIR} leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-a: leaked ${HX_LOGS_DIR}/ or .partial"; FAIL=$((FAIL+1)); }
fi
rm -rf "$SANDBOX_B7a"

# B7-b: pre-block ${HX_DEC_DIR}.partial as a regular file → mid-migration mkdir fails
# AFTER Dev Log staging succeeds. Verifies trap cleans ${HX_LOGS_DIR}.partial + restores ${HX_LEGACY_MAIN_FILE}.
SANDBOX_B7b=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7b/${HX_LEGACY_MAIN_FILE}"
touch "$SANDBOX_B7b/${HX_DEC_DIR}.partial"  # regular file blocks mkdir -p
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7b" >/dev/null 2>&1
ec=$?
assert_exit "B7-b: blocked partial dir → exit 1" 1 "$ec"
grep -q '## 📜 Development Log' "$SANDBOX_B7b/${HX_LEGACY_MAIN_FILE}" && { echo "  ✅ B7-b: ${HX_LEGACY_MAIN_FILE} preserved as v1"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_LEGACY_MAIN_FILE} was modified"; FAIL=$((FAIL+1)); }
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B7b/${HX_LEGACY_MAIN_FILE}" && { echo "  ❌ B7-b: ${HX_LEGACY_MAIN_FILE} got v2 marker despite failure"; FAIL=$((FAIL+1)); } || { echo "  ✅ B7-b: ${HX_LEGACY_MAIN_FILE} has no v2 marker"; PASS=$((PASS+1)); }
[ ! -d "$SANDBOX_B7b/${HX_LOGS_DIR}" ] && { echo "  ✅ B7-b: no final ${HX_LOGS_DIR}/ leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_LOGS_DIR}/ leaked (rollback failed)"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7b/${HX_LOGS_DIR}.partial" ] && { echo "  ✅ B7-b: ${HX_LOGS_DIR}.partial cleaned up by trap"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_LOGS_DIR}.partial leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7b/${HX_DEC_DIR}" ] && { echo "  ✅ B7-b: no final ${HX_DEC_DIR}/ leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_DEC_DIR}/ leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/${HX_GOTCHAS_FILE}" ] && { echo "  ✅ B7-b: no ${HX_GOTCHAS_FILE} leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_GOTCHAS_FILE} leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] && { echo "  ✅ B7-b: backup file removed by rollback"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: backup file leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/${HX_MAIN_FILE}.new" ] && { echo "  ✅ B7-b: no ${HX_MAIN_FILE}.new leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: ${HX_MAIN_FILE}.new leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_B7b"

# Regression: legacy Dev Log entry without HH:MM (e.g. `### 2026-04-20 — title`).
# Triggered self-migration failure on the actual project ${HX_LEGACY_MAIN_FILE} (K3) under
# set -euo pipefail because grep -oE for HH:MM had no match → pipefail aborted
# the assignment before the [ -z "$time_part" ] guard could fire. Fix is `|| true`
# on the time/date extractor pipelines.
SANDBOX_NOTIME=$(mktemp -d)
cat > "$SANDBOX_NOTIME/${HX_LEGACY_MAIN_FILE}" <<'EOF'
# Handoff
## 📦 Project Overview
test
## 🐛 Known Gotchas
### Gotcha #1 — `[build]` x
- foo
## 📜 Development Log

> entries

---

### 2026-04-20 — date-only legacy entry
**触发**: legacy v0.5 vintage style with no HH:MM
**改动**: foo
**验证**: ok
**关联**: 无

---

### 2026-04-21 12:34 — modern entry with time
**触发**: ok
**改动**: bar
**验证**: ok
**关联**: 无
EOF
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_NOTIME" >/dev/null 2>&1
ec=$?
assert_exit "regression: date-only entry → migration succeeds" 0 "$ec"
n_files=$(ls "$SANDBOX_NOTIME/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "regression: 2 entries written" "$n_files" "2"
[ -f "$SANDBOX_NOTIME/${HX_LOGS_DIR}/0001-2026-04-20T0000-"*.md ] && { echo "  ✅ regression: date-only entry got T0000 timestamp"; PASS=$((PASS+1)); } || { echo "  ❌ regression: 0001 missing or wrong format"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_NOTIME"

# B7-d (Codex review #1): preflight rejects pre-existing migration targets.
# Re-running --apply on an already-migrated project, or any state where the
# final destination directories/files exist, must abort cleanly before any
# modification — not silently clobber or leave half-state.
SANDBOX_PREFLIGHT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_PREFLIGHT/${HX_LEGACY_MAIN_FILE}"
mkdir -p "$SANDBOX_PREFLIGHT/${HX_LOGS_DIR}"   # pre-existing → should abort
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_PREFLIGHT" 2>&1)
ec=$?
assert_exit "B7-d preflight: pre-existing ${HX_LOGS_DIR}/ → exit 1" 1 "$ec"
# A new-name dir beside a legacy main is a mixed tree: the classifier refuses it
# and names both sides (fix wave 1 A1), before the per-target preflight.
assert_contains "B7-d preflight: clear abort message (mixed, both sides named)" "$out" "mixed layout"
grep -q '## 📜 Development Log' "$SANDBOX_PREFLIGHT/${HX_LEGACY_MAIN_FILE}" && { echo "  ✅ B7-d: ${HX_LEGACY_MAIN_FILE} untouched on preflight reject"; PASS=$((PASS+1)); } || { echo "  ❌ B7-d: ${HX_LEGACY_MAIN_FILE} modified after preflight"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_PREFLIGHT/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] && { echo "  ✅ B7-d: no backup created (preflight before backup)"; PASS=$((PASS+1)); } || { echo "  ❌ B7-d: backup created despite preflight reject"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_PREFLIGHT"

# B7-e (Codex review #1): pre-existing ${HX_GOTCHAS_FILE} as a regular file blocks too.
SANDBOX_PG=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_PG/${HX_LEGACY_MAIN_FILE}"
echo "stale gotcha file" > "$SANDBOX_PG/${HX_GOTCHAS_FILE}"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_PG" >/dev/null 2>&1
ec=$?
assert_exit "B7-e preflight: pre-existing ${HX_GOTCHAS_FILE} → exit 1" 1 "$ec"
[ "$(cat "$SANDBOX_PG/${HX_GOTCHAS_FILE}")" = "stale gotcha file" ] && { echo "  ✅ B7-e: pre-existing ${HX_GOTCHAS_FILE} untouched"; PASS=$((PASS+1)); } || { echo "  ❌ B7-e: pre-existing ${HX_GOTCHAS_FILE} was clobbered"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_PG"

# B7-archive (Codex review #4): ${HX_LEGACY_MAIN_FILE%.md}.archive.md content must migrate too.
# v1 archive-devlog.sh moves overflowed Dev Log entries to ${HX_LEGACY_MAIN_FILE%.md}.archive.md;
# previously --apply unconditionally deleted that file claiming "content was
# migrated", but the parser only read the main ${HX_LEGACY_MAIN_FILE} Dev Log section.
SANDBOX_AR=$(mktemp -d)
cat > "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE}" <<'EOF'
# Handoff
## 📦 Project Overview
test
## 📜 Development Log

### 2026-05-01 14:00 — recent main entry
**触发**: t
**改动**: f
**验证**: ok
**关联**: 无

EOF
cat > "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE%.md}.archive.md" <<'EOF'
# Sample — Development Log Archive

> 从主文件归档的旧 Dev Log 条目。最新在最上面。

### 2026-04-15 09:00 — UNIQUE_ARCHIVE_SENTINEL_FOO
**触发**: archive trigger
**改动**: archive change
**验证**: archive verified
**关联**: 无

---

### 2026-04-10 09:00 — UNIQUE_ARCHIVE_SENTINEL_BAR
**触发**: bar
**改动**: bar
**验证**: bar
**关联**: 无
EOF
# tree_digest <dir> — file list + per-file bytes, so "exact v1 state" is a string compare.
tree_digest() { ( cd "$1" && find . -print | LC_ALL=C sort && find . -type f -print | LC_ALL=C sort | xargs shasum ); }
AR_V1=$(tree_digest "$SANDBOX_AR")
AR_ORIG=$(mktemp -d); cp "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE}" "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE%.md}.archive.md" "$AR_ORIG/"
out_ar=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_AR" 2>&1)
ec=$?
assert_exit "B7-archive: --apply with archive file → exit 0" 0 "$ec"

n_files=$(ls "$SANDBOX_AR/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B7-archive: 3 entries written (1 main + 2 archive)" "$n_files" "3"

# Sentinel content from archive must survive in ${HX_LOGS_DIR}/
grep -lF 'UNIQUE_ARCHIVE_SENTINEL_FOO' "$SANDBOX_AR/${HX_LOGS_DIR}/"*.md >/dev/null 2>&1 \
    && { echo "  ✅ B7-archive: archive entry FOO migrated"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: archive entry FOO lost"; FAIL=$((FAIL+1)); }
grep -lF 'UNIQUE_ARCHIVE_SENTINEL_BAR' "$SANDBOX_AR/${HX_LOGS_DIR}/"*.md >/dev/null 2>&1 \
    && { echo "  ✅ B7-archive: archive entry BAR migrated"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: archive entry BAR lost"; FAIL=$((FAIL+1)); }

# Oldest entry (2026-04-10) gets 0001 NNNN; main file's 2026-05-01 gets 0003.
[ -f "$SANDBOX_AR/${HX_LOGS_DIR}/0001-2026-04-10T0900-"*.md ] \
    && { echo "  ✅ B7-archive: oldest archive entry got 0001"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: 0001 not the oldest archive entry"; FAIL=$((FAIL+1)); }

# Archive file deleted after successful migration
[ ! -f "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE%.md}.archive.md" ] \
    && { echo "  ✅ B7-archive: ${HX_LEGACY_MAIN_FILE%.md}.archive.md cleaned up"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: ${HX_LEGACY_MAIN_FILE%.md}.archive.md not cleaned"; FAIL=$((FAIL+1)); }
[ ! -e "$SANDBOX_AR/${HX_LEGACY_MAIN_FILE}" ] && [ -f "$SANDBOX_AR/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ B7-archive: legacy main renamed to ${HX_MAIN_FILE}"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: legacy main not renamed"; FAIL=$((FAIL+1)); }
# The archive is deleted on success and its entries live only in the new logs
# dir — so it needs a retained backup too, or the Restore line (which removes
# the logs dir) would destroy archived Dev Logs for good.
for f in "${HX_LEGACY_MAIN_FILE}" "${HX_LEGACY_MAIN_FILE%.md}.archive.md"; do
    cmp -s "$SANDBOX_AR/$f.pre-v2-backup" "$AR_ORIG/$f" \
        && { echo "  ✅ B7-archive: $f.pre-v2-backup retained, byte-equal to the input"; PASS=$((PASS+1)); } \
        || { echo "  ❌ B7-archive: $f.pre-v2-backup missing or differs from the input"; FAIL=$((FAIL+1)); }
done
restore_line=$(printf '%s\n' "$out_ar" | sed -n 's/^ *Restore: //p')
assert_contains "B7-archive: Restore line restores the archive too" "$restore_line" "${HX_LEGACY_MAIN_FILE%.md}.archive.md.pre-v2-backup"
bash -c "$restore_line"; ec=$?
assert_exit "B7-archive: printed Restore line runs cleanly" 0 "$ec"
assert_exit "B7-archive: Restore line rebuilds the exact v1 tree (file list + bytes)" 0 "$([ "$(tree_digest "$SANDBOX_AR")" = "$AR_V1" ] && echo 0 || echo 1)"
rm -rf "$SANDBOX_AR" "$AR_ORIG"

# B7-archive-inject: retire-legacy fires after BOTH the legacy main and the
# archive were removed, so this is the trap's "original missing → restore from
# backup" branch, for each of the two files.
SB=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
printf '# Archive\n\n### 2026-04-10 09:00 — ARCHIVE_ONLY_ENTRY\n**触发**: x\n' > "$SB/${HX_LEGACY_MAIN_FILE%.md}.archive.md"
SB_V1=$(tree_digest "$SB")
out=$(HANDOFFX_MIGRATE_FAIL_AT=retire-legacy bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
[ "$ec" -ne 0 ] && { echo "  ✅ B7-archive-inject: non-zero exit"; PASS=$((PASS+1)); } || { echo "  ❌ B7-archive-inject: exited 0"; FAIL=$((FAIL+1)); }
assert_contains "B7-archive-inject: archive restored from its backup" "$out" "${HX_LEGACY_MAIN_FILE%.md}.archive.md restored from backup"
assert_exit "B7-archive-inject: tree back to the exact v1 state (no backups, no new pieces)" 0 "$([ "$(tree_digest "$SB")" = "$SB_V1" ] && echo 0 || echo 1)"
rm -rf "$SB"

# B7-d-backup: a pre-existing backup name would be overwritten, then deleted on
# rollback — refuse before touching anything.
for bk in "${HX_LEGACY_MAIN_FILE}.pre-v2-backup" "${HX_LEGACY_MAIN_FILE%.md}.archive.md.pre-v2-backup"; do
    SB=$(mktemp -d)
    cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
    echo "someone's old backup" > "$SB/$bk"
    SB_V1=$(tree_digest "$SB")
    out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
    assert_exit "B7-d-backup[$bk]: pre-existing backup → exit 1" 1 "$ec"
    assert_contains "B7-d-backup[$bk]: names it" "$out" "Migration target already exists: $SB/$bk"
    assert_exit "B7-d-backup[$bk]: tree unchanged" 0 "$([ "$(tree_digest "$SB")" = "$SB_V1" ] && echo 0 || echo 1)"
    rm -rf "$SB"
done

# B7-stale-partial (Codex review #6): pre-existing .partial path from a prior
# crashed run must NOT be silently merged; preflight aborts with guidance.
SANDBOX_SP=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_SP/${HX_LEGACY_MAIN_FILE}"
mkdir -p "$SANDBOX_SP/${HX_LOGS_DIR}.partial"
echo "ghost from prior crash" > "$SANDBOX_SP/${HX_LOGS_DIR}.partial/0001-stale.md"
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_SP" 2>&1)
ec=$?
assert_exit "B7-stale-partial: pre-existing .partial → exit 1" 1 "$ec"
assert_contains "B7-stale-partial: hints stale staging" "$out" "Stale staging path"
[ "$(cat "$SANDBOX_SP/${HX_LOGS_DIR}.partial/0001-stale.md")" = "ghost from prior crash" ] \
    && { echo "  ✅ B7-stale-partial: stale content untouched"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-stale-partial: stale content was modified"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_SP/${HX_LOGS_DIR}" ] \
    && { echo "  ✅ B7-stale-partial: no real ${HX_LOGS_DIR}/ created"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-stale-partial: ${HX_LOGS_DIR}/ leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_SP"

# B7-c: success path leaves backup file in place AND no .partial dirs (regression test for finalization).
SANDBOX_B7c=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7c/${HX_LEGACY_MAIN_FILE}"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7c" >/dev/null 2>&1
ec=$?
assert_exit "B7-c: success exits 0" 0 "$ec"
[ -f "$SANDBOX_B7c/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] && { echo "  ✅ B7-c: backup retained on success"; PASS=$((PASS+1)); } || { echo "  ❌ B7-c: backup missing on success"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7c/${HX_LOGS_DIR}.partial" ] && [ ! -d "$SANDBOX_B7c/${HX_DEC_DIR}.partial" ] && [ ! -f "$SANDBOX_B7c/${HX_GOTCHAS_FILE}.partial" ] && { echo "  ✅ B7-c: no .partial residue on success"; PASS=$((PASS+1)); } || { echo "  ❌ B7-c: .partial residue leaked"; FAIL=$((FAIL+1)); }
[ ! -e "$SANDBOX_B7c/${HX_MAIN_FILE}.new" ] && { echo "  ✅ B7-c: no ${HX_MAIN_FILE}.new residue on success"; PASS=$((PASS+1)); } || { echo "  ❌ B7-c: ${HX_MAIN_FILE}.new leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_B7c"

# B7-d-main: the new-name main file is a migration target too (v1 → v4 writes
# it under a different name than it reads). Without the preflight entry an
# existing one would be overwritten by — or swallow — the final rename.
# Covered as a regular file, a directory and a dangling symlink (`[ -e ]` alone
# misses the last one). Preflight must refuse before the backup is taken.
for kind in file dir symlink; do
    SANDBOX_PM=$(mktemp -d)
    cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_PM/${HX_LEGACY_MAIN_FILE}"
    case "$kind" in
        file)    echo "pre-existing new main" > "$SANDBOX_PM/${HX_MAIN_FILE}" ;;
        dir)     mkdir "$SANDBOX_PM/${HX_MAIN_FILE}"; echo keep > "$SANDBOX_PM/${HX_MAIN_FILE}/keep" ;;
        symlink) ln -s "$SANDBOX_PM/nowhere" "$SANDBOX_PM/${HX_MAIN_FILE}" ;;
    esac
    before=$(ls -la "$SANDBOX_PM" | grep -F "${HX_MAIN_FILE}"; [ -d "$SANDBOX_PM/${HX_MAIN_FILE}" ] && ls -la "$SANDBOX_PM/${HX_MAIN_FILE}")
    out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_PM" 2>&1); ec=$?
    after=$(ls -la "$SANDBOX_PM" | grep -F "${HX_MAIN_FILE}"; [ -d "$SANDBOX_PM/${HX_MAIN_FILE}" ] && ls -la "$SANDBOX_PM/${HX_MAIN_FILE}")
    assert_exit "B7-d-main[$kind]: pre-existing ${HX_MAIN_FILE} → exit 1" 1 "$ec"
    # The occupied new main makes the tree mixed (a dangling symlink included —
    # fix wave 1 A4: one presence predicate, -e || -L).
    assert_contains "B7-d-main[$kind]: names the occupied target (mixed refusal)" "$out" "new [ ${HX_MAIN_FILE} ]"
    [ "$before" = "$after" ] && { [ "$kind" != file ] || [ "$(cat "$SANDBOX_PM/${HX_MAIN_FILE}")" = "pre-existing new main" ]; } \
        && { echo "  ✅ B7-d-main[$kind]: pre-existing target unchanged (type + content)"; PASS=$((PASS+1)); } \
        || { echo "  ❌ B7-d-main[$kind]: pre-existing target changed"; FAIL=$((FAIL+1)); }
    cmp -s "$SANDBOX_PM/${HX_LEGACY_MAIN_FILE}" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" && [ ! -e "$SANDBOX_PM/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] \
        && { echo "  ✅ B7-d-main[$kind]: legacy input untouched, no backup (refused before backup)"; PASS=$((PASS+1)); } \
        || { echo "  ❌ B7-d-main[$kind]: legacy input changed or backup left behind"; FAIL=$((FAIL+1)); }
    rm -rf "$SANDBOX_PM"
done

# B7-inject: rollback AFTER preflight (design §4b-4). B7-b above is a preflight
# refusal, so it never exercises the trap; these points fire inside the apply
# flow via the test-only HANDOFFX_MIGRATE_FAIL_AT hook (same contract as
# install.sh's HANDOFFX_INSTALL_FAIL_AT). retire-legacy is the one that proves
# the new main's FINALIZED_PATHS registration: the new main is already in place
# when it fires, so only that registration can take it back out.
for point in new-main final-mv retire-legacy; do
    SB=$(mktemp -d)
    cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
    out=$(HANDOFFX_MIGRATE_FAIL_AT="$point" bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
    [ "$ec" -ne 0 ] && { echo "  ✅ B7-inject[$point]: non-zero exit ($ec)"; PASS=$((PASS+1)); } || { echo "  ❌ B7-inject[$point]: exited 0 despite injected failure"; FAIL=$((FAIL+1)); }
    assert_contains "B7-inject[$point]: the injection actually fired" "$out" "injected failure at $point"
    cmp -s "$SB/${HX_LEGACY_MAIN_FILE}" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" \
        && { echo "  ✅ B7-inject[$point]: legacy main byte-identical to the fixture"; PASS=$((PASS+1)); } \
        || { echo "  ❌ B7-inject[$point]: legacy main missing or changed"; FAIL=$((FAIL+1)); }
    left=""
    for p in "${HX_MAIN_FILE}" "${HX_MAIN_FILE}.new" "${HX_LOGS_DIR}" "${HX_DEC_DIR}" "${HX_GOTCHAS_FILE}" \
             "${HX_LOGS_DIR}.partial" "${HX_DEC_DIR}.partial" "${HX_GOTCHAS_FILE}.partial" \
             "${HX_LEGACY_MAIN_FILE}.pre-v2-backup"; do
        [ -e "$SB/$p" ] && left="$left $p"
    done
    # retire-legacy fires after the legacy main was removed: only the trap's
    # restore-when-missing branch can bring it back.
    [ "$point" = retire-legacy ] && assert_contains "B7-inject[$point]: legacy main restored from backup (it was gone)" "$out" "${HX_LEGACY_MAIN_FILE} restored from backup"
    [ -z "$left" ] && { echo "  ✅ B7-inject[$point]: rolled back — no new piece, staging path or backup left"; PASS=$((PASS+1)); } \
        || { echo "  ❌ B7-inject[$point]: residue after rollback:$left"; FAIL=$((FAIL+1)); }
    rm -rf "$SB"
done

# A1 (fix wave 1): the v1 migrator only migrates a v1 tree. Reading the legacy
# name and writing the new ones removed the old implicit guard (targets used to
# collide), so a four-piece tree "succeeded": real entries left in the legacy
# dirs, empty new dirs, legacy main deleted — a mixed tree every tool refuses.
# Each case must refuse before the backup: exit non-zero, tree byte-identical.
for case_ in v3-with-gotchas v3-no-gotchas mixed; do
    SB=$(mktemp -d)
    p21_materialize "$SB" || FAIL=$((FAIL+1))
    case "$case_" in
        v3-no-gotchas) rm -f "$SB/$HX_GOTCHAS_FILE" ;;
        mixed)         mkdir "$SB/$HX_LOGS_DIR" ;;
    esac
    SB_V=$(tree_digest "$SB")
    out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
    [ "$ec" -ne 0 ] && { echo "  ✅ A1[$case_]: refused (exit $ec)"; PASS=$((PASS+1)); } || { echo "  ❌ A1[$case_]: exited 0 on a non-v1 tree"; FAIL=$((FAIL+1)); }
    assert_exit "A1[$case_]: tree byte-identical, no backup taken" 0 "$([ "$(tree_digest "$SB")" = "$SB_V" ] && echo 0 || echo 1)"
    case "$case_" in
        mixed) assert_contains "A1[$case_]: names the legacy side" "$out" "legacy [ $HX_LEGACY_MAIN_FILE"
               assert_contains "A1[$case_]: names the new side" "$out" "new [ $HX_LOGS_DIR"
               assert_not_contains "A1[$case_]: never claims success" "$out" "Migration complete" ;;
        *)     assert_contains "A1[$case_]: routes to schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
               assert_not_contains "A1[$case_]: never claims success" "$out" "Migration complete" ;;
    esac
    rm -rf "$SB"
done
# dry-run must refuse too: its counts of a four-piece main (0 entries) would
# read as a plan for an empty migration.
SB=$(mktemp -d); p21_materialize "$SB" || FAIL=$((FAIL+1))
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --dry-run --root "$SB" 2>&1); ec=$?
assert_exit "A1[dry-run v3]: refused with exit 1" 1 "$ec"
rm -rf "$SB"
# A pre-existing gotchas file beside a v1 main may be someone's real gotchas
# log: the refusal routes (schema-upgrade / merge and move aside), never "remove".
SB=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
echo "real gotchas" > "$SB/${HX_GOTCHAS_FILE}"
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
assert_exit "A1[gotchas beside v1]: refused with exit 1" 1 "$ec"
assert_not_contains "A1[gotchas beside v1]: does not suggest removing it" "$out" "Remove or rename"
assert_contains "A1[gotchas beside v1]: routes to schema-upgrade for a four-piece tree" "$out" "schema-upgrade"
rm -rf "$SB"

# F1 (fix wave 1): an entry-less v1 main (no marker, no dated entries) is v1
# by elimination; it migrates to the v4 skeleton with empty dirs. Before, it
# classified as unknown and the refusal sent the user back to this script.
SB=$(mktemp -d)
printf '# Project\n\n## 📦 Project Overview\nnew project\n\n## 📜 Development Log\n\n## 🧭 Decision Log\n\n## 🐛 Known Gotchas\n' > "$SB/${HX_LEGACY_MAIN_FILE}"
cp "$SB/${HX_LEGACY_MAIN_FILE}" "$SB.orig"
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --dry-run --root "$SB" 2>&1); ec=$?
assert_exit "F1[entry-less v1]: dry-run exit 0" 0 "$ec"
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
assert_exit "F1[entry-less v1]: --apply exit 0" 0 "$ec"
assert_file_exists "F1[entry-less v1]: new main present" "$SB/${HX_MAIN_FILE}"
{ [ -d "$SB/${HX_LOGS_DIR}" ] && [ -z "$(ls -A "$SB/${HX_LOGS_DIR}")" ] && [ -d "$SB/${HX_DEC_DIR}" ] && [ -z "$(ls -A "$SB/${HX_DEC_DIR}")" ] && [ -f "$SB/${HX_GOTCHAS_FILE}" ]; } \
    && { echo "  ✅ F1[entry-less v1]: logs/decisions dirs exist and are empty, gotchas file present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ F1[entry-less v1]: skeleton dirs missing or not empty"; FAIL=$((FAIL+1)); }
cmp -s "$SB/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" "$SB.orig" && [ ! -e "$SB/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ F1[entry-less v1]: backup retained byte-equal, legacy main retired"; PASS=$((PASS+1)); } \
    || { echo "  ❌ F1[entry-less v1]: backup missing/different or legacy main left"; FAIL=$((FAIL+1)); }
rm -rf "$SB" "$SB.orig"
# …but a marker-less main beside a legacy dir is unknown: refused, tree untouched.
SB=$(mktemp -d); cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"; mkdir "$SB/${HX_LEGACY_LOGS_DIR}"
SB_V=$(tree_digest "$SB")
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
assert_exit "F1[v1 main + legacy dir]: refused with exit 1" 1 "$ec"
assert_exit "F1[v1 main + legacy dir]: tree byte-identical" 0 "$([ "$(tree_digest "$SB")" = "$SB_V" ] && echo 0 || echo 1)"
rm -rf "$SB"

# A5 (fix wave 1): the EXIT trap must attempt every cleanup and restore even
# when one removal fails. Under the old trap `set -e` aborted the handler at its
# first failing rm, so a failure after retire-legacy left the legacy main gone.
# A shim `rm` plants, at trap time, a 555 directory with a file inside on the
# .new staging path (the only moment that path is removed), so the real rm
# really fails with EACCES. Root ignores the mode bits → nothing would fail.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ A5: trap residue under a failing staging removal SKIPPED (root bypasses chmod 555)"
else
    SB=$(mktemp -d); SHIM=$(mktemp -d)
    cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
    REAL_RM=$(command -v rm)
    cat > "$SHIM/rm" <<EOF
#!/bin/bash
for a in "\$@"; do
    if [ "\$a" = "$SB/${HX_MAIN_FILE}.new" ] && [ ! -e "\$a" ]; then
        mkdir "\$a" && echo squat > "\$a/inside" && chmod 555 "\$a"
    fi
done
exec "$REAL_RM" "\$@"
EOF
    chmod +x "$SHIM/rm"
    out=$(PATH="$SHIM:$PATH" HANDOFFX_MIGRATE_FAIL_AT=retire-legacy bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
    assert_exit "A5: exit status is the original failure's (1), not the cleanup's" 1 "$ec"
    cmp -s "$SB/${HX_LEGACY_MAIN_FILE}" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" \
        && { echo "  ✅ A5: legacy main restored despite the failed staging removal"; PASS=$((PASS+1)); } \
        || { echo "  ❌ A5: legacy main missing or changed (trap aborted before restore)"; FAIL=$((FAIL+1)); }
    [ -f "$SB/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] \
        && { echo "  ✅ A5: backup kept on incomplete rollback"; PASS=$((PASS+1)); } \
        || { echo "  ❌ A5: backup dropped although the rollback left residue"; FAIL=$((FAIL+1)); }
    { [ ! -e "$SB/${HX_MAIN_FILE}" ] && [ ! -e "$SB/${HX_LOGS_DIR}" ] && [ ! -e "$SB/${HX_DEC_DIR}" ] && [ ! -e "$SB/${HX_GOTCHAS_FILE}" ]; } \
        && { echo "  ✅ A5: finalized pieces still removed after the failed staging removal"; PASS=$((PASS+1)); } \
        || { echo "  ❌ A5: finalized pieces left behind"; FAIL=$((FAIL+1)); }
    assert_contains "A5: the staging residue is named" "$out" "rollback could not remove $SB/${HX_MAIN_FILE}.new"
    assert_contains "A5: incomplete recovery reported" "$out" "rollback incomplete"
    chmod 755 "$SB/${HX_MAIN_FILE}.new" 2>/dev/null
    rm -rf "$SB" "$SHIM"
fi

# A6 (fix wave 1): the printed Restore line must survive a root whose path holds
# a space and an apostrophe — single-quoted operands broke on the apostrophe.
SBP=$(mktemp -d); SB="$SBP/it's a root"; mkdir "$SB"
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SB/${HX_LEGACY_MAIN_FILE}"
printf '# Archive\n\n### 2026-04-10 09:00 — ARCHIVE_ENTRY\n**触发**: x\n' > "$SB/${HX_LEGACY_MAIN_FILE%.md}.archive.md"
SB_V1=$(tree_digest "$SB")
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SB" 2>&1); ec=$?
assert_exit "A6: migration under an apostrophe root → exit 0" 0 "$ec"
restore_line=$(printf '%s\n' "$out" | sed -n 's/^ *Restore: //p')
bash -c "$restore_line"; ec=$?
assert_exit "A6: printed Restore line runs cleanly" 0 "$ec"
assert_exit "A6: Restore line rebuilds the exact v1 tree" 0 "$([ "$(tree_digest "$SB")" = "$SB_V1" ] && echo 0 || echo 1)"
rm -rf "$SBP"

summary
