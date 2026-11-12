---
description: 实验：把 Claude 本地记忆固化到项目目录
---

激活 handoffx skill 并执行**实验性记忆同步**流程。严格按 handoffx skill 的 `references/handoffx-memory.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 解析子命令：`/handoffx-memory` → status；`/handoffx-memory on` / `off` / `sync`
- 调用 `<skill-path>/scripts/sync-memory.sh <subcommand>` 并把输出回显给用户
- **这是实验性功能**：首次 `on` 之前要向用户明示"这是 experimental，会在项目下创建 ./memory/ 目录并把 Claude Code 的本地记忆复制进去"
- **不自动触发 /handoffx** —— 这是独立工具
- **不改 HANDOFF.md** —— 只操作 ./memory/
- 别名：`handoffx-memory` / `/handoffx-mem` / `/记忆同步` 一律按 `/handoffx-memory` 执行
