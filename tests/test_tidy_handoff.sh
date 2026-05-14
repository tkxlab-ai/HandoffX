#!/bin/bash
source "$(dirname "$0")/common.sh"
TIDY="$SCRIPTS_DIR/tidy-handoff.sh"

# Cases 1-14 below test the legacy v1 tidy diagnostics on v1-layout fixtures.
# Phase I will replace them with v2-aware versions. Until then, bypass the v2
# layout gate so they run unchanged. Cases 15-* below clear this and exercise
# the gate explicitly.
export HANDOFF_TIDY_SKIP_V2_GATE=1

# 生成一个 valid HANDOFF.md 基线
mk_valid() {
    local f="$1"
    cat > "$f" <<'EOF'
# Demo — Project Handoff

## 📦 Project Overview
placeholder.

## 🏗 Architecture
placeholder.

## 🎯 Current State
placeholder.

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
**改动**: commands/handoff.md / commands/handoff-recall.md
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
extract_content() {
    grep -v "^$" "$1" | grep -v "🚨 AI 注意"
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
placeholder.

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
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX15a/HANDOFF.md"
sha_15a_before=$(shasum "$SANDBOX15a/HANDOFF.md" | cut -d' ' -f1)
out_15a=$("$TIDY" "$SANDBOX15a/HANDOFF.md" </dev/null 2>&1)
ec_15a=$?
sha_15a_after=$(shasum "$SANDBOX15a/HANDOFF.md" | cut -d' ' -f1)

assert_exit "Case 15a: non-interactive v1 → exit 0 (skip)" 0 "$ec_15a"
assert_contains "Case 15a: warns about v1 layout" "$out_15a" "v1 layout detected"
assert_contains "Case 15a: hints HANDOFF_TIDY_AUTO_MIGRATE" "$out_15a" "HANDOFF_TIDY_AUTO_MIGRATE"
if [ "$sha_15a_before" = "$sha_15a_after" ]; then
    echo "  ✅ Case 15a: HANDOFF.md untouched on skip"; PASS=$((PASS+1))
else
    echo "  ❌ Case 15a: HANDOFF.md was mutated"; FAIL=$((FAIL+1))
fi
[ ! -d "$SANDBOX15a/Handoff_Logs" ] && [ ! -d "$SANDBOX15a/Handoff_Logs.partial" ] && { echo "  ✅ Case 15a: no Handoff_Logs created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15a: Handoff_Logs leaked"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15a"

# 15b: HANDOFF_TIDY_AUTO_MIGRATE=1 → tidy invokes migrate-to-v2.sh --apply,
#      file gains v2 marker, sibling dirs/files appear.
SANDBOX15b=$(mktemp -d)
cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$SANDBOX15b/HANDOFF.md"
HANDOFF_TIDY_AUTO_MIGRATE=1 "$TIDY" "$SANDBOX15b/HANDOFF.md" </dev/null >/dev/null 2>&1
ec_15b=$?

assert_exit "Case 15b: AUTO_MIGRATE=1 → exit 0" 0 "$ec_15b"
grep -q '<!-- HANDOFF v2 schema -->' "$SANDBOX15b/HANDOFF.md" && { echo "  ✅ Case 15b: v2 marker added"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: marker missing"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX15b/Handoff_Logs" ] && { echo "  ✅ Case 15b: Handoff_Logs/ created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: Handoff_Logs missing"; FAIL=$((FAIL+1)); }
[ -d "$SANDBOX15b/Handoff_Decisions" ] && { echo "  ✅ Case 15b: Handoff_Decisions/ created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: Handoff_Decisions missing"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX15b/GOTCHAS.md" ] && { echo "  ✅ Case 15b: GOTCHAS.md created"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15b: GOTCHAS.md missing"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15b"

# ── Case 16 (C2): tidy renumbers duplicate Handoff_Logs/ entries ──────────
# Simulates Syncthing race: two machines independently created `0001-...md`.
SANDBOX16=$(mktemp -d)
cat > "$SANDBOX16/HANDOFF.md" <<'EOF'
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
mkdir -p "$SANDBOX16/Handoff_Logs"
echo "first 0001"  > "$SANDBOX16/Handoff_Logs/0001-2026-05-01T1000-first.md"
echo "race 0001"   > "$SANDBOX16/Handoff_Logs/0001-2026-05-01T1100-race.md"
echo "second 0002" > "$SANDBOX16/Handoff_Logs/0002-2026-05-02T1000-second.md"

"$TIDY" "$SANDBOX16/HANDOFF.md" </dev/null >/dev/null 2>&1

n_files=$(ls "$SANDBOX16/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16: 3 files preserved" "$n_files" "3"

n_unique=$(ls "$SANDBOX16/Handoff_Logs/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16: 3 unique numbers (no dupes left)" "$n_unique" "3"

n_0003=$(ls "$SANDBOX16/Handoff_Logs/"0003-*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16: 0003 created (duplicate bumped)" "$n_0003" "1"

# Original 0001 file (first by sort) keeps its number
[ -f "$SANDBOX16/Handoff_Logs/0001-2026-05-01T1000-first.md" ] && { echo "  ✅ Case 16: first-by-sort 0001 retained"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: 0001-first.md missing"; FAIL=$((FAIL+1)); }
# Original 0002 untouched
[ -f "$SANDBOX16/Handoff_Logs/0002-2026-05-02T1000-second.md" ] && { echo "  ✅ Case 16: 0002 untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: 0002 disturbed"; FAIL=$((FAIL+1)); }

# Renamed file's content is preserved (mv, not rewrite)
race_file=$(ls "$SANDBOX16/Handoff_Logs/"0003-*-race.md 2>/dev/null)
[ -n "$race_file" ] && grep -q "^race 0001$" "$race_file" && { echo "  ✅ Case 16: renamed file content intact"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16: race file content lost"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX16"

# Case 16-triple (Codex review #2): three files sharing the same NNNN must
# all be reduced to unique numbers. Earlier `prev_num` chain was broken — once
# the second file got renamed to e.g. 0003, prev_num became 0003, and the
# third still-0001 file no longer compared equal, so it was left as a dupe.
SANDBOX16t=$(mktemp -d)
cat > "$SANDBOX16t/HANDOFF.md" <<'EOF'
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
mkdir -p "$SANDBOX16t/Handoff_Logs"
echo "a" > "$SANDBOX16t/Handoff_Logs/0001-2026-05-01T1000-a.md"
echo "b" > "$SANDBOX16t/Handoff_Logs/0001-2026-05-01T1100-b.md"
echo "c" > "$SANDBOX16t/Handoff_Logs/0001-2026-05-01T1200-c.md"
echo "d" > "$SANDBOX16t/Handoff_Logs/0002-2026-05-02T1000-d.md"

"$TIDY" "$SANDBOX16t/HANDOFF.md" </dev/null >/dev/null 2>&1

n_files=$(ls "$SANDBOX16t/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "Case 16-triple: all 4 files preserved" "$n_files" "4"

n_unique=$(ls "$SANDBOX16t/Handoff_Logs/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16-triple: 4 unique numbers (no dupes left)" "$n_unique" "4"

# First-by-sort 0001-A keeps its number; B and C get renumbered (to 0003, 0004 typically)
[ -f "$SANDBOX16t/Handoff_Logs/0001-2026-05-01T1000-a.md" ] && { echo "  ✅ Case 16-triple: first-by-sort 0001 retained"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16-triple: 0001-a was disturbed"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX16t/Handoff_Logs/0002-2026-05-02T1000-d.md" ] && { echo "  ✅ Case 16-triple: 0002 untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16-triple: 0002 disturbed"; FAIL=$((FAIL+1)); }

rm -rf "$SANDBOX16t"

# Case 16b: dups in Handoff_Decisions/ also renumbered
SANDBOX16b=$(mktemp -d)
cat > "$SANDBOX16b/HANDOFF.md" <<'EOF'
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
mkdir -p "$SANDBOX16b/Handoff_Decisions"
echo "dec1" > "$SANDBOX16b/Handoff_Decisions/0001-2026-05-01-first.md"
echo "dec1-dup" > "$SANDBOX16b/Handoff_Decisions/0001-2026-05-02-dup.md"
"$TIDY" "$SANDBOX16b/HANDOFF.md" </dev/null >/dev/null 2>&1
n_unique=$(ls "$SANDBOX16b/Handoff_Decisions/"[0-9]*.md 2>/dev/null | xargs -n1 basename | grep -oE '^[0-9]{4}' | sort -u | wc -l | tr -d ' ')
assert_contains "Case 16b: Handoff_Decisions/ dups renumbered" "$n_unique" "2"
rm -rf "$SANDBOX16b"

# Case 16c: clean v2 layout (no dups) — tidy must NOT touch existing files
SANDBOX16c=$(mktemp -d)
cat > "$SANDBOX16c/HANDOFF.md" <<'EOF'
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
mkdir -p "$SANDBOX16c/Handoff_Logs"
echo "a" > "$SANDBOX16c/Handoff_Logs/0001-2026-05-01T1000-a.md"
echo "b" > "$SANDBOX16c/Handoff_Logs/0002-2026-05-02T1000-b.md"
sha_before=$(shasum "$SANDBOX16c/Handoff_Logs/0001-2026-05-01T1000-a.md" "$SANDBOX16c/Handoff_Logs/0002-2026-05-02T1000-b.md" | sort)
"$TIDY" "$SANDBOX16c/HANDOFF.md" </dev/null >/dev/null 2>&1
sha_after=$(shasum "$SANDBOX16c/Handoff_Logs/0001-2026-05-01T1000-a.md" "$SANDBOX16c/Handoff_Logs/0002-2026-05-02T1000-b.md" | sort)
[ "$sha_before" = "$sha_after" ] && { echo "  ✅ Case 16c: no-dup layout left untouched"; PASS=$((PASS+1)); } || { echo "  ❌ Case 16c: clean layout was disturbed"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX16c"

# 15c: v2-marker file passes the gate (regression — gate must not interfere with v2 layouts).
SANDBOX15c=$(mktemp -d)
cat > "$SANDBOX15c/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test

## 🏗 Architecture
test

## 🎯 Current State
test

## 📜 Development Log

> pointer block — entries in Handoff_Logs/

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
ec_15c=0; "$TIDY" "$SANDBOX15c/HANDOFF.md" </dev/null >/dev/null 2>&1 || ec_15c=$?
# Exit code may be 0 (clean) or 1 (findings about other RECOMMENDED sections).
# What matters is that gate did NOT trigger migration.
[ ! -d "$SANDBOX15c/Handoff_Logs.partial" ] && { echo "  ✅ Case 15c: v2 file did not trigger migration"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15c: gate erroneously triggered on v2"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX15c/HANDOFF.md.pre-v2-backup" ] && { echo "  ✅ Case 15c: no backup file (no migration)"; PASS=$((PASS+1)); } || { echo "  ❌ Case 15c: migration ran on v2 file"; FAIL=$((FAIL+1)); }
rm -rf "$SANDBOX15c"

summary
