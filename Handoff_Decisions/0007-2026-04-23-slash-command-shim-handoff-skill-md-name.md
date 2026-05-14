---
schema: 2
type: decision
date: 2026-04-23
number: 0007
title: slash command 单源注册：拒绝三源 shim，`/handoff` 只走 SKILL.md name
---

### 2026-04-23 — slash command 单源注册：拒绝三源 shim，`/handoff` 只走 SKILL.md name
- **背景**: Claude Code 发现 3 个 slash 注册来源（SKILL.md name / `~/.claude/commands/` / skill 嵌套 `commands/`）。旧 install.sh 把 `handoff.md` 同时写入后两处，再加上 SKILL.md name，palette 出现 4 条 `/handoff`。
- **选项**:
  - A. **SKILL.md name 单源**，`commands/` 只留 recall/tidy shim，安装时剥离 skill 嵌套 `commands/`
  - B. 删 SKILL.md `name:` 字段，改由 `handoff.md` shim 注册
  - C. 保持三源，在 shim 里加 marker 让 Claude Code 去重
- **选择**: A
- **拒绝 B 的原因**: skill name 是 Anthropic 官方推荐的 skill 自注册机制；删掉会丢"自然语言触发 skill"能力（如"帮我做一次交接"）；shim 只是给 fuzzy-match 问题打补丁，不应反客为主
- **拒绝 C 的原因**: Claude Code 没有跨源去重合约；靠 marker 消重是与内部实现耦合，版本升级即破
- **反悔代价**: 低——仅涉及 install.sh 两处 `rm` 和 shim 清单；回滚只需把 `handoff.md` 加回 for 循环
- **不变量**: 每条 slash command **恰有一个**注册源。`/handoff` = SKILL.md name；`/handoff-recall` / `/handoff-tidy` = `~/.claude/commands/<name>.md` shim（防被 fuzzy-match 吞进 `/handoff`）。

