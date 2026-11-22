# (B) doc-freshness 计数 drift guard 硬化（设计）

> Status: DESIGN（Boss 确认 + Codex 第3源连续 4 finding 修订 2026-05-18 → writing-plans）
> 母决策: Decision 0023 选项 (B)（Codex no-ship → 延后独立 Decision）
> Boss 已确认：静态廉价 guard + URL-decode 归一 + Test 15 双语折入 + 显式改词（断言点 /
> assertion sites）消除静默改义 + **单一共享 CANONICAL_DOCS 三 guard 共用（根治分散清单各漏）**

## 1. 目标

堵 `tests/test_doc_freshness.sh` 计数 drift 结构盲点：断言数无动态 guard（Test 10 仅
拦退役号黑名单，不校验当前值 → 757 事件靠 Codex/人工兜）；Test 15（套件）三洞
（zh-only / 不解 URL → badge 双数漏 / 与断言同源）；**且 Test 10/15 doc 清单分散各漏
README_CN.md（Codex 第4源）**。一次根除「断言无 guard + URL-encoded badge + 语言变体 +
分散 doc 清单各漏」整类。P2 将 churn count loci ~100×，此为前置 de-risk
（Gotcha #20：结构护栏先于风险变更）。

## 2. 真相源语义（Codex 第3 finding 后定调）

doc `768 assertions`/`757 断言` 名义指运行时执行数（≈run_all N-passed 求和）。guard
真相源用**静态 assert 调用点计数**（廉价/无递归/无 manifest）。沿用 `assertions/断言`
字样会把 ~768 静默改义为静态 ~469、误导读者（Codex 第3源，成立）。**解决=显式改词**：
doc 一律 `N 断言点` / `N assertion sites`（号称=实际度量「assert 调用点数，结构指标」）。
metric 仍廉价静态（(B) 可行性不变），无静默语义变更。要运行时覆盖数者自跑 run_all
（不写进受 guard 的 doc，YAGNI）。与 Test 15 同哲学（`ls|wc` 结构计数，措辞即「套件」=
文件数；此处「断言点」=assert 调用点数）。

## 3. 方案

### 3.0 单一共享 CANONICAL_DOCS（根治分散清单各漏；Codex 第4 finding）

**机械派生 + 逐一裁定**（清单本身不犯手列漏/多病）：派生谓词 = 全仓 `*.md` 含
`[0-9]+ *(套件|suites|断言|assertions)|tests-[0-9]|%20(suites|assertions)`，排除
immutable history（Handoff_Logs/ Decisions/ archive）、tests/ scripts/ Release/
graphify-out/ Independent_Research/ docs/2026-* CHANGELOG GOTCHAS。结果裁定：

```
CANONICAL_DOCS = README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md
```
- 含 **README_CN.md**（Codex 第4源抓出：现 Test 10/15 清单皆漏，zh 镜像独立漂移、
  badge+plain 计数声称全 unguarded——最高风险遗漏）。
- 排除（各记因，非手猜）：`docs/GITHUB_RELEASE_SOP.md:72`（SOP 内 shell 注释**示例**
  `# 期望: 26 套件/591+`，非 live canonical；EXACT 会强制示例永等当前=错。可选另做
  doc 卫生：示例改 `<N>` 占位——**非 (B) scope，仅记**）；
  `docs/heuristic-evaluation-2026-04-29.md`（dated 冻结评估产物，同 Dev Log immutable，
  强改=Karpathy#3 改写历史）；`INSTALL.md`（不存在/无声称；Test10/15 对它的引用是
  pre-existing 死引用，非 (B) scope，Karpathy#3 提及不修）。

**三 guard（新断言点 / Test 15 / Test 10）全改用同一 `CANONICAL_DOCS` 变量**——根除
「3 份分散清单各漏」整类母题（亦 P2 单一改名 locus de-risk）。

### 3.1 共享归一 helper `_normalize_doc_for_scan <file>`

两步：① **历史块剥离**（结构 marker 非魔数）：删 HANDOFF.md `### 最近完成` 行→下一
`^## `（不含）、`## 📜 Development Log` 行→下一 `^## ` 或 EOF；其余 doc 不剥离；
marker 缺失=不剥离（保守全扫，fail-closed 同向）。② **窄 URL 解码**：仅 `%20`→空格
`%2F`→`/` `%2B`→`+`（`sed 's/%20/ /g;s/%2F/\//g;s/%2B/+/g'`），**不通用 `%XX`**
（防误伤/正则灾难 footgun）。pipeline = normalize → 双语 regex → EXACT。

### 3.2 新 Test：断言点动态 drift guard（编号=现最大+1，与 Test 15 同构）

- **真相源=静态 assert 调用点计数（排除函数定义）**：
  `STATIC = (Σ test_*.sh 中 ^[[:space:]]*assert_ 行) − (Σ 中 ^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\) 定义签名行)`
  仅 glob `test_*.sh`（排除 common.sh 定义）；锚行首（排除注释/串内）；减 3 处自定义
  helper 定义（`assert_skill_frontmatter_valid()` 等，Codex 第2 finding——定义≠断言，
  调用仍各计 1）。实测当前 = 472−3 = **469**（确定、连跑一致、无其他非调用泄漏，
  探针验证）。两次 `grep -hcE` 求差实现（POSIX/bash3.2/mawk safe）。
- **doc 措辞**：受 guard 数字一律 `N 断言点`/`N assertion sites`（prose 首现可加一次
  「（assert 调用点，结构指标）」；badge 紧→仅 `29 suites / 469 assertion sites`）。
  不再用 `N 断言`/`N assertions`。
- 对 `CANONICAL_DOCS` 每 doc 跑 normalize，提取 `([0-9]+)\+? *(断言点|assertion sites)`
  整数 N，**EXACT**：`N != STATIC` → FAIL，输出 `<file>: 声称 N 断言点，实际 STATIC`。

### 3.3 Test 15 喂归一 + 双语 + 用 CANONICAL_DOCS（Boss 决定折入；pre-existing 洞）

- doc loop 改用 `CANONICAL_DOCS`（含 README_CN）；每 doc 先 normalize；提取式
  `[0-9]+ 套件` → `[0-9]+ *(套件|suites)`（双语；badge `27%20suites`→`27 suites` 入网）。
  EXACT 逻辑不变。
- 机械溯源（§4/Gotcha#19）：Test 15 zh-only/不解 URL/漏 README_CN 皆 **pre-existing**
  （早于 (B)，Codex 第3+4源抓）；**非静默扩张**——Boss 显式决定经共享机制根治折入，
  实现后记 Decision 0023 Outcome（escalation 透明）。Test 16（`X/Y ✅` 仅 HANDOFF
  current-state，无 badge/URL/语言/多 doc 母题）**不折**（YAGNI，记因）。

### 3.4 Test 10 硬化 + 用 CANONICAL_DOCS（Boss 批准）

`sed -n '1,420p' HANDOFF.md` 魔数 + 硬编 doc 列表 → 改 `CANONICAL_DOCS` 逐 doc 跑
`_normalize_doc_for_scan`（共用历史块剥离，消除「420 失准」+「清单漏 README_CN」双母题）。
退役号 blocklist `(228|270|279) (断言|assertions)` 逻辑**保留不动**（additive，
Karpathy#3；针对旧 wording 退役旧值，与新 `断言点` 措辞正交）。

### 3.5 连带 doc 重基线（entailed；改词+改数+loci 机械派生）

迁移 loci **机械派生**（手列必漏——本稿历轮即漏验证状态行/badge/README_CN，母题
实证）：对 `CANONICAL_DOCS` 每 doc normalize 后 grep **旧** wording
`([0-9]+)\+? *(断言|assertions)` 与 `[0-9]+ *(套件|suites)` 全部命中行，逐一改：
套件→ACTUAL_SUITE_COUNT；断言数字→STATIC 且**词改 `断言点`/`assertion sites`**。
已知必含 README.md:9 + **README_CN.md:9** badge（`27%20suites`→`29`、
`653%2B%20assertions`→`469%20assertion%20sites`，同串耦合一并改）、HANDOFF
（Quick Start/构建状态/验证状态/套件表合计）、README/README_CN/CONTRIBUTING/
TEST-SCENARIOS plain。冻结历史落排除块且旧词 `断言`≠新 `断言点` regex → 双重不动
（Karpathy#3）。

## 4. 架构与隔离

单文件改 `tests/test_doc_freshness.sh`：+`CANONICAL_DOCS` 共享变量、
+`_normalize_doc_for_scan` helper、+新 Test（断言点）、Test 15 改提取式+喂归一+用
共享列表、Test 10 换 helper+用共享列表。**零碰**产品脚本/`run_all.sh`/双源 bundle
（纯 tests/）。

## 5. 测试策略（TDD 强判据，subagent-driven 可独立 loop）

1. **RED 断言点 guard**：迁移前 doc 旧词旧数 → 新 Test FAIL 精确指明 file。
2. **RED badge 双数**：stale badge(27/653+) → 归一+双语后 Test15 FAIL(套件)+新 Test
   FAIL(断言点)。
3. **GREEN**：badge+plain 全 loci 改词+改数 → 三 Test 全 PASS。
4. **负控·历史排除**（最关键）：HANDOFF `### 最近完成` 内 `744 断言`→`999 断言点`
   → 新 Test **仍 PASS**（块排除）；反向改当前 canonical 行→FAIL。两向断言。
5. **负控·README_CN 入网**（Codex 第4 finding）：README_CN.md plain `29 套件`→`99
   套件` **及** badge 篡改 → Test15+新 Test FAIL（证 README_CN 现被 guard，不再逃逸）。
6. **负控·英文 plain 入网**：README.md `29 suites`→`99 suites` → Test15 FAIL。
7. **窄解码不误伤** + Test10 退役号 228/270/279 仍被拦（硬化无回归）。
8. **负控·真相源排除定义行**（Codex 第2 finding）：加 `assert_dummy(){` 定义(无调用)
   → STATIC 不变；加其调用 → STATIC+1。两向断言「调用计、定义不计」。
9. **自指收敛**：新 Test 自身 assert 增大 STATIC → TDD 序：写 Test(RED)→代码定稿→
   算**含新 Test**终值→改词+同步全 loci(GREEN)→负控；一次收敛回算验证无二次扰动。
10. **run_all 全绿** + 双源无关；`bash -n` clean；bash3.2/mawk safe（sed/POSIX 区间）。
11. **旧词清干净收尾**：迁移后 `CANONICAL_DOCS` normalize 当前区无 `[0-9]+\+? *(断言|
   assertions)` 残留（除冻结块），证旧 wording 清净。

## 6. 关键风险与处理

- 过度 URL 解码 footgun：只解三码（§3.1 锁定）。
- 改词遗漏：§3.5 grep 旧词找全 + §5.11 收尾断言双保。
- 自指收敛：§5.9 严按序。
- Test15 折入回归面：双语+归一+README_CN 令其捕获此前漏扫合法行——本就该 guard，
  不符即真 drift（应修非豁免）；GREEN 机械同步，负控 5/6 证正确入网。
- CANONICAL_DOCS 完整性：§3.0 机械派生+逐一裁定（非手猜），排除项各记因；新增
  canonical doc 时须重派生（写入 §3.0 注：清单是派生结果非永久硬列，复审用同谓词）。
- marker 缺失（他项目复用）：helper 保守不剥离，不报错。

## 7. 范围外（YAGNI）

改名感知（P2 manifest 职责）；运行时精确数写 doc（§2 已定结构指标）；Test16 平台
`X/Y ✅`（无该母题，不折记因）；GITHUB_RELEASE_SOP 示例占位化（doc 卫生，另事，仅记）；
recall 分层/HANDOFF 瘦身/per-file 重写（性能轨另轨）；不删 Test10 blocklist、不重排
其他 Test、不动产品脚本/run_all.sh。

## 8. 关联

- Decision `0023`（(B) 来源；实现后回填 Outcome：(B) shipped + Test15 pre-existing 多洞
  + 真相源语义 + CANONICAL_DOCS 根治，经 Boss 显式逐项决定折入，全 escalation 透明）。
- **Codex stop-time 第3源连续 4 finding 触发本设计 4 轮修订**：① badge URL-encoded
  全漏 ② 真相源错计 helper 定义 ③ 静态计数静默改义仍叫 assertions ④ README_CN.md
  被 Test10/15 完全不 guard（分散清单各漏）。**Gotcha #22 多异构源母题最强实证**：
  opus/controller 自审 + 4 轮设计稿连漏，Codex 第3源连补——**brainstorming 设计稿
  （非仅代码）同样需第3异构源**；本设计自身即该 doctrine 最强案例，写入 Decision
  0023 Outcome 与 Gotcha #22 关联。
- Gotcha `#20`（结构 guard 先于风险变更）/`#22`（多异构源）。
- 既有 `test_doc_freshness.sh` Test 10（硬化）/15（折入）/16（不折，记因）。
- P2（Decision 0020）前置 de-risk，grill open#2 排序原理同向。
