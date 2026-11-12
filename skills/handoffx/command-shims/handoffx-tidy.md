---
description: 整理 HANDOFFX.md 结构，不改内容；显式 schema-upgrade 子命令做 P2.1 schema 迁移（dry-run / apply / 幂等）
---
🚀 HandoffX：开始执行**整理**流程。按 `<skill-path>/references/handoffx-tidy.md` 严格执行（skill 路径由 CLI 决定：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级 `<project>/.claude/`、`.opencode/`、`.agents/` 下的 `skills/handoffx/` 优先）。先做步骤 0：
**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 根下存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，判定与清单原样给用户看。
2. 问：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 确认 → `--apply`，回显结果、残留清单与后续动作；未确认 → 不写任何文件。exit 1 = 迁移已完成但后置检查未过：不重试、不回滚，用 `/handoffx-tidy` 补章节再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑。
4. 新旧并存 / 无法判定 → 脚本拒绝并点名，转述给用户，不猜。
5. 用户本轮已明确要求升级 → 直接 --dry-run 再 --apply，不再重复询问（清单照样给用户看；脚本拒绝或要求 --sync-paused 时仍停下转述）。

然后跑 `bash <skill-path>/scripts/tidy-handoff.sh HANDOFFX.md`（仍遇旧布局 → exit 2 并打印升级命令：转述后停止，不自行迁移），按诊断逐项修复（缺字段补 `—` 不编造），再跑 `handoff-postflight.sh HANDOFFX.md`（不传 `--files=`），回显摘要 + 三态检查 + 备份路径。**绝对禁止**：合并 Dev Log / 改写 Decision 原文 / 删 Gotcha / 重编号 / 删 pending / 改用户已填内容。
## schema-upgrade（显式子命令，不自动触发）：仅在用户显式要求时运行；默认整理流程不会调用它——`bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --dry-run|--apply --root <项目根>`，细节见 `references/handoffx-tidy.md` 同名一节。
