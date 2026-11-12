---
description: 把当前对话里完成的工作写入 HANDOFF.md 的 Dev Log
---

激活 handoffx skill 并执行**写入**流程。严格按 handoffx skill 的 `references/handoffx-write.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 用 `date` 采集时间戳
- 从对话上下文提取改动文件、验证、关联
- 写成 `Handoff_Logs/` 下的独立 Dev Log 文件（`acquire_next_number` 取编号），并重写主文件 pointer stat
- 如本次含显式权衡 → 同时写 Decision Log
- 覆盖 Current State
- 跑后置五连检查（`handoff-postflight.sh` 聚合：scan-credentials / validate-handoff / handoff-lint / rotation-reminder / archive-devlog；传 `--files=` 时加跑 handoff-xref-lint）
- 回显新条目与三态检查结果

**不要**把本次调用误解为 recall 或 tidy——写入就是写入。
