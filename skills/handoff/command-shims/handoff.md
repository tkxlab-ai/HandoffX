---
description: 把当前对话里完成的工作写入 HANDOFF.md 的 Dev Log
---

激活 handoff skill 并执行**写入**流程。严格按 handoff skill 的 `references/handoff-write.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoff/`、OpenCode `~/.config/opencode/skills/handoff/`、Codex `~/.agents/skills/handoff/`；项目级：Claude Code `<project>/.claude/skills/handoff/`、OpenCode `<project>/.opencode/skills/handoff/`、Codex `<project>/.agents/skills/handoff/`）：

- 用 `date` 采集时间戳
- 从对话上下文提取改动文件、验证、关联
- 追加到 Dev Log 顶部（按锚点定位）
- 如本次含显式权衡 → 同时写 Decision Log
- 覆盖 Current State
- 跑后置四连检查（scan-credentials / validate-handoff / rotation-reminder / archive-devlog）
- 回显新条目与三态检查结果

**不要**把本次调用误解为 recall 或 tidy——写入就是写入。
