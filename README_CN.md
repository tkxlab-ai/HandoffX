<div align="center">

# HandoffX — 面向 AI 编程 agent 的项目交接系统

**把散落在对话历史、个人记忆、私有 AI 缓存里的默会知识，凝结成一份纯 markdown 交接 —— 同事 10 分钟内即可接手。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v4.2.1-blue.svg)](https://github.com/tkxlab-ai/HandoffX/releases)
[![Tests](https://img.shields.io/badge/tests-39%20suites%20%2F%202038%2B%20assertion%20sites-brightgreen.svg)](#8-测试)
[![Platform](https://img.shields.io/badge/platform-macOS%20bash%203.2%2B%20%C2%B7%20Linux-lightgrey.svg)](#9-兼容性)
[![Pure Markdown](https://img.shields.io/badge/format-pure%20markdown%20%C2%B7%20no%20lock--in-success.svg)](#2-设计哲学)

[English](README.md) · [中文](README_CN.md)

</div>

---

> 🔄 **跨 AI agent 工具是设计目标。** 交接文档是纯 markdown —— 任何能读文件的 agent（Claude Code · [Codex](https://github.com/openai/codex) · [OpenCode](https://opencode.ai/) · [Droid](https://factory.ai/) · Cursor · Copilot）和真人都能读。技能命令在 **Claude Code / OpenCode / Codex** 原生安装；其余工具通过文档层兼容。

---

## 目录

- [1. 为什么需要 HandoffX](#1-为什么需要-handoffx)
- [2. 设计哲学](#2-设计哲学)
- [3. 方法论](#3-方法论)
- [4. 逻辑模型](#4-逻辑模型)
- [5. 工作原理](#5-工作原理)
- [6. 命令说明](#6-命令说明)
- [7. 安装 / 升级 / 卸载](#7-安装--升级--卸载)
- [8. 测试](#8-测试)
- [9. 兼容性](#9-兼容性)
- [10. 引用与出处](#10-引用与出处)
- [11. 许可与贡献](#11-许可与贡献)

---

## 1. 为什么需要 HandoffX

软件工程里最难传承的不是代码，而是**默会知识**（tacit knowledge）：为什么这样选、坑在哪、当前在哪一步、谁是隐性专家、哪些看似可做却被故意不做。

这些知识通常藏在会辜负你的地方：

| 藏匿位置 | 致命缺陷 |
|---------|---------|
| AI 对话历史 | 私有、易丢、跨工具不兼容（Cursor 看不到 Claude 的历史）|
| Notion / Confluence | 常年漂移、与代码脱节；一年后没人敢信 |
| Git commit message | 碎片化，只讲 *what* 不讲 *why* |
| 开发者大脑 | 离职就没了，出差两周就开始模糊 |

**HandoffX 用一份强制结构的 markdown 替代以上全部。** `HANDOFFX.md` 常驻项目根，与代码一起演化，对所有 AI 工具透明，**真人也能直接读**。

> 💡 交接的单位是 markdown，不是对话。工具会变，文档长存。新接手人跑 `/handoffx-recall`，10 分钟内开始贡献。

---

## 2. 设计哲学

HandoffX 的设计经过领域权威面板审查。每条原则直接落到代码 —— 不是口号，是可执行断言。

### Don Norman — *The Design of Everyday Things*（1988）

> "If users can't tell what your system did, it doesn't matter that it worked."

- **Gulf of Evaluation** —— 每次写入回显"做了什么""检查发现什么"，不让用户猜。
- **Gulf of Execution** —— 命令名本身即行为（`/handoffx`=写、`/handoffx-recall`=读、`/handoffx-tidy`=整理），无需手册。
- **Feedback** —— 后置检查用**三态**信号 `✅ 通过 / ⚠️ 发现 / ❌ 失败`；脚本缺失记失败，绝不伪装成"通过"。

### Edsger W. Dijkstra — *A Discipline of Programming*（1976）

> "Program testing can be used to show the presence of bugs, but never to show their absence."

- **Invariants over conventions** —— 用可计算谓词替代模糊判断（重复检测＝*改动文件集精确相等＋10 分钟窗口*，不用 LLM 相似度）。
- **Atomic commits** —— `archive-devlog.sh` 先写新归档并完整性校验，*再*原子 `mv`；中途断电不丢数据。
- **Separation of concerns** —— Core / Init / Labs 分层，每个入口只做一件事，可独立测试、可组合。

### Ikujiro Nonaka — *The Knowledge-Creating Company*（1995），SECI 模型

> "The essence of creating knowledge is the conversion of tacit knowledge into explicit knowledge."

- **Externalization**（tacit → explicit）—— Decision Log 强制六字段：*背景 / 选项 A·B·C / 选择 / 拒绝原因 / 反悔代价*。
- **Ba**（场域）—— `Reader Notes` 让后读者回填 `YYYY-MM-DD [name]: 这条 Decision 的假设不成立了` —— 文档从广播变对话。
- **Respect for uncertainty** —— `Open Questions` 章节承接"看到但不懂"的知识；*填不出写 `—`，不要编造* 是硬规则。
- **知识不被改写** —— `/handoffx-tidy` 可重排、补缺字段为 `—`，**但不合并、不摘要、不润色**用户原文。默会知识不能被 AI 转述。

### 面板灵感（5-persona 审查）

模板与安全模型另外吸收：**Kent Beck** —— *Extreme Programming Explained*（TDD 纪律，RED→GREEN→REFACTOR）；**Bruce Schneier** —— *Secrets and Lies* / 威胁建模（凭证扫描信任边界）；**Andrew S. Grove** —— *High Output Management*（交接作为管理杠杆）。

---

## 3. 方法论

| 方法 | 出处 / 灵感 | HandoffX 如何落地 |
|------|------------|------------------|
| **SECI 知识转换** | Nonaka & Takeuchi, *The Knowledge-Creating Company*（1995）| `/handoffx`=外化，`/handoffx-recall`=内化，`/handoffx-tidy`=组合/再组织 |
| **可计算不变量** | Dijkstra, *A Discipline of Programming*（1976）| 重复检测＝集合精确相等＋时间窗，无 LLM 相似度启发 |
| **原子文件操作** | 崩溃安全设计（write-verify-rename）| `archive-devlog.sh`：staging → 完整性校验 → 原子 `mv` |
| **可发现性 / 反馈** | Norman, *The Design of Everyday Things*（1988）| 动词即命令命名；三态后置回显 |
| **测试驱动开发** | Beck, *Test-Driven Development: By Example*（2002）| 新行为必先写 RED 测试；39 套件 / 2038+ 断言点守门 |
| **信任边界威胁建模** | Schneier, 威胁建模 | `scan-credentials.sh` 在落盘前硬阻断 14 类 secret 前缀——供应商前缀、PEM 私钥头，以及明文写出的自建 Git 服务 token（`Authorization: token <值>`、`*GIT*_TOKEN=<40 位 hex>`）；`$VAR` / `vault://` 引用与裸 commit SHA 放行，表头标为 密码 / password / token / secret 的列里写明文同样阻断，其余列表之外的模式不检测（见 `--help`） |
| **对抗式审查循环** | 多轮独立 code review | 发版过 N 轮 Codex adversarial-review 直到连续干净（见 Decision Log）|

### 后置安全检查链（每次写入都跑）

```
scan-credentials.sh   → 硬阻断明文凭证（11 类前缀）
validate-handoff.sh   → 结构完整性（REQUIRED fail / RECOMMENDED warn）
handoff-lint.sh       → per-file frontmatter + 正文字段校验（v2）
rotation-reminder.sh  → 凭证到期预警（已过期 / 7d / 30d）
archive-devlog.sh     → v2：Handoffx_Logs/ 按年归档（保留当年与上一年）
handoff-xref-lint.sh  → 本次写入文件的交叉引用校验（仅传 --files= 时）
```

---

## 4. 逻辑模型

`HANDOFFX.md` 里每段信息都在唯一象限，由时间维度与读写模式定义：

| 信息类型 | 章节 | 时间维度 | 写入模式 |
|---------|------|---------|---------|
| 项目背景（*为何存在*）| Project Overview / Milestones / Features | 低频演化 | 手动，少改 |
| 当前状态（*现在在哪*）| Current State | 每次 `/handoffx` 刷新 | **覆盖**（只留最新）|
| 工作流水（*发生了什么*）| Development Log | 严格倒序 | **追加**（永不覆盖）|
| 决策理由（*为何选 A*）| Decision Log | 发生权衡时 | **追加** |
| 踩过的坑（*默会陷阱*）| Known Gotchas | 遇到时，编号稳定 | **追加**（不重编号）|
| 未解之谜 | Open Questions | 观察到时 | **追加** |
| 后读者反馈 | Reader Notes | 任何读者可补注 | **追加** |
| 凭证 / 参考 / 约定 | Credentials / References | 低频 | 手动 |

---

## 5. 工作原理

v2.0.0 起 `HANDOFFX.md` 不再是单文件 —— 大型项目单文件曾涨到 121K+、吃掉 47% 模型上下文窗口。v2 拆成**四件套**：

```
<project root>/
├── HANDOFFX.md            v2 schema 标记 + 11 个设计章节
│                          + Dev Log / Decision / Gotchas pointer stats
├── GOTCHAS.md             所有 Known Gotchas（单文件知识库；recall 整合读）
├── Handoffx_Logs/         Dev Log，每条一文件
│   └── <NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md
└── Handoffx_Decisions/    Decision Log，每条一文件
    └── <NNNN>-<YYYY-MM-DD>-<slug>.md
```

效果：主文件压缩约 77%，`recall` token 成本降约 63%，完整历史按需仍可寻址。

---

## 6. 命令说明

| 命令 | 行为 | 认知活动 |
|------|------|---------|
| `/handoffx` | 把当前工作追加到 Dev Log（+ Decision 分流 + 后置检查）| 外化 |
| `/handoffx-recall` | 读取并报告；只读，不依赖 git | 内化 |
| `/handoffx-recall <N>` | 同上，读最近 N 条 Dev Log | 内化 |
| `/handoffx-tidy` | 重排 / 补骨架 —— 绝不合并或改写内容 | 再组织 |
| `/handoffx-init` | 创建最小可用交接起点 | 起步 |
| `/handoffx-memory` | 🧪 实验性 opt-in：把本地经验条目迁入项目 | Labs |

自然语言触发（"交接一下""接着上次继续"）在 Claude Code 中也能激活技能。

---

## 7. 安装 / 升级 / 卸载

```bash
# 方式 A — 源码安装（多 CLI：--claude / --opencode / --codex）
./install.sh --claude

# 方式 B — 单 .skill 文件（离线分发）
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o handoffx-v4.2.1.skill -d ~/.claude/skills/   # 包内唯一顶层目录即 <skill-dir>（unzip -l 可见）
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
cp ~/.claude/skills/<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md ~/.claude/commands/

# 方式 C — 手动目录拷贝（最大透明）
cp -R skills/handoffx ~/.claude/skills/handoffx
```

发布产物（`.skill` + checksums + SBOM）在 **[Releases](https://github.com/tkxlab-ai/HandoffX/releases)** 页。完整矩阵与卸载步骤见 [`INSTALL.md`](INSTALL.md)。

- **仍是 v4 之前 handoff 布局的项目**：`/handoffx`、`/handoffx-recall`、`/handoffx-tidy`、`/handoffx-init` 会检测到它，先给出 dry-run 清单并询问；确认后跑 `scripts/handoffx-upgrade.sh --apply`（原子迁移、失败自动回滚，随后跑 validate + postflight 并列出项目里仍引用旧路径的其它文件）。多机 / 多 CLI 项目的固定升级顺序见 [`MIGRATION_GUIDE_v2.md`](MIGRATION_GUIDE_v2.md) §5.6。非 git 项目会先把旧件打包成校验过的 `.handoffx-pre-upgrade-<时间>.tar.gz`（`--no-backup` 跳过）；`HANDOFFX_SCAN_PRUNE="dirA dirB"` 追加残留扫描要跳过的目录。
- **同步目录里的项目**（Syncthing / Dropbox / iCloud）：`handoffx-upgrade.sh` 会点名它在项目上方找到的同步标记，`--apply` 在你暂停同步并加 `--sync-paused` 之前拒绝执行。
- **安装备份会保留**：安装替换掉的旧件留在 `~/.handoffx-install/bak.<时间>/`，结束时打印一行 `install.sh --restore <bak>` 还原命令；`--purge-backups` 删除更早的备份。
- **加载共享库**：`scripts/lib/handoff-v2.sh` 必须在 bash 下加载（`bash -c '. <skill-path>/scripts/lib/handoff-v2.sh && …'`）；在 zsh 等其他 shell 下它拒绝加载（报 ❌、不定义任何函数），不会再用空名字写文件或无锁取号。写入流程请用 `scripts/hx.sh`，不要直接 source lib。

---

## 8. 测试

| 类型 | 覆盖 | 命令 |
|------|------|------|
| 脚本单元 | ~100%（所有入口 + 边界）| `bash tests/run_all.sh` |
| 模板结构 | 100%（REQUIRED + RECOMMENDED）| `tests/test_validate_handoff.sh` |
| 双副本一致 | 100%（dev vs bundle 字节相等）| `tests/test_scripts_sync.sh` |
| 静态分析 | severity=warning 下 0 警告 | `tests/test_shellcheck.sh` |
| 结构漂移 guard | 跨文档 计数/版本/资产 一致性 | `tests/test_doc_freshness.sh`（Test 15–17）|

**合计：39 套件 / 2038+ 断言点 / 0 失败**，macOS bash 3.2 全绿；Linux mawk/POSIX-safe（容器实测见 v4.1.1 / Dev Log 0081 / Gotcha #15 / Decision 0016）。TDD 纪律：新行为必先有 RED 测试。

---

## 9. 兼容性

| 平台 | 状态 |
|------|------|
| macOS（bash 3.2+）| 主测，完整覆盖 |
| Linux（Ubuntu 22.04，mawk）| v4.1.1 容器实测全绿（非 root，当时全部套件，详见 Dev Log 0081 / Gotcha #15 / Decision 0016）；当前 macOS 全绿（需 shellcheck + ruby + unzip + zip + rsync + `LANG=C.UTF-8`）|
| Claude Code / OpenCode / Codex | 经 `install.sh` 原生安装技能 |
| Droid / Cursor / Copilot / 任意 agent | 经纯 markdown 文档层兼容 |

支持矩阵（OS / shell / CLI / 项目形态）见 [`INSTALL.md`](INSTALL.md) 的「支持矩阵」一节。

---

## 10. 引用与出处

### 书目与模型

| 著作 | 作者 | 用于 |
|------|------|------|
| *The Design of Everyday Things*（1988）| Donald A. Norman | 可发现性、Gulf of Execution/Evaluation、反馈模型 |
| *A Discipline of Programming*（1976）| Edsger W. Dijkstra | 可计算不变量、原子操作、关注点分离 |
| *The Knowledge-Creating Company*（1995）| Nonaka & Takeuchi | SECI 显隐知识转换；Ba；外化模板 |
| *Test-Driven Development: By Example*（2002）| Kent Beck | RED→GREEN→REFACTOR 发版纪律 |
| *Extreme Programming Explained*（1999）| Kent Beck | 持续、小步、可验证的改动 |
| *High Output Management*（1983）| Andrew S. Grove | 交接作为管理杠杆 |
| 威胁建模 / *Secrets and Lies*（2000）| Bruce Schneier | 凭证扫描信任边界 |

### 引用的跨工具生态

- **[OpenAI Codex](https://github.com/openai/codex)** —— 终端 AI 编程 agent（原生安装目标）
- **[OpenCode](https://opencode.ai/)** —— MIT、provider-agnostic 终端 agent（原生安装目标）
- **[Factory Droid](https://factory.ai/)** —— agent-native CLI（文档层兼容）

### 内部知识资产

`Handoffx_Decisions/`（权衡理由，18+ 条）· `Handoffx_Logs/`（开发日志，46+ 条）· `GOTCHAS.md`（累积陷阱）—— 项目自己吃自己的方法论狗粮。

---

## 11. 许可与贡献

- **许可**：MIT —— 见 [`LICENSE`](LICENSE)。
- **贡献**：本 GitHub 仓库为发布镜像；见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。Bug 反馈走 [Issues](https://github.com/tkxlab-ai/HandoffX/issues)；安全问题走 [private advisory](https://github.com/tkxlab-ai/HandoffX/security/advisories/new) 或 [`SECURITY.md`](SECURITY.md) 中列出的联系方式。

---

<div align="center">

**[tkxlab-ai/HandoffX](https://github.com/tkxlab-ai/HandoffX)**

纯 markdown · 无 vendor lock-in · 为真人与所有 AI agent 而写

</div>
