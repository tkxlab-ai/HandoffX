# `/handoffx` — 写入规范（v2 多文件布局）

启动时仅提示「🚀启动handoffX项目交接流程.」一次；宿主已显示则不重复。执行中的异常、警告、阻断和必要确认应及时正常提醒，不受常规字数或单次回复限制，不必等到结束或用户要求详情；需要确认时暂停相应操作。不得泄露凭证，普通进度不输出。

## 静默执行与定位

不输出「先读技能 / I’ll read / Now update / 开始检查」等中间说明，只发启动句和最终确认；异常及时报告。入口已给技能根则直接使用；否则根为本技能SKILL.md所在目录。读写仅用当前项目的原生文件工具；无本地Read时单独调用cat，编辑可用原生Edit/Write或shell。不要使用其他项目绑定的filesystem MCP。禁止ls -R、递归find及拼接echo分隔符的复合读取命令（zsh会对未引用的等号分隔符作命令扩展）。只读本规范，不回到入口、不查其他CLI。正常完成时最终≤120字（常规可见说明≤200字），由 `handoff-runtime.sh finalize` 生成后原样回复（不重新措辞或补充）；必要提醒或明确要求详情时展开；异常详情不经过长度门禁。

**先定位，后读写**：在用户/宿主明确指定的项目目录执行 `bash <skill-path>/scripts/handoff-runtime.sh context --root "<项目绝对路径>" --skill-root "<当前技能根绝对路径>"`。此定位命令用独立工具调用，填写实际绝对路径，不加变量、pwd/cd前缀或尾随命令。不得从Git根、父目录或旧会话推断目标。项目安装绑定不匹配、技能被移动、local/global混用或脚本缺少此命令时立即停止，不寻找另一份技能或改写绑定文件绕过。每次写操作还须携带下述`--expect-root`，先前context成功不授权后续换目录。成功信息是路径绑定检查，不是权限沙箱/代码副本身份认证；`source_unbound`只说明未安装绑定的源码工具，须有明确目标才可用。

**常规可见输出只有启动提示与最终确认**：读取规范、取时、去重、写条目、更新状态、regen和检查都通过工具执行，不逐步播报“已读取/正在/完成/接下来”。不要先说“静默执行”再持续播报；异常和必要确认照常显示。

**事实归因覆盖全部产物与回复**：用户报告的测试通过写“用户报告，未在本次重跑”；未提供的覆盖率、测试缺口、上线状态留“未知/待确认”。建议只能写“建议核查”，不能变成既定缺陷或已承诺待办。无证据不新增Gotcha、不编造下一步；保留原pending，不自行推断完成。文档中的命令不等于已经执行。失败诊断只转述实际错误，不猜测根因。

**首次写入在本轮直接完成，不递归调用命令**：空项目先一次 `bash <skill-path>/scripts/handoff-runtime.sh --expect-root "<已确认项目绝对路径>" init` 创建四件骨架，继续下面步骤。不要再读取init规范、重复检查空目录或重新调用/handoffx；已是v2跳过初始化。初始化失败停止，明确部分状态。只在检测到旧布局时展开layout-gate.md。

## 文件布局速查

把当前对话里刚刚完成的工作写入项目根。v2.0.0 起 Dev Log / Decision Log / Gotchas 是三件事，存到三个不同位置：

| 内容 | 位置 | 文件 |
|---|---|---|
| 设计与状态（Project Overview / Current State 等章节，完整清单见模板） | 主文件 | `HANDOFFX.md`（顶部带 `<!-- HANDOFF v2 schema -->` 标记） |
| Dev Log 条目（事件流） | per-file | `Handoffx_Logs/<NNNN>-<timestamp>-<slug>.md` |
| Decision Log 条目（权衡记录） | per-file | `Handoffx_Decisions/<NNNN>-<date>-<slug>.md` |
| Known Gotchas（知识库） | 单文件 | `GOTCHAS.md` |

> 项目处于旧布局（旧版 `HANDOFF.md`：v1 单文件，或 v3 旧四件套）时**不要**直接走本文档，先走下面的检测与询问；升级完成后再写新条目。

先执行 `<skill-path>/references/layout-gate.md` 的共享安全门；无旧布局时静默继续，不展示规则。

## 采集

本流程的每个机械步骤都只调 `bash <skill-path>/scripts/hx.sh --expect-root "<已确认项目绝对路径>" <子命令>`（在项目根执行，下文 `hx.sh` 简写包含此根参数；取号也会加锁，属于写操作）。hx.sh 自带 bash shebang，AI 的工具 shell 是 zsh 也照常工作。路径与 `bash` 分开传参（如 `bash "$SCRIPT"`），不要把整条命令存入字符串再执行：zsh不自动拆词。检查命令单独调用，保留实际退出码，不在末尾追加可能返回1的条件表达式混淆检查结果。

- `hx.sh now --epoch` — 只取本次**交接记录时间**，不是开发/测试发生时间，别自己推测。一次输出时间与绝对秒数：`human=YYYY-MM-DD HH:MM`（正文标题）/ `fm=YYYY-MM-DDTHH:MM`（frontmatter `date:`）/ `fn=YYYY-MM-DDTHHMM`（文件名）/ `epoch=<Unix秒数>`（新条目的可选 `epoch:` 字段，跨时区重复检测优先使用）
- 从对话上下文提取：改动的文件路径、验证方式、关联的 Decision / Gotcha
- **不读** `git branch` / `git log` / `git status`——本命令与版本管理正交

## 验证事实：来源与事件时间分开

本轮有新的测试/验证结果时，使用当前技能的纯渲染工具，不手工猜时间：

```bash
bash <skill-path>/scripts/handoff-runtime.sh verification \
  --source runner_report --command "<原验证命令>" --result "<所报告结果>" \
  --evidence "<已提供证据路径；未提供可省略>"
```

- 数量必须带原始范围：分别记录“本轮新增测试N项”和“回归共M项通过”；不能把全量回归数写成某个新增函数的测试数。recent、日志、hx:recall摘要都沿用同一口径，未提供分类数量就不推算。
- `source`按事实取`agent_observed`（本次实际执行）、`user_report`、`runner_report`（测试驱动）、`historical_record`或`unknown`；命令文本不代表执行过。
- 工具默认产生`performed_at: unknown`、`time_basis: not_provided`与`time_evidence: not_provided`。**执行时间未提供就保留unknown**；绝不以`hx.sh now`、本条frontmatter的date/epoch、当前日期、文件mtime或运行耗时反推，摘要、recent、日志正文和回复也不得这样补时间。
- 仅原材料明确给出事件时间时原样传`--performed-at`，并给`--time-basis explicit_report|execution_receipt|historical_event`与`--time-evidence "<该时间的具体出处>"`；不补未提供的时区/精度。格式校验不认证声明真实，不能编造出处凑齐字段。
- 输出的`<!-- verification:v1 -->`声明原样放入recent（当前验证事实唯一位置）及新日志`**验证**`段（该次历史记录），通过`hx.sh block set recent`更新。摘要/回复只转述来源、结果与未验证边界，不复制或改写未知时间。本轮没新验证事实则保留已有验证；recent已有结构化声明时，新日志同样保留该声明并注明“沿用历史验证，本轮未重跑”，不得改成新验证。两边原本均为旧散文时不强行补块、不迁移旧记录。
- 写后由下述finalize统一比对声明；单独诊断可执行`handoff-runtime.sh verification-check --current --require --match-file "<本轮新日志>"`。任一失败停止成功确认；已写入事实如实说明。它只以recent满足当前声明要求，并限定匹配文件为当前项目主日志目录中编号最新的直接条目（不能拿主文件自证），并比对其`**验证**`段内全部声明字段及顺序（摘要或正文其他位置引用的声明不参与比对；忽略字段排列、不比较周围散文）；不是事件真实性/新鲜度认证或多文件事务。

## 重复检测（写入前）

跑 `hx.sh dup-check --files <本次改动文件,逗号分隔>`。它计算的是一个**可计算谓词**，而非模糊相似度：

1. 取 `Handoffx_Logs/` 下文件名最大的条目（`[0-9]*.md` 排序取末位）；目录不存在或为空 → stdout `first-entry`，exit 0（本次为首条）
2. 优先读 frontmatter `epoch:`（Unix秒数）；旧条目没有该字段时读 `date:`（`YYYY-MM-DDTHH:MM`）按本地时区转换；距现在 ≥ 600 秒（10 分钟）→ stdout `ok`，exit 0
3. 两边路径集合同一规整（所以条目里的**路径须在反引号里**，否则这一步看不到它）：上一条取 `**改动**` / `**Changes**` 段（到下一个 `**字段**` 行为止）里反引号包裹的 token，本次取 `--files`；去掉 `:行号` 尾巴与结尾 `/`，只保留相对项目根**真实存在**的文件或目录（仓库名、commit SHA、分支名自然滤掉）
4. 两集合都空 → `ok`；非空且 **100% 相等** → 疑似重复，stderr 打印下面的 ⚠️ 三行，exit 3；否则 `ok`
5. 上一条路径集无法提取但本次有真实路径、日志目录存在但读不了、时间字段不可解析或 `date:` 缺失或不是 `YYYY-MM-DDTHH:MM`（如 `T2144`）→ stderr `❌ 无法判定：…`，exit 2——绝不当作 `ok`

只有 exit 3 才问用户：
```
⚠️ 检测到可能重复：
  上一条: <X> 分钟前 "<旧标题>" 改动文件: {a, b, c}
  本次:   改动文件: {a, b, c}  ← 完全相同
选 (a) **替换**（覆盖该 entry 文件）/ (b) **追加**（写新文件，声明这是不同工作） / (c) 取消？
```

exit 0 直接写入新文件，不询问；exit 2（及其它非零）把 ❌ 原因转述给用户，由用户决定是否继续。

## 写入 Dev Log entry（per-file）

1. **取下一编号**：`hx.sh next-number logs`（stdout 只有四位编号；失败时 stdout 为空、非零退出，不要自己编号）。只保护取号读取，不保证整次写入互斥；同一项目避免并行写入。有 `flock`（Linux）用 flock；否则（macOS 默认无 flock）退化为 `mkdir` 锁 `Handoffx_Logs/.lock.d`，约 5 秒拿不到锁即报错——进程崩溃遗留的 `.lock.d` 不会自动清理，需手动 `rmdir`。扫描现有 `[0-9]{4}-*.md` 取 max + 1，零填充到 4 位。同机重叠写入与 Cross-machine race（Syncthing）的重号由 `/handoffx-tidy` 的 `detect_dup_numbers` 兜底
2. **生成 slug**：`hx.sh slug "<title>"`。ASCII 标题 → lowercase + dash-join，最多 40 字符；非 ASCII 标题 → `entry-<sha1[:8]>` 回退
3. **构造文件名**：`<NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md`（时间段用 `hx.sh now` 的 `fn=`）
4. **写文件**：

```markdown
---
schema: 2
type: dev-log
date: 2026-05-08T00:10
epoch: <hx.sh now --epoch 的 epoch 值，不推测>
number: 0031
title: <一句话标题>
---

### 2026-05-08 00:10 — <一句话标题>

<!-- hx:recall -->
- 本次改变：<有证据的改变>
- 验证边界：<已验证 / 未验证；用户报告须注明>
- 本次结束停点：<本轮工作完成后的具体状态，交给下一session；不是开始本轮前的旧停点>
- 下一步：<既定安排；没有则写未记录，建议另标>
- 相关任务：<仅任务标识；当前TODO以主文件pending为准>
<!-- /hx:recall -->

**触发**: <为什么做这件事>

**改动**:
- `<文件:行号>` — <变化>
- <若走过弯路 / 失败尝试 / 被放弃的方案，写一行 `走过的弯路: <一句话 + 为什么不行>`——这类默会知识最值钱也最易丢>

**验证**:
- <本次新验证使用上面的verification声明；没有新验证写未执行。执行时间未提供则unknown，不用本条记录时间代替。>

**关联**: <Gotcha #N / Decision <NNNN>-<date>-<slug> | 无>
```

`hx:recall` 是新日志的**可选**摘要块，放在正文标题之后、必填字段之前，最多2048 UTF-8字节；无摘要可整块省略。摘要停点必须对应本轮结束后的状态，并与更新后的recent一致；本轮开始前状态仅在需要时标为“本轮开始前”，不得混为当前停点。它不替代触发/改动/验证/关联，不复制完整TODO，不新增第二份状态快照。只为本次新日志填写，不回填、改写历史或自动迁移；读取与降级预算见 `handoffx-recall.md`。

填不出写 `—`，不要编造。

**字段名接受英文别名**（v2.1.0+）：`**触发**`≡`**Trigger**` / `**改动**`≡`**Changes**` / `**验证**`≡`**Verification**` / `**关联**`≡`**Related**`。同一条目内可混用；handoff-lint 和 handoffx-tidy 都识别两种。新条目维持原条目语言风格（避免一个文件中英文混杂）。

frontmatter 之下的 `### date — title` 行 + 必填字段格式与 v1 完全一致——这是为了 grep / human-read 的兼容性。

## Decision Log 分流（per-file）

若本次对话含**显式权衡**（"考虑了 A 和 B，选了 A 因为..."），**额外**写一个 Decision 文件：

1. 取下一 Decision 编号：`hx.sh next-number decisions`
2. slug = `hx.sh slug "<决策标题>"`
3. 文件名：`Handoffx_Decisions/<NNNN>-<YYYY-MM-DD>-<slug>.md`（决策按天，不带时间）
4. 内容：

```markdown
---
schema: 2
type: decision
date: 2026-05-08
number: 0012
title: <决策标题>
---

### 2026-05-08 — <决策标题>
- **背景**: <约束>
- **选项**: A / B / C
- **选择**: A
- **拒绝 B/C 的原因**: <...>
- **反悔代价**: <低 | 中 | 高>
```

并在 Dev Log entry 的 `关联` 字段填 `Decision <NNNN>-<date>-<slug>`（用文件 stem 引用，便于 grep）。

## Known Gotchas（追加到 GOTCHAS.md）

新坑写到 `GOTCHAS.md` **底部**，编号继承（`Gotcha #N` 全项目单调递增）：

```markdown
### Gotcha #N — `[build|runtime|data|security|perf]` <一句话症状>
- **症状**: <...>
- **根因**: <...>
- **方案**: <...>
- **教训**: <...>
- **关联**: <Dev Log 文件 stem | Decision 文件 stem>
```

> Gotchas 累积保留，不清理。

## 同步主 HANDOFFX.md（最少改动）

主文件按本次证据最少改动；不新增文件或第二份状态快照，schema 2不变：

0. **Project Overview 权威方向区**：仅在本次有证据补充/改变方向或初始化时，维护唯一 `<!-- hx:continuity -->` … `<!-- /hx:continuity -->` 块（≤4096 UTF-8字节）。总目标/受益者与问题、成功标准、范围/非目标、关键技术/安全/兼容性约束与授权门控、仍有效决策及原因/出处只在该区保存当前权威表述，其他章节引用而不复制同一可变事实。Decision原文保留历史权衡；当前适用性和必要原因不能只放默认不读的Decision/GOTCHAS中。旧Overview未设块且≤4096字节可原文保留为legacy_unverified；保留边界仅到下一个围栏外 `#` / `##` 标题（不是整个主文件），内部子标题应为 `###`，同级Goals在范围外时仍报告缺口；更大则预检失败且stdout为空，绝不整段延后或静默删减。需要划分/整理时确认范围，保留非重复背景，不自动改写既有目标。
   - 缺失写“未记录/待确认”，冲突写明来源，不从标题/TODO猜目标，不按最新时间戳裁决。改变目标或不可逆操作前确认；无害任务不必一律暂停。结构合法不代表语义齐全；逐项核查方向、阶段、定位、验证与阻塞覆盖缺口。

1. **Current State 章节**：只更新本次有证据支持的最近改动和验证状态。recent保持有界，明确阶段目标与阶段验收、停点与工作定位（模块/文件/入口及已知项目/工作副本位置）、未完成改动与已知未提交/未保存状态、既定下一步、验证命令/日期/范围及未验证边界、当前阻塞/依赖/风险与未知。项目级约束与有效决策引用continuity，不另存副本；任务详情只在pending，此处用任务标识引用。pending作为当前TODO唯一事实源，完整保留旧任务及阻塞/暂缓/负责人/依赖/用户门控。已勾选行若仍有有效约束/未决事项不能整行移进done；仅在有证据分离遗留上下文后才归档纯历史。recall保留pending全块，超预算须显式整理，不用“见日志”代替；部分完成或仍含遗留说明不得整项勾选完成；只有用户明确确认完成，或明确确认取消/不再需要，并批准具体移除范围时才移出（见下节定期待办审查），明确提出新任务才添加。建议与未知事实不可改写为确定待办
   - 有 `<!-- hx:recent -->` … `<!-- /hx:recent -->` 锚点 → 先确保项目内 `wip/tmp/` 存在，用 `mktemp wip/tmp/handoff-recent.XXXXXX` 创建唯一临时文件，再写入新的最近改动 / 验证状态（使用返回的实际路径；不使用无路径的mktemp或系统临时目录）。完成后用 `unlink "<刚创建的实际路径>"` 只删除这一个临时文件，跑 `hx.sh block set recent --from <临时文件>`（只换锚点之间的内容，块外不动；exit 2 / 4 = 文件或锚点有问题、目标未改，按 ❌ 提示处理，不要退回手编整节）。`hx:done` / `hx:pending` 块由你在块内直接编辑
   - 无 `hx:recent` 锚点（老项目）→ 先跑 `bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" HANDOFFX.md` 补锚点（它总会生成 `hx:recent`；若 tidy 报「anchored outside Current State」或「anchors broken」，说明主文件里有节外/半对的锚点块，按报错点名先手工移进 Current State 或删除，tidy 此时不写文件），再 `hx.sh block set recent`；**永不**整节覆盖（会抹掉已有的 `hx:done` / `hx:pending` 块）
2. **三组 pointer stat 行**（每个 section 末尾的 1–3 行）：

   - `## 📜 Development Log` 段尾：`最近一条`/`最早一条`/`共 N 条`
   - `## 🐛 Known Gotchas` 段尾：`共 N 条；最新：<Gotcha #N 标题>`
   - `## 🧭 Decision Log` 段尾：`共 N 条；最新：<最新 Decision 文件名>`

   这三组 stat 与 `Handoffx_Decisions/INDEX.md` 由 `hx.sh regen` 自动重写；不要手编。

   不要直接source库调用regenerate函数绕过入口；调试也先用`hx.sh regen`保留本次根检查。

> 主文件**不再**承载 Dev Log 条目正文 / Decision 条目正文 / Gotcha 条目正文。所有内容存在 sibling 文件，主文件保留权威方向与当前接手状态，并负责"地图 + 指针"。

## 定期待办审查（finalize之前）

日志与recent写完后、memory同步与finalize之前，独立调用：

```bash
bash <skill-path>/scripts/handoff-runtime.sh --expect-root "<已确认项目绝对路径>" review-due --log Handoffx_Logs/<刚写的NNNN文件>
```

- 非0：报告原因与已写状态，不当作无需审查，不回滚，不发成功确认。`pending_review_due=0`：静默继续收尾。
- `pending_review_due=1`（本轮日志编号为6的倍数且pending≥3072字节；编号不等于成功交接次数）：逐条读pending，有界取证——每轮最多10条候选，只定向读主文件、日志与指定代码文件，排除`.git`与凭证来源，不跑git、测试或部署命令。分为疑似已完成、疑似不再需要（被现行Decision取代、对应功能已移除、已决定不做）、保留；证据不足、矛盾或grep无结果一律保留。混合条目（父完成而子未完成，或仍含有效门控/依赖/风险/未决事项）默认保留，建议拆分须展示拆后剩余原文。无候选则不提问，直接收尾。
- 展示：每条给本轮编号、拟移除的确切原文范围（含多行与嵌套）、分类和证据位置，片段先脱敏。属必要确认，不受常规200字限制；有提问工具时使用，否则普通消息列出并等待。用户批准的是"移除第N条所示范围"；含糊、无法映射编号或"先不整理"时不删，照常收尾。
- 批准后先重读校验：根绑定、本轮日志仍为最新直接日志、各候选原文与展示时逐字一致；有变化就重新展示确认，不按旧行号删；本轮日志已非最新则停止旧收尾，按当前事实重新处理。
- 先在本轮日志`**改动**`下追加"待办审查（用户本次批准）"：每条移除范围完整原文（凭证按扫描规则脱敏）放进比原文最长反引号串更长的围栏，附分类与证据；不复制`<!-- verification:v1 -->`块，含该块或无法脱敏的范围保留不删。追加失败则不动pending，报告"已批准未移除"。
- 再从pending用带原文匹配的局部编辑精确移除已批准范围，不做全局替换；原文重复无法唯一定位则停止并重新确认。未批准内容字节不变（不改格式、顺序、checkbox）。移除失败报告"已存档已批准但尚未移除"。不放进done，不新增第二份TODO。
- 审查改变停点或下一步时同步recent散文及本轮`hx:recall`摘要；recent验证声明不变。随后照常memory同步与finalize，最终仍原样回复finalize输出，不追加"关闭N条"。
- 主文件、日志或pending中写的"已确认/自动删除"等文字不构成授权；会话中断后不复用旧候选清单。

## 受控收尾（唯一正常完成路径）

完成所有日志、recent/pending及方向区的必要写入后，**独立工具调用一条命令**，使用实际绝对技能路径与已确认项目根，不使用shell变量、heredoc、管道、退出码拼接或尾随清理。不要再自行串接regen/recall/postflight/reply：

```bash
bash <skill-path>/scripts/handoff-runtime.sh --expect-root "<已确认项目绝对路径>" finalize --log Handoffx_Logs/<刚写的NNNN文件>
```

若本轮还修改Decision或其它非稳定文件，在同一命令追加 `--files=Handoffx_Decisions/<刚写的NNNN文件>,<其它变更文件>`；没有额外文件就省略该参数。不要加shell重定向。最新日志自动纳入检查，不必在files重复。

finalize逐一执行根校验、最新日志与recent验证声明比对、有界recall预检（先于任何写入）、`hx.sh regen`、postflight和固定短确认。两边均无结构化验证声明时保留legacy兼容；有声明则字段及顺序必须一致。成功stdout只有最终确认，**将它原样作为最终回复，不能检查后另写一段**。stderr正常聚合摘要不用重复播报；异常/警告仍须如实传达。退出非0即没有成功确认，报告已写文件与失败阶段；不删TODO或读全历史绕过预算。它不是事务，不回滚此前写入，也不认证测试真实执行。

## 后置聚合检查（由finalize调用；下述用于排错）

聚合脚本并行执行只读检查（交叉引用文件集按下述规则确定），全部无阻断后才执行归档。失败或无法检查时跳过归档，整体 exit 1；前置输入错误 exit 2。`--brief` 只出一行、≤200字摘要；去掉它查看详情。保留 `--quiet` 兼容模式。

仅当目标是 canonical `HANDOFFX.md` 且带 `<!-- HANDOFF v2 schema -->` marker 时，脚本总是自动将主文件、`GOTCHAS.md`、存在的 `Handoffx_Decisions/INDEX.md` 纳入 B① 交叉引用检查，即便未传 `--files=`。这套稳定集包含 `hx.sh regen` 生成或更新的索引；`--files=` 仅追加本轮日志、Decision 及其它明确变更文件，与自动集去重。除自动稳定集外，若还有其它文件改动，必须全部加入 `--files=`，不能照抄漏项。先核对全部输出路径，再运行 postflight；不能把“凭证扫描包含全布局”当作交叉引用检查也包含漏传文件。

`--files=` 各项相对项目根，不随当前目录变。B① 仅检查上述自动稳定集与显式追加集，不依据 git diff、不扫描所有历史日志或 Decision（Decision 0019 ① 限域）；canonical v2 的 tidy/手动 postflight 省略 `--files=` 时仅检查自动稳定集。其它 ad-hoc/v1 目标保持原契约：仅显式传 `--files=` 才运行 xref，没有自动稳定集。显式 CSV 为空或含空项（如 `--files=`、前后逗号、连续逗号）均拒绝，不能因自动文件集存在而变绿。位置参数须是目标文件本身（postflight 由它的 dirname 推项目根）；传目录会在任何检查之前 exit 2。

**调试需要时**可单独跑某个脚本定位问题。根据退出码判定三态：

| 退出码 | 含义 | 回显 |
|--------|------|------|
| 0 | 脚本运行，没有发现问题 | `✅ 通过` |
| 非0 | 默认阻断；仅 rotation 的 `--classify` exit 3 为非阻断临期提醒，exit 1 已过期、exit 2 无法检查 | `⚠️ 临近到期` 或 `❌ 未通过/无法检查` |
| 127 / ENOENT | **脚本不存在** | `❌ 脚本未找到`——postflight 记该项失败（`❌ exit=127`）并整体 exit 1；不能伪装成通过，也不算跳过 |

5 个底层脚本（`<skill-path>` = 全局 skill 安装目录，详见 SKILL.md）：

1. `bash <skill-path>/scripts/scan-credentials.sh <project-root>` — 多文件凭证扫描：HANDOFFX.md + GOTCHAS.md + Handoffx_Logs/* + Handoffx_Decisions/*（含两者的 .archive/ 子目录，递归）；非 0 **硬阻断**，要求改成 `$ENV_VAR` 或 `vault://`。表格里表头标为密码 / password / token / secret 的列同样只能放 `$VAR` / `vault://` 引用或占位符（纯数字或含非 ASCII 字符的值不算明文，如 token 用量、中文说明）；SSH 私钥只写路径
2. `bash <skill-path>/scripts/validate-handoff.sh <project-root>` — 结构检查；聚合器独立运行下一项 lint 一次，不重复内嵌 lint。单独诊断可使用 `bash <skill-path>/scripts/validate-handoff.sh --readiness <project-root>`，它内嵌lint，不要在聚合流程重复运行
3. `bash <skill-path>/scripts/handoff-lint.sh HANDOFFX.md` — v2 per-file frontmatter + body field（触发/改动/验证/关联，支持英文同义词）严格校验
4. `bash <skill-path>/scripts/rotation-reminder.sh --classify <project-root>` — 凭证轮换：只读主文件，不扫 sibling；临近30天及到期当天 exit 3（警告），已过期 exit 1（阻断），非法日期/无法检查 exit 2。未传 `--classify` 保持旧契约：任何轮换提醒 exit 1
5. `bash <skill-path>/scripts/archive-devlog.sh --expect-root "<已确认项目绝对路径>" <project-root>` — v2 改为按年归档：符合年份条件的日志移到 `Handoffx_Logs.archive/<年>/`，主目录只保留当年与上一年。未超阈值 exit 0 幂等

## 🧪 Experimental：记忆同步（opt-in）

如果存在 `./memory/.sync-enabled` 标志文件，**在finalize之前**独立执行同步；同步失败如实报告，不发正常成功确认。finalize成功后直接原样回复，不再调用工具改写文件：

```bash
bash <skill-path>/scripts/sync-memory.sh --expect-root "<已确认项目绝对路径>" sync
```

详见 `handoffx-memory.md`。

## 默认回显（不超过200字）

启动提示逐字使用「🚀启动handoffX项目交接流程.」，不另写开场白。除启动提示和最终确认外，不输出读文件、改状态、检查等普通进度。正常完成时原样转发 `handoff-runtime.sh finalize` 成功stdout（内置 `reply` 门禁≤120字）；不再自行起草或调用reply替代finalize。无异常的常规调用所有用户可见说明合计不超过200字（含标点、路径）；定期待办审查的候选清单属必要确认例外。**不贴代码、命令、entry片段、规则或逐项检查清单**。这不减少检查或记录内容。最终确认不声称开发测试通过；测试证据及未知保存在交接内容中。

失败示例：
> 日志0090已写入，但凭证检查未通过，未执行归档。请移除明文凭证后重试；需要时可展开详情。

只有用户明确说“详细/展开”才展示路径、验证证据和必要错误详情；不要回显凭证原文。不得把写入成功等同所有检查通过。仅启用且有异常时提记忆同步，正常不重复提醒实验功能、归档策略或可用命令。

## 别名

`handoffx` / `/交接` 一律按 `/handoffx` 执行，不质疑拼法。

## 首次使用（HANDOFFX.md 不存在）

执行本规范顶部的一次 `handoff-runtime.sh init` 后直接继续写首条Dev Log。不要递归调用 `/handoffx`，不要重复读取初始化模板。未知项目背景保留模板占位，不补造源码或事实。

## 旧布局项目升级路径

项目根是旧版 `HANDOFF.md`（v1.x 安装、缺 v2 marker 的单文件，或 v3 旧四件套）而没有 `HANDOFFX.md`：按本文顶部「旧布局检测 → 询问 → 标准升级」处理——先 dry-run 给用户看、问、确认后 `--apply`；用户不确认就停止，不写任何文件。升级后所有历史 Dev Log / Decision / Gotchas 会被分流到对应文件，主文件留 pointer。多机 / 多 CLI 项目的固定升级顺序见 `references/migration-order.md`。

最终正常确认必须逐字使用 `finalize` 成功输出；不要在验证字数后重新润色、扩写或追加结束语。异常仍及时如实报告。
