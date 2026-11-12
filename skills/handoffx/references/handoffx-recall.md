# `/handoffx-recall` — 读取与汇报规范（v2 多文件布局）

## 概述

读取 v2 四件套（HANDOFF.md + GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/），结构化汇报项目现状，让用户（可能是刚接手的同事）快速掌握：**项目在哪一步、最近做了什么、还剩什么、哪里容易踩坑**。

> v1 单文件 HANDOFF.md（无 v2 marker + inline Dev Log 条目）：默认仍能读，但走 v1 兼容路径。建议先 `/handoffx-tidy` 迁移到 v2，recall 性能/体验更好。

## 参数：读几条 Dev Log

用户可以在命令后传一个正整数覆盖默认值：

| 输入 | 读取 Dev Log 条数 |
|------|-----------------|
| `/handoffx-recall` | **5**（默认） |
| `/handoffx-recall 3` | 3 |
| `/handoffx-recall 10` | 10 |
| `/handoffx-recall 20` | 20 |

每次调用都是**独立**的——用户第二次输入 `/handoffx-recall 10` 就是读最新 10 条，**不累加**也不记住上次的数字。若解析不出正整数，用默认 5。若用户输入 0 或负数，拒绝并回 `请给一个正整数，例如 /handoffx-recall 10`。

## 采集范围（永远 + 按 N + 按需）

**永远读（精华 + 整合知识库）**：
- `HANDOFF.md` 的 `## 📦 Project Overview` — 项目背景 / Goals / Non-Goals / Stakeholder / 核心功能
- `HANDOFF.md` 的 `## 🎯 Current State` — 最近改动区域 / 验证状态 / 待办
- `GOTCHAS.md`（整文件）— 踩过的坑（v2 已外移到 sibling 单文件，整合读取避免遗漏）

**按 N 读（事件流）**：
- `Handoff_Logs/` 最近 N 条 entry：

  ```bash
  ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -N
  ```

  对结果中的每个文件读全文（含 frontmatter 之下的 `### date — title` + 必填字段）。

**按需读（默认不读，用户要求时才读）**：
- `Handoff_Decisions/` — "为什么这样决定"。用户问到具体选择理由时：`ls Handoff_Decisions/` 看标题，按需 `cat <文件>`。全读约 10 文件 ~10K，安全区
- `HANDOFF.md` 的 `## 🏗 Architecture` — 目录结构，动手改代码前再读
- `HANDOFF.md` 的 `## 🧪 Testing` / `## 🛠 Build / Run / Test` — 要跑测试 / 构建前再读
- `HANDOFF.md` 的 `## 📚 References` / `## 🔐 Credentials` — 查外链 / 凭证时再读
- `HANDOFF.md` 的 `## 🗺 Milestones` / `## ✨ Features` — 看项目全局进度时再读
- `Handoff_Logs.archive/<year>/`（v2 yearly 归档）— 用户明确要"翻旧账"时才读
- `./memory/*.md`（若 `./memory/.sync-enabled` 存在）— 用户说"读记忆"/"load memory" 时才读正文（见 `handoffx-memory.md`）

读 `CLAUDE.md`（如存在）作为项目约定的补充。

**不读** git 状态——handoff 不依赖版本管理。

### 为什么这样切分（v2 的整合 vs 切分原则）

| 内容 | v2 存储 | recall 默认 | 理由 |
|---|---|---|---|
| 设计 / 状态 / 11 章节 | HANDOFF.md（~28K） | ✅ Project Overview + Current State + 三组 pointer stats | 主文件即"地图"，全文都该读 |
| Known Gotchas（知识库） | GOTCHAS.md（~16K） | ✅ 整文件读 | 知识库切片有遗漏风险；整合读最稳 |
| Decision Log（权衡记录） | per-file Handoff_Decisions/ | ❌ 按需 | 接手人不一定关心历史决策；问到再读 |
| Dev Log（事件流） | per-file Handoff_Logs/ | ✅ 最近 N 条 | 只关心最近活动；老条目按需翻 |

切分后单次 recall 约 7 文件 / 5-7K tokens（默认 N=5），剩余 context 留给后续对话。

### 如何精确地"只读最近 N 条"（v2）

```bash
# 1. 列出 Dev Log 文件，按文件名（含 sequential number）倒序
ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -N

# 2. 对每个返回的路径直接读全文
```

文件名规则保证排序的正确性：`<NNNN>-<timestamp>-<slug>.md` 中 `NNNN` 单调递增，`sort -r` 即按时间倒序。

### v1 兼容路径（HANDOFF.md 无 v2 marker）

若 HANDOFF.md 顶部缺 `<!-- HANDOFF v2 schema -->` 标记 + 主文件含 inline `### YYYY-MM-DD` Dev Log 条目（即 v1 layout）：

1. 提示用户 "v1 layout — recommend running `/handoffx-tidy` to migrate"
2. 走 v1 兼容读取：从主文件 `## 📜 Development Log` 段顺序数 N 条 `### date` 块；Gotchas / Decision Log 仍读主文件

继续阅读其他章节的语义不变。

## 汇报模板

第一行必须先向用户**明示读取范围**（Norman: Gulf of Evaluation）：

```
📖 本次读取：HANDOFF.md（Project Overview + Current State + 三组 pointer stats）+ GOTCHAS.md + 最近 N 条 Dev Log。
（如需 Decision Log / Architecture / Testing / 更多条，请说"看一下 XXX"或 /handoffx-recall <更大数字>）
（若存在 ./memory/.sync-enabled）🧪 项目记忆：<N> 文件可用于 ./memory/（输入"读记忆"查看正文）

## 🔄 Project Recall — <项目名>

**当前版本 / 阶段**: <从 Project Overview 提取>
**最近工作日期**: <从最新 Dev Log 文件 frontmatter date 提取>

### 最近一次工作（Handoff_Logs/ 顶部）
- 时间 / 标题（来自 frontmatter `title` 或 `### date — title` 行）
- 做了什么（摘要，别复读全文）
- 验证状态

### 待办（Pending）
- [ ] ...（来自 Current State）

### 相关已知坑
<GOTCHAS.md 里与最近改动相关的 2-3 条，按标签筛选>

### 建议下一步
<基于最近 Dev Log 推断，或询问用户目标>

（如有归档）📦 历史条目存档于 Handoff_Logs.archive/<year>/，本次未读取。
```

## 汇报原则

- **简洁**：最近一次工作 + 待办 + 2-3 条相关 Gotcha。不要复读整份 HANDOFF.md / GOTCHAS.md
- **相关性**：Gotcha 按最近改动区域（build / runtime / data / security / perf 标签）筛选，不要全部列出
- **可执行**：待办和建议下一步要具体，避免"继续开发"这种废话

## 规则

- **只读不写**——不自动触发 `/handoffx`，不改任何文件
- **不 SSH 到服务器**——实时采集是 `/handoffx` 的职责
- **不依赖版本管理**——不读 git 状态，不做 git 漂移检测
- **不主动读 Decision / 按需章节 / 归档**——用户明确要求时才读
- **汇报完等用户指令**——不主动开始改代码，哪怕 Dev Log 里写着"下一步做 X"
- **不擅自更新 HANDOFF.md**——如果用户说文档漂移了，提醒他用 `/handoffx` 主动同步

## 别名

`handoffx-recall` / `/交接回忆` / `/接手` 一律按 `/handoffx-recall` 执行。参数位置一致：`/接手 10` = `/handoffx-recall 10`。
