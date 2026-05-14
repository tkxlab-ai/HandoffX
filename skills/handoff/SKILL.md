---
name: handoff
description: 把项目交接写进 HANDOFF.md，供同事或未来接手
---

# Handoff — 项目级交接文档系统（v2 多文件布局）

把分散在对话历史 / 个人记忆 / 私有 AI 缓存里的项目上下文，写成项目根四件套：

- `HANDOFF.md`（主文件，顶部 `<!-- HANDOFF v2 schema -->` 标记 + 11 个设计章节 + 三组 pointer stat）
- `GOTCHAS.md`（Known Gotchas 知识库，单文件 integrated reading）
- `Handoff_Logs/<NNNN>-<timestamp>-<slug>.md`（Dev Log per-file，事件流）
- `Handoff_Decisions/<NNNN>-<date>-<slug>.md`（Decision Log per-file，权衡记录）

让任何同事拿到文件夹就能 10 分钟内接手。核心写入 / 读取 / 整理流程不依赖版本管理。

> v1 单文件项目升级走 `/handoff-tidy`——检测到 v1 layout 会提示是否迁移，原子迁移失败自动回滚。详见 `MIGRATION_GUIDE_v2.md`。

## 何时触发

- 用户输入 `/handoff` / `/handoff-recall` / `/handoff-tidy` / `/tidy` / 旧名 `hand off` / `/hand-off`
- 用户说"做一次交接" / "接手这个项目" / "整理一下交接文档" / "升级 handoff 结构" / "这个仓库我刚拿到"
- 用户希望把当前对话里完成的工作"留下来"给后续的人（无论后续是另一个 AI session、自己几周后、还是同事）

## 工作模式：Core / Init / Labs

| 命令 | 触发词 | 行为 | 输出位置 |
|------|--------|------|----------|
| `/handoff` | 写入 / 追加 / 同步 | 写新 Dev Log 文件 + （若有权衡）写 Decision 文件 + 覆盖主文件 Current State + 自动重写三组 pointer stat | `Handoff_Logs/<NNNN>-*.md` / `Handoff_Decisions/<NNNN>-*.md` / `HANDOFF.md` |
| `/handoff-recall [N]` | 接手 / 汇报 / 看进度 | 读 HANDOFF.md 精华 + GOTCHAS.md + 最近 N 条 Dev Log 文件（默认 5）| 对话回复（不写文件） |
| `/handoff-tidy` | 整理 / 升级 / 清理 | 结构整理 + v1 检测自动迁移 + Syncthing 编号冲突修复 | 项目根（有备份） |
| `/handoff-init` | 初始化 / 冷启动 | 创建 v2 四件套骨架；适合空项目或首次接手 | `HANDOFF.md` + `GOTCHAS.md` + `Handoff_Logs/` + `Handoff_Decisions/` |
| `/handoff-memory` | 记忆同步 | Labs：显式 opt-in 后同步 Claude Code 本地 memory | 项目根 `memory/` |

详细行为规范见 `references/handoff-write.md` / `references/handoff-recall.md` / `references/handoff-tidy.md` / `references/handoff-memory.md` / `references/handoff-init.md`。

## 关键约束（与 README.md §4 "核心约束" 保持一致）

1. **不读 / 不写 git**。handoff 是用户级工作记忆，与版本管理正交。即使项目未 `git init` 也照常工作。
2. **凭证不写明文**。SSH 私钥只写路径；API key / token 用 `$ENV_VAR` 或 `vault://` 引用。`scripts/scan-credentials.sh` 在 v2 directory mode 下扫主文件 + GOTCHAS + 两个 per-file 目录。
3. **Dev Log 命名严格倒序可计算**：`<NNNN>-<timestamp>-<slug>.md`，`ls Handoff_Logs | sort -r | head -N` 直接给出最新 N 条。
4. **Decision Log 独立分流**：本次工作含**显式权衡**（"考虑了 A 和 B，因 X 选了 A"）才写——单独的 `Handoff_Decisions/<NNNN>-<date>-<slug>.md` 文件。Why 留这里，What 留 Dev Log。
5. **自动归档防肿胀**：v2 改为按年归档——`Handoff_Logs/<NNNN>-<YYYY>-*` 当 YYYY < 当前年-1 时移到 `Handoff_Logs.archive/<YYYY>/`。
6. **重复写入检测**：最近 10 分钟内 Handoff_Logs/ 顶部条目与本次改动文件集合相同时，询问用户是替换 / 追加 / 取消。
7. **Recall 按需读**：`/handoff-recall` 默认读 HANDOFF.md（Project Overview + Current State + 三组 stat） + GOTCHAS.md + 最近 5 条 Dev Log 文件（约 7 个文件）。Decision Log / Architecture / Testing 等**按需读**。
8. **Tidy 只动结构不动内容**：`/handoff-tidy` 可以重排骨架、补字段为 `—`、检测 v1 触发迁移、修复 Syncthing 编号冲突，但**不合并、不摘要、不润色**用户原文。
9. **Token 成本节制**：v2 把主文件从 v1 的 121K（实测）压到 ~28K；recall 默认 ~7 文件 / 5-7K tokens。

> AI 操作层：时间戳一律用 `date "+%Y-%m-%d %H:%M"` 采集，不凭推测填日期——见下方「执行流程」Step 2。

## 执行流程

### 写入（`/handoff`）

1. 读 `references/handoff-write.md` 的完整规范
2. 用 `date "+%Y-%m-%d %H:%M"` 取时间戳
3. 读 `Handoff_Logs/` 顶部条目（`ls | sort | tail -1`）做**重复检测**，疑似重复先问用户
4. `acquire_next_number Handoff_Logs/` 取 NNNN，slugify 标题，写 `Handoff_Logs/<NNNN>-<timestamp>-<slug>.md`（含 frontmatter）
5. 若有显式权衡 → `acquire_next_number Handoff_Decisions/`，写 `Handoff_Decisions/<NNNN>-<date>-<slug>.md`
6. **覆盖** HANDOFF.md `## 🎯 Current State`（只保留最近改动 / 验证状态 / 待办三部分）
7. 新坑 → append 到 `GOTCHAS.md` 底部，编号 `Gotcha #N`，标签 `[build]/[runtime]/[data]/[security]/[perf]`
8. 调 `regenerate_pointers HANDOFF.md`（来自 `lib/handoff-v2.sh`）—— 自动重写主文件三组 stat
9. 后置五连检查（v2.1.0 起一行聚合）：
   - **推荐**：`bash <skill-path>/scripts/handoff-postflight.sh <project-root>` —— 跑 5 个检查 + 一行 PASS/FAIL 汇总；任一失败整体 exit 1；`--quiet` 仅出汇总
   - 或单独跑（调试时方便定位具体哪一项）：
     - `scan-credentials.sh <project-root>` — 多文件凭证扫描
     - `validate-handoff.sh --readiness <project-root>` — 结构 + v2 marker + pointer stats 校验
     - `handoff-lint.sh HANDOFF.md` — v2 per-file frontmatter + body field 严格校验
     - `rotation-reminder.sh <project-root>` — 凭证轮换
     - `archive-devlog.sh <project-root>` — 按年归档 Handoff_Logs/
10. 把刚写的 Dev Log 文件路径 + 片段回显给用户

### 读取（`/handoff-recall [N]`）

1. 读 `references/handoff-recall.md` 的完整规范
2. 解析参数 `N`：默认 5；非数字回退默认；0 或负数 → 拒绝并提示
3. 永远读：
   - `HANDOFF.md` 的 `## 📦 Project Overview` + `## 🎯 Current State` + 三组 pointer stat
   - `GOTCHAS.md`（整文件，知识库 integrated reading）
4. 按 N 读：`ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -N`，对每个文件读全文
5. 读 `CLAUDE.md`（如存在）
6. 汇报第一行明示读取范围（Norman: Gulf of Evaluation）
7. 按模板汇报：当前阶段 / 最近一次工作 / 待办 / 相关已知坑 / 建议下一步
8. 只读不写

### 整理（`/handoff-tidy`）

1. 读 `references/handoff-tidy.md` 的完整规范
2. 跑 `bash <skill-path>/scripts/tidy-handoff.sh HANDOFF.md`：
   - 检测 v1 layout（缺 v2 marker + inline Dev Log entries）→ 提示是否触发 `migrate-to-v2.sh --apply`
   - 检测 Handoff_Logs / Handoff_Decisions 同号冲突（Syncthing 多机 race）→ 自动 renumber
   - 自动：压缩多余空行 / 补齐 Dev Log 锚点
   - 诊断：缺章节 / Dev Log 乱序 / 缺字段
3. 按诊断结果**逐项修复**（严格规则见 references）
4. 后置五连检查（v2.1.0 推荐 `handoff-postflight.sh`；或单独跑 5 个脚本）
5. 回显整理摘要 + 三态检查结果 + 备份文件路径

**禁止**：合并 Dev Log 文件、改写 Decision 原文、删 Gotcha、重编 Gotcha 号、删 pending。

## 首次安装

若项目根没有 `HANDOFF.md`：跑 `/handoff-init`——它创建四件套（HANDOFF.md + GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/），骨架来自 `assets/HANDOFF.template.md`（v2 marker + pointer 块）和 `assets/GOTCHAS.template.md`。引导用户填 Project Overview / Architecture / Coding Conventions。

## 何时**不**触发

- 用户只是问"git status 是什么意思"——这是 git 知识问题，与 handoff 无关
- 用户要写 README / API 文档 / ADR——那是面向公众/架构的文档，handoff 是面向接手人的工作记忆
- 用户要导出 AI 对话历史——那是 session 管理工具的事，handoff 不替代

## 设计哲学（Why this exists）

接手人最痛的不是"代码看不懂"，是"不知道当前在哪一步、为何这样选、哪里已经踩过坑"。AI 对话历史私有易丢、跨工具不兼容；wiki 常年漂移；commit message 太碎且只讲 What 不讲 Why。Handoff 用一份强制结构 + 自动追加日志 + 显式决策记录，把这些隐性知识固化成项目资产。

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This project is licensed under the MIT License - see the LICENSE file for details.

Copyright (c) 2026 TKXLAB.AI - https://github.com/tkxlab-ai

> Permission Notice: Free for personal and commercial use. If you integrate this skill into your own agentic workflows, providing a link back to our GitHub organization is appreciated.
