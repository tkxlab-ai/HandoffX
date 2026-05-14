---
description: 创建最小 HANDOFF.md 起点
---

激活 handoff skill 并执行**最小初始化**流程。严格按 handoff skill 的 `references/handoff-init.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoff/`、OpenCode `~/.config/opencode/skills/handoff/`、Codex `~/.agents/skills/handoff/`；项目级：Claude Code `<project>/.claude/skills/handoff/`、OpenCode `<project>/.opencode/skills/handoff/`、Codex `<project>/.agents/skills/handoff/`）：

- 若项目根已有 `HANDOFF.md`，不要覆盖；提示用户可用 `/handoff-recall` 或 `/handoff-tidy`
- 若不存在，基于 `assets/HANDOFF.template.md` 创建 `HANDOFF.md`
- 引导用户优先填写最小 5 块：Project Overview / Current State / Build Run Test / Known Gotchas / Development Log
- 不读取 git，不创建 commit，不自动写 Dev Log
- 创建后运行 `validate-handoff.sh --readiness HANDOFF.md` 并回显结果

**这是 init，不是 write。不要把当前对话工作追加到 Dev Log。**
