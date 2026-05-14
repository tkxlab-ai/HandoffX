---
description: 整理 HANDOFF.md 结构，不改内容
---

激活 handoff skill 并执行**整理**流程。严格按 handoff skill 的 `references/handoff-tidy.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoff/`、OpenCode `~/.config/opencode/skills/handoff/`、Codex `~/.agents/skills/handoff/`；项目级：Claude Code `<project>/.claude/skills/handoff/`、OpenCode `<project>/.opencode/skills/handoff/`、Codex `<project>/.agents/skills/handoff/`）：

1. 跑 `bash <skill-path>/scripts/tidy-handoff.sh HANDOFF.md`——做确定性整理（压缩空行、补锚点）+ 收集诊断
2. 按脚本输出的诊断清单**逐项修复**（严格规则）：
   - 缺 REQUIRED 章节 → 从 template 补骨架
   - 缺 RECOMMENDED 章节 → 问用户要不要补
   - Dev Log 乱序 → 整块移动重排为时间戳倒序，**不拆开条目内部**
   - Dev Log 缺字段 → 补为 `—`，**不编造**
3. 跑后置四连检查（与 /handoff 一致）
4. 回显整理摘要 + 三态检查 + 备份文件路径

**绝对禁止**：合并 Dev Log 条目 / 改写 Decision 原文 / 删 Gotcha / 重编号 / 删 pending / 基于 AI 判断修改用户已填内容。

**这是 tidy，不是 write 或 recall。不要追加 Dev Log，不要直接汇报。**
