# Handoff — Claude Code 项目交接系统

> 把分散在对话历史、个人记忆、私有 AI 缓存里的项目上下文，凝结成一份纯 markdown 的 `HANDOFF.md` + 三个 sibling（GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/）。
> 同事拿到文件夹就能 10 分钟内接手，**不依赖 AI 对话历史、不依赖 git**。

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

> **v2.0.0 breaking change**：v1 单文件 HANDOFF.md 在大型项目实测涨到 121K+，吃掉 47% 模型上下文窗口。v2 拆成"主文件 + GOTCHAS.md 知识库 + 两个 per-file 目录"四件套，主文件压到 ~28K。从 v1 升级：项目根跑 `/handoff-tidy`——检测到 v1 layout 会提示是否迁移，原子迁移失败自动回滚。详见 [`MIGRATION_GUIDE_v2.md`](./MIGRATION_GUIDE_v2.md)。

---

## 📖 目录

- [1. 为什么需要（问题）](#1-为什么需要问题)
- [2. 设计哲学（Philosophy）](#2-设计哲学philosophy)
- [3. 逻辑结构（Logical Model）](#3-逻辑结构logical-model)
- [4. 工作原理（How It Works）](#4-工作原理how-it-works)
- [5. 命令说明](#5-命令说明)
- [🧪 Experimental：`/handoff-memory`（记忆跟随项目走）](#-experimentalhandoff-memory记忆跟随项目走)
- [6. 安装 / 升级 / 卸载](#6-安装--升级--卸载)
- [7. 目录结构](#7-目录结构)
- [8. 许可与贡献](#8-许可与贡献)

---

## 1. 为什么需要（问题）

软件工程里最难传承的不是代码，而是**默会知识**（tacit knowledge）：为什么这样选、哪里踩过坑、当前在哪一步、谁是隐性专家、哪些看似可做但故意不做。

这些信息通常藏在几个不可靠的地方：

| 藏匿位置 | 致命缺陷 |
|---------|---------|
| AI 对话历史 | 私有、易丢、跨工具不兼容（Cursor 看不到 Claude 的历史） |
| Notion / Confluence | 常年漂移，和代码脱节；一年后没人敢信 |
| Git commit message | 碎片化、只讲 What 不讲 Why |
| 开发者大脑 | 离职就没了，出差两周就开始模糊 |

**Handoff 用一份强制结构的 markdown 替代这些**。`HANDOFF.md` 常驻项目根，和代码一起演化，对任何 AI 工具（Claude、Cursor、Windsurf、Copilot）都透明，**真人也能直接读**。

---

## 2. 设计哲学（Philosophy）

本技能的设计通过了三位顶级专家的审查，每条哲学直接落到代码里：

### Don Norman — *Design of Everyday Things*

> "If users can't tell what your system did, it doesn't matter that it worked."

- **Gulf of Evaluation**：每个写入操作都回显"我做了什么"、"检查结果是什么"，不让用户猜
- **Gulf of Execution**：命令名本身就是行为（`/handoff` = 写、`/handoff-recall` = 读、`/handoff-tidy` = 整理），不需要阅读手册
- **Feedback**：后置检查用 `✅ 通过` / `⚠️ 发现` / `➖ 跳过（脚本未找到）`**三态**，绝不把"跳过"伪装成"通过"

### Edsger Dijkstra — *A Discipline of Programming*

> "Program testing can be used to show the presence of bugs, but never to show their absence."

- **Invariants over conventions**：能用可计算谓词就不用模糊判断（如"重复检测"改为"改动文件集合精确相等 + 10 分钟窗口"，不依赖 LLM 判断相似度）
- **Atomic commits**：`archive-devlog.sh` 先写新归档 + 完整性检查，再原子 mv 主文件——中间断电也不会丢数据
- **Separation of concerns**：Core / Init / Labs 分层，每个入口只做一件明确的事；可独立测试、可组合

### Ikujiro Nonaka — *The Knowledge-Creating Company*（SECI 模型）

> "The essence of creating knowledge is the conversion of tacit knowledge into explicit knowledge."

- **Externalization（tacit → explicit）**：Decision Log 强制 `背景 / 选项 A/B/C / 选择 / 拒绝原因 / 反悔代价` 六字段
- **Ba（场域）**：`Reader Notes` 章节让后读者能回填 `YYYY-MM-DD [name]: 这条 Decision 的假设不成立了` —— 文档从广播变对话
- **Respect for uncertainty**：`Open Questions / Mysteries` 章节专门承接"看到但不懂"的未解知识；`填不出写 —，不要编造`是硬规则
- **Tidy 不动内容**：`/handoff-tidy` 可以重排、补骨架、补缺字段为 `—`，**但不合并、不摘要、不润色**用户已填的 Dev Log / Decision / Gotcha 原文 —— 默会知识不能被 AI 改写

---

## 3. 逻辑结构（Logical Model）

### 数据分层（最关键的不变量）

HANDOFF.md 里的每一段信息都在一个明确的象限里：

| 信息类型 | 章节 | 时间维度 | 读写模式 |
|---------|------|---------|---------|
| **项目背景**（why the project exists）| Project Overview / Milestones / Features | 低频演化 | 手动写、少改 |
| **当前状态**（where are we now）| Current State | 每次 `/handoff` 都刷新 | **覆盖**（只留最新） |
| **工作流水**（what happened）| Development Log | 严格倒序追加 | **追加**（永不覆盖） |
| **决策理由**（why we chose A）| Decision Log | 发生权衡时追加 | **追加** |
| **踩过的坑**（tacit traps）| Known Gotchas | 遇到时追加，编号稳定 | **追加**（不重编号）|
| **未解之谜**（unknown territory）| Open Questions | 观察到时追加 | **追加** |
| **后读者反馈**（dialogue）| Reader Notes | 任何读者都可补注 | **追加** |
| **凭证 / 参考 / 约定** | Credentials / References / Conventions | 低频 | 手动 |

### Core / Init / Labs 对应的认知活动

```
/handoff         → 把刚完成的工作「外化」为 Dev Log 条目（Nonaka: Externalization）
/handoff-recall  → 让新接手人「内化」他人留下的知识（Nonaka: Internalization）
/handoff-tidy    → 让累积的信息「再组织化」为清晰结构（Norman: 减少认知负荷）
/handoff-init    → 低负担启动最小可用交接
/handoff-memory  → Labs：显式 opt-in 后迁移本地经验条目
```

### 后置安全四连（每次写入都跑）

```
scan-credentials.sh  → 阻断明文凭证写入（硬阻断）
validate-handoff.sh  → 结构完整性检查（REQUIRED fail / RECOMMENDED warn）
rotation-reminder.sh → 凭证到期预警（已过期 / 7d / 30d）
archive-devlog.sh    → > 50 条时原子归档（保持主文件可读）
```

---

## 4. 工作原理（How It Works）

### v2.0.0 文件布局（四件套）

v2 起 HANDOFF.md 不再是单文件——为了避免大型项目主文件膨胀到几百 K 占满 LLM 上下文窗口，拆成四件套：

```
<project root>/
├── HANDOFF.md                顶部 <!-- HANDOFF v2 schema --> 标记
│                             含 11 个设计章节（Project Overview / Architecture / 等）
│                             + Dev Log / Decision / Gotchas 三组 pointer stat（每组 1-3 行）
├── GOTCHAS.md                所有 Known Gotchas（单文件知识库；recall 整合读取）
├── Handoff_Logs/             Dev Log per-file
│   └── <NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md
└── Handoff_Decisions/        Decision Log per-file
    └── <NNNN>-<YYYY-MM-DD>-<slug>.md
```

**主文件 HANDOFF.md 章节**（共 11 个 `##` 章节，4 REQUIRED / 7 RECOMMENDED）：

```
📦 Project Overview          定位 / Goals / Non-Goals / 硬提问 Stakeholder
🏗 Architecture              目录结构 + 核心文件（热区）
🔑 Coding Conventions        命名 / 测试 / 提交规范
🔐 Credentials & Access      凭证引用（只写路径，绝不写原文）
🗺 Milestones & Roadmap      已完成 + 当前阶段 + 未来路线
✨ Features & Modules         全景表（Shipped / WIP / Paused / Deprecated）
🎯 Current State             最近改动区域 + 待办              ← 覆盖写
🐛 Known Gotchas             pointer → GOTCHAS.md
🧭 Decision Log              pointer → Handoff_Decisions/
🛠 Build / Run / Test        命令索引
🧪 Testing                   覆盖率 / 套件清单 / 已知缺口
📚 References & Docs Map     外部链接 / 记忆索引
📜 Development Log           pointer → Handoff_Logs/
```

> **从 v1 升级**：跑 `/handoff-tidy`——它检测到 v1 layout（缺 v2 marker + inline Dev Log entries）会提示是否迁移，迁移过程原子（部分失败自动回滚），全量保留历史内容。详见 `MIGRATION_GUIDE_v2.md`。

### 核心约束（共 9 条）

1. **不读 / 不写 git** — handoff 是用户级工作记忆，与版本管理正交；即使项目未 `git init` 也正常工作
2. **凭证不写明文** — API key / token 用 `$ENV_VAR` 或 `vault://` 引用
3. **Dev Log 命名严格倒序可计算** — `<NNNN>-<timestamp>-<slug>.md`，`ls | sort -r | head -N` 即得最新 N 条
4. **Decision Log 独立分流** — Why 放 Handoff_Decisions/，What 放 Handoff_Logs/，通过文件名互相引用
5. **自动归档防肿胀** — v2 改为按年归档：`Handoff_Logs/<NNNN>-<YYYY>-*` 当 YYYY < 当前年-1 时移到 `Handoff_Logs.archive/<YYYY>/`
6. **重复写入检测** — 10 分钟内改动文件集合相等时询问用户，避免手滑双写
7. **Recall 按需读** — 默认 HANDOFF.md（精华章节 + 三组 stat）+ GOTCHAS.md + 最近 5 条 Dev Log；`/handoff-recall N` 可扩展
8. **Tidy 只动结构不动内容** — 重排、补骨架、补缺字段为 `—`、Syncthing 编号冲突恢复，但不改写用户原文；遇 v1 提示迁移
9. **Token 成本节制** — recall 默认 ~7 文件 / 5-7K tokens（v1 单文件 121K → v2 主文件 28K）

---

## 5. 命令说明

| 命令 | 作用 | 典型场景 | 参数 |
|------|------|---------|------|
| **`/handoff`** | 把刚做完的工作写入 Dev Log | 完成一小步后留痕 | 无 |
| **`/handoff-recall [N]`** | 读文档并汇报现状（默认 5 条 Dev Log） | 开早上接着写 / 新人接手 | N = 读几条 Dev Log（默认 5）|
| **`/handoff-tidy`** | 整理结构、升级到最新 template | 文档看着乱 / 刚升级 skill | 无 |
| **`/handoff-init`** | 从模板初始化 `HANDOFF.md` | 新项目第一次建档 | 无 |

### 自然语言触发

各命令都支持自然语言：

```
做完功能     → /handoff         或    帮我留个档
接手项目     → /handoff-recall  或    这个项目我刚拿到，看看现状
整理文档     → /handoff-tidy    或    HANDOFF.md 结构有点乱，帮我整理
初始化文档   → /handoff-init    或    帮我新建一个 HANDOFF.md
```

---

## 🧪 Experimental：`/handoff-memory`（记忆跟随项目走）

> **状态**：Experimental。API 可能变；默认关闭，opt-in。

### 问题

Claude Code 的 auto-memory（feedback / project / reference / user 四类经验）存在：

```
~/.claude/projects/<encoded-path>/memory/
```

这是**机器本地**的——换电脑、换同事、换 AI 工具时，这些积累的经验**不跟项目走**。HANDOFF.md 解决了显性知识的可移植，但 auto-memory 里藏的默会经验还在机器里。

### 做法

| 命令 | 作用 |
|------|------|
| `/handoff-memory` | 显示状态（enabled / disabled + 已同步文件数） |
| `/handoff-memory on` | 启用：在项目根创建 `./memory/.sync-enabled` 标志 + 立刻同步一次 |
| `/handoff-memory off` | 关闭（已同步的 .md 文件保留，由用户决定是否手动删） |
| `/handoff-memory sync` | 手动触发一次同步 |

启用后，**每次 `/handoff` 写入 Dev Log 完成后会自动跑一次 sync**，把 `~/.claude/projects/<encoded>/memory/*.md` 覆盖式复制到 `./memory/`。

跨机器场景：
- A 机器：`/handoff-memory on` → `./memory/` 带着当前记忆被打包进项目
- B 机器（新机器 / 同事）：打开项目，`/handoff-memory` 显示 `./memory/*.md` 已在；可选择说"读记忆"让 Claude 加载正文进入 context

### 边界与注意

- **只是记忆正文的拷贝**，不是对话历史——不违反 Handoff 的 Non-Goal"不做 AI 对话历史导出/重放"
- **不碰 `HANDOFF.md`**、**不改 git**、**不主动加 `.gitignore`**——记忆是否入版本由项目自己决定
- **覆盖式同步，不做镜像**：项目本地多出的 `./memory/*.md` 文件不会被删（允许用户手写本地记忆）
- **内置两道敏感信息保护**：
  - 首次 `on` 且检测到 `.git/` → 提示你考虑把 `memory/` 加入 `.gitignore`
  - 每次 `sync` 结束自动跑 `scan-credentials.sh` 检查 11 种密钥前缀；发现即红色警告 + 非零退出
- **Symlink 一律跳过**：防止攻击者在 CC memory 里植入指向 `/etc/passwd` 等的链接
- **Experimental**：行为可能调整。欢迎反馈。

---

## 6. 安装 / 升级 / 卸载

> **完整命令参考**（含 4 种安装方式、SSH 远程部署、排错）见 [INSTALL.md](./INSTALL.md)。

### 安装（首次）

```bash
./install.sh           # 全局装到 ~/.claude/skills/handoff/
```

### 升级（新版本发布后）

```bash
# 源码用户
cd handoff && git pull && ./install.sh

# .skill 单文件用户（在 .skill 所在目录）
unzip -o ./handoff-v<版本>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp ~/.claude/skills/handoff/command-shims/handoff-{recall,tidy,memory}.md ~/.claude/commands/
cp ~/.claude/skills/handoff/command-shims/handoff-init.md ~/.claude/commands/
```

升级后在 Claude Code 里 `/reload-plugins`，或重启 Claude Code。

### 已有项目文档结构同步

```
/handoff-tidy      # 补缺章节 + 整理 Dev Log + 跑后置四连检查
```

### 卸载

```bash
./install.sh --uninstall
```

保留各项目根目录里的 `HANDOFF.md` 数据，只清 `~/.claude/skills/handoff/` 和 shims。

---

## 7. 目录结构

```
handoff/
├── README.md                 ← 你正在读：Philosophy / Logic / 技能说明
├── INSTALL.md                ← 完整的安装 / 升级 / 卸载 / 维护命令参考
├── CONTRIBUTING.md           ← 贡献约定
├── LICENSE                   ← MIT
├── install.sh                ← 安装脚本（幂等）
├── release.sh                ← 发版打包 + 安全扫描
├── skills/handoff/           ← Skill 本体（可直接拷到 ~/.claude/skills/）
│   ├── SKILL.md              ← 入口（~2700 tok）
│   ├── references/           ← 命令详细规范
│   │   ├── handoff-write.md
│   │   ├── handoff-recall.md
│   │   ├── handoff-tidy.md
│   │   ├── handoff-memory.md
│   │   └── handoff-init.md
│   ├── scripts/              ← 可分发脚本（不占 token）
│   │   ├── scan-credentials.sh
│   │   ├── validate-handoff.sh
│   │   ├── handoff-lint.sh
│   │   ├── rotation-reminder.sh
│   │   ├── archive-devlog.sh
│   │   ├── tidy-handoff.sh
│   │   ├── sync-codex-skills.sh
│   │   ├── sync-memory.sh
│   │   ├── encode-cc-path.sh
│   │   ├── emit-sbom.sh
│   │   ├── emit-token-usage.sh
│   │   └── validate-skill-metadata.sh
│   ├── assets/
│   │   └── HANDOFF.template.md    ← 新项目起点
│   ├── command-shims/        ← slash command shims（v2.1.3 起改名，原 `commands/`）
│   └── evals/                ← 评估场景定义
├── scripts/                  ← 开发版脚本（与 skill 内副本同步）
├── tests/                    ← 回归测试（26 套件，含 v2 schema / migrate / recall contract / postflight / K4 chicken-egg guard）
└── Release/
    ├── CHANGELOG.md          ← 版本历史
    ├── latest → handoff-v2.2.2             ← 软链接
    └── handoff-v2.2.2/
        ├── handoff-v2.2.2.skill            ← 单文件分发
        ├── handoff-v2.2.2-source.tar.gz    ← 源码包
        └── RELEASE_NOTES.md
```

---

## 8. 许可与贡献

- **许可**：MIT（见 [`LICENSE`](./LICENSE)）
- **贡献约定**：见 [`CONTRIBUTING.md`](./CONTRIBUTING.md)
- **版权**：© 2026 TKXLAB.AI — [github.com/tkxlab-ai](https://github.com/tkxlab-ai)

> 如果你把本 skill 集成进自己的 agentic workflow，欢迎在 README 里回链到我们的 GitHub 组织。
