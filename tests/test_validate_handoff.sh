#!/bin/bash
source "$(dirname "$0")/common.sh"
VAL="$SCRIPTS_DIR/validate-handoff.sh"

# --- template file itself must have all key sections ---
TPL="$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md"
assert_file_exists "template exists" "$TPL"

for section in "Project Overview" "Architecture" "Coding Conventions" "Current State" "Known Gotchas" "Decision Log" "References" "Milestones" "Features" "Testing" "Development Log"; do
    if grep -qE "^## [^A-Za-z]*$section" "$TPL"; then
        echo "  ✅ template has section: $section"; PASS=$((PASS+1))
    else
        echo "  ❌ template missing section: $section"; FAIL=$((FAIL+1))
    fi
done

if grep -q "🚨 AI 注意" "$TPL"; then
    echo "  ✅ template has anchor comment"; PASS=$((PASS+1))
else
    echo "  ❌ template missing anchor"; FAIL=$((FAIL+1))
fi

# --- validator: good file passes ---
ex=0; "$VAL" "$TPL" > /dev/null 2>&1 || ex=$?
assert_exit "validator passes on template" 0 "$ex"

# --- validator readiness mode delegates to handoff-lint invariants ---
ready="$TMP_DIR/ready_$$.md"
cat > "$ready" <<'EOF'
# T
## 📦 Project Overview
x
## 🏗 Architecture
x
## 🎯 Current State
x
## 📜 Development Log
### 2026-04-30 10:00 — Newer
**触发**: x
**改动**:
- a
**验证**:
- ok
**关联**: 无
### 2026-04-29 10:00 — Older
**触发**: x
**改动**:
- b
**验证**:
- ok
**关联**: 无
<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ex=0; "$VAL" --readiness "$ready" > /dev/null 2>&1 || ex=$?
assert_exit "validator --readiness passes on recall-ready file" 0 "$ex"

not_ready="$TMP_DIR/not_ready_$$.md"
perl -0pe 's/2026-04-29 10:00/2026-05-01 10:00/' "$ready" > "$not_ready"
out=$("$VAL" --readiness "$not_ready" 2>&1 || true)
ex=0; "$VAL" --readiness "$not_ready" > /dev/null 2>&1 || ex=$?
assert_exit "validator --readiness fails on out-of-order Dev Log" 1 "$ex"
assert_contains "validator --readiness reports lint finding" "$out" "reverse chronological"

# --- validator: missing required section fails ---
bad="$TMP_DIR/bad_$$.md"
grep -v "Current State" "$TPL" > "$bad"
ex=0; "$VAL" "$bad" > /dev/null 2>&1 || ex=$?
assert_exit "validator fails without Current State" 1 "$ex"

# --- validator: v1 layout missing anchor fails (v2 layouts don't need it) ---
# Strip v2 marker first so we test the v1 anchor invariant unambiguously.
bad2="$TMP_DIR/bad2_$$.md"
grep -v -F -- '<!-- HANDOFF v2 schema -->' "$TPL" | grep -v "🚨 AI 注意" > "$bad2"
ex=0; "$VAL" "$bad2" > /dev/null 2>&1 || ex=$?
assert_exit "validator fails without anchor (v1 layout)" 1 "$ex"

# --- validator: missing Decision Log warns but does not fail ---
bad3="$TMP_DIR/bad3_$$.md"
grep -v "Decision Log" "$TPL" > "$bad3"
out=$("$VAL" "$bad3" 2>&1 || true)
ex=0; "$VAL" "$bad3" > /dev/null 2>&1 || ex=$?
assert_exit    "validator exits 0 when only Decision Log missing" 0 "$ex"
assert_contains "validator warns about Decision Log" "$out" "Decision Log"

# --- validator: missing References warns but does not fail ---
bad4="$TMP_DIR/bad4_$$.md"
grep -v "References" "$TPL" > "$bad4"
out=$("$VAL" "$bad4" 2>&1 || true)
ex=0; "$VAL" "$bad4" > /dev/null 2>&1 || ex=$?
assert_exit    "validator exits 0 when only References missing" 0 "$ex"
assert_contains "validator warns about References" "$out" "References"

# --- validator recognises the project-knowledge trio as RECOMMENDED ---
for sec in Milestones Features Testing; do
    bad="$TMP_DIR/bad_${sec}_$$.md"
    grep -v "$sec" "$TPL" > "$bad"
    out=$("$VAL" "$bad" 2>&1 || true)
    ex=0; "$VAL" "$bad" > /dev/null 2>&1 || ex=$?
    assert_exit    "validator exits 0 when only $sec missing" 0 "$ex"
    assert_contains "validator warns about $sec"          "$out" "$sec"
done

# --- Overview must include Goals + Non-Goals (Nonaka/Grove: why, not just what) ---
assert_contains "template Overview has Goals"     "$(cat "$TPL")" "Goals"
assert_contains "template Overview has Non-Goals" "$(cat "$TPL")" "Non-Goals"

# --- validator: nonexistent file ---
ex=0; "$VAL" "/no/such/file.md" > /dev/null 2>&1 || ex=$?
assert_exit "validator fails on missing file" 2 "$ex"

# --- validator: 复合标题 "X & Y" / "X — Z" 必须被识别（regex 右端锚定修复回归） ---
compound="$TMP_DIR/compound_$$.md"
cat > "$compound" <<'EOF'
# T
## 📦 Project Overview
x
## 🏗 Architecture
x
## 🎯 Current State
x
## 🧭 Decision Log
x
## 🗺 Milestones & Roadmap
x
## ✨ Features & Modules — 已交付全景
x
## 🧪 Testing — 详细测试状况
x
## 📚 References & Docs Map
x
## 🔑 Coding Conventions
x
## 🐛 Known Gotchas
x
## 📜 Development Log
x
<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ex=0; "$VAL" "$compound" > /dev/null 2>&1 || ex=$?
assert_exit "compound titles (X & Y / X — Z) recognized" 0 "$ex"

# --- validator: 反向检查——"Architecture Notes" 不能被误判为 "Architecture" 存在 ---
false_pos="$TMP_DIR/falsepos_$$.md"
cat > "$false_pos" <<'EOF'
# T
## 📦 Project Overview
x
## 🏗 Architecture Notes
x
## 🎯 Current State
x
## 📜 Development Log
x
<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ex=0; "$VAL" "$false_pos" > /dev/null 2>&1 || ex=$?
assert_exit "'Architecture Notes' does NOT match 'Architecture' (still rejected)" 1 "$ex"

# ─── v2 directory-arg mode (H3) ─────────────────────────────────────────────
SANDBOX_V2=$(mktemp -d)
cat > "$SANDBOX_V2/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
x

## 🏗 Architecture
x

## 🎯 Current State
x

## 📜 Development Log

最近一条：(none)
最早一条：(none)
共 0 条

## 🐛 Known Gotchas

共 0 条；最新：(none)

## 🧭 Decision Log

共 0 条；最新：`(none)`

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ex=0; "$VAL" "$SANDBOX_V2" >/dev/null 2>&1 || ex=$?
assert_exit "v2 dir arg with valid pointer blocks → exit 0" 0 "$ex"

EMPTY_V2=$(mktemp -d)
ex=0; "$VAL" "$EMPTY_V2" >/dev/null 2>&1 || ex=$?
assert_exit "v2 empty dir → exit 2" 2 "$ex"

# v2 marker but missing pointer stats → warning printed, exit still 0 (soft).
SANDBOX_BROKEN=$(mktemp -d)
cat > "$SANDBOX_BROKEN/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
## 📦 Project Overview
x
## 🏗 Architecture
x
## 🎯 Current State
x
## 📜 Development Log
(missing 共 N 条 stat line)
## 🐛 Known Gotchas
(missing stat)
## 🧭 Decision Log
(missing stat)
<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
out=$("$VAL" "$SANDBOX_BROKEN/${HX_MAIN_FILE}" 2>&1 || true)
assert_contains "v2 marker without stats → warns about pointer stats" "$out" "pointer stat lines missing"

rm -rf "$SANDBOX_V2" "$EMPTY_V2" "$SANDBOX_BROKEN"

# B③ regression: validate-handoff --readiness delegates to handoff-lint, which
# must NOT flag the generated INDEX.md in ${HX_DEC_DIR}/ as non-canonical.
SANDBOX_IDX_V=$(mktemp -d)
cat > "$SANDBOX_IDX_V/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
x

## 🏗 Architecture
x

## 🎯 Current State
x

## 📜 Development Log

最近一条：(none)
最早一条：(none)
共 0 条

## 🐛 Known Gotchas

共 0 条；最新：(none)

## 🧭 Decision Log

共 1 条；最新：`x`

EOF
mkdir -p "$SANDBOX_IDX_V/${HX_LOGS_DIR}" "$SANDBOX_IDX_V/${HX_DEC_DIR}"
echo "# Known Gotchas" > "$SANDBOX_IDX_V/${HX_GOTCHAS_FILE}"
cat > "$SANDBOX_IDX_V/${HX_DEC_DIR}/0001-2026-01-01-x.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-01-01
number: 0001
title: x
---
- **背景**: x
EOF
# Simulate the B③-generated INDEX.md sibling
printf '| # | Date | Title |\n|---|------|-------|\n| 0001 | 2026-01-01 | x |\n' \
    > "$SANDBOX_IDX_V/${HX_DEC_DIR}/INDEX.md"
out=$("$VAL" --readiness "$SANDBOX_IDX_V/${HX_MAIN_FILE}" 2>&1 || true)
ex=0; "$VAL" --readiness "$SANDBOX_IDX_V/${HX_MAIN_FILE}" >/dev/null 2>&1 || ex=$?
assert_exit "validate --readiness: generated INDEX.md does NOT cause failure" 0 "$ex"
if printf '%s' "$out" | grep -q "INDEX.md.*non-canonical"; then
    echo "  ❌ B③ regression: validate flagged INDEX.md as non-canonical"; FAIL=$((FAIL+1))
else
    echo "  ✅ B③ regression: INDEX.md not flagged by validate --readiness"; PASS=$((PASS+1))
fi
rm -rf "$SANDBOX_IDX_V"

# P2.4 §4b-4 legacy-layout guard: --readiness on a project still on a legacy
# layout must exit 2 with the upgrade command, not "file not found" or a pass.
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
ex=0; out=$("$VAL" --readiness "$LG" 2>&1) || ex=$?
assert_exit "legacy v3 tree → validate --readiness exit 2" 2 "$ex"
assert_contains "legacy v3 tree → names schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
rm -rf "$LG"
LG=$(mktemp -d); cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$LG/$HX_LEGACY_MAIN_FILE"
ex=0; out=$(cd "$LG" && "$VAL" --readiness 2>&1) || ex=$?
assert_exit "legacy v1 file → validate --readiness exit 2" 2 "$ex"
assert_contains "legacy v1 file → names migrate-to-v2 --apply" "$out" "migrate-to-v2.sh --apply"
rm -rf "$LG"
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
cp "$LG/$HX_LEGACY_MAIN_FILE" "$LG/$HX_MAIN_FILE"
ex=0; out=$("$VAL" --readiness "$LG" 2>&1) || ex=$?
assert_exit "mixed legacy+new → validate --readiness exit 2" 2 "$ex"
assert_contains "mixed legacy+new → names the mixed state" "$out" "mixed layout"
rm -rf "$LG"

# --- v4.2.0 Task 3: RECOMMENDED one-liner + hx: anchor info ---
RQ=$(mktemp -d)
mk_v2() { # $1=file $2=extra line inside Current State
    cat > "$1" <<EOF2
# T
<!-- HANDOFF v2 schema -->
## 📋 Project Overview
x
## 🏗 Architecture
x
## 🎯 Current State
$2
## 📜 Development Log
共 1 条
## 🐛 Known Gotchas
共 1 条；最新：x
## 🧭 Decision Log
共 1 条；最新：x
## 📚 References
x
## 🏁 Milestones
x
## ✨ Features
x
EOF2
}
mk_v2 "$RQ/noanchor.md" "plain"
ex=0; out=$("$VAL" "$RQ/noanchor.md" 2>&1) || ex=$?
assert_exit "RECOMMENDED missing → exit still 0" 0 "$ex"
assert_contains "RECOMMENDED one-liner has count + names" "$out" "RECOMMENDED missing (2): Coding Conventions, Testing"
assert_contains "RECOMMENDED one-liner points to tidy" "$out" "/handoffx-tidy"
n=$(printf '%s\n' "$out" | grep -c 'RECOMMENDED missing')
assert_exit "RECOMMENDED missing printed on exactly one line" 1 "$n"
assert_not_contains "no structure OK when RECOMMENDED missing" "$out" "structure OK"
assert_contains "no anchor → info line" "$out" "Current State has no hx: anchors"
mk_v2 "$RQ/anchor.md" "<!-- hx:recent -->"
ex=0; out=$("$VAL" "$RQ/anchor.md" 2>&1) || ex=$?
assert_exit "with anchor → exit 0" 0 "$ex"
assert_not_contains "with anchor → no info line" "$out" "no hx: anchors"
# Scope: an hx: marker outside Current State (here in Development Log) must not count.
mk_v2 "$RQ/scope_src.md" "plain"
awk '{print} /^共 1 条$/ && !d {print "<!-- hx:x -->"; d=1}' "$RQ/scope_src.md" > "$RQ/scope.md"
grep -qF -- '<!-- hx:x -->' "$RQ/scope.md" || FAIL=$((FAIL+1))
ex=0; out=$("$VAL" "$RQ/scope.md" 2>&1) || ex=$?
assert_exit "anchor outside Current State → exit 0" 0 "$ex"
assert_contains "anchor outside Current State still reports no hx: anchors" "$out" "no hx: anchors"
# final M1: a comment with trailing text is not an anchor line — validate,
# tidy and hx.sh must agree on that.
mk_v2 "$RQ/textline.md" "<!-- hx:x --> 文字"
ex=0; out=$("$VAL" "$RQ/textline.md" 2>&1) || ex=$?
assert_exit "anchor-shaped comment with text → exit 0" 0 "$ex"
assert_contains "anchor-shaped comment with text → still no hx: anchors" "$out" "no hx: anchors"
# A closing anchor alone is still an anchor line (tidy leaves such a section alone).
mk_v2 "$RQ/close.md" "<!-- /hx:x -->  "
ex=0; out=$("$VAL" "$RQ/close.md" 2>&1) || ex=$?
assert_not_contains "closing anchor line with trailing blanks counts" "$out" "no hx: anchors"
# N=1: exactly one missing section, no stray separator.
{ cat "$RQ/noanchor.md"; printf '## 🧭 Coding Conventions\nx\n'; } > "$RQ/one.md"
ex=0; out=$("$VAL" "$RQ/one.md" 2>&1) || ex=$?
assert_exit "N=1 RECOMMENDED → exit 0" 0 "$ex"
assert_contains "N=1 line is exact" "$out" "RECOMMENDED missing (1): Testing —"
n=$(printf '%s\n' "$out" | grep -c 'RECOMMENDED missing')
assert_exit "N=1 RECOMMENDED printed on exactly one line" 1 "$n"
rm -rf "$RQ"
# v4.2.0 Task 5: the template ships with Current State anchors, so a fresh
# project never gets the "no hx: anchors" hint.
out=$("$VAL" "$TPL" 2>&1) || true
assert_not_contains "template: no 'no hx: anchors' info line" "$out" "no hx: anchors"

summary
