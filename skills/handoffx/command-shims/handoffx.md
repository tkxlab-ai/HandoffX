---
description: 把当前对话里完成的工作写入 HANDOFFX.md 的 Dev Log
---

激活 handoffx skill 并执行**写入**流程。严格按 handoffx skill 的 `references/handoffx-write.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

步骤 0（先于下面各条）：

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 项目根存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先跑 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，把判定结果与清单原样给用户看
2. 问用户：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup 备份，v3 原地改名不留副本（靠 git 回退））」
3. 用户确认 → 跑 `--apply`，回显结果、残留清单与后续动作；未确认 → 停止，不写任何文件；脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续
4. 新旧并存 / 无法判定 → 脚本会拒绝并点名，转述给用户，不猜

升级完成（或本来就是新布局）后再写入：

- 用 `date` 采集时间戳
- 从对话上下文提取改动文件、验证、关联
- 写成 `Handoffx_Logs/` 下的独立 Dev Log 文件（`acquire_next_number` 取编号），并重写主文件 pointer stat
- 如本次含显式权衡 → 同时写 Decision Log
- 覆盖 Current State
- 跑后置五连检查（`handoff-postflight.sh` 聚合：scan-credentials / validate-handoff / handoff-lint / rotation-reminder / archive-devlog；传 `--files=` 时加跑 handoff-xref-lint）
- 回显新条目与三态检查结果

**不要**把本次调用误解为 recall 或 tidy——写入就是写入。
