---
description: 把当前对话里完成的工作写入 HANDOFFX.md 的 Dev Log
---
🚀 HandoffX：开始执行**写入**流程。按 `<skill-path>/references/handoffx-write.md` 严格执行（skill 路径由 CLI 决定：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级 `<project>/.claude/`、`.opencode/`、`.agents/` 下的 `skills/handoffx/` 优先）。先做步骤 0，升级完成（或本来就是新布局）后再写入：
**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 根下存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，判定与清单原样给用户看。
2. 问：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 确认 → `--apply`，回显结果、残留清单与后续动作；未确认 → 不写任何文件。exit 1 = 迁移已完成但后置检查未过：不重试、不回滚，用 `/handoffx-tidy` 补章节再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑。
4. 新旧并存 / 无法判定 → 脚本拒绝并点名，转述给用户，不猜。
5. 用户本轮已明确要求升级 → 直接 --dry-run 再 --apply，不再重复询问（清单照样给用户看；脚本拒绝或要求 --sync-paused 时仍停下转述）。

写入只调 `bash <skill-path>/scripts/hx.sh <子命令>`（在项目根执行），不 source lib：`hx.sh now` → `hx.sh dup-check --files <改动文件,逗号分隔>`（exit 3 才问替换 / 追加 / 取消；exit 2 转述无法判定的原因）→ `hx.sh next-number logs` + `hx.sh slug` 写 Dev Log（有显式权衡再 `next-number decisions` 写 Decision）→ `hx.sh block set recent --from <临时文件>`（exit 2 / 4 按 ❌ 提示处理，不要手编整节；无 `hx:recent` 锚点先跑 `tidy-handoff.sh HANDOFFX.md` 补）→ `hx.sh regen` → `handoff-postflight.sh --files=… HANDOFFX.md`。
回显新条目与三态检查结果。写入就是写入，不要当成 recall 或 tidy。
