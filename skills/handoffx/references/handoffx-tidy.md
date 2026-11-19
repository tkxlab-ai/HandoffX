# `/handoffx-tidy` — 整理与升级规范

启动时仅提示「🚀启动handoffX项目交接流程.」一次；宿主已显示则不重复。执行中的异常、警告、阻断和必要确认应及时正常提醒，不受常规字数或单次回复限制，不必等到结束或用户要求详情；需要确认时暂停相应操作。不得泄露凭证，正常进度不反复播报。

把已有的 `HANDOFFX.md` 整理成"干净、可扫、跟最新 template 对齐"的状态。可以在任何时候重复调用——幂等。

## 触发词

`/handoffx-tidy`、`/tidy`、`整理 handoff`、`清理一下 handoff 文档`、`升级 handoff 结构`、"`HANDOFFX.md 需要整理`"

## 核心原则（先读这段）

这是 **tidy**，不是 **rewrite**：

1. **只动结构，不动内容**。用户已写的 Dev Log body、Decision 原文、Gotcha 描述、Project Overview 等**一字不改**
2. **排序不重写**。Dev Log 按时间戳倒序 → 只是**移动条目位置**，不合并、不摘要、不润色
3. **缺失章节从 template 补骨架**。从 `<skill-path>/assets/HANDOFFX.template.md` 复制章节 header + 说明 + 占位符。**不替换**用户已填的章节
4. **缺失字段补 `—` 不编造**。比如 Dev Log 条目缺 `**验证**:`，补 `**验证**: —` 即可。**不要**从上下文猜测验证方式去填
5. **疑问先问用户**。遇到冲突（如 Gotcha 编号重复、Decision 反转旧 Decision）→ 问用户选择，不擅自改

有界召回适配不重写历史、不自动迁移：不为旧日志回填 `hx:recall`，不压缩或删减pending来凑预算，不把建议变成任务；当前TODO只认pending。recent需语义精简时先报告，由用户另行授权，不冒充结构整理。预算与旧日志降级统一见 `handoffx-recall.md`。

连续性方向区仅在write/init或获授权整理时维护；默认tidy不自动提炼、迁移或补造 `hx:continuity`。若用户授权整理，唯一块必须位于Project Overview内且≤4096 UTF-8字节，保存总目标/受益者与问题、成功标准、范围/非目标、关键约束/授权门控、有效决策原因/出处，不在别处复制可变事实；recent保留阶段目标/阶段验收、工作定位/未完成改动、验证命令/日期/范围、阻塞与未知；pending仍是唯一当前TODO事实源。当前有效关键信息不得仅留在按需资料中，不新增文件或第二份状态快照，schema 2不变。

无块旧Overview≤4096字节全文原样保留为legacy_unverified；保留边界仅到下一个围栏外 `#` / `##` 标题（不是整个主文件），内部子标题应为 `###`，同级Goals在范围外时仍报告缺口；超限非零且stdout为空，绝不整段延后。结构合法不代表语义齐全；报告缺失/冲突，不从标题/TODO猜测，也不以最新时间戳静默消解。改变目标或不可逆操作前确认；需要语义重写时另行确认范围，不伪装成默认结构整理。

违反以上任何一条 = bug。

## 执行流程

### 步骤 0：旧 layout 检测（如适用）

先执行 `<skill-path>/references/layout-gate.md` 的共享安全门；无旧布局时静默继续，不展示规则。

- 两者都没有 → 跑 `/handoffx-init`

用户不升级时，tidy 脚本遇旧版 `HANDOFF.md`（v1 单文件或 v3 旧四件套）仍会 exit 2 并打印确切的升级命令；agent 原样转述给用户后停止，不自行迁移。

- 旧版 `HANDOFF.md` 是 v1 单文件：输出的命令是 `migrate-to-v2.sh --dry-run --root <dir>` 再 `--apply`（也可显式 `bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" --apply HANDOFF.md`，该旧文件路径保留给 v1 迁移）；
- 旧四件套：输出 `/handoffx-tidy schema-upgrade`；
- 新旧并存：拒绝并点名两边，先解决冲突。

v1 迁移的详细机制（历史）见 `MIGRATION_GUIDE_v2.md`（完整发行包）§2；v3 → v4 见同文 §5，多机 / 多 CLI 的升级顺序已随 skill 安装：`references/migration-order.md`。

### 步骤 1：跑脚本做确定性整理 + 收集诊断

```bash
bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" HANDOFFX.md
```

脚本自动会：
- 压缩 > 2 连续空行为 2
- 若缺 Dev Log 锚点，在末尾补
- 补 Current State 锚点：节内还没有任何锚点行（整行是 `<!-- hx:名字 -->` 或 `<!-- /hx:名字 -->`，行尾只允许空白）时，用 `hx:recent` / `hx:done` / `hx:pending` 包住状态行、`### 最近完成`、`### 待办…`（只加锚点行、不动内容）。`hx:recent` **总会**生成：节里没有状态行时是紧跟引用行之后的空块；节里已有 `hx:done` / `hx:pending` 等块但没有 `hx:recent` 时，只在引用行之后补一个空 `hx:recent`，已有块一个字节不动——`/handoffx` 的 `block set recent` 因此总有落点。已有完整 `hx:recent` 则不动；锚点损坏（某块不是恰好一行开、一行闭且开在前）→ `❌`、不写文件、tidy exit 1，需手工修
- 规整 Dev Log 单文件 frontmatter 的 `date: …THHMM` → `THH:MM`（只动 frontmatter 区这一行；逐文件原子写，失败计数并让 tidy 以 exit 1 结束）。只认第 1 行是 `---` 且有收尾 `---` 的 frontmatter；CRLF 行尾的候选、符号链接候选报失败、不改写；扫描读不了的文件也算失败，不当作干净跳过；日志目录本身读不了 / 进不去 → `❌` 并 exit 1（目录不存在才跳过）。**日期改写的 Dev Log 不备份**（原地改写，回退靠 git）
- 改号（`detect_dup_numbers` 修复同号条目）拿不到编号锁 → `❌` 并 **exit 1 停止**，不做后面的整理
- **备份**主文件到 `HANDOFFX.md.bak`（只在主文件真有改动时创建；备份写不了 → `❌ tidy: backup failed`、exit 1，主文件不动）

脚本会**诊断**（不改）：
- 缺失的 REQUIRED / RECOMMENDED 章节
- Dev Log 条目是否乱序（应严格按时间戳倒序）
- Dev Log 条目缺必要字段（触发/改动/验证/关联）
- Dev Log 超过 50 条（提示归档）

脚本退出码：
- `0` = 无需 AI 介入（可能做了自动空行/锚点修复）
- `1` = 诊断有发现，AI 需处置
- `2` = 文件不存在

### 步骤 2：AI 逐项处置诊断结果

按脚本输出的诊断清单，用 Edit 工具修复。**每一类处置都有严格规则**：

#### 2.1 缺失 REQUIRED 章节

从 `<skill-path>/assets/HANDOFFX.template.md` 复制对应章节（`## 📦 xxx` 整段到下一个 `## `），插入到 HANDOFFX.md 合适位置（按 template 顺序）。

**不要**填入用户内容——就让章节 body 保持 template 里的占位符（`<one-liner>` / `—` / 等）。用户会后续通过 `/handoffx` 自然填入。

插入顺序严格按 template：Project Overview → Architecture → Coding Conventions → Credentials & Access → Milestones & Roadmap → Features & Modules → Current State → Known Gotchas → Open Questions → Reader Notes → Decision Log → Build / Run / Test → Testing → References & Docs Map → Development Log。

#### 2.2 缺失 RECOMMENDED 章节

**问用户要不要加**：
> 检测到缺失 RECOMMENDED 章节：{list}。要不要从 template 补骨架？(y=补 / n=跳过 / 只补某几个=列出名字)

得到肯定回答后按 2.1 同样方式补。

#### 2.3 Dev Log 条目乱序

**小心操作**——这是最容易出 bug 的一步：

1. 读 `## 📜 Development Log` 到锚点 `<!-- 🚨 AI 注意 -->` 之间的全部内容
2. 解析每个 `### YYYY-MM-DD HH:MM — title` 开头的条目块（包括其下所有内容直到下一个 `### ` 或锚点）
3. **整块移动**，不要拆开条目内部
4. 按时间戳倒序排序（新的在上）
5. 条目间保留一个 `---` 分隔符

**禁止**：合并相同日期的条目、删除条目、简化条目内容。

#### 2.4 Dev Log 条目缺字段

对脚本报告的每个条目，读条目原文：
- 若缺 `**触发**:` → 在条目适当位置补 `**触发**: —` 空行
- 缺 `**改动**:` → 补 `**改动**: —`
- 缺 `**验证**:` → 补 `**验证**: —`
- 缺 `**关联**:` → 补 `**关联**: —`

保持字段顺序 **触发 → 改动 → 验证 → 关联**。

**字段名英文别名识别**（v2.1.0+）：脚本接受 `**Trigger**`/`**Changes**`/`**Verification**`/`**Related**` 作为对应中文字段的别名。如果原条目主要用英文，补 stub 时也用英文别名（如 `**Trigger**: —`），避免把英文条目里塞中文字段名造成 split-personality。

#### 2.5 Dev Log > 50 条

跑 `bash <skill-path>/scripts/archive-devlog.sh --expect-root "<已确认项目绝对路径>" <project-root>` 自动按年归档（传带 v2 marker 的主文件也会分派到兄弟目录）。

### 步骤 3：跑后置五连检查（与 /handoffx 完全一致）

**推荐**（v2.1.0 起一行聚合，含 handoff-lint）：

```bash
bash <skill-path>/scripts/handoff-postflight.sh --expect-root "<已确认项目绝对路径>" HANDOFFX.md
```

> 位置参须是 HANDOFFX.md（postflight 取 file、由其 dirname 推项目根）；传目录（`.` / `<project-root>`）撞 `[ ! -f ]` → exit 2「file not found」先于任何检查。tidy 默认省略 `--files=`：仅当目标是 canonical `HANDOFFX.md` 且带 `<!-- HANDOFF v2 schema -->` marker 时，B① 仍自动检查主文件、`GOTCHAS.md`、存在的 `Handoffx_Decisions/INDEX.md`，仅此稳定集，不扩展扫描所有历史日志或 Decision（Decision 0019 ① 限域）。若本轮另有日志、Decision 或其它文件改动，须用 `--files=` 全部追加，与自动集去重。其它 ad-hoc/v1 目标仍仅在显式传 `--files=` 时运行 xref；显式空 CSV 或含空项 CSV 均拒绝，不因自动集存在而通过。

或单独跑（调试时定位具体哪一项）：

1. `bash scripts/scan-credentials.sh <project-root>`（目录模式扫四件套 + 归档；单文件模式只扫一个文件）
2. `bash scripts/validate-handoff.sh --readiness HANDOFFX.md`
3. `bash scripts/handoff-lint.sh HANDOFFX.md`
4. `bash scripts/rotation-reminder.sh HANDOFFX.md`
5. `bash <skill-path>/scripts/archive-devlog.sh --expect-root "<已确认项目绝对路径>" <project-root>`

三态原则同 handoffx-write：`✅ 通过` / `⚠️ 发现问题` / `❌ 失败`（脚本未找到 = exit 127，postflight 记失败、整体 exit 1，不算跳过）。

### 步骤 4：有界召回预检与回显

执行 `bash <skill-path>/scripts/handoff-runtime.sh recall ""`；失败说明已改内容和预算/读取缺口，不宣称全部通过，不全文补读或自动改历史。此写后预检不提供多文件事务或自动回滚。


```
✨ tidy 完成

自动修复：
- <列脚本做的事，如 "压缩 3 处连续空行"，"补齐锚点">

AI 处置：
- <列 AI 做的事，如 "按倒序重排 8 条 Dev Log"，"补齐 3 条 Dev Log 缺字段"，"从 template 补入 Open Questions 章节">

后置检查：
🔐 凭证扫描：✅ 通过 | ❌ 发现 | ❌ 无法扫描（exit 2）| ❌ 脚本未找到（exit 127）
📐 结构校验：✅ 通过 | ⚠️ 缺 RECOMMENDED | ❌ 缺 REQUIRED | ❌ 脚本未找到（exit 127）
🔄 轮换提醒：✅ 无到期 | ⚠️ <findings> | ❌ 脚本未找到（exit 127）
📦 归档：➖ 未触发 | ✅ 已归档 N 条 | ❌ 失败（exit 2–6）| ❌ 脚本未找到（exit 127）

原文备份：HANDOFFX.md.bak（若无改动则未创建）
```

## 禁止清单（Tidy 绝对不做的事）

- ❌ 合并 / 摘要 Dev Log 条目
- ❌ 改写 Decision Log 的 `背景 / 选项 / 选择 / 反悔代价` 内容
- ❌ 删除 Gotcha
- ❌ 重编号 Gotcha（即使有跳号）——`Gotcha #N` 在 Dev Log 里的反向引用会失效
- ❌ 删 pending 列表里的项（即使看起来过时）——让用户自己划掉
- ❌ 基于 AI 判断修改 Project Overview 文字

如果用户**明确要求**做上面任一件事（例如"请帮我摘要 Dev Log"），那是另一个命令的职责，告知用户这不属于 tidy。

## 别名

`/handoffx-tidy` / `/tidy` / `/整理 handoff` / `/清理 handoff` / `/升级 handoff` 一律按本规范执行（默认整理流程；不含 schema-upgrade）。

## schema-upgrade（显式子命令，不自动触发）

把 v2 旧四件套（旧版 HANDOFF.md / Handoff_Logs/ / Handoff_Decisions/）迁移到 handoffx schema（HANDOFFX.md / Handoffx_Logs/ / Handoffx_Decisions/；GOTCHAS.md 不变 ADR-0005 LEAVE）。仅在用户显式要求时运行；上面的默认整理流程不会调用它（自迁移属 P2.4）。

由 `tidy-handoff.sh schema-upgrade` subcommand 实现（脚本基名 `tidy-handoff.sh` LEAVE T1）：

```bash
bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" schema-upgrade --help
bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" schema-upgrade --dry-run --root <project-dir>
bash <skill-path>/scripts/tidy-handoff.sh --expect-root "<已确认项目绝对路径>" schema-upgrade --apply --root <project-dir>
```

约束：幂等 / 双平台 / 原子回滚 / root-safe（Gotcha #15）。详见 `docs/2026-05-21-p2-1-handoffx-tidy-migrator-plan.md`。
