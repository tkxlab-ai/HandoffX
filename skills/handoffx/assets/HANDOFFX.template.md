<!-- HANDOFF v2 schema -->
# <项目名> — Project Handoff

> 拿到这个文件夹，在 Claude Code 输入 `/handoffx-recall` 即可接手。
> v2.0.0 多文件布局：Dev Log / Decision Log / Gotchas 分别在 `Handoffx_Logs/` / `Handoffx_Decisions/` / `GOTCHAS.md`。

---

## 🚀 Quick Start

```bash
cd <project-root>
<install command>
<test command>
```

Claude Code 输入 `/handoffx-recall`，默认汇报项目方向、当前接手状态、完整当前待办和最近6条有界摘要；末尾「从这里继续」按停点 → 下一步 → 当前TODO排列，其后不追加内容。

| 命令 | 作用 | 写入模式 |
|------|------|----------|
| `/handoffx` | 记录当前工作 | **Dev Log 新文件** / **recent 更新、pending 保留** / **Gotchas 累积** |
| `/handoffx-recall [N]` | 当前状态 + 最近N条有界摘要（默认6） | 只读，不执行待办 |

---

## 📦 Project Overview

> Overview止于围栏外下一个 `#` / `##` 标题，内部子标题用 `###`；同级 `## Goals` 不在召回的Overview范围内，缺失须报告，不能由recall自动合并。
> 唯一continuity块是当前方向的权威区，≤4096 UTF-8字节；不在其他章节重复同一可变事实。块外仅放按需背景，当前有效关键信息不得只留在延后资料中。
> 无块的旧Overview≤4096字节须全文原样保留为legacy_unverified；更大则失败且stdout为空，绝不整段延后。结构合法不代表语义齐全，缺失/冲突写未记录/待确认，未知不等于没有。

<!-- hx:continuity -->
### 🎯 Goals（总目标、受益者与问题）
<项目要为谁解决什么问题；未记录/待确认，不从标题或TODO反推>

### 📏 成功标准（怎么判断做成了）
<项目级可核验标准及证据要求；未记录则注明>

### 🚫 范围 / Non-Goals（明确做什么、不做什么）
<纳入范围与明确非目标；未知不得猜测>

### 🔒 关键约束与授权门控
<技术/栈/目标平台、接口与数据不变量、安全、兼容性、禁止事项及必须获授权的操作/批准人；未记录则注明>

### 🧭 仍有效决策（原因与出处）
<当前适用的决策、必要原因、来源路径/编号；未记录不等于没有；历史全文按需>
<!-- /hx:continuity -->

> 空块或仅空白块会失败；非空占位仍需报告语义缺口，不能宣称内容齐全。

> 以下为按需背景与联系人，不另存当前目标、约束或决策副本；当前阶段及验收见recent，任务见pending。

### 👥 相关方 / Stakeholder
> 填明确的人；未知填 `—`。

| 硬问题 | 答案 |
|--------|------|
| 架构变更批准人 | 见continuity授权门控，不另存副本 |
| 谁是这个模块的**隐性专家**（即使不是 owner，但出了问题会去找）？ | — |
| 最后一个深度贡献者是谁？怎么联系？ | — |
| 离开后谁最可能接手这部分？他们知道这事吗？ | — |
| 项目外部依赖谁？（上游 API / 下游消费者的联系人） | — |

### 核心功能（高层，详细见 ✨ Features 章节）
- <feature 1>
- <feature 2>

---

## 🗺 Milestones & Roadmap

> 项目从开始到现在走过了哪些关键节点，接下来往哪走。
> 与 Dev Log 互补：Dev Log 是每次改动（细粒度），这里是阶段性里程碑（粗粒度）。

### ✅ 已完成（时间倒序）
| 日期 | 里程碑 | 主要交付 | 关联 Decision |
|------|--------|----------|---------------|
| YYYY-MM-DD | <M3 标题> | <交付内容> | <Decision YYYY-MM-DD> |
| YYYY-MM-DD | <M2 标题> | <...> | — |
| YYYY-MM-DD | <M1 MVP> | <...> | — |

### 🟢 当前 Milestone
<仅引用Current State的recent阶段目标/验收及pending任务标识，不另存阶段状态或TODO副本>

### 🔮 未来路线图
- **<M5>**（下个 quarter）— <标题 + 一句话>
- **<M6>**（更远）— —
- **长期愿景** — <仅作非当前承诺的背景；已生效项目方向以continuity为准>

---

## ✨ Features & Modules — 已交付全景

> Dev Log 记录"每次改了什么"，这里记录"整个项目到现在完成了什么"。
> 接手人一眼看懂项目做到哪一步。以下是格式示例；当前未完成改动/阻塞仅在recent登记，任务仅在pending登记，此处引用而不另存状态。

| 模块 | 状态 | 说明 | 主要文件 / 入口 |
|------|------|------|-----------------|
| <用户认证> | ✅ Shipped | OAuth + JWT，v1.0 上线 | `src/auth/*` |
| <账单> | 🚧 WIP | 暂停：等法务审查 | `src/billing/*` |
| <通知> | 📦 Backlog | 计划 M5 启动 | — |
| <旧版分析> | ❌ Deprecated | v2.0 后移除 | `legacy/analytics/` |

**状态图例**：✅ Shipped ｜ 🚧 WIP ｜ ⏸ Paused ｜ 📦 Backlog ｜ ❌ Deprecated / Abandoned

### 模块间依赖（可选）
```
<用户认证> → <账单>
<账单> → <通知>
```

---

## 🏗 Architecture

```
<project root>/
├── <dir>/         <说明>
```

### 核心文件
| 文件 | 说明 |
|------|------|
| <path> | <作用> |

---

## 🔑 Coding Conventions

<命名 / 测试框架 / 提交格式>

---

## 🔐 Credentials & Access

> 私钥只写路径不写原文。含凭证时务必把 `HANDOFFX.md` 排除出分享范围。

| 服务 | 位置 | 过期 |
|------|------|------|
| <service> | `memory/xxx.md` 或 env `<VAR>` | YYYY-MM-DD / — |

---

## 🖥 Server / Infra Status

> 运维类项目专用，非运维项目可删除此章节。`/handoffx` 存在此章节时会 SSH 采集。

| 服务器 | IP | 角色 |
|--------|----|----|
| <host> | <ip> | <role> |

---

> recent保存当前执行上下文，pending完整；项目方向/约束引用continuity，不复制；当前状态预算与读取规则见技能 `references/handoffx-recall.md`。未完成任务不能因不在最近6条日志中而丢失。

## 🎯 Current State

<!-- hx:recent -->
**阶段目标**: <当前阶段要达成什么；未记录则注明>
**阶段验收**: <本阶段完成标准及证据；未记录则注明>
**工作定位**: <模块 / 文件 / 入口及已知项目/工作副本位置；不为填写而运行git>
**未完成改动**: <尚未完成的改动、已知未提交/未保存状态及相关pending任务标识；未记录不代表工作区干净>
**上次停点**: <停止时的具体状态；未知则写未知>
**下一步**: <既定安排及先决条件；未记录则注明，建议另标>
**验证边界**: <命令 / 结果 / 日期 / 验证范围 / 未验证部分；用户报告注明来源，历史验证不是当前健康证明>
**阻塞与未知**: <当前阻塞 / 依赖 / 风险 / 未决问题；任务详情引用pending标识，不另建清单>
<!-- /hx:recent -->

<!-- hx:pending -->
### 待办
> 当前TODO唯一事实源；完整保留优先级、负责人、依赖、期限、阻塞/暂缓原因与用户门控。建议不当作既定任务，详情链接不能替代任务本身。
- [ ] <任务标识与动作；状态 / 负责人 / 依赖 / 门控；未知项注明>
<!-- /hx:pending -->

## 🐛 Known Gotchas

> 全部 Known Gotchas 储存在 `GOTCHAS.md`，按踩坑序号 `Gotcha #N` 累积保留。
> recall默认不展开正文；当前有效关键约束及必要原因写入continuity，当前阻塞与未知写入recent，详情由用户指定后按需读取。

共 0 条；最新：(none)

---

## 🔍 Open Questions / Mysteries

> Nonaka: 老手最重要的 tacit 知识常藏在"看到了但不懂"的地方。Gotcha 是已解问题；这里留给**未解**。
> 坦白"我不知道"比假装有答案更有价值——接手人知道哪里需要小心。当前仍影响接手的未决问题在recent保存，此处仅引用或记录非当前调查背景。

| # | 症状 / 可疑现象 | 发现日期 | 谁发现的 | 目前猜测 |
|---|---------------|---------|---------|---------|
| Q1 | <如"偶发 503，每周 1-2 次，无复现"> | YYYY-MM-DD | — | <假设或"不知道"> |

---

## 💬 Reader Notes

> Nonaka Ba（场）: 文档只有作者在写就是广播；接手人能附注就变成对话。
> 后读者（包括你自己几个月后）看到过期/可疑/有疑问的内容，直接在这里留一条。格式宽松。

- YYYY-MM-DD [name]: <这个 Gotcha 在 2026-04 被修复了，可以移除>
- YYYY-MM-DD [name]: <这个 Decision 的前提 (用户量 < 10k) 已不成立，需重审>

---

## 🧭 Decision Log

> 全部Decision储存在 `Handoffx_Decisions/`，每个权衡一文件。recall默认不展开正文；当前仍有效决策及必要原因/出处在continuity维护，历史权衡全文显式需要时按确切路径读取，不递归展开。

共 0 条；最新：`(none)`

---

## 🛠 Build / Run / Test

```bash
<install>
<build>
<test>
```

---

## 🧪 Testing — 详细测试状况

> 详细验证资料按需读；默认召回的当前验证边界写入recent。新的验证声明由runtime verification生成，执行时间未提供为unknown；交接记录时间不能代替测试发生时间。
> 诚实列出缺口比假装覆盖率高更有价值。

### 覆盖率（历史记录，当前验证边界见recent）
| 类型 | 覆盖率 | 跑测命令 | 报告位置 |
|------|--------|----------|----------|
| 单元 | <XX%> | `<cmd>` | `<path>` |
| 集成 | <XX%> | `<cmd>` | `<path>` |
| E2E | <XX%> | `<cmd>` | `<path>` |

### 测试套件清单
| 套件 | 位置 | 范围 | 最近运行 | 状态 |
|------|------|------|----------|------|
| 单元 | `tests/unit/` | 纯函数 / 业务逻辑 | YYYY-MM-DD | ✅ |
| 集成 | `tests/integration/` | DB + API | YYYY-MM-DD | ✅ |
| E2E | `tests/e2e/` | 浏览器全流程 | YYYY-MM-DD | ⚠️ 陈旧 |
| 性能 | `tests/bench/` | 基准测试 | YYYY-MM-DD | — |

### ⚠️ 已知测试缺口
> 当前验证缺口在recent，若成为既定任务，在pending登记；此处仅引用标识或保留有日期的历史证据，不另存当前事实。
- <测试缺口与相关pending任务标识；未知不编造>

### 如何新增测试
- 单元测试放 `tests/unit/`，命名约定 `<pattern>`
- 运行单个：`<cmd>`
- 观察覆盖率变化：`<cmd>`
- CI 门槛：<如 "单元 ≥ 80%，PR 触发">

---

## 📚 References & Docs Map

> 接手人的第一站——**所有**参考资料在哪里都指到这。
> 只写"在哪找"，不复制内容本身（防漂移）。

### 项目内文档
| 类型 | 位置 |
|------|------|
| README | `./README.md` |
| 变更记录 | `./CHANGELOG.md` |
| 架构图 / 设计文档 | `./docs/architecture/` |
| API 规格 | `./docs/api/` |
| ADR（架构决策记录） | `./docs/adr/` |
| 运行手册 / Runbook | `./docs/runbook/` |
| AI 规则 | `./CLAUDE.md` |
| 记忆索引 | `./memory/MEMORY.md` |

### 外部链接
| 类型 | URL |
|------|-----|
| 代码仓库 | <GitHub/GitLab URL> |
| 问题跟踪 | <Linear/Jira URL> |
| 内部 wiki | <Notion/Confluence URL> |
| 设计稿 | <Figma URL> |
| CI/CD | <Actions/Jenkins URL> |
| 监控面板 | <Grafana/Datadog URL> |
| 日志聚合 | <Loki/Sumo URL> |

### 关键第三方文档
| SDK / 服务 | 官方文档 |
|------------|----------|
| <name> | <URL> |

---

## 📜 Development Log

> 所有 Dev Log 条目储存在 `Handoffx_Logs/`，每条一文件，按 `<NNNN>-<timestamp>-<slug>.md`
> 命名。接手 → `/handoffx-recall`（最近6条有界摘要）；`/handoffx-recall 20` 仍受总预算约束。
> 新日志可在正文标题后加可选hx:recall摘要（不替代必填字段，格式见write规范）；旧长日志只返元数据，不自动回填摘要或迁移历史。

最近一条：(none)
最早一条：(none)
共 0 条

<!-- 🚨 AI 注意：v2 写入流程见 references/handoffx-write.md：
1. `bash <skill-path>/scripts/hx.sh next-number logs`（在项目根执行）
2. 写 `Handoffx_Logs/<NNNN>-<timestamp>-<slug>.md`（含 frontmatter）
3. `bash <skill-path>/scripts/hx.sh regen`（自动重写上面三行 stat）
-->
