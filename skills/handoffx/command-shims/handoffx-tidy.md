---
description: 整理 HANDOFFX.md 结构，不改内容；显式 schema-upgrade 子命令做 P2.1 schema 迁移（dry-run / apply / 幂等）
---

激活 handoffx skill 并执行**整理**流程。严格按 handoffx skill 的 `references/handoffx-tidy.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

1. 跑 `bash <skill-path>/scripts/tidy-handoff.sh HANDOFFX.md`——做确定性整理（压缩空行、补锚点）+ 收集诊断；遇旧版 `HANDOFF.md` 布局时脚本 exit 2 并打印确切的升级命令——把该命令转述给用户后停止，不要自行迁移
2. 按脚本输出的诊断清单**逐项修复**（严格规则）：
   - 缺 REQUIRED 章节 → 从 template 补骨架
   - 缺 RECOMMENDED 章节 → 问用户要不要补
   - Dev Log 乱序 → 整块移动重排为时间戳倒序，**不拆开条目内部**
   - Dev Log 缺字段 → 补为 `—`，**不编造**
3. 跑后置五连检查（与 /handoffx 一致）：`handoff-postflight.sh HANDOFFX.md`，tidy 不传 `--files=`
4. 回显整理摘要 + 三态检查 + 备份文件路径

**绝对禁止**：合并 Dev Log 条目 / 改写 Decision 原文 / 删 Gotcha / 重编号 / 删 pending / 基于 AI 判断修改用户已填内容。

**这是 tidy，不是 write 或 recall。不要追加 Dev Log，不要直接汇报。**

## schema-upgrade（显式子命令，不自动触发）

**布局分流**（按内容判定，不按文件名猜）：
- 项目根有旧版 `HANDOFF.md` 而无 `HANDOFFX.md` → 本命令会按内容判定并给出命令（v1 单文件 → `migrate-to-v2.sh`；旧四件套 → `schema-upgrade`）
- 新旧文件并存 → 先解决冲突（保留权威的一套、移除另一套），再重跑
- 两者都没有 → 跑 `/handoffx-init`

把 v2 旧四件套（旧版 HANDOFF.md / Handoff_Logs/ / Handoff_Decisions/）迁移到 handoffx schema
（HANDOFFX.md / Handoffx_Logs/ / Handoffx_Decisions/；GOTCHAS.md 不变 ADR-0005 LEAVE）。
仅在用户显式要求时运行；默认整理流程不会调用它。

由 `tidy-handoff.sh schema-upgrade` subcommand 实现（Q1 2026-05-21 Boss 拍板 subcommand 模式；
脚本基名 `tidy-handoff.sh` LEAVE T1）。

调用（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

```bash
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --help
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --dry-run --root <project-dir>
bash <skill-path>/scripts/tidy-handoff.sh schema-upgrade --apply --root <project-dir>
```

约束：幂等 / 双平台 / 原子回滚 / root-safe（Gotcha #15）。详见 `docs/2026-05-21-p2-1-handoffx-tidy-migrator-plan.md`。
