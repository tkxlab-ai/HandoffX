---
description: 创建最小 HANDOFF.md 起点
---

激活 handoffx skill 并执行**最小初始化**流程。严格按 handoffx skill 的 `references/handoffx-init.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 若项目根已有 `HANDOFF.md`，不要覆盖；提示用户可用 `/handoffx-recall` 或 `/handoffx-tidy`
- 若不存在，在项目根创建 v2 四件套：`HANDOFF.md`（← `assets/HANDOFF.template.md`，含 v2 marker）、`GOTCHAS.md`（← `assets/GOTCHAS.template.md`）、空目录 `Handoff_Logs/`、`Handoff_Decisions/`
- 引导用户优先填写最小 5 块：Project Overview / Current State / Build Run Test / Architecture / Coding Conventions
- 不读取 git，不创建 commit，不自动写 Dev Log
- 创建后运行 `validate-handoff.sh --readiness HANDOFF.md` 并回显结果

**这是 init，不是 write。不要把当前对话工作追加到 Dev Log。**
