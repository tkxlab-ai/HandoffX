# per-suite 计数 drift guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给「逐套件计数」补上 Test 18 级别的机械 EXACT 结构护栏（真相源=逐文件静态 assert 调用点），顺手修掉 TEST-SCENARIOS.md header/表 pre-existing 语义矛盾，为 P2 改名去险。

**Architecture:** 折入 `tests/test_doc_freshness.sh` 作 Test 20（非新套件，不触发 Test 15 套件数变更）；新 helper `_count_static_asserts_one(file)` 单文件谓词，`_count_static_asserts` 重构为 Σ over it（DRY，数学等价）；负控加进 `tests/test_doc_freshness_bguard.sh`，键 gate 判决非诊断 echo + gate-中性化变异（Gotcha #25）。自指收敛：本计划自身新增 assert_ 行会抬高静态总数，故 rebaseline 在**全测试码冻结后机械算终值**（循 (B) Dev Log 0058 范式），不硬编码 485。

**Tech Stack:** Bash 3.2 / mawk-POSIX-safe（无 awk interval；`comm` + 进程替换 + `grep -cE`）；TDD RED→GREEN；spec = `Handoff_Decisions/0024-2026-05-19-per-suite-count-drift-guard.md`。

---

## File Structure

| 文件 | 责任 | 改动 |
|------|------|------|
| `tests/test_doc_freshness.sh` | 真相源谓词 + Test 18 重构 + Test 20 三层 guard + Test 0 单元佐证 | Modify |
| `tests/test_doc_freshness_bguard.sh` | Test 20 load-bearing 负控（c1 逐行 / c2 完整性 / c3 Σ + gate-中性化矩阵） | Modify |
| `TEST-SCENARIOS.md` | per-suite 真相载体：31 行 `断言数`→静态值、列头改名、:353 header 校准 | Modify（rebaseline，机械生成） |
| `HANDOFF.md` | :37 剔除 inline per-suite 列表只留 aggregate | Modify（1 行） |

**关键不变式**：Test 20 用 manual `if/FAIL/PASS` 模式（同 Test 1–19，Tacit#2），**不新增 `^assert_` 行**；唯一新增 assert_ = Task 1 Test 0 一行（`_count_static_asserts_one` 单元）+ Task 3 bguard c1/c2/c3。故最终静态总数 = 485 + 1 + (bguard 新增数)，**由 Task 5 机械算定**，全程不硬编码。

---

### Task 1: `_count_static_asserts_one` 单文件谓词 + Test 18 DRY 重构

**Files:**
- Modify: `tests/test_doc_freshness.sh:45-51`（`_count_static_asserts` 重构）
- Modify: `tests/test_doc_freshness.sh:53-63`（Test 0 加 `_one` 单元佐证）

- [ ] **Step 1: 写 RED——Test 0 加 `_count_static_asserts_one` 单元断言**

在 `tests/test_doc_freshness.sh` 第 62 行（现有 `assert_exit "Test0: 静态计数减定义=2" ...`）**之后**插入一行：

```bash
assert_exit "Test0: _one 单文件计数=2" 0 "$([ "$(_count_static_asserts_one "$_t0/tests/test_f.sh")" = 2 ] && echo 0 || echo 1)"
```

- [ ] **Step 2: 跑验证 RED**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -A1 'Test0: _one'`
Expected: FAIL（`_count_static_asserts_one: command not found` 或断言失败，helper 未定义）

- [ ] **Step 3: 实现——加 `_count_static_asserts_one` + 重构 `_count_static_asserts`**

把 `tests/test_doc_freshness.sh:45-51` 当前块：

```bash
# 静态 assert 调用点计数（排除函数定义签名行；Codex 第2 finding）。入参=含 test_*.sh 目录。
_count_static_asserts() {
    local d="$1" a df
    a=$(grep -hcE '^[[:space:]]*assert_' "$d"/test_*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
    df=$(grep -hcE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' "$d"/test_*.sh 2>/dev/null | awk '{s+=$1} END{print s+0}')
    echo $((a - df))
}
```

整体替换为（新 `_one` 单文件谓词 + 旧函数重构为 Σ；数学等价 Σ(aᵢ−dfᵢ)=Σaᵢ−Σdfᵢ）：

```bash
# 单文件静态 assert 调用点（排除函数定义签名行）。Test 18 + Test 20 共用同谓词，
# 单点定义消两份漂移（design 0024 §1）。grep -cE 单文件无匹配退 1 → || true + :-0 兜底。
_count_static_asserts_one() {
    local f="$1" a df
    a=$(grep -cE '^[[:space:]]*assert_' "$f" 2>/dev/null || true)
    df=$(grep -cE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' "$f" 2>/dev/null || true)
    echo $(( ${a:-0} - ${df:-0} ))
}

# 目录求和（入参=含 test_*.sh 目录）= Σ 单文件谓词（DRY）。
_count_static_asserts() {
    local d="$1" f s=0
    for f in "$d"/test_*.sh; do
        [ -f "$f" ] || continue
        s=$((s + $(_count_static_asserts_one "$f")))
    done
    echo "$s"
}
```

- [ ] **Step 4: 跑验证 GREEN（Test 0 + Test 18 回归）**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -E 'Test0|Test 18|断言点'`
Expected: `Test0: _one 单文件计数=2` PASS；`Test0: 静态计数减定义=2` 仍 PASS；Test 18 行此刻**可能 RED**（_REAL_STATIC 因新增 1 行 assert_ 升到 486，而文档仍写 485）——**这是预期的中途态**，Task 5 收口（循 (B) 自指收敛）。其余 Test 0 子断言 PASS。

- [ ] **Step 5: Commit**

```bash
git add tests/test_doc_freshness.sh
git commit -m "feat(doc-freshness): _count_static_asserts_one per-file predicate + Test 18 DRY refactor"
```

---

### Task 2: Test 20 — per-suite 三层 drift guard（manual 模式，DEV_ONLY 三态）

**Files:**
- Modify: `tests/test_doc_freshness.sh`（Test 19 块之后、`summary`（现 :370）之前插入 Test 20）

- [ ] **Step 1: 写 RED——插入 Test 20（manual if/FAIL/PASS，0 新 assert_）**

在 `tests/test_doc_freshness.sh` 的 `summary`（现第 370 行，Task 1 后行号下移）之前插入：

```bash
# ── Test 20: per-suite 静态断言点逐套件 drift guard（design 0024 §1，Test 18 per-suite 精炼）──
# 真相源 = 逐文件静态 assert 调用点（_count_static_asserts_one，与 Test 18 同谓词）。
# 三层：① 表每行 N==静态 ② 完整性（每套件恰一行/无孤儿）③ Σ==_REAL_STATIC。
# TEST-SCENARIOS.md 是 DEV_ONLY（Test 3 范式）：缺席显式 ➖skip，绝不 cat||echo 假绿（Gotcha #18）。
# _REAL_STATIC 由上方 Test 18 计算并在作用域内（DRY 复用，勿重算）。
_TS="$DOC_DIR/TEST-SCENARIOS.md"
if [[ ! -f "$_TS" ]]; then
    echo "  ➖ Test20: TEST-SCENARIOS.md 缺席（dev-only，公开镜像已删）→ skip"
else
    _ps_drift=0
    _actual_suites=$(ls "$DOC_DIR"/tests/test_*.sh 2>/dev/null | sed 's|.*/||' | sort)
    # 表行机械解析：^| `test_X.sh` | N → "test_X.sh N"（[|] 避 ERE alternation；单引号内 ` 字面）
    _table_rows=$(grep -oE '^[|] `test_[A-Za-z0-9_]+\.sh` [|] [0-9]+' "$_TS" \
        | sed -E 's/^[|] `([^`]+)` [|] ([0-9]+).*/\1 \2/' | sort)
    _table_suites=$(echo "$_table_rows" | awk '{print $1}' | sort)
    # ② 完整性：actual ⊕ table 双向差必空
    _miss=$(comm -23 <(echo "$_actual_suites") <(echo "$_table_suites"))
    _orphan=$(comm -13 <(echo "$_actual_suites") <(echo "$_table_suites"))
    if [ -n "$_miss" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表缺套件行: $(echo $_miss | tr '\n' ' ')"
        _ps_drift=1
    fi
    if [ -n "$_orphan" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表孤儿行(套件不存在): $(echo $_orphan | tr '\n' ' ')"
        _ps_drift=1
    fi
    # ① 逐行 EXACT + ③ Σ
    _ps_sum=0
    while read -r _sfx _claim; do
        [ -z "$_sfx" ] && continue
        _real_one=$(_count_static_asserts_one "$DOC_DIR/tests/$_sfx")
        _ps_sum=$((_ps_sum + _claim))
        if [ "$_claim" != "$_real_one" ]; then
            echo "  ❌ Test20: $_sfx 表声称 '$_claim 断言点'，实际静态 $_real_one"
            _ps_drift=1
        fi
    done <<EOF
$_table_rows
EOF
    if [ "$_ps_sum" != "$_REAL_STATIC" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表 Σ=$_ps_sum ≠ 静态总数 $_REAL_STATIC"
        _ps_drift=1
    fi
    if [ "$_ps_drift" -eq 0 ]; then
        echo "  ✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致 ($_REAL_STATIC)"
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
fi
```

- [ ] **Step 2: 跑验证 RED**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep 'Test20'`
Expected: 多行 `❌ Test20: <suite> 表声称 'N 断言点'，实际静态 M`（现表是 runtime 数，~25 行漂移）+ 末 `FAIL`。证 Test 20 load-bearing 非空过。

- [ ] **Step 3: 实现** — 无（Test 20 即实现；GREEN 由 Task 5 rebaseline 表达成，TDD 中途 RED 预期）

- [ ] **Step 4: 跑验证（确认 RED 形态正确，非崩溃）**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -cE '❌ Test20:'`
Expected: 正整数（逐行漂移计数 > 0），无 `command not found`/语法错。

- [ ] **Step 5: Commit**

```bash
git add tests/test_doc_freshness.sh
git commit -m "feat(doc-freshness): Test 20 per-suite static-assert drift guard (3-layer, DEV_ONLY tri-state)"
```

---

### Task 3: bguard load-bearing 负控（c0–c4，gate-coupled + gate-中性化矩阵）

**Files:**
- Modify: `tests/test_doc_freshness_bguard.sh`（在末行 `summary`（现 :88）之前插入）

变异一律用 `awk … > t && mv t`（同既有 bguard 风格，mawk-safe，**不引入 perl**，Tacit#2/#3）。

- [ ] **Step 1: 写 RED 前置——确认 baseline pass-verdict 文案锚**

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -F '✅ Test20:'`
Expected: 当前（Task 2 后、未 rebaseline）无 pass-verdict（Test 20 RED 中）——确认文案锚 `✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致` 字面正确（c0 在 Task 5 GREEN 后才有意义，故 bguard 整体在 Task 5 后跑）。

- [ ] **Step 2: 实现——插入 c0–c4 负控块**

在 `tests/test_doc_freshness_bguard.sh` 的 `summary`（现第 88 行）之前插入：

```bash
# ════ Test 20 per-suite guard load-bearing 负控（design 0024 §4，Gotcha #25 gate-coupled）════
# 键在 gate 判决（pass-verdict 缺席 ⟺ _ps_drift 真置 1 进 FAIL），非诊断 ❌ echo。
T20_PASS="✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致"

# (c0) baseline：干净 fixture → pass-verdict 出现（反向锚：信号非环境噪声产物）
FXP0=$(mktemp -d); _mk_fx "$FXP0"
p0_out=$(DOC_DIR="$FXP0" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c0 baseline: 干净 fixture pass-verdict 出现" "$p0_out" "$T20_PASS"
rm -rf "$FXP0"

# (c1) 逐行漂移：首个表行数字→9999（机械定位首行，不手挑套件名）
FXP1=$(mktemp -d); _mk_fx "$FXP1"
awk 'BEGIN{d=0} !d && /^\| `test_[A-Za-z0-9_]+\.sh` \| [0-9]+ \|/ { sub(/\| [0-9]+ \|/,"| 9999 |"); d=1 } {print}' \
  "$FXP1/TEST-SCENARIOS.md" > "$FXP1/TS.t" && mv "$FXP1/TS.t" "$FXP1/TEST-SCENARIOS.md"
p1_out=$(DOC_DIR="$FXP1" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c1: 逐行漂移 → 精确报 9999 断言点" "$p1_out" "表声称 '9999 断言点'"
assert_not_contains "Test20 c1 gate-coupled: 漂移后 pass-verdict 不得出现" "$p1_out" "$T20_PASS"
rm -rf "$FXP1"

# (c2) 完整性：删一表行（套件仍在）→ 报缺套件行 + pass-verdict 缺席
FXP2=$(mktemp -d); _mk_fx "$FXP2"
awk '!/^\| `test_skill_metadata_budget\.sh` \|/' \
  "$FXP2/TEST-SCENARIOS.md" > "$FXP2/TS.t" && mv "$FXP2/TS.t" "$FXP2/TEST-SCENARIOS.md"
p2_out=$(DOC_DIR="$FXP2" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c2: 删表行 → 报缺套件行" "$p2_out" "表缺套件行"
assert_not_contains "Test20 c2 gate-coupled: 缺行后 pass-verdict 不得出现" "$p2_out" "$T20_PASS"
rm -rf "$FXP2"

# (c3) 孤儿行（套件不存在）→ 报孤儿 + pass-verdict 缺席
FXP3=$(mktemp -d); _mk_fx "$FXP3"
printf '| `test_ZZZ_nonexistent.sh` | 7 | 孤儿行 |\n' >> "$FXP3/TEST-SCENARIOS.md"
p3_out=$(DOC_DIR="$FXP3" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c3: 孤儿行 → 报孤儿" "$p3_out" "孤儿行(套件不存在)"
assert_not_contains "Test20 c3 gate-coupled: 孤儿后 pass-verdict 不得出现" "$p3_out" "$T20_PASS"
rm -rf "$FXP3"

# (c4) load-bearing 矩阵：gate-中性化但保留 ❌ 诊断 echo → 证负控键在 verdict 非 echo
# 注入漂移(❌ echo 必打) + 强制 Test20 收尾判定恒真(_ps_drift 旁路)；若键在 echo 会假绿，
# 键在 pass-verdict 则：中性化使 pass-verdict 出现 → 正向坐实 c1「pass-verdict 缺席」
# 与 gate 同步翻转（Gotcha #25 CRITICAL-2 直接落地）。
FXP4=$(mktemp -d); _mk_fx "$FXP4"
awk 'BEGIN{d=0} !d && /^\| `test_[A-Za-z0-9_]+\.sh` \| [0-9]+ \|/ { sub(/\| [0-9]+ \|/,"| 9999 |"); d=1 } {print}' \
  "$FXP4/TEST-SCENARIOS.md" > "$FXP4/TS.t" && mv "$FXP4/TS.t" "$FXP4/TEST-SCENARIOS.md"
awk '{ if ($0 ~ /if \[ "\$_ps_drift" -eq 0 \]; then/) print "    if [ 0 -eq 0 ]; then"; else print }' \
  "$FXP4/tests/test_doc_freshness.sh" > "$FXP4/td.t" && mv "$FXP4/td.t" "$FXP4/tests/test_doc_freshness.sh"
p4_out=$(DOC_DIR="$FXP4" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c4 前置: gate-中性化后 ❌ 诊断 echo 仍在" "$p4_out" "表声称 '9999 断言点'"
assert_contains "Test20 c4 load-bearing: gate-中性化→pass-verdict 出现(键 gate 非 echo)" "$p4_out" "$T20_PASS"
rm -rf "$FXP4"
```

同步把 `trap` 行（现第 19 行 `trap 'rm -rf "$FXB" ...' EXIT INT TERM`）追加新 fixture 变量，防中断泄漏：

```bash
trap 'rm -rf "$FXB" "$FXI" "$FXT" "$FXR" "$FXH" "$FXC1" "$FXP0" "$FXP1" "$FXP2" "$FXP3" "$FXP4" 2>/dev/null' EXIT INT TERM
```

并在文件变量初始化行（现第 18 行 `FXB=""; FXI=""; ...`）追加 `FXP0=""; FXP1=""; FXP2=""; FXP3=""; FXP4=""`。

- [ ] **Step 3: 跑验证（Task 5 前预期 RED，仅查无语法/崩溃）**

Run: `bash -n tests/test_doc_freshness_bguard.sh && echo "syntax-ok"`
Expected: `syntax-ok`（语义 GREEN 须待 Task 5 表 rebaseline 后；此刻 c0 会 RED，预期）。

- [ ] **Step 4: Commit**

```bash
git add tests/test_doc_freshness_bguard.sh
git commit -m "test(doc-freshness): Test 20 load-bearing controls c0-c4 (gate-coupled + neutralize matrix)"
```

---

### Task 4: 剔除 HANDOFF.md:37 inline per-suite 列表

**Files:**
- Modify: `HANDOFF.md:37`

- [ ] **Step 1: 实现——删 inline per-suite 段，只留 aggregate**

把 `HANDOFF.md` 第 37 行当前整行：

```
| 构建状态 | ✅ 31 套件 / 485 断言点 macOS bash 3.2 全绿；Linux mawk/POSIX-safe（容器实测见 v2.1.2 / Gotcha #15 / Decision 0016，其后未在容器重验）（lint 46/0 + tidy 53/0 + postflight 26/0 + doc-freshness 24/0 + k4-chicken-egg 1/0 + migrate-to-v2 77/0 + install 87/0 + review-loop 81/0 + xref-lint 62/0 + 19 个其他） |
```

替换为（删末尾 `（lint 46/0 … + 19 个其他）` 整段；`485` 数字本身由 Task 5 机械改成终值，本步只删 inline 列表保留 aggregate 句式）：

```
| 构建状态 | ✅ 31 套件 / 485 断言点 macOS bash 3.2 全绿；Linux mawk/POSIX-safe（容器实测见 v2.1.2 / Gotcha #15 / Decision 0016，其后未在容器重验） |
```

- [ ] **Step 2: 跑验证**

Run: `sed -n '37p' HANDOFF.md | grep -c 'lint 46/0\|19 个其他'`
Expected: `0`（inline 列表已剔除）。

- [ ] **Step 3: Commit**

```bash
git add HANDOFF.md
git commit -m "refactor(doc): cull HANDOFF.md:37 inline per-suite list, keep aggregate only (design 0024)"
```

---

### Task 5: 冻结后机械收敛 rebaseline（自指终值，循 (B) Dev Log 0058 范式）

**Files:**
- Modify: `TEST-SCENARIOS.md`（31 行 `断言数`→静态值 + 列头 + :353 header）
- Modify: `README.md` / `README_CN.md` / `HANDOFF.md` / `CONTRIBUTING.md` / `TEST-SCENARIOS.md`（aggregate `485`→终值）

**前提**：Task 1–4 全部 commit、测试码冻结。本计划自身新增 `^assert_` 行（Task 1 +1、Task 3 bguard +9）抬高静态总数 → 终值 ≈ 495（**仅 sanity 预期**；实际由下方生成器机械算定，**禁硬编码**）。

- [ ] **Step 1: 机械生成 per-suite 向量 + 终值（数字脚本生成非手敲）**

```bash
: > /tmp/ps_vec.txt; tot=0
for f in tests/test_*.sh; do
  a=$(grep -cE '^[[:space:]]*assert_' "$f" 2>/dev/null || true)
  d=$(grep -cE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' "$f" 2>/dev/null || true)
  n=$(( ${a:-0} - ${d:-0} )); tot=$((tot+n))
  echo "$(basename "$f") $n" >> /tmp/ps_vec.txt
done
FINAL=$tot; echo "FINAL_STATIC=$FINAL"; cat /tmp/ps_vec.txt
```
Expected: `FINAL_STATIC=<终值>`（≈495）+ 31 行 `<suite> <n>`。记下 `$FINAL`。

- [ ] **Step 2: 机械改写 TEST-SCENARIOS 31 行 `断言数`→静态值**

```bash
awk 'NR==FNR{v[$1]=$2;next}
     /^\| `test_[A-Za-z0-9_]+\.sh` \| [0-9]+ \|/ {
       nm=$0; sub(/^\| `/,"",nm); sub(/`.*/,"",nm);
       if (nm in v) sub(/\| [0-9]+ \|/,"| " v[nm] " |") }
     {print}' /tmp/ps_vec.txt TEST-SCENARIOS.md > TS.t && mv TS.t TEST-SCENARIOS.md
```

- [ ] **Step 3: 列头改名 + :353 header 校准（消静默改义，沿用 (B) 断言→断言点）**

`TEST-SCENARIOS.md` 现第 355 行 `| 套件 | 断言数 | 覆盖 |` 整行替换为：

```
| 套件 | 断言点（静态调用点） | 覆盖 |
```

`TEST-SCENARIOS.md` 现第 353 行 `**当前覆盖率：485 断言点 / 31 套件 / 100% 通过**…` 中 `485`→`$FINAL`（句式与 `100% 通过` 保留——run_all 全绿是另一维度事实，不与静态点冲突）。Step 4 的 aggregate 替换会一并覆盖此处。

- [ ] **Step 4: 机械替换 5 canonical doc 的 aggregate `485`→`$FINAL`（grep 谓词派生，禁手列 loci）**

```bash
for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md; do
  sed -E "s/485( *\+? *(断言点|assertion[ -]sites?))/${FINAL}\1/g" "$d" > "$d.t" && mv "$d.t" "$d"
done
```
（覆盖 README:101/197、README_CN:101/197、HANDOFF:15/37/317 + Current State、CONTRIBUTING:32、TEST-SCENARIOS:353——即 Test 18/Test 10 `_normalize` 后所扫全部 `N (断言点|assertion sites)` locus；机械谓词非手枚举，Gotcha #25 §2。）

- [ ] **Step 5: 跑验证 GREEN（全收敛）**

Run: `bash tests/run_all.sh 2>&1 | tail -3`
Expected: `All suites passed ✅`。

Run: `bash tests/test_doc_freshness.sh 2>&1 | grep -E 'Test 18|Test20|Test 15|Test 10|Test 19|Test0' | grep -c '✅'`
Expected: 全 `✅`（Test 0/10/15/16/18/19/20 + B② 全 PASS，无 ❌/➖ 非预期）。

Run: `bash tests/test_doc_freshness_bguard.sh 2>&1 | tail -2`
Expected: `All ... passed`（c0–c4 全 GREEN：c0/c4 pass-verdict 在、c1/c2/c3 gate-coupled RED 触发被正确断言）。

Run: `bash tests/test_doc_freshness_seam.sh 2>&1 | tail -1`
Expected: PASS（seam 不回归）。

- [ ] **Step 6: Commit**

```bash
git add TEST-SCENARIOS.md README.md README_CN.md HANDOFF.md CONTRIBUTING.md
git commit -m "chore(doc-freshness): rebaseline per-suite table + aggregate to static call-sites (design 0024 convergence)"
```

---

### Task 6: 多源异构终审（Gotcha #22/#24/#25 强制，§4 authoring/review 分离）

**Files:** 无代码改动（review 闭环；finding 走 TDD 修则补 commit）

- [ ] **Step 1: controller 机械对抗复现（信号非报告）**

逐条独立复现：gate-中性化矩阵（Task 3 c4 思路：强制 `_ps_drift`/`suite_drift`/`ap_drift` 旁路，断言负控仍 RED）；冻结历史 P1.2 757 / P1.1 744 散文未被本轮误改（`git log` + grep）；`_count_static_asserts` 重构数学等价（重构前后 `_REAL_STATIC` 对同一 commit 树相等）。

- [ ] **Step 2: opus code-reviewer（异构源 1，正确性 lens）**

`Task` → `pr-review-toolkit:code-reviewer`，scope = 本计划全 commit 链 diff。重点：DRY 重构等价、Test 20 三层逻辑、DEV_ONLY 三态非假绿、rebaseline 机械性。

- [ ] **Step 3: silent-failure-hunter（异构源 2，fail-open/假绿 lens）**

`Task` → `pr-review-toolkit:silent-failure-hunter`。重点：Test 20 在退化输入（空表/全 typo/`comm` 空/缺 tests dir）下是否 fail-open；bguard c0–c4 是否真 gate-coupled（非诊断 echo 假绿，Gotcha #25 CRITICAL-2 复验）；`grep -cE || true` 兜底无静默坍缩。

- [ ] **Step 4: Codex 第3源（Boss 触发，controller 不自调——诚实声明）**

`codex:adversarial-review` 是 `disable-model-invocation`：controller **无法自调**，列为 Boss 触发的剩余外部 gate（`/codex:adversarial-review --base <pre-plan-base>`）。**不伪称已跑**（claim≠fact 母题）。Boss 触发后 finding 走 TDD（RED 复现→修→GREEN）+ controller 对抗复现确认闭合。

- [ ] **Step 5: finding 闭环 + 不 push**

每独立 finding TDD 修 + 三源 re-review ✅。**全链本地 commit，不 push**（handoff git-orthogonal；§4 push 待 Boss 单独显式授权——新 context 不顺延）。Outcome 回填 Decision 0024（plan-vs-actual delta / 多源 finding / 自指终值，循 0017 惯例）。

---

## Plan Self-Review

**1. Spec coverage（对 `Handoff_Decisions/0024`）**：真相源=逐文件静态调用点 → Task 1；Test 18 DRY 重构 → Task 1；Test 20 三层（逐行/完整性/Σ）→ Task 2；DEV_ONLY 三态 Test 3 范式 → Task 2 Step 1；rebaseline 表+列头+header 机械生成 → Task 5；HANDOFF:37 剔除 → Task 4；负控 gate-coupled + gate-中性化矩阵 → Task 3（c0–c4）；loci 机械派生禁手枚举 → Task 2/Task 5 awk/grep 谓词；自指收敛冻结后机械算终值 → Task 5；多源异构终审 → Task 6；不 push → Task 6 Step 5。**无 spec 要求缺对应 task**。

**2. Placeholder scan**：无 TBD/TODO；每代码步给完整 verbatim 代码；rebaseline 终值不硬编码（生成器产出 `$FINAL`，spec「数字脚本生成非手敲」要求——这是机械可执行步骤非占位）；Decision Outcome「待回填」是 0017 既有惯例非计划占位。

**3. Type/名称一致**：`_count_static_asserts_one` 在 Task 1 定义、Task 2（Test 20）+ Task 5 生成器同签名调用；`_REAL_STATIC` Task 2 复用 Test 18 已算变量（同名）；`$FINAL` Task 5 Step 1 定义、Step 3/4 一致引用；pass-verdict 文案 `✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致` 在 Task 2 产生、Task 3 `T20_PASS` 逐字一致。一致，无漂移。

---

## Execution Handoff

Plan complete and saved to `docs/2026-05-19-per-suite-count-drift-guard-plan.md`. Two execution options:

**1. Subagent-Driven（推荐）** - 每任务 fresh subagent + 两段审（spec→quality）+ controller 任务间机械对抗，与 (B)/P1.x 同链路；最后 Task 6 多源异构终审。

**2. Inline Execution** - 本 session executing-plans，批执行带 checkpoint。

哪种？（推荐 1——guard/oracle 类 + Gotcha #25 母题，fresh context + 逐任务对抗最契合）
