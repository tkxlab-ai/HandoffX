---
description: 实验：把 Claude 本地记忆固化到项目目录
---

激活 handoff skill 并执行**实验性记忆同步**流程。严格按 handoff skill 的 `references/handoff-memory.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoff/`、OpenCode `~/.config/opencode/skills/handoff/`、Codex `~/.agents/skills/handoff/`；项目级：Claude Code `<project>/.claude/skills/handoff/`、OpenCode `<project>/.opencode/skills/handoff/`、Codex `<project>/.agents/skills/handoff/`）：

- 解析子命令：`/handoff-memory` → status；`/handoff-memory on` / `off` / `sync`
- 调用 `<skill-path>/scripts/sync-memory.sh <subcommand>` 并把输出回显给用户
- **这是实验性功能**：首次 `on` 之前要向用户明示"这是 experimental，会在项目下创建 ./memory/ 目录并把 Claude Code 的本地记忆复制进去"
- **不自动触发 /handoff** —— 这是独立工具
- **不改 HANDOFF.md** —— 只操作 ./memory/
- 旧名兼容：`handoff-memory` / `/handoff-mem` / `/记忆同步` 一律按 `/handoff-memory` 执行
