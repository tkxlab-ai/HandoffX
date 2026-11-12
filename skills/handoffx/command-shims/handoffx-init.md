---
description: 创建最小 HANDOFFX.md 起点
---

激活 handoffx skill 并执行**最小初始化**流程。严格按 handoffx skill 的 `references/handoffx-init.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

- 若项目根已有 `HANDOFFX.md`，不要覆盖；提示用户可用 `/handoffx-recall` 或 `/handoffx-tidy`
- **布局分流**（按内容判定，不按文件名猜）：
  - 项目根有旧版 `HANDOFF.md` 而无 `HANDOFFX.md` → 先跑 `/handoffx-tidy`：它按内容判定并给出命令（v1 单文件 → `migrate-to-v2.sh`；旧四件套 → `schema-upgrade`）
  - 新旧文件并存 → 先解决冲突（保留权威的一套、移除另一套），再重跑
  - 两者都没有 → 继续下一条（`/handoffx-init`）
- 若两者都没有，在项目根创建 v2 四件套：`HANDOFFX.md`（← `assets/HANDOFFX.template.md`，含 v2 marker）、`GOTCHAS.md`（← `assets/GOTCHAS.template.md`）、空目录 `Handoffx_Logs/`、`Handoffx_Decisions/`
- 引导用户优先填写最小 5 块：Project Overview / Current State / Build Run Test / Architecture / Coding Conventions
- 不读取 git，不创建 commit，不自动写 Dev Log
- 创建后运行 `validate-handoff.sh --readiness HANDOFFX.md` 并回显结果

**这是 init，不是 write。不要把当前对话工作追加到 Dev Log。**
