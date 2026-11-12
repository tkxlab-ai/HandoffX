---
description: 创建最小 HANDOFFX.md 起点
---

激活 handoffx skill 并执行**最小初始化**流程。严格按 handoffx skill 的 `references/handoffx-init.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 若项目根已有 `HANDOFFX.md`，不要覆盖；提示用户可用 `/handoffx-recall` 或 `/handoffx-tidy`

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 项目根存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先跑 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，把判定结果与清单原样给用户看
2. 问用户：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup 备份，v3 原地改名：git 仓库靠 git 回退，非 git 项目自动先打 .handoffx-pre-upgrade-<时间>.tar.gz）」
3. 用户确认 → 跑 `--apply`，回显结果、残留清单与后续动作；未确认 → 停止，不写任何文件；脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续；exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑
4. 新旧并存 / 无法判定 → 脚本会拒绝并点名，转述给用户，不猜
5. 用户在本轮对话里已明确要求升级 → 直接跑 --dry-run 再 --apply，不再重复询问（dry-run 结果照样原样给用户看；脚本拒绝或 --apply 要求 --sync-paused 时仍按上面停下转述）

- 两者都没有 → 继续下一条（`/handoffx-init`）
- 若两者都没有，在项目根创建 v2 四件套：`HANDOFFX.md`（← `assets/HANDOFFX.template.md`，含 v2 marker）、`GOTCHAS.md`（← `assets/GOTCHAS.template.md`）、空目录 `Handoffx_Logs/`、`Handoffx_Decisions/`
- 引导用户优先填写最小 5 块：Project Overview / Current State / Build Run Test / Architecture / Coding Conventions
- 不读取 git，不创建 commit，不自动写 Dev Log
- 创建后运行 `validate-handoff.sh --readiness HANDOFFX.md` 并回显结果

**这是 init，不是 write。不要把当前对话工作追加到 Dev Log。**
