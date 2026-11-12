---
description: 读 HANDOFFX.md 汇报现状，可传数字读更多 Dev Log
---

激活 handoffx skill 并执行**读取**流程。严格按 handoffx skill 的 `references/handoffx-recall.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 解析参数 N：`/handoffx-recall` → N=5；`/handoffx-recall 10` → N=10；非数字 → 默认 5；0 或负数 → 拒绝并提示"请给一个正整数，例如 /handoffx-recall 10"
- 永远读：Project Overview / Current State / Known Gotchas
- 按 N 条读：最近 N 条 Dev Log 条目
- 不读：Decision Log / Architecture / Testing / Credentials / Milestones / Features / References（除非用户明确要求）
- 不读：HANDOFFX.archive.md（除非用户明确要求"翻旧账"）
- 汇报第一行必须明示本次读取范围
- **只读不写**——不自动触发 /handoffx，不改任何文件
- 汇报完等用户指令，不主动开始改代码

**这是 recall，不是 write。不要调用 date 或追加 Dev Log。**
