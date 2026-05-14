# `/handoff-tidy` — 整理与升级规范

把已有的 `HANDOFF.md` 整理成"干净、可扫、跟最新 template 对齐"的状态。可以在任何时候重复调用——幂等。

## 触发词

`/handoff-tidy`、`/tidy`、`整理 handoff`、`清理一下 handoff 文档`、`升级 handoff 结构`、"`HANDOFF.md 需要整理`"

## 核心原则（先读这段）

这是 **tidy**，不是 **rewrite**：

1. **只动结构，不动内容**。用户已写的 Dev Log body、Decision 原文、Gotcha 描述、Project Overview 等**一字不改**
2. **排序不重写**。Dev Log 按时间戳倒序 → 只是**移动条目位置**，不合并、不摘要、不润色
3. **缺失章节从 template 补骨架**。从 `<skill-path>/assets/HANDOFF.template.md` 复制章节 header + 说明 + 占位符。**不替换**用户已填的章节
4. **缺失字段补 `—` 不编造**。比如 Dev Log 条目缺 `**验证**:`，补 `**验证**: —` 即可。**不要**从上下文猜测验证方式去填
5. **疑问先问用户**。遇到冲突（如 Gotcha 编号重复、Decision 反转旧 Decision）→ 问用户选择，不擅自改

违反以上任何一条 = bug。

## 执行流程

### 步骤 1：跑脚本做确定性整理 + 收集诊断

```bash
bash <skill-path>/scripts/tidy-handoff.sh HANDOFF.md
```

脚本自动会：
- 压缩 > 2 连续空行为 2
- 若缺 Dev Log 锚点，在末尾补
- **备份**到 `HANDOFF.md.bak`（只在真有改动时创建）

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

从 `<skill-path>/assets/HANDOFF.template.md` 复制对应章节（`## 📦 xxx` 整段到下一个 `## `），插入到 HANDOFF.md 合适位置（按 template 顺序）。

**不要**填入用户内容——就让章节 body 保持 template 里的占位符（`<one-liner>` / `—` / 等）。用户会后续通过 `/handoff` 自然填入。

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

#### 2.5 Dev Log > 50 条

跑 `bash <skill-path>/scripts/archive-devlog.sh HANDOFF.md` 自动归档。

### 步骤 3：跑后置四连检查（与 /handoff 完全一致）

1. `bash scripts/scan-credentials.sh HANDOFF.md`
2. `bash scripts/validate-handoff.sh --readiness HANDOFF.md`
3. `bash scripts/rotation-reminder.sh HANDOFF.md`
4. `bash scripts/archive-devlog.sh HANDOFF.md`

三态原则同 handoff-write：`✅ 通过` / `⚠️ 发现问题` / `➖ 跳过（脚本未找到）`。

### 步骤 4：回显整理结果

```
✨ tidy 完成

自动修复：
- <列脚本做的事，如 "压缩 3 处连续空行"，"补齐锚点">

AI 处置：
- <列 AI 做的事，如 "按倒序重排 8 条 Dev Log"，"补齐 3 条 Dev Log 缺字段"，"从 template 补入 Open Questions 章节">

后置检查：
🔐 凭证扫描：✅ 通过 | ❌ 发现 | ➖ 跳过
📐 结构校验：✅ 通过 | ⚠️ 缺 RECOMMENDED | ❌ 缺 REQUIRED | ➖ 跳过
🔄 轮换提醒：✅ 无到期 | ⚠️ <findings> | ➖ 跳过
📦 归档：➖ 未触发 | ✅ 已归档 N 条

原文备份：HANDOFF.md.bak（若无改动则未创建）
```

## 禁止清单（Tidy 绝对不做的事）

- ❌ 合并 / 摘要 Dev Log 条目
- ❌ 改写 Decision Log 的 `背景 / 选项 / 选择 / 反悔代价` 内容
- ❌ 删除 Gotcha
- ❌ 重编号 Gotcha（即使有跳号）——`Gotcha #N` 在 Dev Log 里的反向引用会失效
- ❌ 删 pending 列表里的项（即使看起来过时）——让用户自己划掉
- ❌ 基于 AI 判断修改 Project Overview 文字

如果用户**明确要求**做上面任一件事（例如"请帮我摘要 Dev Log"），那是另一个命令的职责，告知用户这不属于 tidy。

## 旧名兼容

`/handoff-tidy` / `/tidy` / `/tidy-handoff` / `/整理 handoff` / `/清理 handoff` / `/升级 handoff` 一律按本规范执行。
