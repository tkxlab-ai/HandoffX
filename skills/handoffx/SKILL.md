---
name: handoffx
description: 把项目交接写成 HANDOFFX.md + 三件套供同事接手；写 Dev Log / Decision / Gotcha / recall 项目状态。Use for /handoffx* commands and project handoff work.
---

# 🚀 HandoffX：开始执行

本文件只是入口——按下表读**对应的一份**规范并严格执行，不要复述本文件。

| 命令 | 规范 | 产出 |
|---|---|---|
| `/handoffx` | `references/handoffx-write.md` | 新 Dev Log（+ 有权衡时 Decision）、Current State 的 `hx:recent` 块、GOTCHAS 追加、`hx.sh regen`、postflight |
| `/handoffx-recall [N]` | `references/handoffx-recall.md` | 只读汇报（默认 6 条） |
| `/handoffx-tidy` | `references/handoffx-tidy.md` | 结构整理（有备份） |
| `/handoffx-init` | `references/handoffx-init.md` | 四件套骨架 |
| `/handoffx-memory` | `references/handoffx-memory.md` | Labs，显式 opt-in |

脚本一律 `bash <skill-path>/scripts/…`（skill 路径由 CLI 决定：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级同名目录优先）。写入的机械步骤用 `scripts/hx.sh`（now / dup-check / next-number / slug / block / regen），补锚点用 `tidy-handoff.sh`，末尾 `handoff-postflight.sh`；不 source lib。

## 步骤 0 · 何时触发：任一 `/handoffx*` 命令，或用户说「做一次交接 / 接手这个项目」；所有命令先做：

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 根下存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，判定与清单原样给用户看。
2. 问：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 确认 → `--apply`，回显结果、残留清单与后续动作；未确认 → 不写任何文件。exit 1 = 迁移已完成但后置检查未过：不重试、不回滚，用 `/handoffx-tidy` 补章节再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑。
4. 新旧并存 / 无法判定 → 脚本拒绝并点名，转述给用户，不猜。
5. 用户本轮已明确要求升级 → 直接 --dry-run 再 --apply，不再重复询问（清单照样给用户看；脚本拒绝或要求 --sync-paused 时仍停下转述）。

**硬约束**：不读写 git；凭证不写明文（`$ENV_VAR` / `vault://`，表格里标为密码/token 的列同样）；Decision 只在显式权衡时写（Why 留 Decision，What 留 Dev Log）；recall 默认 6 条、其它章节按需读；tidy 只动结构不动内容；时间戳只从 `hx.sh now` 取，不猜。

**不触发**：git 知识问题、README/API/ADR 写作、导出对话历史。
