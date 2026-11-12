---
description: 读 HANDOFFX.md 汇报现状，可传数字读更多 Dev Log
---

激活 handoffx skill 并执行**读取**流程。严格按 handoffx skill 的 `references/handoffx-recall.md` 规范执行（skill 路径由当前 CLI 决定——全局：Claude Code `~/.claude/skills/handoffx/`、OpenCode `~/.config/opencode/skills/handoffx/`、Codex `~/.agents/skills/handoffx/`；项目级：Claude Code `<project>/.claude/skills/handoffx/`、OpenCode `<project>/.opencode/skills/handoffx/`、Codex `<project>/.agents/skills/handoffx/`）：

步骤 0（先于下面各条；recall 本身只读，升级只在用户确认后发生）：

**旧布局检测 → 询问 → 标准升级**（按内容判定，不按文件名猜）：
1. 项目根存在任一旧版件（旧版 `HANDOFF.md` / `Handoff_Logs/` / `Handoff_Decisions/`）→ 先跑 `bash <skill-path>/scripts/handoffx-upgrade.sh --dry-run --root <项目根>`，把判定结果与清单原样给用户看
2. 问用户：「检测到旧版 handoff 文档布局，是否现在升级到 handoffx 布局？（原子迁移、失败自动回滚；v1 单文件另留 .pre-v2-backup 备份，v3 原地改名不留副本（靠 git 回退））」
3. 用户确认 → 跑 `--apply`，回显结果、残留清单与后续动作；未确认 → 停止，不写任何文件；脚本 exit 1 = 迁移已完成但后置检查未过（常见于 v1 缺 REQUIRED 章节）：不要重试、不要回滚，按输出用 `/handoffx-tidy` 补章节后再继续
4. 新旧并存 / 无法判定 → 脚本会拒绝并点名，转述给用户，不猜

用户不升级时仍可只读旧版主文件汇报（按 `references/handoffx-recall.md`「旧 v1 单文件读取」），汇报第一行注明「读的是旧布局，未升级」。

- 解析参数 N：`/handoffx-recall` → N=5；`/handoffx-recall 10` → N=10；非数字 → 默认 5；0 或负数 → 拒绝并提示"请给一个正整数，例如 /handoffx-recall 10"
- 永远读：Project Overview / Current State / Known Gotchas
- 按 N 条读：最近 N 条 Dev Log 条目
- 不读：Decision Log / Architecture / Testing / Credentials / Milestones / Features / References（除非用户明确要求）
- 不读：HANDOFFX.archive.md（除非用户明确要求"翻旧账"）
- 汇报第一行必须明示本次读取范围
- **只读不写**——不自动触发 /handoffx，不改任何文件（唯一例外：步骤 0 里用户明确确认的升级）
- 汇报完等用户指令，不主动开始改代码

**这是 recall，不是 write。不要调用 date 或追加 Dev Log。**
