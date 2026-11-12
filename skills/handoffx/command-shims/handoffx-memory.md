---
description: 实验：把 Claude 本地记忆固化到项目目录
---
🚀 HandoffX：开始执行**实验性记忆同步**流程。按 `<skill-path>/references/handoffx-memory.md` 严格执行（skill 路径由 CLI 决定：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级 `<project>/.claude/`、`.opencode/`、`.agents/` 下的 `skills/handoffx/` 优先）。

- 子命令：`/handoffx-memory` → status；`on` / `off` / `sync`；调 `bash <skill-path>/scripts/sync-memory.sh <subcommand>` 并回显输出。别名 `/handoffx-mem` / `/记忆同步` 同此
- 首次 `on` 前向用户明示「这是 experimental，会在项目下创建 ./memory/ 并把 Claude Code 的本地记忆复制进去」
- 不自动触发 /handoffx；不改 HANDOFFX.md，只操作 ./memory/
