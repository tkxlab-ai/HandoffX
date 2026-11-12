---
description: 读 HANDOFFX.md 汇报现状，可传数字读更多 Dev Log
---
🚀 HandoffX：开始执行**读取**流程。按 `<skill-path>/references/handoffx-recall.md` 严格执行（skill 路径由 CLI 决定：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级 `<project>/.claude/`、`.opencode/`、`.agents/` 下的 `skills/handoffx/` 优先）。先做步骤 0（recall 本身只读，升级只在用户确认后发生）：
**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 根下存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，判定与清单原样给用户看。
2. 问：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 确认 → `--apply`，回显结果、残留清单与后续动作；未确认 → 不写任何文件。exit 1 = 迁移已完成但后置检查未过：不重试、不回滚，用 `/handoffx-tidy` 补章节再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑。
4. 新旧并存 / 无法判定 → 脚本拒绝并点名，转述给用户，不猜。
5. 用户本轮已明确要求升级 → 直接 --dry-run 再 --apply，不再重复询问（清单照样给用户看；脚本拒绝或要求 --sync-paused 时仍停下转述）。

参数 N：无 → 6；正整数 → N；非数字 → 6；0 或负数 → 拒绝并提示「请给一个正整数，例如 /handoffx-recall 10」。用户不升级时可只读旧版主文件汇报，第一行注明「读的是旧布局，未升级」。
只读不写（唯一例外：步骤 0 里用户确认的升级）；Decision Log 等其它章节与 `Handoffx_Logs.archive/<年>/` 用户明确要求才读；汇报第一行明示读取范围，汇报完等用户指令。
