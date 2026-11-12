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

Claude Code 输入 `/handoffx-recall`，AI 会读取本文件，报告进度和下一步。

| 命令 | 作用 | 写入模式 |
|------|------|----------|
| `/handoffx` | AI 把当前工作追加到本文档 Dev Log | **Dev Log 追加**（倒序累积）/ **Current State 覆盖**（只留最新）/ **Known Gotchas 累积** |
| `/handoffx-recall [N]` | AI 读本文档，汇报并准备继续（默认 N=6 条最近 Dev Log） | 只读 |

---

## 📦 Project Overview

| 字段 | 值 |
|------|-----|
| 定位（一句话） | <one-liner> |
| 语言 / 栈 | <stack> |
| 目标平台 | <platforms> |
| 当前版本 | <version> |
| 项目阶段 | Pre-Alpha / Alpha / Beta / GA / Maintenance |
| 构建状态 | ✅ / ⚠️ / ❌ |

### 🎯 Goals（做什么、为什么）
> 接手人最需要理解的是**为什么做**，而不只是做了什么。
- <主要目标 1：商业或技术目标>
- <主要目标 2>

### 🚫 Non-Goals（明确不做什么）
> 接手人最常踩的坑：把不是本项目职责的事当成本职责做。**显式列出边界**。
- <non-goal 1>
- <non-goal 2>

### 📏 成功标准（怎么判断做成了）
> 尽量可度量：日活 / p99 / 覆盖率 / NPS / 转化率。
- <指标 1>
- <指标 2>

### 👥 相关方 / Stakeholder
> Nonaka: 社交知识是最容易漂移的一类 tacit knowledge。别填"产品/技术"这种空泛角色——逼自己回答下面这些硬问题。填 `—` 代表"不知道"（这本身就是一条重要情报）。

| 硬问题 | 答案 |
|--------|------|
| 谁能批准架构变更？（不是职位，是人） | — |
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
**<M4 — 标题>**
- **目标**：<想达成什么>
- **预计完成**：<日期>
- **进度**：<x%>
- **剩余关键任务**：
  - [ ] <任务 1>
  - [ ] <任务 2>

### 🔮 未来路线图
- **<M5>**（下个 quarter）— <标题 + 一句话>
- **<M6>**（更远）— <标题>
- **长期愿景** — <1-3 年的方向>

---

## ✨ Features & Modules — 已交付全景

> Dev Log 记录"每次改了什么"，这里记录"整个项目到现在完成了什么"。
> 接手人一眼看懂项目做到哪一步。

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

## 🎯 Current State

> `/handoffx` 会自动更新此章节。

<!-- hx:recent -->
**最近改动区域**: <模块 / 文件>
**验证状态**: ✅ / ⚠️ / ❌
<!-- /hx:recent -->

<!-- hx:pending -->
### 待办
- [ ] <item>
<!-- /hx:pending -->

---

## 🐛 Known Gotchas

> 全部 Known Gotchas 储存在 `GOTCHAS.md`，按踩坑序号 `Gotcha #N` 累积保留。
> recall 默认会读 `GOTCHAS.md`。直接查询 → `cat GOTCHAS.md` 或
> `grep -n '^### Gotcha' GOTCHAS.md` 看全部标题列表

共 0 条；最新：(none)

---

## 🔍 Open Questions / Mysteries

> Nonaka: 老手最重要的 tacit 知识常藏在"看到了但不懂"的地方。Gotcha 是已解问题；这里留给**未解**。
> 坦白"我不知道"比假装有答案更有价值——接手人知道哪里需要小心。

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

> 全部 Decision 储存在 `Handoffx_Decisions/`，每个权衡一文件。recall 默认不读，
> 按需 → `ls Handoffx_Decisions/` 看标题，`cat Handoffx_Decisions/<NNNN>-*.md` 读 body。
> 全读（约 10 文件 ~10K，安全区） → `cat Handoffx_Decisions/*.md`

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

> 接手人必看：**哪些测过、哪些没测、怎么跑、最近结果**。
> 诚实列出缺口比假装覆盖率高更有价值。

### 覆盖率（最近一次）
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
> 诚实。让接手人知道哪里"没保险"。
- [ ] <模块 X 无集成测试>
- [ ] <边界条件 Y 未覆盖>
- [ ] <第三方 Z 的 mock 不完整>
- [ ] <并发场景未测>

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
> 命名。接手 → `/handoffx-recall`（读最近 6 条）；翻多条 → `/handoffx-recall 20`。
> 直接查询 → `ls -1 Handoffx_Logs/ | sort -r | head -6`

最近一条：(none)
最早一条：(none)
共 0 条

<!-- 🚨 AI 注意：v2 写入流程见 references/handoffx-write.md：
1. `bash <skill-path>/scripts/hx.sh next-number logs`（在项目根执行）
2. 写 `Handoffx_Logs/<NNNN>-<timestamp>-<slug>.md`（含 frontmatter）
3. `bash <skill-path>/scripts/hx.sh regen`（自动重写上面三行 stat）
-->
