#!/bin/bash
source "$(dirname "$0")/common.sh"
TIDY="$SCRIPTS_DIR/tidy-handoff.sh"

# Cases 1-14 below test the legacy v1 tidy diagnostics on v1-layout fixtures.
# Phase I will replace them with v2-aware versions. Until then, bypass the v2
# layout gate so they run unchanged. Cases 15-* below clear this and exercise
# the gate explicitly.
export HANDOFF_TIDY_SKIP_V2_GATE=1

# 生成一个 valid $HX_MAIN_FILE 基线
# (Current State carries its hx: anchors: since v4.2.0 tidy adds them to an
# anchor-less section, so a clean file has them.)
mk_valid() {
    local f="$1"
    cat > "$f" <<'EOF'
# Demo — Project Handoff

## 📦 Project Overview
placeholder.

## 🏗 Architecture
placeholder.

## 🎯 Current State
<!-- hx:recent -->
placeholder.
<!-- /hx:recent -->

## 🐛 Known Gotchas
placeholder.

## 🧭 Decision Log

### 2026-04-01 — Older decision
- **背景**: x
- **选择**: A

### 2026-04-15 — Newer decision
- **背景**: y
- **选择**: B

## 📜 Development Log

### 2026-04-10 12:00 — Second entry

**触发**: reason
**改动**: file2.md
**验证**: ok
**关联**: 无

---

### 2026-04-20 10:00 — First entry (newest)

**触发**: reason
**改动**: file1.md
**验证**: ok
**关联**: 无

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
}

# --- Case 1: missing file exits 2 ---
ex=0; "$TIDY" "/no/such.md" >/dev/null 2>&1 || ex=$?
assert_exit "missing file exits 2" 2 "$ex"

# --- Case 2: clean file stays clean (idempotent) ---
f1="$TMP_DIR/tidy_clean_$$.md"
mk_valid "$f1"
sha_before=$(shasum "$f1" | cut -d' ' -f1)
"$TIDY" "$f1" >/dev/null 2>&1
sha_after=$(shasum "$f1" | cut -d' ' -f1)
assert_exit "clean file unchanged after tidy" "$sha_before" "$sha_after"

# --- Case 3: collapse 3+ blank lines to 2 ---
f2="$TMP_DIR/tidy_blanks_$$.md"
mk_valid "$f2"
# inject 5 blank lines in the middle
awk 'NR==5{print "\n\n\n\n"} {print}' "$f2" > "$f2.tmp" && mv "$f2.tmp" "$f2"
"$TIDY" "$f2" >/dev/null 2>&1
max_consec=$(awk 'BEGIN{b=0;max=0} /^$/{b++; if(b>max)max=b; next} {b=0} END{print max}' "$f2")
if [ "$max_consec" -le 2 ]; then
    echo "  ✅ collapsed >2 blank lines to ≤2"; PASS=$((PASS+1))
else
    echo "  ❌ still has $max_consec consecutive blank lines"; FAIL=$((FAIL+1))
fi

# --- Case 4: add missing anchor ---
f3="$TMP_DIR/tidy_noanchor_$$.md"
mk_valid "$f3"
grep -v "🚨 AI 注意" "$f3" > "$f3.tmp" && mv "$f3.tmp" "$f3"
"$TIDY" "$f3" >/dev/null 2>&1
if grep -q "🚨 AI 注意" "$f3"; then
    echo "  ✅ anchor re-added"; PASS=$((PASS+1))
else
    echo "  ❌ anchor missing after tidy"; FAIL=$((FAIL+1))
fi

# --- Case 5: report Dev Log entries out of order ---
f4="$TMP_DIR/tidy_unsorted_$$.md"
mk_valid "$f4"
out=$("$TIDY" "$f4" 2>&1)
# baseline has older-on-top BEFORE tidy fixes? actually mk_valid has 2026-04-10 then 2026-04-20 — old on top = out of order
assert_contains "detects out-of-order dev log" "$out" "Dev Log"

# --- Case 6: report missing REQUIRED sections ---
f5="$TMP_DIR/tidy_missing_$$.md"
cat > "$f5" <<'EOF'
# Incomplete
## 📦 Project Overview
x
## 📜 Development Log
### 2026-04-01 10:00 — e
**触发**: —
**改动**: —
**验证**: —
**关联**: —
---
<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
out=$("$TIDY" "$f5" 2>&1)
assert_contains "reports missing Architecture" "$out" "Architecture"
assert_contains "reports missing Current State" "$out" "Current State"

# --- Case 7: report Dev Log entries with missing fields ---
f6="$TMP_DIR/tidy_missingfield_$$.md"
cat > "$f6" <<'EOF'
# Demo

## 📦 Project Overview
x
## 🏗 Architecture
x
## 🎯 Current State
x
## 📜 Development Log

### 2026-04-20 10:00 — Half-filled entry

**触发**: did a thing

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
out=$("$TIDY" "$f6" 2>&1)
assert_contains "reports missing 改动 field" "$out" "改动"

# --- Case 8: idempotent after fix (run twice, 2nd run same as 1st output file) ---
f7="$TMP_DIR/tidy_idem_$$.md"
mk_valid "$f7"
# inject multi-blank
awk 'NR==5{print "\n\n\n"} {print}' "$f7" > "$f7.tmp" && mv "$f7.tmp" "$f7"
"$TIDY" "$f7" >/dev/null 2>&1
sha1=$(shasum "$f7" | cut -d' ' -f1)
"$TIDY" "$f7" >/dev/null 2>&1
sha2=$(shasum "$f7" | cut -d' ' -f1)
assert_exit "idempotent second run" "$sha1" "$sha2"

# --- Case 9: backup file created before mutation ---
f8="$TMP_DIR/tidy_backup_$$.md"
mk_valid "$f8"
awk 'NR==5{print "\n\n\n"} {print}' "$f8" > "$f8.tmp" && mv "$f8.tmp" "$f8"
"$TIDY" "$f8" >/dev/null 2>&1
if [ -f "${f8}.bak" ]; then
    echo "  ✅ backup file created"; PASS=$((PASS+1))
else
    echo "  ❌ no backup file"; FAIL=$((FAIL+1))
fi

# --- Case 10: I9 invariant — tidy 只动结构不动内容（Expert Weber P0 / Okafor P1） ---
# 构造内容丰富且脏的文件，验证 tidy 后每一行"有内容的文本"都字节级保留。
# 允许被 tidy 改动的只有：空行数量、末尾追加的锚点注释。
f9="$TMP_DIR/tidy_i9_$$.md"
cat > "$f9" <<'EOF'
# Rich content — I9 invariant test

## 📦 Project Overview
一个用于验证 tidy 不篡改用户内容的夹具。含中英混排、引号、代码块、emoji 🚀。



## 🏗 Architecture
```bash
echo "don't eat my quotes" | grep --line-buffered 'foo|bar'
```

## 🎯 Current State
最近改动：重写了 archive 脚本。
待办：
- [ ] 补 CI
- [x] 发 v0.9



## 🐛 Known Gotchas

### Gotcha #1 — `[build]` grep pattern 以 `-` 开头
- **症状**：`-----BEGIN PRIVATE KEY-----` 永远匹配不到
- **根因**：grep 解析到 `-----` 当 option flags
- **方案**：`grep -E -- "$pattern"`
- **教训**：加 `--` 显式结束选项

## 🧭 Decision Log

### 2026-04-20 — 去 git 化
- **背景**: handoff 是用户级工作记忆
- **选项**: A/B/C
- **选择**: B
- **拒绝 A 的原因**: 多一层条件分支
- **反悔代价**: 低

## 📜 Development Log

### 2026-04-20 10:00 — 首条
**触发**: 用户指出在非 git 仓库报 fatal
**改动**: commands/handoffx.md / commands/handoffx-recall.md
**验证**: bash tests/run_all.sh → green
**关联**: Decision 2026-04-20

---




### 2026-04-10 09:00 — 更早
**触发**: —
**改动**: —
**验证**: —
**关联**: —

---
EOF
# 故意不加锚点，也故意多空行——tidy 必须补锚点 + 压空行，但不能动上面的内容

# 抽取"非空非锚点"行 —— I9 invariant 要求这些必须完全相等
# (hx: block anchors in Current State are structure too, since v4.2.0.)
extract_content() {
    grep -v "^$" "$1" | grep -v "🚨 AI 注意" | grep -v '^<!-- /\{0,1\}hx:'
}

before_content=$(extract_content "$f9")
"$TIDY" "$f9" >/dev/null 2>&1
after_content=$(extract_content "$f9")

if [ "$before_content" = "$after_content" ]; then
    echo "  ✅ I9: tidy 保全所有非空非锚点行（字节级相等）"
    PASS=$((PASS+1))
else
    echo "  ❌ I9 VIOLATED: tidy 篡改了用户内容"
    diff <(printf '%s\n' "$before_content") <(printf '%s\n' "$after_content") | head -20
    FAIL=$((FAIL+1))
fi

# 进一步验证：tidy 确实做了结构工作（不是什么都没动导致 trivially 相等）
if grep -q "🚨 AI 注意" "$f9"; then
    echo "  ✅ I9: 结构工作生效（锚点已补）"
    PASS=$((PASS+1))
else
    echo "  ❌ I9: tidy 未执行结构修复（测试未真正挑战 invariant）"
    FAIL=$((FAIL+1))
fi

# ── Case 11: Diagnose-4 — >50 条 Dev Log 时输出归档建议 ──────────────────────
f10="$TMP_DIR/tidy_c11_many_entries.md"
{
    cat <<'EOF'
# Demo — Project Handoff

## 📦 Project Overview
placeholder.

## 🏗 Architecture
placeholder.

## 🎯 Current State
placeholder.

## 🐛 Known Gotchas
placeholder.

## 📜 Development Log

> 最新在最上面。

---

EOF
    for i in $(seq 60 -1 1); do
        printf "### 2026-01-%02d 10:00 — Entry %d\n\n" "$((i % 28 + 1))" "$i"
        printf "**触发**: mock\n**改动**: file-%d.md\n**验证**: ok\n**关联**: 无\n\n---\n\n" "$i"
    done
    echo '<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->'
} > "$f10"

out11=$("$TIDY" "$f10" 2>&1 || true)
assert_contains "Case 11: >50 条给出归档建议" "$out11" "archive"

# ── Case 12: Duplicate / outside anchors are diagnosed by tidy ───────────────
f12="$TMP_DIR/tidy_bad_anchor_$$.md"
mk_valid "$f12"
cat >> "$f12" <<'EOF'

## Later

<!-- 🚨 AI 注意：outside duplicate -->
EOF
out12=$("$TIDY" "$f12" 2>&1 || true)
ex12=0; "$TIDY" "$f12" >/dev/null 2>&1 || ex12=$?
assert_exit "Case 12: anchor invariant exits 1" 1 "$ex12"
assert_contains "Case 12: reports anchor invariant" "$out12" "anchor must be inside Development Log"

# --- Case 13: anchor placed INSIDE Dev Log when a section follows Dev Log ---
f11="$TMP_DIR/tidy_anchor_pos_$$.md"
cat > "$f11" <<'EOF'
# Demo

## 📦 Project Overview
x

## 🏗 Architecture
x

## 🎯 Current State
x

## 📜 Development Log

### 2026-04-20 10:00 — Entry

**触发**: reason
**改动**: file.md
**验证**: ok
**关联**: 无

---

## 💬 Appendix
This section follows Dev Log.
EOF

# File has NO anchor — tidy must add one INSIDE Dev Log, not after Appendix
"$TIDY" "$f11" >/dev/null 2>&1

# Assertion 13A: anchor appears inside Development Log
anchor_in_log=$(awk '
    /^## 📜 Development Log/ { in_log=1 }
    /^## / && !/Development Log/ && in_log { in_log=0 }
    /🚨 AI 注意/ && in_log { found=1 }
    END { print found+0 }
' "$f11")
if [ "$anchor_in_log" = "1" ]; then
    echo "  ✅ Case 13A: anchor inside Development Log"
    PASS=$((PASS+1))
else
    echo "  ❌ Case 13A: anchor NOT inside Development Log"
    FAIL=$((FAIL+1))
fi

# Assertion 13B: anchor does NOT appear after Appendix section
anchor_after_appendix=$(awk '
    /^## 💬 Appendix/ { in_appendix=1 }
    /🚨 AI 注意/ && in_appendix { found=1 }
    END { print found+0 }
' "$f11")
if [ "$anchor_after_appendix" = "0" ]; then
    echo "  ✅ Case 13B: anchor not after Appendix"
    PASS=$((PASS+1))
else
    echo "  ❌ Case 13B: anchor appears after Appendix"
    FAIL=$((FAIL+1))
fi

# Assertion 13C: idempotent — running tidy again must not change the file
sha_c13_before=$(shasum "$f11" | cut -d' ' -f1)
"$TIDY" "$f11" >/dev/null 2>&1
sha_c13_after=$(shasum "$f11" | cut -d' ' -f1)
assert_exit "Case 13C: idempotent with post-Dev-Log section" "$sha_c13_before" "$sha_c13_after"

# --- Case 14: short-form anchor already present → tidy is a no-op ---
# A file that already contains "🚨 AI 注意" anywhere causes the anchor-insertion
# auto-fix to be skipped (guard: `if ! grep -q "🚨 AI 注意"`). This case verifies
# that a well-formed, full-structure file with a short-form anchor is left
# byte-for-byte unchanged, exits 0, and produces no .bak file.
f14="$TMP_DIR/tidy_c14_shortanchor_$$.md"
cat > "$f14" <<'EOF'
# Demo — Project Handoff

## 📦 Project Overview
placeholder.

## 🏗 Architecture
placeholder.

## 🎯 Current State
<!-- hx:recent -->
placeholder.
<!-- /hx:recent -->

## 🐛 Known Gotchas
placeholder.

## 📜 Development Log

### 2026-04-20 10:00 — Only entry

**触发**: reason
**改动**: file1.md
**验证**: ok
**关联**: 无

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF

sha_c14_before=$(shasum "$f14" | cut -d' ' -f1)
ex14=0; "$TIDY" "$f14" >/dev/null 2>&1 || ex14=$?
sha_c14_after=$(shasum "$f14" | cut -d' ' -f1)

# 14A: byte-identical (no mutation occurred)
if [ "$sha_c14_before" = "$sha_c14_after" ]; then
    echo "  ✅ Case 14A: short-form anchor — file unchanged (byte-identical)"
    PASS=$((PASS+1))
else
    echo "  ❌ Case 14A: short-form anchor — file was mutated unexpectedly"
    FAIL=$((FAIL+1))
fi

# 14B: exit code is 0
assert_exit "Case 14B: short-form anchor — exit code 0" 0 "$ex14"

# 14C: no .bak file was created (auto-fix must not have run)
if [ ! -f "${f14}.bak" ]; then
    echo "  ✅ Case 14C: short-form anchor — no .bak file created"
    PASS=$((PASS+1))
else
    echo "  ❌ Case 14C: short-form anchor — .bak file was created (unexpected auto-fix)"
    FAIL=$((FAIL+1))
fi


# ── Case 15 (C1): v2 layout gate — v1 detection + migration trigger ────────
# Disable the bypass for these cases so we exercise the real gate.
unset HANDOFF_TIDY_SKIP_V2_GATE

# 15a: non-interactive run on a v1 file with no auto-migrate env →
#      tidy MUST NOT migrate silently; must warn and exit 0 leaving file untouched.
SANDBOX15a=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX15a/${HX_LEGACY_MAIN_FILE}"
sha_15a_before=$(shasum "$SANDBOX15a/${HX_LEGACY_MAIN_FILE}" | cut -d' ' -f1)
out_15a=$("$TIDY" "$SANDBOX15a/${HX_LEGACY_MAIN_FILE}" </dev/null 2>&1)
ec_15a=$?
sha_15a_after=$(shasum "$SANDBOX15a/${HX_LEGACY_MAIN_FILE}" | cut -d' ' -f1)

assert_exit "Case 15a: non-interactive v1 → exit 0 (skip)" 0 "$ec_15a"
assert_contains "Case 15a: warns about v1 layout" "$out_15a" "v1 layout detected"
assert_contains "Case 15a: hints HANDOFF_TIDY_AUTO_MIGRATE" "$out_15a" "HANDOFF_TIDY_AUTO_MIGRATE"
if [ "$sha_15a_before" = "$sha_15a_after" ]; then
    echo "  ✅ Case 15a: ${HX_LEGACY_MAIN_FILE} untouched on skip"; PASS=$((PASS+1))
else
    echo "  ❌ Case 15a: ${HX_LEGACY_MAIN_FILE} was mutated"; FAIL=$((FAIL+1))
fi
[ ! -d "$SANDBOX15a/${HX_LOGS_DIR}" ] && [ ! -d "$SANDBOX15a/${HX_LOGS_DIR}.partial" ] && { echo "  ✅ Case 15a: no ${HX_LOGS_DIR} created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15a: ${HX_LOGS_DIR} leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15a"

# 15b: HANDOFF_TIDY_AUTO_MIGRATE=1 → tidy invokes migrate-to-v2.sh --apply,
#      file gains v2 marker, sibling dirs/files appear.
SANDBOX15b=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX15b/${HX_LEGACY_MAIN_FILE}"
HANDOFF_TIDY_AUTO_MIGRATE=1 "$TIDY" "$SANDBOX15b/${HX_LEGACY_MAIN_FILE}" </dev/null >/dev/null 2>&1
ec_15b=$?

assert_exit "Case 15b: AUTO_MIGRATE=1 → exit 0" 0 "$ec_15b"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX15b/${HX_MAIN_FILE}" && { echo "  ✅ Case 15b: v2 marker added"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: marker missing"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX15b/${HX_LOGS_DIR}" ] && { echo "  ✅ Case 15b: ${HX_LOGS_DIR}/ created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: ${HX_LOGS_DIR} missing"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX15b/${HX_DEC_DIR}" ] && { echo "  ✅ Case 15b: ${HX_DEC_DIR}/ created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: ${HX_DEC_DIR} missing"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX15b/${HX_GOTCHAS_FILE}" ] && { echo "  ✅ Case 15b: ${HX_GOTCHAS_FILE} created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: ${HX_GOTCHAS_FILE} missing"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15b"

# ── Case 16 (C2): tidy renumbers duplicate ${HX_LOGS_DIR}/ entries ──────────
# Simulates Syncthing race: two machines independently created `0001-...md`.
SANDBOX16=$(mktemp -d)
cat > "$SANDBOX16/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test
## 🏗 Architecture
test
## 🎯 Current State
test
## 📜 Development Log

> pointer

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
mkdir -p "$SANDBOX16/${HX_LOGS_DIR}"
echo "first 0001"  > "$SANDBOX16/${HX_LOGS_DIR}/0001-2026-05-01T1000-first.md"
echo "race 0001"   > "$SANDBOX16/${HX_LOGS_DIR}/0001-2026-05-01T1100-race.md"
echo "second 0002" > "$SANDBOX16/${HX_LOGS_DIR}/0002-2026-05-02T1000-second.md"

"$TIDY" "$SANDBOX16/${HX_MAIN_FILE}" </dev/null >/dev/null 2>&1

n_files=$(ls "$SANDBOX16/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16: 3 files preserved" "$n_files" "3"

n_unique=$(ls "$SANDBOX16/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16: 3 unique numbers (no dupes left)" "$n_unique" "3"

n_0003=$(ls "$SANDBOX16/${HX_LOGS_DIR}/"0003-*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16: 0003 created (duplicate bumped)" "$n_0003" "1"

# Original 0001 file (first by sort) keeps its number
[ -f "$SANDBOX16/${HX_LOGS_DIR}/0001-2026-05-01T1000-first.md" ] && { echo "  ✅ Case 16: first-by-sort 0001 retained"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: 0001-first.md missing"; FAIL=$((FAIL+1)); }
# Original 0002 untouched
[ -f "$SANDBOX16/${HX_LOGS_DIR}/0002-2026-05-02T1000-second.md" ] && { echo "  ✅ Case 16: 0002 untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: 0002 disturbed"; FAIL=$((FAIL+1)); }

# Renamed file's content is preserved (mv, not rewrite)
race_file=$(ls "$SANDBOX16/${HX_LOGS_DIR}/"0003-*-race.md 2>/dev/null)
[ -n "$race_file" ] && grep -q "^race 0001$" "$race_file" && { echo "  ✅ Case 16: renamed file content intact"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: race file content lost"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX16"

# Case 16-triple (Codex review #2): three files sharing the same NNNN must
# all be reduced to unique numbers. Earlier `prev_num` chain was broken — once
# the second file got renamed to e.g. 0003, prev_num became 0003, and the
# third still-0001 file no longer compared equal, so it was left as a dupe.
SANDBOX16t=$(mktemp -d)
cat > "$SANDBOX16t/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test
## 🏗 Architecture
test
## 🎯 Current State
test
## 📜 Development Log

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
mkdir -p "$SANDBOX16t/${HX_LOGS_DIR}"
echo "a" > "$SANDBOX16t/${HX_LOGS_DIR}/0001-2026-05-01T1000-a.md"
echo "b" > "$SANDBOX16t/${HX_LOGS_DIR}/0001-2026-05-01T1100-b.md"
echo "c" > "$SANDBOX16t/${HX_LOGS_DIR}/0001-2026-05-01T1200-c.md"
echo "d" > "$SANDBOX16t/${HX_LOGS_DIR}/0002-2026-05-02T1000-d.md"

"$TIDY" "$SANDBOX16t/${HX_MAIN_FILE}" </dev/null >/dev/null 2>&1

n_files=$(ls "$SANDBOX16t/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16-triple: all 4 files preserved" "$n_files" "4"

n_unique=$(ls "$SANDBOX16t/${HX_LOGS_DIR}/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16-triple: 4 unique numbers (no dupes left)" "$n_unique" "4"

# First-by-sort 0001-A keeps its number; B and C get renumbered (to 0003, 0004 typically)
[ -f "$SANDBOX16t/${HX_LOGS_DIR}/0001-2026-05-01T1000-a.md" ] && { echo "  ✅ Case 16-triple: first-by-sort 0001 retained"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16-triple: 0001-a was disturbed"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX16t/${HX_LOGS_DIR}/0002-2026-05-02T1000-d.md" ] && { echo "  ✅ Case 16-triple: 0002 untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16-triple: 0002 disturbed"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX16t"

# Case 16b: dups in ${HX_DEC_DIR}/ also renumbered
SANDBOX16b=$(mktemp -d)
cat > "$SANDBOX16b/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test
## 🏗 Architecture
test
## 🎯 Current State
test
## 📜 Development Log

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
mkdir -p "$SANDBOX16b/${HX_DEC_DIR}"
echo "dec1" > "$SANDBOX16b/${HX_DEC_DIR}/0001-2026-05-01-first.md"
echo "dec1-dup" > "$SANDBOX16b/${HX_DEC_DIR}/0001-2026-05-02-dup.md"
"$TIDY" "$SANDBOX16b/${HX_MAIN_FILE}" </dev/null >/dev/null 2>&1
n_unique=$(ls "$SANDBOX16b/${HX_DEC_DIR}/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16b: ${HX_DEC_DIR}/ dups renumbered" "$n_unique" "2"
rm -rf "$SANDBOX16b"

# Case 16c: clean v2 layout (no dups) — tidy must NOT touch existing files
SANDBOX16c=$(mktemp -d)
cat > "$SANDBOX16c/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test
## 🏗 Architecture
test
## 🎯 Current State
test
## 📜 Development Log

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
mkdir -p "$SANDBOX16c/${HX_LOGS_DIR}"
echo "a" > "$SANDBOX16c/${HX_LOGS_DIR}/0001-2026-05-01T1000-a.md"
echo "b" > "$SANDBOX16c/${HX_LOGS_DIR}/0002-2026-05-02T1000-b.md"
sha_before=$(shasum "$SANDBOX16c/${HX_LOGS_DIR}/0001-2026-05-01T1000-a.md" "$SANDBOX16c/${HX_LOGS_DIR}/0002-2026-05-02T1000-b.md" | sort)
"$TIDY" "$SANDBOX16c/${HX_MAIN_FILE}" </dev/null >/dev/null 2>&1
sha_after=$(shasum "$SANDBOX16c/${HX_LOGS_DIR}/0001-2026-05-01T1000-a.md" "$SANDBOX16c/${HX_LOGS_DIR}/0002-2026-05-02T1000-b.md" | sort)
[ "$sha_before" = "$sha_after" ] && { echo "  ✅ Case 16c: no-dup layout left untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16c: clean layout was disturbed"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX16c"

# 15c: v2-marker file passes the gate (regression — gate must not interfere with v2 layouts).
SANDBOX15c=$(mktemp -d)
cat > "$SANDBOX15c/${HX_MAIN_FILE}" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test

## 🏗 Architecture
test

## 🎯 Current State
test

## 📜 Development Log

> pointer block — entries live in the logs dir

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ec_15c=0; "$TIDY" "$SANDBOX15c/${HX_MAIN_FILE}" </dev/null >/dev/null 2>&1 || ec_15c=$?
# Exit code may be 0 (clean) or 1 (findings about other RECOMMENDED sections).
# What matters is that gate did NOT trigger migration.
[ ! -d "$SANDBOX15c/${HX_LOGS_DIR}.partial" ] && { echo "  ✅ Case 15c: v2 file did not trigger migration"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15c: gate erroneously triggered on v2"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX15c/${HX_LEGACY_MAIN_FILE}.pre-v2-backup" ] && { echo "  ✅ Case 15c: no backup file (no migration)"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15c: migration ran on v2 file"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15c"

# ── Case 17 (v2.1.0 UX #2): --apply CLI flag replaces hidden ENV var ────────
# UX: HANDOFF_TIDY_AUTO_MIGRATE is hidden + undocumented to a CLI-first user;
# --apply is industry convention (git/npm/brew --yes/--force). Flag must work
# in any position; ENV var must keep working for backward compat.

# 17a: --apply (flag before file path) → migration triggered
SANDBOX17a=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX17a/${HX_LEGACY_MAIN_FILE}"
"$TIDY" --apply "$SANDBOX17a/${HX_LEGACY_MAIN_FILE}" </dev/null >/dev/null 2>&1
ec_17a=$?
assert_exit "Case 17a: --apply before file → exit 0" 0 "$ec_17a"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX17a/${HX_MAIN_FILE}" && { echo "  ✅ Case 17a: v2 marker added via --apply"; PASS=$((PASS+1)); } || { echo "  ❌ Case 17a: --apply did not migrate"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX17a"

# 17b: file path before --apply (positional flexibility, GNU-style)
SANDBOX17b=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX17b/${HX_LEGACY_MAIN_FILE}"
"$TIDY" "$SANDBOX17b/${HX_LEGACY_MAIN_FILE}" --apply </dev/null >/dev/null 2>&1
ec_17b=$?
assert_exit "Case 17b: file then --apply → exit 0" 0 "$ec_17b"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX17b/${HX_MAIN_FILE}" && { echo "  ✅ Case 17b: positional --apply works"; PASS=$((PASS+1)); } || { echo "  ❌ Case 17b: positional --apply failed"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX17b"

# 17c: non-interactive warning must mention --apply (CLI-first discoverability)
SANDBOX17c=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX17c/${HX_LEGACY_MAIN_FILE}"
out_17c=$("$TIDY" "$SANDBOX17c/${HX_LEGACY_MAIN_FILE}" </dev/null 2>&1)
assert_contains "Case 17c: warning mentions --apply CLI flag" "$out_17c" "--apply"
rm -rf "$SANDBOX17c"

# 17d: --apply + ENV var together → no conflict (backward compat preserved)
SANDBOX17d=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX17d/${HX_LEGACY_MAIN_FILE}"
HANDOFF_TIDY_AUTO_MIGRATE=1 "$TIDY" --apply "$SANDBOX17d/${HX_LEGACY_MAIN_FILE}" </dev/null >/dev/null 2>&1
ec_17d=$?
assert_exit "Case 17d: --apply + ENV together → exit 0 (no conflict)" 0 "$ec_17d"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX17d/${HX_MAIN_FILE}" && { echo "  ✅ Case 17d: combined flag+env works"; PASS=$((PASS+1)); } || { echo "  ❌ Case 17d: combined failed"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX17d"

# 17e: -h / --help output documents --apply (self-documenting)
out_17e=$("$TIDY" -h 2>&1)
assert_contains "Case 17e: -h mentions --apply" "$out_17e" "--apply"

# ── Case 18 (P2.4 §4b-1/4): legacy-layout guard ────────────────────────────
# After the v4 rename the default file is the new main; a project still on a
# legacy layout must get the exact upgrade command and exit 2 — never be
# treated as "no main file" or tidied half-way.
# 18a: v3 legacy four-piece (no new main) → schema-upgrade
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
ec=0; out=$(cd "$LG" && "$TIDY" </dev/null 2>&1) || ec=$?
assert_exit "Case 18a: v3 legacy tree, default file → exit 2" 2 "$ec"
assert_contains "Case 18a: names the schema-upgrade command" "$out" "/handoffx-tidy schema-upgrade"
assert_contains "Case 18a: names the script form" "$out" "tidy-handoff.sh schema-upgrade --dry-run|--apply"
# 18a': explicit legacy main of a v3 tree is refused the same way
ec=0; out=$("$TIDY" "$LG/$HX_LEGACY_MAIN_FILE" </dev/null 2>&1) || ec=$?
assert_exit "Case 18a': v3 legacy main passed explicitly → exit 2" 2 "$ec"
assert_contains "Case 18a': names the schema-upgrade command" "$out" "/handoffx-tidy schema-upgrade"
rm -rf "$LG"
# 18b: v1 single legacy file (inline dated entries) → migrate-to-v2
LG=$(mktemp -d); cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$LG/$HX_LEGACY_MAIN_FILE"
ec=0; out=$(cd "$LG" && "$TIDY" </dev/null 2>&1) || ec=$?
assert_exit "Case 18b: v1 legacy file, default file → exit 2" 2 "$ec"
assert_contains "Case 18b: names migrate-to-v2 dry-run" "$out" "migrate-to-v2.sh --dry-run"
assert_contains "Case 18b: names migrate-to-v2 apply" "$out" "migrate-to-v2.sh --apply"
assert_not_contains "Case 18b: v1 hint is not the schema-upgrade one" "$out" "schema-upgrade"
cmp -s "$LG/$HX_LEGACY_MAIN_FILE" "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" && [ ! -e "$LG/$HX_MAIN_FILE" ] \
    && { echo "  ✅ Case 18b: nothing written"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Case 18b: tree changed"; FAIL=$((FAIL+1)); }
rm -rf "$LG"
# 18c: mixed — legacy and new pieces together → refused, both sets named
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
mkdir -p "$LG/$HX_LOGS_DIR"; mk_valid "$LG/$HX_MAIN_FILE"
ec=0; out=$("$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || ec=$?
assert_exit "Case 18c: mixed legacy+new → exit 2" 2 "$ec"
assert_contains "Case 18c: names the mixed state" "$out" "mixed layout"
assert_contains "Case 18c: names a legacy piece" "$out" "$HX_LEGACY_LOGS_DIR"
assert_contains "Case 18c: names a new piece" "$out" "$HX_LOGS_DIR"
rm -rf "$LG"

# Case 19 (fix wave 2, opus I1): an entry-less v1 file is v1 by elimination
# (F1). tidy's own v1 gate used to require dated entries, so the printed
# fallback `tidy-handoff.sh --apply <legacy main>` returned 0 and tidied the
# legacy file as if it were current — the loop F1 removed, reopened here.
# The tidy contract: --apply on a v1 file runs migrate-to-v2.
LG=$(mktemp -d)
printf '# Project\n\n## 📦 Project Overview\nnew\n\n## 🎯 Current State\nstart\n' > "$LG/$HX_LEGACY_MAIN_FILE"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" 2>&1) || rc=$?
assert_exit "Case 19: default tidy on an entry-less v1 root → exit 2" 2 "$rc"
assert_contains "Case 19: refusal names the tidy --apply fallback" "$out" "tidy-handoff.sh --apply $LG/$HX_LEGACY_MAIN_FILE"
rc=0; out=$(bash "$TIDY" --apply "$LG/$HX_LEGACY_MAIN_FILE" 2>&1) || rc=$?
assert_exit "Case 19: following the printed fallback → exit 0" 0 "$rc"
{ [ -f "$LG/$HX_MAIN_FILE" ] && [ -d "$LG/$HX_LOGS_DIR" ] && [ -d "$LG/$HX_DEC_DIR" ] && [ ! -e "$LG/$HX_LEGACY_MAIN_FILE" ]; } \
    && { echo "  ✅ Case 19: the fallback really migrated (new main + dirs, legacy main retired)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Case 19: --apply returned without migrating"; FAIL=$((FAIL+1)); }
rm -rf "$LG"

# Case 20 (v4.2.0 Task 4): acquire_next_number now fails closed when the lock
# cannot be taken; renumbering must then stop, not mv the dup to "-<rest>"
# (an empty number), which drops it out of every [0-9]* scan. A fake flock
# first on PATH drives the flock branch on macOS too.
LG=$(mktemp -d) || { echo "  ❌ Case 20: mktemp -d failed"; exit 1; }
mkdir -p "$LG/bin-fail" "$LG/bin-ok" "$LG/p/$HX_LOGS_DIR"
printf '#!/bin/sh\nexit 1\n' > "$LG/bin-fail/flock"; printf '#!/bin/sh\nexit 0\n' > "$LG/bin-ok/flock"
chmod +x "$LG/bin-fail/flock" "$LG/bin-ok/flock"
printf '<!-- HANDOFF v2 schema -->\n# Demo\n\n## 📜 Development Log\n' > "$LG/p/$HX_MAIN_FILE"
echo a > "$LG/p/$HX_LOGS_DIR/0001-a.md"; echo b > "$LG/p/$HX_LOGS_DIR/0001-b.md"
before=$(ls "$LG/p/$HX_LOGS_DIR")
cp "$LG/p/$HX_MAIN_FILE" "$LG/main.orig"
rc=0; out=$(PATH="$LG/bin-fail:$PATH" bash "$TIDY" "$LG/p/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 20: no safe number → tidy exits 1" 1 "$rc"
assert_contains "Case 20: says it cannot renumber" "$out" "cannot renumber"
# rc 1 alone proves nothing: a tidy that goes on also exits 1 on this
# minimal main file. Stopping means no later step ran at all.
assert_not_contains "Case 20: tidy stopped before its later steps (no summary)" "$out" "tidy summary"
assert_exit "Case 20: main file untouched" 0 "$(cmp -s "$LG/p/$HX_MAIN_FILE" "$LG/main.orig" && echo 0 || echo 1)"
assert_exit "Case 20: no .bak written" 0 "$([ ! -e "$LG/p/$HX_MAIN_FILE.bak" ] && echo 0 || echo 1)"
assert_exit "Case 20: both duplicate names left as they were" 0 "$([ "$(ls "$LG/p/$HX_LOGS_DIR")" = "$before" ] && echo 0 || echo 1)"
rc=0; PATH="$LG/bin-ok:$PATH" bash "$TIDY" "$LG/p/$HX_MAIN_FILE" </dev/null >/dev/null 2>&1 || rc=$?
assert_exit "Case 20: fake flock rc 0 → the dup is renumbered (fake is the one used)" 0 \
    "$([ -f "$LG/p/$HX_LOGS_DIR/0001-a.md" ] && [ -f "$LG/p/$HX_LOGS_DIR/0002-b.md" ] && echo 0 || echo 1)"
rm -rf "$LG"

# Case 21 (v4.2.0 Task 5): tidy wraps an anchor-less Current State in hx:
# blocks so `hx.sh block set` can replace it — structure only, content
# untouched, idempotent. Fixture mirrors this repo's own main file.
LG=$(mktemp -d) || { echo "  ❌ Case 21: mktemp -d failed"; exit 1; }
cat > "$LG/$HX_MAIN_FILE" <<'EOF'
# Demo

## 🎯 Current State

> `/handoffx` 会自动更新此章节。

**日期**：2026-11-02 18:12 -0700
**最近改动**：did a thing
**验证状态**：✅ green

### 最近完成

- 0082 shipped
- 0081 cut

### 待办（pending）

- [ ] next step

**group**：
- [ ] another

### 其它

free text

---

## 📜 Development Log

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
cp "$LG/$HX_MAIN_FILE" "$LG/orig.md"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_contains "Case 21: one line names the three blocks" "$out" "补锚点: Current State → hx:recent, hx:done, hx:pending"
F21="$LG/$HX_MAIN_FILE"
# line_of <exact line> — first line number, or 0
line_of() { awk -v t="$1" '$0 == t {print NR; f=1; exit} END{if(!f) print 0}' "$F21"; }
for b in recent "done" pending; do
    assert_exit "Case 21: hx:$b start anchor once" 1 "$(grep -cx "<!-- hx:$b -->" "$F21")"
    assert_exit "Case 21: hx:$b end anchor once" 1 "$(grep -cx "<!-- /hx:$b -->" "$F21")"
done
in_block() {  # in_block <name> <exact line> → 0 when the line sits inside the block
    local s e l; s=$(line_of "<!-- hx:$1 -->"); e=$(line_of "<!-- /hx:$1 -->"); l=$(line_of "$2")
    [ "$s" -gt 0 ] && [ "$l" -gt "$s" ] && [ "$l" -lt "$e" ] && echo 0 || echo 1
}
assert_exit "Case 21: hx:recent holds the date line" 0 "$(in_block recent '**日期**：2026-11-02 18:12 -0700')"
assert_exit "Case 21: hx:recent holds the verify line" 0 "$(in_block recent '**验证状态**：✅ green')"
assert_exit "Case 21: hx:done holds 最近完成 and its list" 0 \
    "$([ "$(in_block "done" '### 最近完成')$(in_block "done" '- 0081 cut')" = 00 ] && echo 0 || echo 1)"
assert_exit "Case 21: hx:pending holds 待办 and its items" 0 \
    "$([ "$(in_block pending '### 待办（pending）')$(in_block pending '- [ ] another')" = 00 ] && echo 0 || echo 1)"
n=0
for b in recent "done" pending; do
    [ "$(in_block "$b" '### 其它')" = 0 ] && n=$((n+1))
    [ "$(in_block "$b" 'free text')" = 0 ] && n=$((n+1))
done
assert_exit "Case 21: ### 其它 stays outside every block" 0 "$n"
# shellcheck disable=SC2016  # literal backticks in the quoted line
assert_exit "Case 21: quote line comes before hx:recent" 0 \
    "$([ "$(line_of '> `/handoffx` 会自动更新此章节。')" -lt "$(line_of '<!-- hx:recent -->')" ] && echo 0 || echo 1)"
grep -v '<!-- .\?hx:' "$F21" > "$LG/stripped.md"
assert_exit "Case 21: only anchor lines added (strip → identical)" 0 "$(cmp -s "$LG/stripped.md" "$LG/orig.md" && echo 0 || echo 1)"
cp "$F21" "$LG/once.md"
rc=0; out=$(bash "$TIDY" "$F21" </dev/null 2>&1) || rc=$?
assert_not_contains "Case 21: second run adds nothing" "$out" "补锚点"
assert_exit "Case 21: second run leaves the file identical" 0 "$(cmp -s "$F21" "$LG/once.md" && echo 0 || echo 1)"
# The template already carries the anchors: tidy must not touch it.
mkdir -p "$LG/tpl"; cp "$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md" "$LG/tpl/$HX_MAIN_FILE"
rc=0; out=$(bash "$TIDY" "$LG/tpl/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_not_contains "Case 21: template → no 补锚点" "$out" "补锚点"
assert_exit "Case 21: template unchanged by tidy" 0 \
    "$(cmp -s "$LG/tpl/$HX_MAIN_FILE" "$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md" && echo 0 || echo 1)"
rm -rf "$LG"

# Case 22 (Task 5 fix round 1): "already anchored" means an anchor LINE —
# start or end — not the text `<!-- hx:` quoted mid-line.
LG=$(mktemp -d) || { echo "  ❌ Case 22: mktemp -d failed"; exit 1; }
printf '# Demo\n\n## 🎯 Current State\n\n**最近改动**：wrote about `<!-- hx:recent -->` anchors\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/mid.md"
rc=0; out=$(bash "$TIDY" "$LG/mid.md" </dev/null 2>&1) || rc=$?
assert_contains "Case 22: mid-line mention of <!-- hx: still gets anchors" "$out" "补锚点: Current State → hx:recent"
assert_exit "Case 22: mid-line mention → start anchor line added" 1 "$(grep -cx '<!-- hx:recent -->' "$LG/mid.md")"
printf '# Demo\n\n## 🎯 Current State\n\n**最近改动**：x\n<!-- /hx:x -->\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/lone.md"
cp "$LG/lone.md" "$LG/lone.orig"
rc=0; out=$(bash "$TIDY" "$LG/lone.md" </dev/null 2>&1) || rc=$?
assert_not_contains "Case 22: lone end anchor → no 补锚点" "$out" "补锚点"
assert_exit "Case 22: lone end anchor → file unchanged" 0 "$(cmp -s "$LG/lone.md" "$LG/lone.orig" && echo 0 || echo 1)"
rm -rf "$LG"

# Case 23 (v4.2.0 Task 7): tidy rewrites frontmatter `date: …THHMM` to THH:MM
# and nothing else; per-file atomic write, failures counted and fatal.
LINT="$SCRIPTS_DIR/handoff-lint.sh"
mk_dl_root() {  # mk_dl_root <dir> — v2 skeleton: main file + logs/decisions/gotchas
    mkdir -p "$1/$HX_LOGS_DIR" "$1/$HX_DEC_DIR"
    printf '<!-- HANDOFF v2 schema -->\n# Demo\n\n## 📦 Project Overview\nx\n## 🏗 Architecture\nx\n## 🎯 Current State\nx\n## 📜 Development Log\n\n<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->\n' > "$1/$HX_MAIN_FILE"
    echo "# Known Gotchas" > "$1/$HX_GOTCHAS_FILE"
}
mk_dl() {  # mk_dl <path> <number> <date value> [body line]
    printf -- '---\nschema: 2\ntype: dev-log\ndate: %s\nnumber: %s\ntitle: t\n---\n\n### 2026-05-01 21:44 — t\n\n**触发**: a\n**改动**: b\n**验证**: c\n**关联**: 无\n%s\n' "$3" "$2" "${4:-}" > "$1"
}
LG=$(mktemp -d) || { echo "  ❌ Case 23: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"
L="$LG/$HX_LOGS_DIR"
mk_dl "$L/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144 "body keeps T2144 here"
mk_dl "$L/0002-2026-05-02T2144-b.md" 0002 2026-05-02T21:44
mk_dl "$L/0003-2026-05-03T2144-c.md" 0003 2026-05-03T214
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-11-02\nnumber: 0001\ntitle: d\n---\n\n### 2026-11-02 — d\n' > "$LG/$HX_DEC_DIR/0001-2026-11-02-d.md"
cp "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig"; cp "$L/0003-2026-05-03T2144-c.md" "$LG/c.orig"
cp "$LG/$HX_DEC_DIR/0001-2026-11-02-d.md" "$LG/d.orig"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_contains "Case 23: T2144 file reported" "$out" "规整日期: $L/0001-2026-05-01T2144-a.md T2144 → T21:44"
assert_exit "Case 23: exactly one detail line" 1 "$(printf '%s\n' "$out" | grep -c '^规整日期: ')"
assert_contains "Case 23: summary 1/1/0" "$out" "规整日期汇总: 候选 1 / 成功 1 / 失败 0"
assert_exit "Case 23: frontmatter date rewritten" 1 "$(grep -c '^date: 2026-05-01T21:44$' "$L/0001-2026-05-01T2144-a.md")"
assert_exit "Case 23: body T2144 untouched" 1 "$(grep -c '^body keeps T2144 here$' "$L/0001-2026-05-01T2144-a.md")"
assert_exit "Case 23: already-correct T21:44 file identical" 0 "$(cmp -s "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig" && echo 0 || echo 1)"
assert_exit "Case 23: malformed T214 file identical" 0 "$(cmp -s "$L/0003-2026-05-03T2144-c.md" "$LG/c.orig" && echo 0 || echo 1)"
assert_exit "Case 23: Decision file identical" 0 "$(cmp -s "$LG/$HX_DEC_DIR/0001-2026-11-02-d.md" "$LG/d.orig" && echo 0 || echo 1)"
assert_exit "Case 23: clean fixture tidy rc 0" 0 "$rc"
cp "$L/0001-2026-05-01T2144-a.md" "$LG/a.once"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_not_contains "Case 23: second run prints no 规整日期" "$out" "规整日期"
assert_exit "Case 23: second run leaves the file identical" 0 "$(cmp -s "$L/0001-2026-05-01T2144-a.md" "$LG/a.once" && echo 0 || echo 1)"
rm -rf "$LG"

# Case 23b: lint exits 0 on a layout whose only problem was the date form.
LG=$(mktemp -d) || { echo "  ❌ Case 23b: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; mk_dl "$LG/$HX_LOGS_DIR/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144
rc=0; bash "$LINT" "$LG/$HX_MAIN_FILE" >/dev/null 2>&1 || rc=$?
assert_exit "Case 23b: lint rejects THHMM before tidy" 1 "$rc"
bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null >/dev/null 2>&1
rc=0; bash "$LINT" "$LG/$HX_MAIN_FILE" >/dev/null 2>&1 || rc=$?
assert_exit "Case 23b: lint exits 0 after tidy" 0 "$rc"
rm -rf "$LG"

# Case 23c: injected failure on the second candidate (HANDOFFX_TEST_TIDY_FAIL_AT).
LG=$(mktemp -d) || { echo "  ❌ Case 23c: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
mk_dl "$L/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144
mk_dl "$L/0002-2026-05-02T2144-b.md" 0002 2026-05-02T2144
cp "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig"
rc=0; out=$(HANDOFFX_TEST_TIDY_FAIL_AT=0002-2026-05-02T2144-b.md bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 23c: failed rewrite → tidy exit 1" 1 "$rc"
assert_contains "Case 23c: failure line" "$out" "规整日期失败"
assert_contains "Case 23c: summary 2/1/1" "$out" "规整日期汇总: 候选 2 / 成功 1 / 失败 1"
assert_exit "Case 23c: first file rewritten" 1 "$(grep -c '^date: 2026-05-01T21:44$' "$L/0001-2026-05-01T2144-a.md")"
assert_exit "Case 23c: second file original" 0 "$(cmp -s "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig" && echo 0 || echo 1)"
# ls -A: the rewrite temp file is a dot file (.tidy-date.*) that plain ls hides.
assert_exit "Case 23c: no temp file left behind" 2 "$(ls -A "$L" | wc -l | tr -d ' ')"
rm -rf "$LG"

# Case 23d: unwritable logs dir (candidate files created BEFORE the chmod).
if [ "${EUID:-$(id -u)}" = "0" ]; then
    echo "  ➖ Case 23d: running as root, chmod 555 cannot block writes — skipped"
else
    LG=$(mktemp -d) || { echo "  ❌ Case 23d: mktemp -d failed"; exit 1; }
    mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
    mk_dl "$L/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144
    mk_dl "$L/0002-2026-05-02T2144-b.md" 0002 2026-05-02T2144
    cp "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig"; cp "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig"
    chmod 555 "$L"
    rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
    chmod 755 "$L"
    assert_exit "Case 23d: read-only logs dir → tidy exit 1" 1 "$rc"
    assert_contains "Case 23d: summary 2/0/2" "$out" "规整日期汇总: 候选 2 / 成功 0 / 失败 2"
    assert_exit "Case 23d: first file original" 0 "$(cmp -s "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig" && echo 0 || echo 1)"
    assert_exit "Case 23d: second file original" 0 "$(cmp -s "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig" && echo 0 || echo 1)"
    rm -rf "$LG"
fi

# Case 23e (fix round 1): frontmatter must start on line 1 AND close; a file
# the scan cannot read or parse is a failure, never a clean skip.
LG=$(mktemp -d) || { echo "  ❌ Case 23e: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
printf 'intro\n---\ndate: 2026-05-01T2144\nnumber: 0001\n---\nbody\n' > "$L/0001-2026-05-01T2144-a.md"
printf -- '---\ndate: 2026-05-02T2144\nnumber: 0002\nbody never closes\n' > "$L/0002-2026-05-02T2144-b.md"
cp "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig"; cp "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 23e: no-line-1 / unclosed files → tidy rc 0" 0 "$rc"
assert_not_contains "Case 23e: not counted as candidates" "$out" "规整日期"
assert_exit "Case 23e: first line not --- → file identical" 0 "$(cmp -s "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig" && echo 0 || echo 1)"
assert_exit "Case 23e: unclosed frontmatter → file identical" 0 "$(cmp -s "$L/0002-2026-05-02T2144-b.md" "$LG/b.orig" && echo 0 || echo 1)"
rm -rf "$LG"

# Case 23f: CRLF candidate is reported as a failure and left byte-identical.
LG=$(mktemp -d) || { echo "  ❌ Case 23f: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
printf -- '---\r\ndate: 2026-05-01T2144\r\nnumber: 0001\r\n---\r\nbody\r\n' > "$L/0001-2026-05-01T2144-a.md"
cp "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 23f: CRLF candidate → tidy exit 1" 1 "$rc"
assert_contains "Case 23f: CRLF failure line" "$out" "CRLF 行尾，不处理"
assert_contains "Case 23f: summary 1/0/1" "$out" "规整日期汇总: 候选 1 / 成功 0 / 失败 1"
assert_exit "Case 23f: CRLF file identical" 0 "$(cmp -s "$L/0001-2026-05-01T2144-a.md" "$LG/a.orig" && echo 0 || echo 1)"
rm -rf "$LG"

# Case 23g: an unreadable file is a scan failure, not "no candidate".
if [ "${EUID:-$(id -u)}" = "0" ]; then
    echo "  ➖ Case 23g: running as root, chmod 000 cannot block reads — skipped"
else
    LG=$(mktemp -d) || { echo "  ❌ Case 23g: mktemp -d failed"; exit 1; }
    mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
    mk_dl "$L/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144
    chmod 000 "$L/0001-2026-05-01T2144-a.md"
    rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
    chmod 644 "$L/0001-2026-05-01T2144-a.md"
    assert_exit "Case 23g: unreadable candidate → tidy exit 1" 1 "$rc"
    assert_contains "Case 23g: scan failure line" "$out" "规整日期扫描失败"
    assert_contains "Case 23g: summary 1/0/1" "$out" "规整日期汇总: 候选 1 / 成功 0 / 失败 1"
    rm -rf "$LG"
fi

# Case 24a (final I3): three states of the logs dir — missing (skipped), empty
# (0 candidates), unreadable (❌, exit 1). An unreadable dir used to glob to
# nothing and end in ✅.
LG=$(mktemp -d) || { echo "  ❌ Case 24a: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 24a: empty logs dir → tidy rc 0" 0 "$rc"
assert_not_contains "Case 24a: empty logs dir → no 规整日期 line" "$out" "规整日期"
rmdir "$L"
rc=0; out=$(HANDOFF_TIDY_SKIP_V2_GATE=1 bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_not_contains "Case 24a: missing logs dir → skipped, no 规整日期 line" "$out" "规整日期"
mkdir "$L"
if [ "${EUID:-$(id -u)}" = "0" ]; then
    echo "  ➖ Case 24a: running as root, chmod 000 cannot block reads — skipped"
else
    mk_dl "$L/0001-2026-05-01T2144-a.md" 0001 2026-05-01T2144
    chmod 000 "$L"
    rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
    chmod 755 "$L"
    assert_exit "Case 24a: unreadable logs dir → tidy exit 1" 1 "$rc"
    assert_contains "Case 24a: unreadable logs dir → named" "$out" "❌ 规整日期: 日志目录不可读: "
    assert_not_contains "Case 24a: unreadable logs dir → no ✅" "$out" "✅"
    assert_exit "Case 24a: candidate untouched" 1 "$(grep -c '^date: 2026-05-01T2144$' "$L/0001-2026-05-01T2144-a.md")"
fi
rm -rf "$LG"

# Case 24b (final C3): a symlinked candidate is neither read nor written — mv
# would replace the link with a regular file.
LG=$(mktemp -d) || { echo "  ❌ Case 24b: mktemp -d failed"; exit 1; }
mk_dl_root "$LG"; L="$LG/$HX_LOGS_DIR"
mk_dl "$LG/target.md" 0001 2026-05-01T2144
cp "$LG/target.md" "$LG/target.orig"
ln -s ../target.md "$L/0001-2026-05-01T2144-a.md"
rc=0; out=$(bash "$TIDY" "$LG/$HX_MAIN_FILE" </dev/null 2>&1) || rc=$?
assert_exit "Case 24b: symlinked candidate → tidy exit 1" 1 "$rc"
assert_contains "Case 24b: symlink failure line" "$out" "（符号链接，不处理）"
assert_exit "Case 24b: link is still a link" 0 "$([ -L "$L/0001-2026-05-01T2144-a.md" ] && echo 0 || echo 1)"
assert_exit "Case 24b: link target byte-identical" 0 "$(cmp -s "$LG/target.md" "$LG/target.orig" && echo 0 || echo 1)"
assert_not_contains "Case 24b: no ✅" "$out" "✅"
rm -rf "$LG"

# Case 24c (final M5): a .bak that cannot be written stops tidy before the
# main file is touched — it used to claim "原文已备份".
if [ "${EUID:-$(id -u)}" = "0" ]; then
    echo "  ➖ Case 24c: running as root, chmod 555 cannot block writes — skipped"
else
    LG=$(mktemp -d) || { echo "  ❌ Case 24c: mktemp -d failed"; exit 1; }
    mkdir "$LG/p"
    printf '# Demo\n\n## 🎯 Current State\n\n**最近改动**：x\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/p/m.md"
    cp "$LG/p/m.md" "$LG/m.orig"
    chmod 555 "$LG/p"
    rc=0; out=$(bash "$TIDY" "$LG/p/m.md" </dev/null 2>&1) || rc=$?
    chmod 755 "$LG/p"
    assert_exit "Case 24c: backup fails → tidy exit 1" 1 "$rc"
    assert_contains "Case 24c: backup failure named" "$out" "❌ tidy: backup failed"
    assert_not_contains "Case 24c: no 已备份 claim" "$out" "已备份"
    assert_exit "Case 24c: main file unchanged" 0 "$(cmp -s "$LG/p/m.md" "$LG/m.orig" && echo 0 || echo 1)"
    rm -rf "$LG"
fi

# Case 24d (final M1): `<!-- hx:x --> 文字` is not an anchor line — tidy must
# add anchors, as validate hints and hx.sh finds none.
LG=$(mktemp -d) || { echo "  ❌ Case 24d: mktemp -d failed"; exit 1; }
printf '# Demo\n\n## 🎯 Current State\n\n<!-- hx:x --> 文字\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/m.md"
rc=0; out=$(bash "$TIDY" "$LG/m.md" </dev/null 2>&1) || rc=$?
assert_contains "Case 24d: comment with trailing text → 补锚点" "$out" "补锚点"
assert_exit "Case 24d: hx:recent added" 1 "$(grep -cx '<!-- hx:recent -->' "$LG/m.md")"
assert_exit "Case 24d: the text line kept" 1 "$(grep -cxF '<!-- hx:x --> 文字' "$LG/m.md")"
rm -rf "$LG"

# Case 24e (final M2): a section with no status line still gets an empty
# hx:recent, so block set always has a target and nothing is overwritten.
LG=$(mktemp -d) || { echo "  ❌ Case 24e: mktemp -d failed"; exit 1; }
printf '# Demo\n\n## 🎯 Current State\n\n> 引用行\n\n### 待办\n- [ ] a\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/m.md"
rc=0; out=$(bash "$TIDY" "$LG/m.md" </dev/null 2>&1) || rc=$?
assert_contains "Case 24e: anchors list names hx:recent" "$out" "补锚点: Current State → hx:recent, hx:pending"
assert_exit "Case 24e: empty hx:recent right after the quote line" 0 \
    "$(awk '/^> 引用行$/{q=NR} /^<!-- hx:recent -->$/{s=NR} /^<!-- \/hx:recent -->$/{e=NR} END{exit !(q && s == q+1 && e == s+1)}' "$LG/m.md" && echo 0 || echo 1)"
assert_exit "Case 24e: 待办 wrapped in hx:pending" 1 "$(grep -cx '<!-- hx:pending -->' "$LG/m.md")"
printf '**最近改动区域**: y\n' > "$LG/r.txt"
rc=0; bash "$SCRIPTS_DIR/hx.sh" block set recent --from "$LG/r.txt" --file "$LG/m.md" >/dev/null 2>&1 || rc=$?
assert_exit "Case 24e: block set recent into the empty block → exit 0" 0 "$rc"
bash "$SCRIPTS_DIR/hx.sh" block get recent --file "$LG/m.md" > "$LG/r.got" 2>/dev/null
assert_exit "Case 24e: block get recent == payload" 0 "$(cmp -s "$LG/r.got" "$LG/r.txt" && echo 0 || echo 1)"
assert_exit "Case 24e: pending block survives" 1 "$(grep -cx -- '- \[ \] a' "$LG/m.md")"
rm -rf "$LG"

# Case 25 (final round 2): a section that already holds other blocks but no
# hx:recent used to be skipped whole, and `block set recent` then had no
# target. An empty hx:recent goes after the quote lines, existing blocks keep
# their bytes; broken anchors are refused without a write.
for kind in pending done; do
    LG=$(mktemp -d) || { echo "  ❌ Case 25: mktemp -d failed"; exit 1; }
    if [ "$kind" = pending ]; then hd='### 待办'; else hd='### 最近完成'; fi
    printf '# Demo\n\n## 🎯 Current State\n\n> 引用行\n\n<!-- hx:%s -->\n%s\n- [ ] a\n<!-- /hx:%s -->\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' "$kind" "$hd" "$kind" > "$LG/m.md"
    awk '/^<!-- hx:/,/^<!-- \/hx:/' "$LG/m.md" > "$LG/blk.orig"
    rc=0; out=$(bash "$TIDY" "$LG/m.md" </dev/null 2>&1) || rc=$?
    # rc is 1 here for the fixture's missing REQUIRED sections; the anchor
    # verdict is read from the output instead.
    assert_not_contains "Case 25 $kind-only: not reported as broken" "$out" "anchors broken"
    assert_contains "Case 25 $kind-only: 补锚点 names hx:recent" "$out" "补锚点: Current State → hx:recent"
    assert_exit "Case 25 $kind-only: empty hx:recent right after the quote line" 0 \
        "$(awk '/^> 引用行$/{q=NR} /^<!-- hx:recent -->$/{s=NR} /^<!-- \/hx:recent -->$/{e=NR} END{exit !(q && s == q+1 && e == s+1)}' "$LG/m.md" && echo 0 || echo 1)"
    awk '/^<!-- hx:'"$kind"' -->/,/^<!-- \/hx:'"$kind"' -->/' "$LG/m.md" > "$LG/blk.new"
    assert_exit "Case 25 $kind-only: existing block byte-identical" 0 "$(cmp -s "$LG/blk.orig" "$LG/blk.new" && echo 0 || echo 1)"
    printf '**最近改动区域**: y\n' > "$LG/r.txt"
    rc=0; bash "$SCRIPTS_DIR/hx.sh" block set recent --from "$LG/r.txt" --file "$LG/m.md" >/dev/null 2>&1 || rc=$?
    assert_exit "Case 25 $kind-only: block set recent → exit 0" 0 "$rc"
    cp "$LG/m.md" "$LG/once.md"
    rc=0; out=$(bash "$TIDY" "$LG/m.md" </dev/null 2>&1) || rc=$?
    assert_not_contains "Case 25 $kind-only: second run adds nothing" "$out" "补锚点"
    assert_exit "Case 25 $kind-only: second run leaves the file identical" 0 "$(cmp -s "$LG/m.md" "$LG/once.md" && echo 0 || echo 1)"
    rm -rf "$LG"
done
LG=$(mktemp -d) || { echo "  ❌ Case 25: mktemp -d failed"; exit 1; }
printf '# Demo\n\n## 🎯 Current State\n\n<!-- hx:pending -->\n### 待办\n- [ ] a\n\n## 📜 Development Log\n\n<!-- 🚨 AI 注意 -->\n' > "$LG/half.md"
cp "$LG/half.md" "$LG/half.orig"
rc=0; out=$(bash "$TIDY" "$LG/half.md" </dev/null 2>&1) || rc=$?
assert_exit "Case 25 half pair: tidy exit 1" 1 "$rc"
assert_not_contains "Case 25 half pair: stops before the summary" "$out" "tidy summary"
assert_contains "Case 25 half pair: ❌ names the block" "$out" "❌ tidy: Current State anchors broken (hx:pending"
assert_not_contains "Case 25 half pair: no 补锚点" "$out" "补锚点"
assert_exit "Case 25 half pair: file unchanged" 0 "$(cmp -s "$LG/half.md" "$LG/half.orig" && echo 0 || echo 1)"
assert_exit "Case 25 half pair: no .bak" 1 "$([ -e "$LG/half.md.bak" ] && echo 0 || echo 1)"
rm -rf "$LG"

summary
