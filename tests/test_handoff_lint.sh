#!/bin/bash
# test_handoff_lint.sh — machine-check $HX_MAIN_FILE recall-readiness invariants
source "$(dirname "$0")/common.sh"

LINT="$SCRIPTS_DIR/handoff-lint.sh"

make_handoff() {
    local file="$1"
    cat > "$file" <<'EOF'
# Demo

## 📦 Project Overview
ok

## 🏗 Architecture
ok

## 🎯 Current State
ok

## 📜 Development Log

### 2026-04-30 10:00 — Newer

**触发**: x
**改动**:
- a
**验证**:
- ok
**关联**: 无

---

### 2026-04-29 10:00 — Older

**触发**: x
**改动**:
- b
**验证**:
- ok
**关联**: 无

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
}

GOOD="$TMP_DIR/lint-good.md"
make_handoff "$GOOD"
bash "$LINT" "$GOOD" >/tmp/handoff-lint-good.out 2>&1
assert_exit "clean handoff exits 0" 0 "$?"

BAD_ANCHOR="$TMP_DIR/lint-bad-anchor.md"
make_handoff "$BAD_ANCHOR"
sed '/🚨 AI 注意/d' "$GOOD" > "$BAD_ANCHOR"
printf '\n## Other Section\n\n<!-- 🚨 AI 注意：outside dev log -->\n' >> "$BAD_ANCHOR"
bash "$LINT" "$BAD_ANCHOR" >/tmp/handoff-lint-anchor.out 2>&1
assert_exit "anchor outside Dev Log exits 1" 1 "$?"
assert_contains "anchor finding explains issue" "$(cat /tmp/handoff-lint-anchor.out)" "anchor must be inside Development Log"

BAD_ORDER="$TMP_DIR/lint-bad-order.md"
make_handoff "$BAD_ORDER"
perl -0pi -e 's/2026-04-29 10:00/2026-05-01 10:00/' "$BAD_ORDER"
bash "$LINT" "$BAD_ORDER" >/tmp/handoff-lint-order.out 2>&1
assert_exit "out-of-order Dev Log exits 1" 1 "$?"
assert_contains "order finding explains issue" "$(cat /tmp/handoff-lint-order.out)" "Dev Log entries must be reverse chronological"

BAD_FIELD="$TMP_DIR/lint-bad-field.md"
make_handoff "$BAD_FIELD"
perl -0pi -e 's/\n\*\*验证\*\*:\n- ok\n//' "$BAD_FIELD"
bash "$LINT" "$BAD_FIELD" >/tmp/handoff-lint-field.out 2>&1
assert_exit "missing required field exits 1" 1 "$?"
assert_contains "field finding explains issue" "$(cat /tmp/handoff-lint-field.out)" "missing fields"

BAD_FLOATING="$TMP_DIR/lint-floating-entry.md"
make_handoff "$BAD_FLOATING"
perl -0pi -e 's/# Demo/# Demo\n\n### 2026-04-30 11:00 — Floating entry\n\n**触发**: x\n**改动**: y\n**验证**: z\n**关联**: 无\n/' "$BAD_FLOATING"
bash "$LINT" "$BAD_FLOATING" >/tmp/handoff-lint-floating.out 2>&1
assert_exit "Dev Log entry outside section exits 1" 1 "$?"
assert_contains "floating entry finding explains issue" "$(cat /tmp/handoff-lint-floating.out)" "outside Development Log"

DECISION_OK="$TMP_DIR/lint-decision-ok.md"
make_handoff "$DECISION_OK"
perl -0pi -e 's/## 📜 Development Log/## 🧭 Decision Log\n\n### 2026-04-30 — Decision title\n- **背景**: x\n- **选择**: A\n\n## 📜 Development Log/' "$DECISION_OK"
bash "$LINT" "$DECISION_OK" >/tmp/handoff-lint-decision.out 2>&1
assert_exit "Decision Log date headings are allowed" 0 "$?"

# ─── v2 per-file frontmatter validation (Codex review #3) ─────────────────
# Previously handoff-lint short-circuited on v2 marker — the readiness gate
# was named-only. Now lint walks $HX_LOGS_DIR/ + $HX_DEC_DIR/ and
# validates frontmatter + body invariants for each entry.

# C-v2-ok: valid v2 layout passes (full four-piece layout present)
SANDBOX_OK=$(mktemp -d)
cat > "$SANDBOX_OK/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
EOF
mkdir -p "$SANDBOX_OK/$HX_LOGS_DIR" "$SANDBOX_OK/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_OK/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_OK/$HX_LOGS_DIR/0001-2026-05-01T1000-test.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: test entry
---

### 2026-05-01 10:00 — test entry

**触发**: foo
**改动**: bar
**验证**: ok
**关联**: 无
EOF
cat > "$SANDBOX_OK/$HX_DEC_DIR/0001-2026-05-01-test.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-05-01
number: 0001
title: test decision
---

### 2026-05-01 — test decision
- **背景**: x
EOF
ec=0; bash "$LINT" "$SANDBOX_OK/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: well-formed entries → exit 0" 0 "$ec"
rm -rf "$SANDBOX_OK"

# C-v2-fm-missing: missing frontmatter field → fail
SANDBOX_BFM=$(mktemp -d)
cat > "$SANDBOX_BFM/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_BFM/$HX_LOGS_DIR"
cat > "$SANDBOX_BFM/$HX_LOGS_DIR/0001-2026-05-01T1000-bad.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
---
no number, no title, body absent
EOF
out=$(bash "$LINT" "$SANDBOX_BFM/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: missing frontmatter field → exit 1" 1 "$ec"
assert_contains "v2 lint: reports missing field name" "$out" "missing field"
rm -rf "$SANDBOX_BFM"

# C-v2-no-frontmatter: file without leading --- → fail
SANDBOX_NF=$(mktemp -d)
cat > "$SANDBOX_NF/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_NF/$HX_LOGS_DIR"
cat > "$SANDBOX_NF/$HX_LOGS_DIR/0001-2026-05-01T1000-nf.md" <<'EOF'
no frontmatter at all
just a body
EOF
out=$(bash "$LINT" "$SANDBOX_NF/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: no frontmatter → exit 1" 1 "$ec"
assert_contains "v2 lint: reports missing frontmatter" "$out" "missing frontmatter"
rm -rf "$SANDBOX_NF"

# C-v2-num-mismatch: frontmatter number ≠ filename prefix → fail
SANDBOX_NUM=$(mktemp -d)
cat > "$SANDBOX_NUM/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_NUM/$HX_LOGS_DIR"
cat > "$SANDBOX_NUM/$HX_LOGS_DIR/0001-2026-05-01T1000-mm.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0042
title: mismatched
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_NUM/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: number ≠ filename prefix → exit 1" 1 "$ec"
assert_contains "v2 lint: reports the mismatch" "$out" "filename prefix"
rm -rf "$SANDBOX_NUM"

# C-v2-type-mismatch: Dev Log file with type:decision → fail
SANDBOX_TM=$(mktemp -d)
cat > "$SANDBOX_TM/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_TM/$HX_LOGS_DIR"
cat > "$SANDBOX_TM/$HX_LOGS_DIR/0001-2026-05-01T1000-wrong.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-05-01T10:00
number: 0001
title: wrong type
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_TM/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: Dev Log dir with type:decision → exit 1" 1 "$ec"
assert_contains "v2 lint: reports type expectation" "$out" "type must be dev-log"
rm -rf "$SANDBOX_TM"

# C-v2-body-fields: Dev Log entry missing required body fields → fail
SANDBOX_BF=$(mktemp -d)
cat > "$SANDBOX_BF/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_BF/$HX_LOGS_DIR"
cat > "$SANDBOX_BF/$HX_LOGS_DIR/0001-2026-05-01T1000-bf.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: missing body
---
just a body, no required fields
EOF
out=$(bash "$LINT" "$SANDBOX_BF/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: Dev Log missing body fields → exit 1" 1 "$ec"
assert_contains "v2 lint: reports specific missing field" "$out" "触发"
rm -rf "$SANDBOX_BF"

# C-v2-non-canonical-name (Codex review #5): non-canonical filename rejected
SANDBOX_NCF=$(mktemp -d)
cat > "$SANDBOX_NCF/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_NCF/$HX_LOGS_DIR"
# 'random-name.md' doesn't match NNNN-YYYY-MM-DDTHHMM-slug.md
cat > "$SANDBOX_NCF/$HX_LOGS_DIR/random-name.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: bad filename
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_NCF/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: non-canonical filename → exit 1" 1 "$ec"
assert_contains "v2 lint: reports non-canonical filename" "$out" "non-canonical filename"
rm -rf "$SANDBOX_NCF"

# C-v2-bad-date (Codex review #5): wrong date format
SANDBOX_BD=$(mktemp -d)
cat > "$SANDBOX_BD/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_BD/$HX_LOGS_DIR"
cat > "$SANDBOX_BD/$HX_LOGS_DIR/0001-2026-05-01T1000-bd.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026/05/01 10:00
number: 0001
title: bad date format
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_BD/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: bad date format → exit 1" 1 "$ec"
assert_contains "v2 lint: reports date format problem" "$out" "date format invalid"
rm -rf "$SANDBOX_BD"

# C-v2-empty-title (Codex review #5): empty title fails
SANDBOX_ET=$(mktemp -d)
cat > "$SANDBOX_ET/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_ET/$HX_LOGS_DIR"
cat > "$SANDBOX_ET/$HX_LOGS_DIR/0001-2026-05-01T1000-et.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title:
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_ET/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: empty title → exit 1" 1 "$ec"
assert_contains "v2 lint: reports empty title" "$out" "title is empty"
rm -rf "$SANDBOX_ET"

# C-v2-bad-number-fmt (Codex review #5): number not 4 digits → fail
SANDBOX_BN=$(mktemp -d)
cat > "$SANDBOX_BN/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_BN/$HX_LOGS_DIR"
cat > "$SANDBOX_BN/$HX_LOGS_DIR/0001-2026-05-01T1000-bn.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 1
title: bad number format
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_BN/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: number not 4 digits → exit 1" 1 "$ec"
assert_contains "v2 lint: reports number format" "$out" "number must be 4 digits"
rm -rf "$SANDBOX_BN"

# C-v2-missing-siblings (Codex review #7): v2 marker without sibling artifacts
# must fail readiness — previously lint silently passed.
SANDBOX_MS=$(mktemp -d)
cat > "$SANDBOX_MS/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
EOF
out=$(bash "$LINT" "$SANDBOX_MS/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: marker w/o siblings → exit 1" 1 "$ec"
assert_contains "v2 lint: reports missing $HX_LOGS_DIR" "$out" "$HX_LOGS_DIR"
assert_contains "v2 lint: reports missing $HX_DEC_DIR" "$out" "$HX_DEC_DIR"
assert_contains "v2 lint: reports missing GOTCHAS" "$out" "$HX_GOTCHAS_FILE"
rm -rf "$SANDBOX_MS"

# C-v2-empty-date (Codex review #9): empty date value fails (was bypassed)
SANDBOX_ED=$(mktemp -d)
cat > "$SANDBOX_ED/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_ED/$HX_LOGS_DIR" "$SANDBOX_ED/$HX_DEC_DIR"
echo "# stub" > "$SANDBOX_ED/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_ED/$HX_LOGS_DIR/0001-2026-05-01T1000-ed.md" <<'EOF'
---
schema: 2
type: dev-log
date:
number: 0001
title: empty date
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_ED/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: empty date value → exit 1" 1 "$ec"
assert_contains "v2 lint: reports empty date" "$out" "date is empty"
rm -rf "$SANDBOX_ED"

# C-v2-date-drift (Codex review #10): filename date must match frontmatter date
SANDBOX_DD=$(mktemp -d)
cat > "$SANDBOX_DD/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_DD/$HX_LOGS_DIR" "$SANDBOX_DD/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_DD/$HX_GOTCHAS_FILE"
# Filename says 2026-05-07T0930, frontmatter says 2026-04-01T10:00 — drift
cat > "$SANDBOX_DD/$HX_LOGS_DIR/0001-2026-05-07T0930-drift.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-04-01T10:00
number: 0001
title: drifted
---
**触发**: x
**改动**: y
**验证**: z
**关联**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_DD/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: filename/frontmatter date drift → exit 1" 1 "$ec"
assert_contains "v2 lint: reports drift specifically" "$out" "filename date"
rm -rf "$SANDBOX_DD"

# C-v2-decision-date-drift: same drift check applies to Decisions
SANDBOX_DDD=$(mktemp -d)
cat > "$SANDBOX_DDD/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_DDD/$HX_LOGS_DIR" "$SANDBOX_DDD/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_DDD/$HX_GOTCHAS_FILE"
# Filename says 2026-05-07, frontmatter says 2026-04-01 — drift
cat > "$SANDBOX_DDD/$HX_DEC_DIR/0001-2026-05-07-drift.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-04-01
number: 0001
title: drifted decision
---
- **背景**: x
EOF
out=$(bash "$LINT" "$SANDBOX_DDD/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: decision date drift → exit 1" 1 "$ec"
rm -rf "$SANDBOX_DDD"

# ─── v2.1.0 UX polish: synonym tolerance for body fields ──────────────────
# Allow English aliases for the 4 Dev Log body fields so users who write in
# English don't trip the readiness gate. Canonical (Chinese) form remains
# the primary; English forms are co-accepted.
#   触发 ≡ Trigger     改动 ≡ Changes
#   验证 ≡ Verification 关联 ≡ Related

# C-v2-en-aliases-ok: full English-alias body → exit 0
SANDBOX_EN=$(mktemp -d)
cat > "$SANDBOX_EN/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_EN/$HX_LOGS_DIR" "$SANDBOX_EN/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_EN/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_EN/$HX_LOGS_DIR/0001-2026-05-01T1000-en.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: english body fields
---

### 2026-05-01 10:00 — english body fields

**Trigger**: user typed this in English
**Changes**: added feature X
**Verification**: tests pass
**Related**: prior Dev Log
EOF
ec=0; bash "$LINT" "$SANDBOX_EN/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: full English aliases → exit 0" 0 "$ec"
rm -rf "$SANDBOX_EN"

# C-v2-mixed-aliases-ok: mix 中文 + English on different fields → exit 0
SANDBOX_MX=$(mktemp -d)
cat > "$SANDBOX_MX/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_MX/$HX_LOGS_DIR" "$SANDBOX_MX/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_MX/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_MX/$HX_LOGS_DIR/0001-2026-05-01T1000-mx.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: mixed bilingual body
---

### 2026-05-01 10:00 — mixed bilingual body

**触发**: bilingual scenario
**Changes**: refactored Y
**验证**: lint passes
**Related**: handoff-lint synonym work
EOF
ec=0; bash "$LINT" "$SANDBOX_MX/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: mixed CN/EN aliases → exit 0" 0 "$ec"
rm -rf "$SANDBOX_MX"

# C-v2-typo-rejected: misspelled alias (Tigger instead of Trigger) → exit 1
# proves synonym tolerance is not "anything goes" — only the dict is accepted
SANDBOX_TP=$(mktemp -d)
cat > "$SANDBOX_TP/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_TP/$HX_LOGS_DIR" "$SANDBOX_TP/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_TP/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_TP/$HX_LOGS_DIR/0001-2026-05-01T1000-tp.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: typo in alias
---

### 2026-05-01 10:00 — typo in alias

**Tigger**: typo, should be rejected
**Changes**: bar
**Verification**: ok
**Related**: 无
EOF
out=$(bash "$LINT" "$SANDBOX_TP/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: typo alias (Tigger) → exit 1" 1 "$ec"
assert_contains "v2 lint: typo report mentions canonical 触发" "$out" "触发"
rm -rf "$SANDBOX_TP"

# C-v2-decision-no-body: Decisions are NOT required to have 触发/改动/验证/关联
# (sandbox needs all three siblings to satisfy the new "require layout" check)
SANDBOX_DEC=$(mktemp -d)
cat > "$SANDBOX_DEC/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_DEC/$HX_LOGS_DIR" "$SANDBOX_DEC/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_DEC/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_DEC/$HX_DEC_DIR/0001-2026-05-01-no-body.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-05-01
number: 0001
title: no body fields
---
- **背景**: x
- **选择**: A
EOF
ec=0; bash "$LINT" "$SANDBOX_DEC/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: Decision without 触发/改动 etc. → exit 0" 0 "$ec"
rm -rf "$SANDBOX_DEC"

# C-v2-index-skip (B③ regression): generated INDEX.md in $HX_DEC_DIR/
# must NOT be flagged as non-canonical — it is a sibling artifact, not a
# decision entry. Validators were written before B③ existed.
SANDBOX_IDX=$(mktemp -d)
cat > "$SANDBOX_IDX/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$SANDBOX_IDX/$HX_LOGS_DIR" "$SANDBOX_IDX/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_IDX/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_IDX/$HX_DEC_DIR/0001-2026-01-01-x.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-01-01
number: 0001
title: x
---
- **背景**: x
EOF
# Simulate the INDEX.md generated by B③ (regenerate_decision_index)
printf '| # | Date | Title |\n|---|------|-------|\n| 0001 | 2026-01-01 | x |\n' \
    > "$SANDBOX_IDX/$HX_DEC_DIR/INDEX.md"
out=$(bash "$LINT" "$SANDBOX_IDX/$HX_MAIN_FILE" 2>&1)
ec=$?
assert_exit "v2 lint: generated INDEX.md in $HX_DEC_DIR → exit 0" 0 "$ec"
if printf '%s' "$out" | grep -q "INDEX.md.*non-canonical"; then
    echo "  ❌ B③ regression: lint flagged INDEX.md as non-canonical"; FAIL=$((FAIL+1))
else
    echo "  ✅ B③ regression: INDEX.md not flagged"; PASS=$((PASS+1))
fi
# C-v2-index-overbroad (Codex stop-time): the INDEX.md exemption must be SCOPED
# to the decisions dir only. An INDEX.md in $HX_LOGS_DIR/ is NOT B③-generated
# and MUST still be flagged malformed (loop walks *.md to catch, not skip).
printf '| # |\n' > "$SANDBOX_IDX/$HX_LOGS_DIR/INDEX.md"
out2=$(bash "$LINT" "$SANDBOX_IDX/$HX_MAIN_FILE" 2>&1)
if printf '%s' "$out2" | grep -q "INDEX.md: non-canonical filename for dev-log"; then
    echo "  ✅ over-broad fix: $HX_LOGS_DIR/INDEX.md still flagged malformed"; PASS=$((PASS+1))
else
    echo "  ❌ over-broad: $HX_LOGS_DIR/INDEX.md silently skipped (exemption too wide)"; FAIL=$((FAIL+1))
fi
rm -rf "$SANDBOX_IDX"

# C-v2-unreadable-dir (2026-06-07 audit CRITICAL-B, Gotcha #24): a $HX_LOGS_DIR/
# that exists but cannot be listed used to collapse into "0 files → clean"
# (`[ -d ] || return 0` + empty glob) → exit 0, and validate --readiness /
# postflight inherited the false green. The twin xref-lint was made fail-closed
# in P1.2; this aligns handoff-lint. Root-skip mirrors B7-a / bguard c5: EUID=0
# bypasses chmod 000 so the unreadable state cannot be constructed.
SANDBOX_UD=$(mktemp -d)
cat > "$SANDBOX_UD/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
EOF
mkdir -p "$SANDBOX_UD/$HX_LOGS_DIR" "$SANDBOX_UD/$HX_DEC_DIR"
echo "# Known Gotchas" > "$SANDBOX_UD/$HX_GOTCHAS_FILE"
cat > "$SANDBOX_UD/$HX_LOGS_DIR/0001-2026-05-01T1000-test.md" <<'EOF'
---
schema: 2
type: dev-log
date: 2026-05-01T10:00
number: 0001
title: test entry
---

### 2026-05-01 10:00 — test entry

**触发**: foo
**改动**: bar
**验证**: ok
**关联**: 无
EOF
cat > "$SANDBOX_UD/$HX_DEC_DIR/0001-2026-05-01-test.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-05-01
number: 0001
title: test decision
---

### 2026-05-01 — test decision
- **背景**: x
EOF
# baseline must be clean, otherwise the negative controls below prove nothing
ec=0; bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: unreadable-dir fixture baseline → exit 0" 0 "$ec"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ v2 lint unreadable-dir/file SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$SANDBOX_UD/$HX_LOGS_DIR"
    out=$(bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" 2>&1); ec=$?
    chmod 755 "$SANDBOX_UD/$HX_LOGS_DIR"
    assert_exit "v2 lint: unreadable $HX_LOGS_DIR/ → exit 1 (not silent clean)" 1 "$ec"
    assert_contains "v2 lint: unreadable dir names itself as uncheckable" "$out" "cannot lint"
    # Lock the per-file path too: today an unreadable entry fails only because
    # `head -1` returns empty → "missing frontmatter". Keep that non-zero so a
    # future refactor of the frontmatter probe cannot reopen it.
    chmod 000 "$SANDBOX_UD/$HX_LOGS_DIR/0001-2026-05-01T1000-test.md"
    ec=0; bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
    chmod 644 "$SANDBOX_UD/$HX_LOGS_DIR/0001-2026-05-01T1000-test.md"
    assert_exit "v2 lint: unreadable single entry → exit 1" 1 "$ec"
fi
# A regular file squatting on the canonical dir path passes the `[ -e ]`
# sibling check but not `[ -d ]`; it used to `return 0` silently. Root-immune
# (no chmod involved), so it runs unconditionally.
rm -rf "$SANDBOX_UD/$HX_LOGS_DIR"; echo x > "$SANDBOX_UD/$HX_LOGS_DIR"
ec=0; bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: $HX_LOGS_DIR is a regular file → exit 1" 1 "$ec"
# A dangling symlink or a directory named *.md used to hit `[ -f ] || continue`
# and vanish — both are broken entries recall would trip on. Root-immune.
# Restore the Logs dir first: the squat above would keep exit 1 on its own
# and make these two assertions pass for the wrong reason.
rm -f "$SANDBOX_UD/$HX_LOGS_DIR"; mkdir "$SANDBOX_UD/$HX_LOGS_DIR"
ec=0; bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: fixture restored → exit 0 before the symlink/dir cases" 0 "$ec"
ln -s /nonexistent/entry.md "$SANDBOX_UD/$HX_DEC_DIR/0002-2026-05-02-link.md"
out=$(bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" 2>&1); ec=$?
assert_exit "v2 lint: dangling symlink entry → exit 1" 1 "$ec"
assert_contains "v2 lint: dangling symlink entry is named" "$out" "dangling symlink"
rm "$SANDBOX_UD/$HX_DEC_DIR/0002-2026-05-02-link.md"
mkdir "$SANDBOX_UD/$HX_DEC_DIR/0003-2026-05-03-dir.md"
ec=0; bash "$LINT" "$SANDBOX_UD/$HX_MAIN_FILE" >/dev/null 2>&1 || ec=$?
assert_exit "v2 lint: directory named *.md → exit 1" 1 "$ec"
rm -rf "$SANDBOX_UD"

summary
