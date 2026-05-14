#!/bin/bash
source "$(dirname "$0")/common.sh"

# Setup: copy fixture into a sandbox
SANDBOX=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX/HANDOFF.md"

# Run dry-run
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --dry-run --root "$SANDBOX" 2>&1)
ec=$?

assert_exit "B2: dry-run exit 0" 0 "$ec"
assert_contains "B2: dry-run mentions Dev Log count" "$out" "Dev Log: 2"
assert_contains "B2: dry-run mentions Decision count" "$out" "Decision Log: 2"
assert_contains "B2: dry-run mentions Gotchas count" "$out" "Gotcha"

# No files should have been created (dry-run is no-op)
[ -d "$SANDBOX/Handoff_Logs" ] && { echo "  ❌ B2: dry-run created Handoff_Logs/"; FAIL=$((FAIL+1)); } || { echo "  ✅ B2: dry-run no side effect"; PASS=$((PASS+1)); }

rm -rf "$SANDBOX"

# B2.6: --root without value should fail gracefully
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --root 2>&1)
ec=$?
assert_exit "B2.6: --root without value exits 1" 1 "$ec"
assert_contains "B2.6: --root error message clear" "$out" "requires"

# B2.7: Dev Log count should not include entries from sections after Dev Log
SANDBOX3=$(mktemp -d)
cat > "$SANDBOX3/HANDOFF.md" <<'EOF'
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

# B3: --apply creates Handoff_Logs/ with per-file entries from fixture
SANDBOX_B3=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B3/HANDOFF.md"

bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B3" >/dev/null 2>&1
ec=$?

assert_exit "B3: --apply exits 0 (Dev Log only)" 0 "$ec"
[ -d "$SANDBOX_B3/Handoff_Logs" ] && { echo "  ✅ B3: Handoff_Logs/ created"; PASS=$((PASS+1)); } || { echo "  ❌ B3: Handoff_Logs/ missing"; FAIL=$((FAIL+1)); }

# Should have 2 Dev Log entry files (fixture has 2)
n=$(ls "$SANDBOX_B3/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B3: 2 Dev Log files created" "$n" "2"

# Filename pattern check
[ -f "$SANDBOX_B3/Handoff_Logs/0001-2026-04-30T1000-"*.md ] && { echo "  ✅ B3: 0001 oldest entry"; PASS=$((PASS+1)); } || { echo "  ❌ B3: 0001 file pattern wrong"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_B3/Handoff_Logs/0002-2026-05-01T1400-"*.md ] && { echo "  ✅ B3: 0002 newest entry"; PASS=$((PASS+1)); } || { echo "  ❌ B3: 0002 file pattern wrong"; FAIL=$((FAIL+1)); }

# Frontmatter check
first_entry=$(ls "$SANDBOX_B3/Handoff_Logs/0001-"*.md | head -1)
head -1 "$first_entry" | grep -q '^---$' && { echo "  ✅ B3: entry frontmatter starts with ---"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing frontmatter"; FAIL=$((FAIL+1)); }
grep -q '^schema: 2$' "$first_entry" && { echo "  ✅ B3: frontmatter schema:2"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing schema"; FAIL=$((FAIL+1)); }
grep -q '^type: dev-log$' "$first_entry" && { echo "  ✅ B3: frontmatter type:dev-log"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing type"; FAIL=$((FAIL+1)); }
grep -q '^number: 0001$' "$first_entry" && { echo "  ✅ B3: frontmatter number:0001"; PASS=$((PASS+1)); } || { echo "  ❌ B3: missing number"; FAIL=$((FAIL+1)); }

# Backup created
[ -f "$SANDBOX_B3/HANDOFF.md.pre-v2-backup" ] && { echo "  ✅ B3: backup file created"; PASS=$((PASS+1)); } || { echo "  ❌ B3: no backup"; FAIL=$((FAIL+1)); }

# HANDOFF.md is now rewritten by B6 (v2 layout); backup should still be v1 original
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B3/HANDOFF.md" && { echo "  ✅ B3: HANDOFF.md now has v2 marker (B6 ran)"; PASS=$((PASS+1)); } || { echo "  ❌ B3: HANDOFF.md missing v2 marker"; FAIL=$((FAIL+1)); }
diff -q "$SANDBOX_B3/HANDOFF.md.pre-v2-backup" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" >/dev/null 2>&1 && { echo "  ✅ B3: backup is original v1 content"; PASS=$((PASS+1)); } || { echo "  ❌ B3: backup mismatch"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B3"

# B4: --apply also creates Handoff_Decisions/ with per-file entries
SANDBOX_B4=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B4/HANDOFF.md"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B4" >/dev/null 2>&1

[ -d "$SANDBOX_B4/Handoff_Decisions" ] && { echo "  ✅ B4: Handoff_Decisions/ created"; PASS=$((PASS+1)); } || { echo "  ❌ B4: missing"; FAIL=$((FAIL+1)); }

n=$(ls "$SANDBOX_B4/Handoff_Decisions/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B4: 2 Decision files created" "$n" "2"

[ -f "$SANDBOX_B4/Handoff_Decisions/0001-2026-04-30-"*.md ] && { echo "  ✅ B4: 0001 oldest"; PASS=$((PASS+1)); } || { echo "  ❌ B4: 0001 wrong"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_B4/Handoff_Decisions/0002-2026-05-01-"*.md ] && { echo "  ✅ B4: 0002 newest"; PASS=$((PASS+1)); } || { echo "  ❌ B4: 0002 wrong"; FAIL=$((FAIL+1)); }

first=$(ls "$SANDBOX_B4/Handoff_Decisions/0001-"*.md | head -1)
grep -q '^type: decision$' "$first" && { echo "  ✅ B4: type:decision"; PASS=$((PASS+1)); } || { echo "  ❌ B4: missing type"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B4"

# B5: --apply also creates GOTCHAS.md (single file)
SANDBOX_B5=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B5/HANDOFF.md"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B5" >/dev/null 2>&1

[ -f "$SANDBOX_B5/GOTCHAS.md" ] && { echo "  ✅ B5: GOTCHAS.md created"; PASS=$((PASS+1)); } || { echo "  ❌ B5: GOTCHAS.md missing"; FAIL=$((FAIL+1)); }
grep -q '^# Known Gotchas$' "$SANDBOX_B5/GOTCHAS.md" && { echo "  ✅ B5: GOTCHAS.md has top header"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing # Known Gotchas"; FAIL=$((FAIL+1)); }
n=$(grep -cE '^### Gotcha #' "$SANDBOX_B5/GOTCHAS.md" || true)
assert_contains "B5: 2 Gotcha entries in GOTCHAS.md" "$n" "2"

# Original Gotcha content preserved
grep -q '示例坑' "$SANDBOX_B5/GOTCHAS.md" && { echo "  ✅ B5: Gotcha #1 content preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing Gotcha #1"; FAIL=$((FAIL+1)); }
grep -q '另一个示例' "$SANDBOX_B5/GOTCHAS.md" && { echo "  ✅ B5: Gotcha #2 content preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B5: missing Gotcha #2"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B5"

# B6: --apply rewrites HANDOFF.md to v2 layout
SANDBOX_B6=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B6/HANDOFF.md"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B6" >/dev/null 2>&1

# v2 marker present
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B6/HANDOFF.md" && { echo "  ✅ B6: v2 marker inserted"; PASS=$((PASS+1)); } || { echo "  ❌ B6: marker missing"; FAIL=$((FAIL+1)); }

# Dev Log section is pointer (no ### YYYY-MM-DD entries inside)
# Use awk to extract section content excluding the terminating ## header (macOS-safe)
devlog_section=$(awk '/^## 📜 Development Log/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/HANDOFF.md")
echo "$devlog_section" | grep -qE '^### [0-9]{4}-[0-9]{2}' && { echo "  ❌ B6: Dev Log still has entries"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Dev Log section is pointer"; PASS=$((PASS+1)); }
echo "$devlog_section" | grep -q '储存在 .Handoff_Logs/.' && { echo "  ✅ B6: Dev Log pointer mentions Handoff_Logs"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing Handoff_Logs pointer"; FAIL=$((FAIL+1)); }
echo "$devlog_section" | grep -qE '共 [0-9]+ 条' && { echo "  ✅ B6: Dev Log shows count"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing count"; FAIL=$((FAIL+1)); }

# Gotchas section is pointer
gotchas_section=$(awk '/^## 🐛 Known Gotchas/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/HANDOFF.md")
echo "$gotchas_section" | grep -qE '^### Gotcha #' && { echo "  ❌ B6: Gotchas still inline"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Gotchas section is pointer"; PASS=$((PASS+1)); }
echo "$gotchas_section" | grep -q 'GOTCHAS.md' && { echo "  ✅ B6: Gotchas pointer mentions GOTCHAS.md"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing GOTCHAS.md pointer"; FAIL=$((FAIL+1)); }

# Decision Log section is pointer
dec_section=$(awk '/^## 🧭 Decision Log/{f=1;next} f && /^## /{exit} f{print}' "$SANDBOX_B6/HANDOFF.md")
echo "$dec_section" | grep -qE '^### [0-9]{4}-[0-9]{2}-[0-9]{2}' && { echo "  ❌ B6: Decision Log still inline"; FAIL=$((FAIL+1)); } || { echo "  ✅ B6: Decision Log section is pointer"; PASS=$((PASS+1)); }
echo "$dec_section" | grep -q 'Handoff_Decisions' && { echo "  ✅ B6: Decision pointer mentions dir"; PASS=$((PASS+1)); } || { echo "  ❌ B6: missing Handoff_Decisions pointer"; FAIL=$((FAIL+1)); }

# Backup is original v1 content (unchanged, has full Dev Log entries)
diff -q "$SANDBOX_B6/HANDOFF.md.pre-v2-backup" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" >/dev/null 2>&1 && { echo "  ✅ B6: backup is original v1 content"; PASS=$((PASS+1)); } || { echo "  ❌ B6: backup mismatch"; FAIL=$((FAIL+1)); }

# Other sections preserved (Project Overview, Current State unchanged)
grep -q '## 📦 Project Overview' "$SANDBOX_B6/HANDOFF.md" && { echo "  ✅ B6: Project Overview preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B6: Project Overview lost"; FAIL=$((FAIL+1)); }
grep -q '## 🎯 Current State' "$SANDBOX_B6/HANDOFF.md" && { echo "  ✅ B6: Current State preserved"; PASS=$((PASS+1)); } || { echo "  ❌ B6: Current State lost"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX_B6"

# B6.fix-A: --apply works when v1 HANDOFF.md lacks Decision Log section
SANDBOX_NO_DEC=$(mktemp -d)
cat > "$SANDBOX_NO_DEC/HANDOFF.md" <<'EOF'
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
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_NO_DEC/HANDOFF.md" && { echo "  ✅ B6.fix-A: v2 marker inserted even without Decision Log"; PASS=$((PASS+1)); } || { echo "  ❌ B6.fix-A: marker missing"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_NO_DEC"

# B7-a: chmod 555 sandbox → backup creation fails before any write → exit 1, HANDOFF.md untouched.
SANDBOX_B7a=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7a/HANDOFF.md"
chmod 555 "$SANDBOX_B7a"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7a" >/dev/null 2>&1
ec=$?
chmod 755 "$SANDBOX_B7a"
assert_exit "B7-a: read-only sandbox → exit non-zero" 1 "$ec"
grep -q '## 📜 Development Log' "$SANDBOX_B7a/HANDOFF.md" && { echo "  ✅ B7-a: HANDOFF.md still v1"; PASS=$((PASS+1)); } || { echo "  ❌ B7-a: HANDOFF.md modified"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7a/Handoff_Logs" ] && [ ! -d "$SANDBOX_B7a/Handoff_Logs.partial" ] && { echo "  ✅ B7-a: no Handoff_Logs leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-a: leaked Handoff_Logs/ or .partial"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_B7a"

# B7-b: pre-block Handoff_Decisions.partial as a regular file → mid-migration mkdir fails
# AFTER Dev Log staging succeeds. Verifies trap cleans Handoff_Logs.partial + restores HANDOFF.md.
SANDBOX_B7b=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7b/HANDOFF.md"
touch "$SANDBOX_B7b/Handoff_Decisions.partial"  # regular file blocks mkdir -p
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7b" >/dev/null 2>&1
ec=$?
assert_exit "B7-b: blocked partial dir → exit 1" 1 "$ec"
grep -q '## 📜 Development Log' "$SANDBOX_B7b/HANDOFF.md" && { echo "  ✅ B7-b: HANDOFF.md preserved as v1"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: HANDOFF.md was modified"; FAIL=$((FAIL+1)); }
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX_B7b/HANDOFF.md" && { echo "  ❌ B7-b: HANDOFF.md got v2 marker despite failure"; FAIL=$((FAIL+1)); } || { echo "  ✅ B7-b: HANDOFF.md has no v2 marker"; PASS=$((PASS+1)); }
[ ! -d "$SANDBOX_B7b/Handoff_Logs" ] && { echo "  ✅ B7-b: no final Handoff_Logs/ leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: Handoff_Logs/ leaked (rollback failed)"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7b/Handoff_Logs.partial" ] && { echo "  ✅ B7-b: Handoff_Logs.partial cleaned up by trap"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: Handoff_Logs.partial leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7b/Handoff_Decisions" ] && { echo "  ✅ B7-b: no final Handoff_Decisions/ leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: Handoff_Decisions/ leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/GOTCHAS.md" ] && { echo "  ✅ B7-b: no GOTCHAS.md leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: GOTCHAS.md leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/HANDOFF.md.pre-v2-backup" ] && { echo "  ✅ B7-b: backup file removed by rollback"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: backup file leaked"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_B7b/HANDOFF.md.new" ] && { echo "  ✅ B7-b: no HANDOFF.md.new leaked"; PASS=$((PASS+1)); } || { echo "  ❌ B7-b: HANDOFF.md.new leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_B7b"

# Regression: legacy Dev Log entry without HH:MM (e.g. `### 2026-04-20 — title`).
# Triggered self-migration failure on the actual project HANDOFF.md (K3) under
# set -euo pipefail because grep -oE for HH:MM had no match → pipefail aborted
# the assignment before the [ -z "$time_part" ] guard could fire. Fix is `|| true`
# on the time/date extractor pipelines.
SANDBOX_NOTIME=$(mktemp -d)
cat > "$SANDBOX_NOTIME/HANDOFF.md" <<'EOF'
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
n_files=$(ls "$SANDBOX_NOTIME/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "regression: 2 entries written" "$n_files" "2"
[ -f "$SANDBOX_NOTIME/Handoff_Logs/0001-2026-04-20T0000-"*.md ] && { echo "  ✅ regression: date-only entry got T0000 timestamp"; PASS=$((PASS+1)); } || { echo "  ❌ regression: 0001 missing or wrong format"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_NOTIME"

# B7-d (Codex review #1): preflight rejects pre-existing migration targets.
# Re-running --apply on an already-migrated project, or any state where the
# final destination directories/files exist, must abort cleanly before any
# modification — not silently clobber or leave half-state.
SANDBOX_PREFLIGHT=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_PREFLIGHT/HANDOFF.md"
mkdir -p "$SANDBOX_PREFLIGHT/Handoff_Logs"   # pre-existing → should abort
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_PREFLIGHT" 2>&1)
ec=$?
assert_exit "B7-d preflight: pre-existing Handoff_Logs/ → exit 1" 1 "$ec"
assert_contains "B7-d preflight: clear abort message" "$out" "Migration target already exists"
grep -q '## 📜 Development Log' "$SANDBOX_PREFLIGHT/HANDOFF.md" && { echo "  ✅ B7-d: HANDOFF.md untouched on preflight reject"; PASS=$((PASS+1)); } || { echo "  ❌ B7-d: HANDOFF.md modified after preflight"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_PREFLIGHT/HANDOFF.md.pre-v2-backup" ] && { echo "  ✅ B7-d: no backup created (preflight before backup)"; PASS=$((PASS+1)); } || { echo "  ❌ B7-d: backup created despite preflight reject"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_PREFLIGHT"

# B7-e (Codex review #1): pre-existing GOTCHAS.md as a regular file blocks too.
SANDBOX_PG=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_PG/HANDOFF.md"
echo "stale gotcha file" > "$SANDBOX_PG/GOTCHAS.md"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_PG" >/dev/null 2>&1
ec=$?
assert_exit "B7-e preflight: pre-existing GOTCHAS.md → exit 1" 1 "$ec"
[ "$(cat "$SANDBOX_PG/GOTCHAS.md")" = "stale gotcha file" ] && { echo "  ✅ B7-e: pre-existing GOTCHAS.md untouched"; PASS=$((PASS+1)); } || { echo "  ❌ B7-e: pre-existing GOTCHAS.md was clobbered"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_PG"

# B7-archive (Codex review #4): HANDOFF.archive.md content must migrate too.
# v1 archive-devlog.sh moves overflowed Dev Log entries to HANDOFF.archive.md;
# previously --apply unconditionally deleted that file claiming "content was
# migrated", but the parser only read the main HANDOFF.md Dev Log section.
SANDBOX_AR=$(mktemp -d)
cat > "$SANDBOX_AR/HANDOFF.md" <<'EOF'
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
cat > "$SANDBOX_AR/HANDOFF.archive.md" <<'EOF'
# Sample — Development Log Archive

> 从主 HANDOFF.md 归档的旧 Dev Log 条目。最新在最上面。

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
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_AR" >/dev/null 2>&1
ec=$?
assert_exit "B7-archive: --apply with archive file → exit 0" 0 "$ec"

n_files=$(ls "$SANDBOX_AR/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "B7-archive: 3 entries written (1 main + 2 archive)" "$n_files" "3"

# Sentinel content from archive must survive in Handoff_Logs/
grep -lF 'UNIQUE_ARCHIVE_SENTINEL_FOO' "$SANDBOX_AR/Handoff_Logs/"*.md >/dev/null 2>&1 \
    && { echo "  ✅ B7-archive: archive entry FOO migrated"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: archive entry FOO lost"; FAIL=$((FAIL+1)); }
grep -lF 'UNIQUE_ARCHIVE_SENTINEL_BAR' "$SANDBOX_AR/Handoff_Logs/"*.md >/dev/null 2>&1 \
    && { echo "  ✅ B7-archive: archive entry BAR migrated"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: archive entry BAR lost"; FAIL=$((FAIL+1)); }

# Oldest entry (2026-04-10) gets 0001 NNNN; main file's 2026-05-01 gets 0003.
[ -f "$SANDBOX_AR/Handoff_Logs/0001-2026-04-10T0900-"*.md ] \
    && { echo "  ✅ B7-archive: oldest archive entry got 0001"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: 0001 not the oldest archive entry"; FAIL=$((FAIL+1)); }

# Archive file deleted after successful migration
[ ! -f "$SANDBOX_AR/HANDOFF.archive.md" ] \
    && { echo "  ✅ B7-archive: HANDOFF.archive.md cleaned up"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-archive: HANDOFF.archive.md not cleaned"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_AR"

# B7-stale-partial (Codex review #6): pre-existing .partial path from a prior
# crashed run must NOT be silently merged; preflight aborts with guidance.
SANDBOX_SP=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_SP/HANDOFF.md"
mkdir -p "$SANDBOX_SP/Handoff_Logs.partial"
echo "ghost from prior crash" > "$SANDBOX_SP/Handoff_Logs.partial/0001-stale.md"
out=$(bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_SP" 2>&1)
ec=$?
assert_exit "B7-stale-partial: pre-existing .partial → exit 1" 1 "$ec"
assert_contains "B7-stale-partial: hints stale staging" "$out" "Stale staging path"
[ "$(cat "$SANDBOX_SP/Handoff_Logs.partial/0001-stale.md")" = "ghost from prior crash" ] \
    && { echo "  ✅ B7-stale-partial: stale content untouched"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-stale-partial: stale content was modified"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_SP/Handoff_Logs" ] \
    && { echo "  ✅ B7-stale-partial: no real Handoff_Logs/ created"; PASS=$((PASS+1)); } \
    || { echo "  ❌ B7-stale-partial: Handoff_Logs/ leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_SP"

# B7-c: success path leaves backup file in place AND no .partial dirs (regression test for finalization).
SANDBOX_B7c=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX_B7c/HANDOFF.md"
bash "$ROOT_DIR/scripts/migrate-to-v2.sh" --apply --root "$SANDBOX_B7c" >/dev/null 2>&1
ec=$?
assert_exit "B7-c: success exits 0" 0 "$ec"
[ -f "$SANDBOX_B7c/HANDOFF.md.pre-v2-backup" ] && { echo "  ✅ B7-c: backup retained on success"; PASS=$((PASS+1)); } || { echo "  ❌ B7-c: backup missing on success"; FAIL=$((FAIL+1)); }
[ ! -d "$SANDBOX_B7c/Handoff_Logs.partial" ] && [ ! -d "$SANDBOX_B7c/Handoff_Decisions.partial" ] && [ ! -f "$SANDBOX_B7c/GOTCHAS.md.partial" ] && { echo "  ✅ B7-c: no .partial residue on success"; PASS=$((PASS+1)); } || { echo "  ❌ B7-c: .partial residue leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX_B7c"

summary
