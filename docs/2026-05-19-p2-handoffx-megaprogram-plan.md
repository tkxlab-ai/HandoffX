# P2 handoffx 大工程 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 把 handoff 整体改名为 handoffx 并执行破坏性四件套 schema 迁移，分 5 个独立可交付阶段，护栏先行、终阶自迁移。

**Architecture:** 方案 A——P2.0 把硬编码四件套路径抽成单一 schema 源（耦合 b/c 前置去险，行为不变）→ P2.1 造 `/handoffx-tidy` 迁移器（不碰真仓）→ P2.2 P-A allowlist 标识符改名 hard-cut → P2.3 全回归 → P2.4 Boss 门控终阶自迁移。

**Tech Stack:** Bash 3.2+ / mawk-safe；TDD（RED→GREEN）；双源 bundle byte-equal；run_all 31(→变动)套件全绿门。

**设计源**：`docs/2026-05-19-p2-handoffx-megaprogram-design.md`（§0 Boss 三问 + §1 T1–T7 不变式 + §2–§7 阶段设计）。承载决策 `Handoff_Decisions/0020`。基线 `Independent_Research/grillme/`（6 ADR + manifest）。

---

## 不变式（每阶段每任务遵守，违反即 plan 失败）

- **T2** 改名 locus ⊆ P-A manifest；**禁 blind `s/handoff/handoffx/g`**；逐 locus 精确 Edit。
- **T4** `scripts/` 与 `skills/handoff(x)/scripts/` 全程 `diff -rq` byte-equal；每任务末断言。
- **T5** 每任务末 `bash tests/run_all.sh` 0 失败；测试码自身四件套 token 改后**机械重算**静态断言点终值（`docs/2026-05-19-per-suite-count-drift-guard-plan.md` 自指收敛范式，禁手工枚举）。
- **T6** 任何 `git push` 须 Boss 逐 context 显式授权；remote 仅私有 `<private-git-host>:<private-org>/Handoff.git`；无 `--no-verify`/`push --force main`。本地 commit 频繁、可（git 正交）。
- **T7** P2.0/P2.1/P2.2/P2.4 = 三异构源评审（opus + silent-failure-hunter + Codex 第3源）；P2.3 = 两段审 + controller 机械对抗。

## 文件结构（P2.0 锁定 decomposition）

- **Create** `scripts/lib/handoff-schema.sh` — 四件套路径 + placeholder 常量唯一定义源（单一 P2 rename locus）。
- **Create** bundle 镜像 `skills/handoff/scripts/lib/handoff-schema.sh`（T4 byte-equal）。
- **Create** `tests/test_handoff_schema.sh` — load-bearing 机械 grep guard（键 gate 判决非诊断 echo，Gotcha #25）+ schema-swap fixture 解析证明。
- **Modify** `scripts/lib/handoff-xref-grammar.sh`(+bundle) — 删自有 `RL_XREF_*` 常量，改 source schema 源。
- **Modify** 耦合 c 脚本集（机械派生，见 P2.0 Task 3 谓词）— 内嵌四件套字面量改引用 schema 源。

---

## 阶段 P2.0 — 护栏 schema-agnostic（全 step 级；三源；可逆）

### Task 1：创建 schema 单源 + load-bearing guard 测试

**Files:** Create `scripts/lib/handoff-schema.sh`、`skills/handoff/scripts/lib/handoff-schema.sh`、`tests/test_handoff_schema.sh`

- [ ] **Step 1: 写失败测试** `tests/test_handoff_schema.sh`

```bash
#!/bin/bash
# P2.0: handoff-schema.sh 是四件套路径常量唯一源 + 零散落 guard。
ROOT=$(cd "$(dirname "$0")/.." && pwd); . "$ROOT/tests/common.sh"
SCHEMA="$ROOT/scripts/lib/handoff-schema.sh"
assert_file_exists "$SCHEMA"
# shellcheck disable=SC1090
. "$SCHEMA"
# common.sh API = assert_exit/assert_contains/assert_not_contains/assert_file_exists/summary
# （非 assert_equals/report——Tacit#3 用真实 API；verdict 惯用法 assert_exit name 0 "$(... )"）
assert_exit "HX_LOGS_DIR const"     0 "$([ \"$HX_LOGS_DIR\"     = Handoff_Logs ]      && echo 0 || echo 1)"
assert_exit "HX_DEC_DIR const"      0 "$([ \"$HX_DEC_DIR\"      = Handoff_Decisions ] && echo 0 || echo 1)"
assert_exit "HX_MAIN_FILE const"    0 "$([ \"$HX_MAIN_FILE\"    = HANDOFF.md ]        && echo 0 || echo 1)"
assert_exit "HX_GOTCHAS_FILE const" 0 "$([ \"$HX_GOTCHAS_FILE\" = GOTCHAS.md ]        && echo 0 || echo 1)"
# load-bearing 机械 guard（baseline-subset ratchet，Gotcha #25：机械派生禁手工枚举）。
# 现状：13 coupling-c 脚本 Task3 才迁完 → Task1 不能要求零散落（违 surgical + Step5）。
# 故 guard 断言「当前散落文件集 ⊆ 机械冻结的 baseline」——无 NEW 文件引入字面量即
# 通过；Task2/Task3 逐步从 baseline 删项，Task3 末 baseline 空 → 自动等价严格零。
# baseline 由本仓自身 grep 谓词生成并 commit（generated artifact，非手编 allowlist），
# 生成命令记于文件头注释；键 gate 判决（comm 差集为空），非诊断 echo。
BASELINE="$ROOT/tests/fixtures/p2_fourpiece_stray_baseline.txt"
assert_file_exists "$BASELINE"
gen_stray() { grep -rlE 'Handoff_Logs|Handoff_Decisions|"HANDOFF\.md"' \
  "$ROOT/scripts" --include='*.sh' 2>/dev/null \
  | sed "s#^$ROOT/##" | grep -vx 'scripts/lib/handoff-schema.sh' | LC_ALL=C sort; }
# EQUALITY 不变式（双向 diff）——subset 形态有 Gotcha #24/#25 fail-open（gen_stray 空
# 时 comm -13 空→假 GREEN；grep 静默漏文件时 subset 仍成立漏检）。equality 同时抓：
# (a) NEW leak（current 多出 baseline 没有的文件）(b) baseline 漂移/未 ratchet（current
# 少了 baseline 有的）(c) 零处理 fail-open（current 空 + baseline 非空 → diff 非空 → RED）。
# Task2/3 每 ratchet 步同 commit 内机械重生成 baseline + 迁脚本，两侧同步收缩，equality
# 始终在稳态成立（语义对齐 test_doc_freshness Test20 第2层双向 comm 范式既有先例）。
drift=$(diff <(grep -v '^#' "$BASELINE" | LC_ALL=C sort) <(gen_stray))
assert_exit "current stray set EQUALS mechanically-frozen baseline (no drift; fail-closed on both directions)" 0 \
  "$([ -z "$drift" ] && echo 0 || echo 1)"
# schema-swap：常量改 Handoffx_* 后被 source 端解析新路径（P2.2 预演，不真改名）
tmp=$(mktemp -d); cp "$SCHEMA" "$tmp/s.sh"
sed 's/Handoff_Logs/Handoffx_Logs/' "$SCHEMA" > "$tmp/s.sh"
swapped=$( . "$tmp/s.sh"; echo "$HX_LOGS_DIR" )
rm -rf "$tmp"
assert_exit "schema-swap honored (rename mechanism proven)" 0 \
  "$([ "$swapped" = "Handoffx_Logs" ] && echo 0 || echo 1)"
summary
```

- [ ] **Step 2: 跑验证失败** `bash tests/test_handoff_schema.sh` → Expected: FAIL（`handoff-schema.sh` not found）

- [ ] **Step 3: 创建 schema 源** `scripts/lib/handoff-schema.sh`

```bash
#!/bin/bash
# handoff-schema.sh — THE single source of four-piece artifact path constants.
# Sourced, never executed. ⚠ P2 RENAME LOCUS (coupling b/c, Decision 0020):
# the future handoffx mega-program renames ONLY the values here; every consumer
# (xref-grammar lib + coupling-c scripts) sources this — never re-hardcodes.
[ -n "${_HX_SCHEMA_SOURCED:-}" ] && return 0
_HX_SCHEMA_SOURCED=1
HX_LOGS_DIR="Handoff_Logs"
HX_DEC_DIR="Handoff_Decisions"
HX_MAIN_FILE="HANDOFF.md"
HX_GOTCHAS_FILE="GOTCHAS.md"
```

- [ ] **Step 4: 镜像 bundle 副本** `cp scripts/lib/handoff-schema.sh skills/handoff/scripts/lib/handoff-schema.sh`

- [ ] **Step 4b: 机械生成 baseline（generated artifact 非手编）** `tests/fixtures/p2_fourpiece_stray_baseline.txt`

```bash
# 文件头两行为生成命令记录（reviewer 可复现）；内容由本仓自身 grep 谓词派生。
ROOT=$(pwd)
{ echo "# generated: grep -rlE 'Handoff_Logs|Handoff_Decisions|\"HANDOFF.md\"' scripts --include=*.sh | drop scripts/lib/handoff-schema.sh | LC_ALL=C sort"
  echo "# P2.0 ratchet baseline — Task2 删 xref-grammar 行，Task3 删余下行至空"
  grep -rlE 'Handoff_Logs|Handoff_Decisions|"HANDOFF\.md"' scripts --include='*.sh' \
    | grep -vx 'scripts/lib/handoff-schema.sh' | LC_ALL=C sort
} > tests/fixtures/p2_fourpiece_stray_baseline.txt
```
（注：guard 的 `comm` 比对须先剥掉 `#` 注释行——见 Step 1 测试 `gen_stray`/`sort "$BASELINE"` 处用 `grep -v '^#'` 过滤注释；implementer 实现时保证 baseline 注释行不污染 comm 集合。）

- [ ] **Step 5: 跑验证通过** `bash tests/run_all.sh` → Expected: 新套件 PASS（current stray ⊆ baseline，无 NEW leak）+ 既有套件经**机械重基线**后不回归（自指收敛：套件 31→32，按 Dev Log 0058/0059 + per-suite-count-drift-guard-plan Task5 机械重算 TEST-SCENARIOS 32 行表 + 5 doc aggregate，禁手工枚举）

- [ ] **Step 6: commit**（本地，T6 不 push）

```bash
git add scripts/lib/handoff-schema.sh skills/handoff/scripts/lib/handoff-schema.sh \
  tests/test_handoff_schema.sh tests/fixtures/p2_fourpiece_stray_baseline.txt \
  TEST-SCENARIOS.md HANDOFF.md README.md README_CN.md CONTRIBUTING.md
git commit -m "feat(p2.0): single-source four-piece schema constants + load-bearing baseline-ratchet guard"
```
（git add 仅含实际被机械重基线改动的文件——以 `git status` 实际为准，勿盲加未改文件）

### Task 2：grammar lib 改 source schema 源（耦合 b 核心）

**Files:** Modify `scripts/lib/handoff-xref-grammar.sh`、bundle 镜像

- [ ] **Step 1: 写 swap-follow RED 断言**：在 `tests/test_handoff_schema.sh` `summary` 前加（真实 API；值偶同会假绿，故必须 swap-follow 而非等值比对——子壳内 swap schema 再 source grammar lib，断言 `RL_XREF_LOGS_DIR` 跟随到 `Handoffx_Logs`）

```bash
gl_follow=$( cd "$ROOT"; tmp2=$(mktemp -d)
  sed 's/Handoff_Logs/Handoffx_Logs/' scripts/lib/handoff-schema.sh > "$tmp2/handoff-schema.sh"
  cp scripts/lib/handoff-xref-grammar.sh "$tmp2/g.sh"
  ( . "$tmp2/handoff-schema.sh"; . "$tmp2/g.sh"; echo "$RL_XREF_LOGS_DIR" ); rm -rf "$tmp2" )
assert_exit "grammar lib derives four-piece path from schema (swap-follow)" 0 \
  "$([ \"$gl_follow\" = Handoffx_Logs ] && echo 0 || echo 1)"
```
（注：测试里 grammar lib 的相对 source 路径——见 Step 3 用 `BASH_SOURCE` dirname——决定 `$tmp2` 里需同放 `handoff-schema.sh`；implementer 按 Step 3 实际 source 写法对齐 fixture 布局，确保 RED 真因是"grammar lib 不跟随"非"路径错"）

- [ ] **Step 2: 跑验证失败** `bash tests/test_handoff_schema.sh` → Expected: FAIL（grammar lib 现自带 `RL_XREF_LOGS_DIR="Handoff_Logs"` 硬编码，不跟随 swap 后的 schema → `gl_follow=Handoff_Logs≠Handoffx_Logs`）

- [ ] **Step 3: 最小实现**：`handoff-xref-grammar.sh` 删 line 15-18 `RL_XREF_*` 三常量，替换为：

```bash
# Four-piece target dirs/files — derived from the single schema source
# (P2.0 coupling-b: ONE rename locus). Do NOT re-hardcode here.
. "$(dirname "${BASH_SOURCE[0]}")/handoff-schema.sh"
RL_XREF_LOGS_DIR="$HX_LOGS_DIR"
RL_XREF_DEC_DIR="$HX_DEC_DIR"
RL_XREF_GOTCHAS_FILE="$HX_GOTCHAS_FILE"
```

  同步 bundle 镜像（T4）。`RL_PLACEHOLDER_ALLOWLIST` 内 `HANDOFF.md` + line 98 CANONICAL 检测的 `[ "$base" = "HANDOFF.md" ]` 改用 `"$HX_MAIN_FILE"`。

- [ ] **Step 3b: ratchet baseline**：xref-grammar.sh 现 source schema、不再自带四件套字面量 → 从 gen_stray 输出消失。机械重生成 baseline（同 Task1 Step4b 命令）确认 `scripts/lib/handoff-xref-grammar.sh` 行已自然消失（**机械重生成非手删**——禁手编 allowlist，Gotcha #25）；`git diff tests/fixtures/p2_fourpiece_stray_baseline.txt` 应只少这一行。

- [ ] **Step 4: 跑验证通过** `bash tests/run_all.sh` → Expected: 全绿（B① 行为 byte-equal——常量值未变；swap-follow 断言转 GREEN；current stray 仍 ⊆ 新 baseline 无 NEW leak）+ `diff -rq scripts/lib skills/handoff/scripts/lib` 空 + 自指收敛若 assert 数变则机械重基线

- [ ] **Step 5: commit** `git add -A && git commit -m "refactor(p2.0): xref-grammar lib derives four-piece paths from schema source (coupling b) + baseline ratchet"`（含 `tests/fixtures/p2_fourpiece_stray_baseline.txt` 少一行 + 任何机械重基线文件）

### Task 3：耦合 c 脚本机械派生收口（禁手工枚举）

**Files:** Modify 耦合 c 脚本集

- [ ] **Step 1: 机械派生 manifest**（禁手工挑，Gotcha #25）：

```bash
grep -rlE 'Handoff_Logs|Handoff_Decisions|HANDOFF\.md' scripts/ --include='*.sh' \
  | grep -vE 'lib/handoff-(schema|xref-grammar)\.sh' | sort > /tmp/p2_coupling_c.manifest
```

  写入设计 doc §7 引用；逐脚本：顶部 `. "<lib path>/handoff-schema.sh"`，内嵌 `Handoff_Logs`/`Handoff_Decisions`/`HANDOFF.md` 字面量改 `$HX_LOGS_DIR`/`$HX_DEC_DIR`/`$HX_MAIN_FILE`（注释/Why 散文中的字面量 LEAVE——仅可执行路径字面量 RENAME；逐 locus 判定，禁 sed 全替）。

- [ ] **Step 2: 逐脚本迁移 + 同步 ratchet baseline**：按 manifest 逐脚本改 source schema 源；每改完一个脚本，**机械重生成** baseline（同 Task1 Step4b 命令，非手删行）——该脚本自然从 gen_stray 与 baseline 双双消失，guard `comm` 始终保持 subset-clean（无 NEW leak），run_all 不变 RED↔GREEN 抖动。13 脚本含 scan-credentials/release-* 安全脚本，逐一谨慎，行为 byte-equal，双源同步。

- [ ] **Step 3: 收敛至空 baseline = 严格零等价**：全 manifest 迁完后机械重生成 baseline → 应仅剩注释行（零数据行）。此刻 `gen_stray` 输出为空，`comm` 差集恒空 → guard 等价于"全 scripts 零散落严格断言"（无需改 guard 逻辑——baseline 空即自动收紧，这是 ratchet 设计意图）。

- [ ] **Step 4: 跑验证通过** `bash tests/run_all.sh` 全绿 + `diff -rq` 双源空 + baseline 零数据行 + 自指收敛机械重基线（若 assert 数变）

- [ ] **Step 5: commit** `git commit -am "refactor(p2.0): coupling-c scripts source schema (mechanically-derived manifest, zero stray)"`

### Task 4：P2.0 三异构源评审 + 阶段收口

- [ ] **Step 1:** controller 机械对抗——schema-swap 全链实测（临时 swap → run_all → B① 对 Handoffx_* fixture clean → 还原），证耦合 b/c 端到端吸收
- [ ] **Step 2:** 三源审（§4 authoring/review 分离，不同 context）：opus（正确性/scope）+ silent-failure-hunter（guard 自身假绿/gate-中性化变异，Gotcha #25）+ Codex 第3源（Boss 触发，挑战 schema-源 approach/假设）
- [ ] **Step 3:** 每 finding TDD 闭 + controller 独立复现；run_all 全绿 + 自指收敛终值机械重算
- [ ] **Step 4:** P2.0 收口报告 → **暂停等 Boss**：是否授权 commit/push（T6）+ 是否进 P2.1

---

## 阶段 P2.1 — `/handoffx-tidy` schema 迁移器（里程碑级；三源；可逆）

> Step 级 plan 在 P2.0 ship 后单独 author（依赖 P2.0 schema 源 API；现写 = 投机，违 YAGNI/Karpathy#2 / Decision 0020 per-phase plan+reviewer）。

- **交付**：`tidy-handoff.sh`（LEAVE 基名）overload `/handoffx-tidy`；旧四件套→handoffx schema；改写内部 xref（schema 源 + B① 文法驱动，有界枚举）；`GOTCHAS.md` 不动。
- **契约**：幂等 / 双平台(bash3.2+mawk) / 原子(`.partial`+`assert_dest_clear`+回滚) / root-safe(Gotcha #15 EUID=0 skip 镜像 B7-a) / 有测试。
- **测试**：合成 fixture + **真仓四件套拷贝快照**（Gotcha #20 真产物 dogfood，对拷贝非 live）+ 原子回滚负控（注入中途失败断完整回退）。
- **Exit**：run_all 全绿 + 三源闭 + 迁移器对拷贝快照证幂等；**暂停等 Boss** 进 P2.2。

## 阶段 P2.2 — 标识符 + scope-edge 改名 hard-cut（里程碑级；三源；breaking）

> Step 级 plan 在 P2.1 ship 后 author（精确 loci 依赖 P2.0/P2.1 产出 + P-A 逐 locus 确认）。

- **Loci**（P-A allowlist 子集，逐 locus Edit 禁 blind sed）：SKILL.md `name:` / skill 目录 `skills/handoff/`→`skills/handoffx/` / `command-shims/`+`references/` 基名 / install.sh 字面量+Codex `$alias`+`skill:`+sweep glob / 品牌→`HandoffX` / `.skill` 产物 / gitx 流水线 / 项目根目录名。脚本 `handoff-` 基名 LEAVE（T1 不对称有意）。
- **产物**：变更 manifest（reviewer 逐行 diff）+ 邻接陷阱 fixture。hard-cut 旧 `/handoff*` 停解析无 shim。
- **Exit**：run_all 全绿（工具 handoffx 但仍产 Handoff_*）+ 三源闭；**暂停等 Boss** 进 P2.3。

## 阶段 P2.3 — 全回归 + 不变式核验（里程碑级；两段审+controller；验证）

- run_all 全绿 + 双源 byte-equal + 自指收敛机械重算 + install.sh 端到端跨 CLI（Claude/OpenCode/Codex 改名 skill 注册成功、旧名彻底消失，Gotcha #16 真机 probe）。
- **Exit**：两段审+controller 闭；**暂停等 Boss** 进 P2.4。

## 阶段 P2.4 — 终阶自迁移（里程碑级；三源；Boss 执行门，不可豁免）

- **执行前门**（§4/Q3/T6 非可豁免）：对 live 仓新鲜拷贝跑 P2.1 迁移器 + 三源审其行为 + **Boss 明文执行授权**（controller 不从任何措辞推断）。
- **执行**：迁移器对本仓真迁——`HANDOFF.md`→`HANDOFFX.md`+59 logs+24 decisions+全历史 xref 重指。
- **执行后**：run_all 全绿(迁移后仓) + B① 对新 schema clean（端到端证 P2.0 耦合 b 吸收）+ postflight 全绿 + pointer 重生对 `Handoffx_*`。
- **回滚**：私有仓 git 可回退（规模极大）+ 迁移器原子兜底。**P2 收口；公开镜像 = Q2 延后独立 Boss 门控发版，非 P2**。

---

## Self-Review

**1. Spec coverage**：design §1 T1-T7 → 不变式节全覆盖；§2 P2.0 三组件 → P2.0 Task1(组件1/3)+Task2(组件1 grammar)+Task3(组件2)+Task4(评审)；§3-§6 → P2.1-P2.4 里程碑节；耦合(a)已解/(b)P2.0 T2+T4/(c)P2.0 T3/(d)已解 → §7 覆盖。无遗漏 spec 项。
**2. Placeholder scan**：P2.0 全 step 含真实代码块/命令/期望；P2.1-P2.4 里程碑级是**有意 per-phase 延后**（Decision 0020 明文 per-phase plan+reviewer + Karpathy#2 反投机，非占位失败）——已显式标注理由。
**3. Type consistency**：常量名 `HX_LOGS_DIR`/`HX_DEC_DIR`/`HX_MAIN_FILE`/`HX_GOTCHAS_FILE` 全 plan 一致；`RL_XREF_*` 沿用既有 grammar lib 名；`test_handoff_schema.sh` 跨 Task1-3 同文件递进。
**4. 修复**：Task2 Step2 修正——原 schema-swap 断言因常量值偶同会假绿，已改为 swap-follow 真 RED（plan 内联修正，符 self-review「fix inline」）。
