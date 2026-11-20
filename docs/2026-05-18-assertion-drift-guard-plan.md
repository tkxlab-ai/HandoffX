# (B) doc-freshness 计数 drift guard 硬化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 给 `tests/test_doc_freshness.sh` 加可测性 seam + 共享 `CANONICAL_DOCS` + `_normalize_doc_for_scan` helper + 静态「断言点」动态 drift guard，并把 Test 15/10 折入同一归一+共享清单，根除断言无 guard / badge URL-encoded / 语言变体 / 分散清单各漏整类盲点。

**Architecture:** 单文件改 `tests/test_doc_freshness.sh`。**关键 TDD 原则（Codex 第5源 finding 后修正）**：每个生产体改动的 RED gate 必须真 gate 生产码——用 `DOC_DIR` 环境覆盖跑**真实** `tests/test_doc_freshness.sh` 对**篡改的 fixture canonical-doc 集**断言真实退出码（改前 FAIL/改后 PASS），而非测 test-local helper mimic（后者非 load-bearing，假绿类 Gotcha #20）。helper 单测保留为辅助。前置任务先建 `DOC_DIR` 可覆盖 seam（向后兼容）。真实 repo 改词+重基线为后置任务（测试代码全冻结后算终值 STATIC，自指收敛）。

**Tech Stack:** bash 3.2 / mawk-safe（POSIX `grep -E` 显式区间、`sed` 窄替换、`awk` marker，循 Gotcha #15）；harness `tests/common.sh`（`assert_*`，`summary` 返回 `[ FAIL = 0 ]`→exit 码可判）；run_all 自动发现 `test_*.sh`。

**Spec:** `docs/2026-05-18-assertion-total-drift-guard-design.md`（Boss 认可，Codex 第3源 4 轮收敛）。

---

### Task 1: 可测性 seam（DOC_DIR 可覆盖）+ CANONICAL_DOCS + 归一 helper

**Files:**
- Modify: `tests/test_doc_freshness.sh:5`（`DOC_DIR="$ROOT_DIR"`）+ 顶部变量区 + helper 定义区

- [ ] **Step 1: 写 seam 的 RED 测试（load-bearing：真实脚本是否认 DOC_DIR）**

新建 `tests/test_doc_freshness_seam.sh`（独立小套件，run_all 自动发现）：

```bash
#!/bin/bash
# DOC_DIR override seam — (B) 可测性前置；使后续 RED gate 能对 fixture 跑真实脚本。
source "$(dirname "$0")/common.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tests"
# 极小 fixture：仅放一个会让 test_doc_freshness 必失败的破绽（README 缺失 → 某 Test FAIL）
# 真相判据：DOC_DIR 指向空 fixture 时真实脚本行为应随 DOC_DIR 变（认这个环境变量）。
printf 'x\n' > "$W/README.md"
out_repo=$(DOC_DIR= bash "$(dirname "$0")/test_doc_freshness.sh" 2>&1 | tail -1)
out_fix=$(DOC_DIR="$W" bash "$(dirname "$0")/test_doc_freshness.sh" 2>&1 | tail -1)
assert_exit "DOC_DIR=fixture 改变真实脚本结果(认 env 覆盖)" 0 \
  "$([ "$out_repo" != "$out_fix" ] && echo 0 || echo 1)"
summary
```

- [ ] **Step 2: 跑确认 RED**

Run: `bash tests/test_doc_freshness_seam.sh 2>&1 | tail -2`
Expected: FAIL（`DOC_DIR="$ROOT_DIR"` 硬赋值，env 被忽略 → 两次输出相同 → assert FAIL）

- [ ] **Step 3: 改 seam（`tests/test_doc_freshness.sh:5`）**

`DOC_DIR="$ROOT_DIR"` → `DOC_DIR="${DOC_DIR:-$ROOT_DIR}"`
（向后兼容：unset 时仍 `$ROOT_DIR`；k4-chicken-egg 等不设 DOC_DIR 不受影响。）

- [ ] **Step 4: 跑确认 GREEN**

Run: `bash tests/test_doc_freshness_seam.sh 2>&1 | tail -1`
Expected: `1 passed, 0 failed`

- [ ] **Step 5: 加 CANONICAL_DOCS + `_normalize_doc_for_scan`（顶部变量区/helper 区）**

```bash
# 共享 canonical 文档集（机械派生+裁定，见 design §3.0；新增 canonical doc 须用
# 同谓词重派生，勿手加）。三 guard（Test10 / 新断言点 / Test15）共用，根除分散清单各漏。
CANONICAL_DOCS="README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md"

# 归一：① 删 HANDOFF.md 历史块（结构 marker 非魔数）；② 窄 URL 解码仅 %20 %2F %2B。
_normalize_doc_for_scan() {
    awk '
      /^### 最近完成/ {skip=1; next}
      /^## 📜 Development Log/ {skip=1; next}
      /^## / { if (skip) skip=0 }
      !skip
    ' "$1" | sed 's/%20/ /g; s/%2F/\//g; s/%2B/+/g'
}

# 静态 assert 调用点计数（排除函数定义签名行；Codex 第2 finding）。入参=含 test_*.sh 目录。
_count_static_asserts() {
    local d="$1" a df
    a=$(grep -hcE '^[[:space:]]*assert_' "$d"/test_*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
    df=$(grep -hcE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' "$d"/test_*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
    echo $((a - df))
}
```

- [ ] **Step 6: helper 辅助单测（Test 0，加在现有 Test 1 前；非 load-bearing 主 gate，仅单元佐证）**

```bash
# ── Test 0: helper 单元佐证（辅助；生产 gate 见后续 fixture-DOC_DIR 任务）──
_t0=$(mktemp -d); trap 'rm -rf "$_t0"' EXIT; mkdir -p "$_t0/tests"
printf '%s\n' '## 🚀 Q' '当前 469 断言点' '### 最近完成' '历史 744 断言点' \
  '## 🐛 G' 'g' 'badge tests-29%20suites%20%2F%20469%2B%20assertion%20sites-x' > "$_t0/H.md"
_o=$(_normalize_doc_for_scan "$_t0/H.md")
assert_not_contains "Test0: 剥 ### 最近完成" "$_o" "744 断言点"
assert_contains "Test0: 留当前声称" "$_o" "469 断言点"
assert_contains "Test0: 窄解码" "$_o" "tests-29 suites / 469+ assertion sites-x"
printf '%s\n' '#!/bin/bash' 'assert_exit a 0 0' 'assert_x() { :; }' 'assert_x f' > "$_t0/tests/test_f.sh"
assert_exit "Test0: 静态计数减定义=2" 0 "$([ "$(_count_static_asserts "$_t0/tests")" = 2 ] && echo 0 || echo 1)"
rm -rf "$_t0"; trap - EXIT
```

- [ ] **Step 7: 跑确认 Test0 GREEN + run_all 不回归**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -E 'Test0|passed,' | tail; bash tests/run_all.sh 2>&1 | tail -1`
Expected: Test0 全 PASS；run_all `All suites passed`（新增 seam 套件计入，套件数 +1）

- [ ] **Step 8: Commit**

```bash
git add tests/test_doc_freshness.sh tests/test_doc_freshness_seam.sh
git commit -m "feat(doc-freshness): DOC_DIR seam + CANONICAL_DOCS + 归一/计数 helper

DOC_DIR 可 env 覆盖(向后兼容)使后续 RED 能对 fixture 跑真实脚本(load-bearing,
非 helper mimic;Codex 第5 finding)。+ CANONICAL_DOCS(机械派生根除分散清单各漏)
+ _normalize_doc_for_scan(历史块 marker 剥离+窄 URL 解码)+ _count_static_asserts
(减定义签名,Codex 第2)。Spec docs/2026-05-18-assertion-total-drift-guard-design.md"
```

---

> **共享 fixture builder（Tasks 2-4 RED gate 复用，写进 plan 不省略）**：每个生产体
> 任务的 load-bearing RED/GREEN 都按此式——建一个**完整 fixture canonical-doc 目录**
> （含 tests/ 以喂 `_count_static_asserts`），注入受测 drift，`DOC_DIR=$FX bash
> tests/test_doc_freshness.sh` 跑**真实脚本**，断言其真实退出码/输出。fixture builder：
> ```bash
> _mk_fx() {  # $1=目标 dir；建最小但通过其他 Test 的 canonical 集
>   local F="$1"; mkdir -p "$F/tests"
>   cp tests/common.sh "$F/tests/"; cp tests/test_*.sh "$F/tests/" 2>/dev/null
>   for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md \
>            INSTALL.md scripts; do cp -R "$d" "$F/" 2>/dev/null; done
>   cp VERSION "$F/" 2>/dev/null; mkdir -p "$F/Release"
> }
> ```
> RED 判据 = **生产改动前** `DOC_DIR=$FX bash tests/test_doc_freshness.sh` 对注入 drift
> **不 FAIL**（漏 = 盲点存在）；**改动后** 对同一注入 **FAIL 且指明 file**（gate 生产码）。

### Task 2: 新 Test — 断言点动态 drift guard（load-bearing fixture-DOC_DIR）

**Files:** Modify `tests/test_doc_freshness.sh`（最末 Test 后、`summary` 前；编号 = `grep -oE '# ── Test [0-9]+' | sort -t' ' -k4 -n | tail` 最大+1，下称 TestN）

- [ ] **Step 1: 写 load-bearing RED（真实脚本 + fixture-DOC_DIR + 注入断言点 drift）**

加 `tests/test_doc_freshness_bguard.sh`（独立套件，专放 (B) load-bearing 负控）：

```bash
#!/bin/bash
source "$(dirname "$0")/common.sh"
RT="$(cd "$(dirname "$0")/.." && pwd)"; FX=$(mktemp -d); trap 'rm -rf "$FX"' EXIT
_mk_fx() { local F="$1"; mkdir -p "$F/tests"; cp "$RT"/tests/common.sh "$F/tests/"
  cp "$RT"/tests/test_*.sh "$F/tests/" 2>/dev/null
  for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md INSTALL.md scripts VERSION; do cp -R "$RT/$d" "$F/" 2>/dev/null; done; mkdir -p "$F/Release"; }
_mk_fx "$FX"
S=$( "$RT"/tests/test_doc_freshness.sh >/dev/null 2>&1; _x=$?; \
     grep -hcE '^[[:space:]]*assert_' "$FX"/tests/test_*.sh|awk '{s+=$1}END{print s}'; )
# 注入：把 fixture HANDOFF.md 当前区某断言点声称改成必错值 9999
sed -i.b 's/[0-9]\{1,\}\( *断言点\)/9999\1/; s/[0-9]\{1,\}\( *assertion sites\)/9999\1/' "$FX/HANDOFF.md" 2>/dev/null || \
  sed -i '' 's/[0-9]\{1,\}\( *断言点\)/9999\1/; s/[0-9]\{1,\}\( *assertion sites\)/9999\1/' "$FX/HANDOFF.md"
DOC_DIR="$FX" bash "$RT"/tests/test_doc_freshness.sh >/tmp/bg_red.out 2>&1; red_rc=$?
assert_exit "TestN load-bearing RED: 注入 9999 断言点 → 真实脚本 FAIL" 1 "$red_rc"
assert_contains "TestN RED: 指明 HANDOFF.md 漂移" "$(cat /tmp/bg_red.out)" "HANDOFF.md"
rm -f /tmp/bg_red.out; summary
```

- [ ] **Step 2: 跑确认 RED**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | tail -2`
Expected: FAIL —— 此刻 test_doc_freshness.sh 无断言点 guard，注入 9999 断言点**不被
任何 Test 抓** → 真实脚本仍 exit 0（其它 Test 偶发失败不指 HANDOFF 断言点）→
`assert_exit ... 1` 与 `assert_contains HANDOFF.md` 失配（证盲点存在、gate 待生产码）

- [ ] **Step 3: 实现 TestN 主体（接真实 CANONICAL_DOCS）**

在 `tests/test_doc_freshness.sh` 最末 Test 后插入：

```bash
# ── Test N: 断言点总数动态 drift guard（静态 assert 调用点计数，design §3.2）──
_REAL_STATIC=$(_count_static_asserts "$DOC_DIR/tests")
ap_drift=0
for _d in $CANONICAL_DOCS; do
    [ -f "$DOC_DIR/$_d" ] || continue
    while IFS= read -r _n; do
        [ -z "$_n" ] && continue
        if [ "$_n" != "$_REAL_STATIC" ]; then
            echo "  ❌ $_d: 声称 '$_n 断言点'，实际 $_REAL_STATIC"
            ap_drift=1
        fi
    done <<EOF
$(_normalize_doc_for_scan "$DOC_DIR/$_d" | grep -oE '[0-9]+\+? *(断言点|assertion sites)' | grep -oE '^[0-9]+')
EOF
done
if [ "$ap_drift" -eq 0 ]; then
    echo "  ✅ 所有 CANONICAL_DOCS '断言点' 与静态计数一致 ($_REAL_STATIC)"
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi
```

- [ ] **Step 4: 跑确认 GREEN（load-bearing：真实脚本现抓注入）**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | tail -1`
Expected: `2 passed, 0 failed`（注入 9999 断言点 → 真实 test_doc_freshness.sh 经新
TestN exit 1 且输出含 `HANDOFF.md`——证生产码被 gate）。
负控反向：`_mk_fx` 干净 fixture（不注入）→ `DOC_DIR=$FX bash test_doc_freshness.sh`
TestN 那条应 ✅（迁移前真实 doc 还是旧词，TestN 对「无断言点声称」doc 视为 0 命中=
不 FAIL；真实数值对齐留 Task 5）。

- [ ] **Step 5: Commit**

```bash
git add tests/test_doc_freshness.sh tests/test_doc_freshness_bguard.sh
git commit -m "feat(doc-freshness): 静态断言点动态 drift guard (Test N) + load-bearing 负控

TestN 迭代 CANONICAL_DOCS,归一+双语 EXACT。RED gate 用 DOC_DIR=fixture 跑真实
脚本断注入 9999 断言点改前漏/改后 FAIL+指 file(真 gate 生产码,非 helper mimic)。"
```

---

### Task 3: Test 15 折入 — 双语+归一+CANONICAL_DOCS（load-bearing）

**Files:** Modify `tests/test_doc_freshness.sh` Test 15（doc loop + `claimed_counts=` 提取行）

- [ ] **Step 1: load-bearing RED（fixture 注入 README_CN badge 套件 drift，真实脚本）**

追加到 `tests/test_doc_freshness_bguard.sh`（`summary` 前）：

```bash
FX2=$(mktemp -d); _mk_fx "$FX2"
# 注入：README_CN.md badge 套件数改 88（旧 Test15 zh-only+不解码 → 漏）
sed -i.b 's#tests-[0-9]\{1,\}%20suites#tests-88%20suites#' "$FX2/README_CN.md" 2>/dev/null || \
  sed -i '' 's#tests-[0-9]\{1,\}%20suites#tests-88%20suites#' "$FX2/README_CN.md"
DOC_DIR="$FX2" bash "$RT"/tests/test_doc_freshness.sh >/tmp/t15.out 2>&1; t15_rc=$?
assert_exit "Test15 load-bearing RED: README_CN badge 88 套件 → 真实脚本 FAIL" 1 "$t15_rc"
assert_contains "Test15 RED: 指明 README_CN.md 套件漂移" "$(cat /tmp/t15.out)" "README_CN.md"
rm -rf "$FX2" /tmp/t15.out
```

- [ ] **Step 2: 跑确认 RED**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | grep -E 'Test15|README_CN' | tail`
Expected: FAIL —— Test 15 现 zh-only + 不解码 + 清单无 README_CN → badge `88%20suites`
不被抓 → 真实脚本不为此 FAIL（或不指 README_CN）→ assert 失配（证三洞、gate 待修）

- [ ] **Step 3: 改 Test 15 主体**

`for doc in "$DOC_DIR/README.md" "$DOC_DIR/HANDOFF.md" "$DOC_DIR/INSTALL.md" "$DOC_DIR/CONTRIBUTING.md" "$DOC_DIR/TEST-SCENARIOS.md"; do` →
```bash
for doc in $CANONICAL_DOCS; do
    doc="$DOC_DIR/$doc"
```
`claimed_counts=$(grep -oE '[0-9]+ 套件' "$doc" | grep -oE '^[1-9][0-9]*' | sort -u)` →
```bash
    claimed_counts=$(_normalize_doc_for_scan "$doc" | grep -oE '[0-9]+ *(套件|suites)' | grep -oE '^[1-9][0-9]*' | sort -u)
```
（EXACT/`suite_drift`/输出逻辑不变。`[ -f "$doc" ] || continue` 已有则保留。）

- [ ] **Step 4: 跑确认 GREEN（真实脚本现抓 README_CN badge）**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | grep -E 'Test15|passed,' | tail`
Expected: Test15 load-bearing 2 条 PASS（注入 README_CN badge 88 → 真实脚本 FAIL 指
README_CN.md）。

- [ ] **Step 5: Commit**

```bash
git add tests/test_doc_freshness.sh tests/test_doc_freshness_bguard.sh
git commit -m "feat(doc-freshness): Test 15 双语+归一+CANONICAL_DOCS 折入 + load-bearing 负控

提取式→(套件|suites)、喂归一、loop 用 CANONICAL_DOCS(纳 README_CN)。RED gate
用 fixture-DOC_DIR 跑真实脚本断 README_CN badge 88 套件改前漏/改后 FAIL 指 file。
pre-existing 三洞经 Boss 显式根治折入(Decision 0023)。"
```

---

### Task 4: Test 10 硬化 — 换 helper+CANONICAL_DOCS（load-bearing）

**Files:** Modify `tests/test_doc_freshness.sh` Test 10（`grep -RInE '(228|270|279)...'` + `sed -n '1,420p' HANDOFF.md` 块）

- [ ] **Step 1: load-bearing RED（fixture 注入 README_CN 退役号 + HANDOFF 历史块退役号）**

追加到 `tests/test_doc_freshness_bguard.sh`（`summary` 前）：

```bash
FX3=$(mktemp -d); _mk_fx "$FX3"
printf '\n当前 270 assertions demo\n' >> "$FX3/README_CN.md"   # Test10 旧清单漏 README_CN
DOC_DIR="$FX3" bash "$RT"/tests/test_doc_freshness.sh >/tmp/t10.out 2>&1
assert_contains "Test10 load-bearing RED: README_CN 退役号 270 → 真实脚本拦" \
  "$(cat /tmp/t10.out)" "旧断言统计"
# 历史块豁免不回归：HANDOFF.md ### 最近完成 内退役号不应误拦
FX4=$(mktemp -d); _mk_fx "$FX4"
DOC_DIR="$FX4" bash "$RT"/tests/test_doc_freshness.sh >/tmp/t10b.out 2>&1
assert_not_contains "Test10: 干净 fixture 不误报旧断言统计" \
  "$(grep '旧断言统计' /tmp/t10b.out || echo CLEAN)" "❌"
rm -rf "$FX3" "$FX4" /tmp/t10.out /tmp/t10b.out
```

- [ ] **Step 2: 跑确认 RED**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | grep -E 'Test10' | tail`
Expected: FAIL —— Test 10 旧清单无 README_CN → 注入 270 不被拦 → `assert_contains
旧断言统计` 失配（证清单漏 README_CN）

- [ ] **Step 3: 改 Test 10 主体（换 helper + CANONICAL_DOCS，blocklist 数字集不变）**

`if { grep -RInE '(228|270|279) ...' "$DOC_DIR/README.md" "$DOC_DIR/INSTALL.md" "$DOC_DIR/CONTRIBUTING.md" "$DOC_DIR/TEST-SCENARIOS.md" ; sed -n '1,420p' "$DOC_DIR/HANDOFF.md" | grep -nE '(228|270|279) ...' ; } >/dev/null 2>&1; then` →
```bash
_t10_hit=0
for _d in $CANONICAL_DOCS; do
    [ -f "$DOC_DIR/$_d" ] || continue
    _normalize_doc_for_scan "$DOC_DIR/$_d" \
      | grep -qE '(228|270|279) (断言|assertions)|(228|270|279) passed' && _t10_hit=1
done
if [ "$_t10_hit" -eq 1 ]; then
```
（退役号集 `(228|270|279)` 不变；doc 源→CANONICAL_DOCS；剥块→`_normalize_doc_for_scan`
取代 `sed 1,420p` 魔数。）

- [ ] **Step 4: 跑确认 GREEN（真实脚本现拦 README_CN 退役号、历史块不误拦）**

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | grep -E 'Test10|passed,' | tail`
Expected: Test10 两条 PASS（README_CN 270 被拦 + 干净 fixture 不误报）。

- [ ] **Step 5: Commit**

```bash
git add tests/test_doc_freshness.sh tests/test_doc_freshness_bguard.sh
git commit -m "feat(doc-freshness): Test 10 硬化 _normalize 代 sed 魔数+CANONICAL_DOCS + load-bearing 负控

去 sed 1,420p 魔数(420 失准母题)+硬编清单(漏 README_CN)→共享 helper+CANONICAL_DOCS。
退役号 blocklist 逻辑保留。RED gate fixture-DOC_DIR 断 README_CN 退役号改前漏/改后拦。"
```

---

### Task 5: 真实 repo 改词+重基线（自指收敛终算，GREEN）

**Files:** Modify `CANONICAL_DOCS` 全部 doc（机械派生 loci，含 badge）

- [ ] **Step 1: 冻结测试代码，算终值**

确认 Tasks 1-4 全 commit（不再新增 `assert_`/test 文件）。算终值：
```bash
A=$(grep -hcE '^[[:space:]]*assert_' tests/test_*.sh|awk '{s+=$1}END{print s}')
D=$(grep -hcE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' tests/test_*.sh|awk '{s+=$1}END{print s}')
echo "FINAL_STATIC=$((A-D)) SUITES=$(ls tests/test_*.sh|wc -l|tr -d ' ')"
```
记 `FINAL_STATIC`、`SUITES`（注：Task1/2/3/4 各新增套件文件 → SUITES 较 29 增加；
此即套件计数 locus 也要同步的真值）。

- [ ] **Step 2: 机械派生待迁移 loci（旧词）**

```bash
for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md; do
  echo "== $d =="; awk '/^### 最近完成/{s=1;next} /^## 📜 Development Log/{s=1;next} /^## /{if(s)s=0} !s' "$d" \
   | sed 's/%20/ /g;s/%2F/\//g;s/%2B/+/g' | grep -nE '[0-9]+\+? *(断言|assertions)|[0-9]+ *(套件|suites)'
done
```
每命中行：套件数→`SUITES`；断言数字→`FINAL_STATIC` **且词 `断言`→`断言点`、
`assertions`→`assertion sites`**。badge 按原 URL 编码改回（`%20`/`%2B` 形态）。
冻结历史块已被 awk 排除，不在命中=不动。

- [ ] **Step 3: 逐 doc 改（read 后 edit；prose 首现加一次「（assert 调用点，结构指标）」）**

按 Step 2 输出逐行精改；每 doc 后 grep 复核落地/无双改/历史未动。

- [ ] **Step 4: 真实 repo GREEN + run_all**

Run: `bash tests/test_doc_freshness.sh 2>&1 | tail -1; bash tests/run_all.sh 2>&1 | tail -1`
Expected: test_doc_freshness 0 failed；run_all `All suites passed`（失败则 clean
重跑 ×2 辨瞬态再判，claim≠fact）。

- [ ] **Step 5: 旧词清净收尾断言**

```bash
for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md; do
  awk '/^### 最近完成/{s=1;next} /^## 📜 Development Log/{s=1;next} /^## /{if(s)s=0} !s' "$d" \
   | sed 's/%20/ /g;s/%2B/+/g' | grep -qE '[0-9]+\+? *(断言|assertions)' && echo "RESIDUE:$d"
done; echo "(无 RESIDUE = 当前区旧词清净)"
```
Expected: 无 RESIDUE。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore(doc-freshness): 改词 断言→断言点/assertion sites + 重基线 (B) GREEN

CANONICAL_DOCS 机械派生 loci 全改:套件→<SUITES>、断言数→<FINAL_STATIC>+改词
(消静默改义,Codex 第3);badge URL 编码同步;冻结历史不动。三 guard+run_all 全绿。"
```

---

### Task 6: 全回归 + 多源异构独立审

**Files:** 无（review-only）

- [ ] **Step 1: 全负控复核（spec §5）**：历史排除 / README_CN 入网(plain+badge) /
  英文 plain 入网 / 真相源排除定义行 / 窄解码不误伤 / Test10 退役号无回归——逐条
  fixture-DOC_DIR 真实脚本跑，贴证据。确认 `test_doc_freshness_bguard.sh` +
  `_seam.sh` 全绿、run_all 全绿（×2 辨瞬态）。
- [ ] **Step 2: 源 1 opus code-reviewer**：focus `git diff <Task1前>..HEAD`。重点：
  awk marker 边界、窄 sed 解码无过度、`_count_static_asserts` 减定义精确、EXACT、
  CANONICAL_DOCS 三 guard 一致、DOC_DIR seam 向后兼容、Test10/15 折入无回归、
  RED gate 真 gate 生产码（非 helper mimic）、scope 干净。
- [ ] **Step 3: 源 2 silent-failure-hunter**：marker 缺失 fail-safe、badge 异常编码、
  空 doc、grep 无命中 vs 真 0、定义 vs 调用边界、迁移后旧词残留是否真被收尾抓、
  fixture builder 是否漏关键文件致 fixture 假绿。确认无 drift 静默放过面。
- [ ] **Step 4: 源 3 Codex stop-time**：`disable-model-invocation` controller 无法
  自调（诚实声明不伪称）。Boss 可 `/codex:adversarial-review --base <Task1前 SHA>`
  补第 3 源。本设计+plan 经 Codex 第3源 5 轮修订（4 spec + 1 plan），实现期同等强制。
- [ ] **Step 5: finding 纪律（§4/Gotcha#19）**：本轮逻辑洞→scope 内 TDD 修+负控；
  pre-existing→`git log <base>..HEAD -- <file>` 机械溯源升 Decision 不 mid-cycle
  扩张。判据=机械溯源，不自我批准。
- [ ] **Step 6: 收口**：全 finding 闭+run_all 绿+三 guard 真实绿→回填 Decision 0023
  Outcome（(B) shipped + Test15 pre-existing 多洞 + 真相源语义 + CANONICAL_DOCS 根治
  + DOC_DIR seam，Boss 逐项决定，escalation 透明）+ Gotcha #22 关联（brainstorming
  设计稿+plan 需第3源最强案例，5 轮 Codex 修订）。superpowers:finishing-a-development-branch
  收尾；§4 push 待 Boss 显式授权（commit 本地不顺延）。

---

## Self-Review（writing-plans 自查，已执行）

**1. Spec coverage:** §3.0 CANONICAL_DOCS→T1S5+三 guard T2/3/4；§3.1 helper→T1S5；
§3.2 断言点 guard（静态减定义/双语/EXACT/改词）→T2+T5；§3.3 Test15 折入→T3；§3.4
Test10 硬化→T4；§3.5 重基线机械派生→T5；§5 测试判据→T2-4 load-bearing
fixture-DOC_DIR + T5 真实 GREEN + T6 全负控；§5.9 自指收敛→T5S1 冻结后终算；§6 风险
（footgun/改词遗漏/marker 缺失/CANONICAL 完整性/Test15 回归面）→T1 保守 helper +
T5S5 收尾断言 + T6 silent-failure。**Codex 第5 finding（RED 不 gate 生产）→ 全任务
RED 改为 DOC_DIR=fixture 跑真实脚本断真实退出，helper 单测降辅助。** 无 gap。

**2. Placeholder scan:** 无 TBD/TODO；FINAL_STATIC/SUITES/编号 N 执行期机械实测
（精确命令获取，非占位）；loci/CANONICAL「机械派生」非手列（spec 一致）。fixture
builder 代码完整给出（不省略）。

**3. Type consistency:** `_normalize_doc_for_scan`/`_count_static_asserts`/
`CANONICAL_DOCS`/`_mk_fx`/`DOC_DIR` 命名 T1→6 一致；regex `([0-9]+)\+? *(断言点|
assertion sites)`、`[0-9]+ *(套件|suites)`、awk marker（`### 最近完成`/`## 📜
Development Log`→`^## `）T1/2/3/4/5 一致；seam `${DOC_DIR:-$ROOT_DIR}` T1 定义、
T2-5 RED gate 依赖一致。
