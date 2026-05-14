---
schema: 2
type: dev-log
date: 2026-04-21T03:24
number: 0002
title: Release policy v2.0 → v2.1：合入 1by1 实战 11 项补充 + handoff v0.9 再装
---

### 2026-04-21 03:24 — Release policy v2.0 → v2.1：合入 1by1 实战 11 项补充 + handoff v0.9 再装

**触发**: 用户要求对比 `<sibling-project>/TKX_Git_Release_policy_and_process.md`（1by1 skill v0.3-β 发布实战总结）与本仓的 v2.0 policy，找出对 release 正确性有帮助的补充；并"全部整合"。完成后请求"更新最新版的 handoff 到 claude 中去"。

**改动**:
- `TKX_Git_Release_policy_and_process.md` — v2.0 → v2.1（889 → 975 行），新增/扩展 11 块：
  - 头部 v2.1 升级表 + TOC 标记 🆕 章节
  - §1 顶层原则 #11/#12/#13/#14：Install path > Code path / 评审不可自评 / 可回滚 / 大文档分批写入
  - §2.1 Pre-release 前置三要素（代码冻结 / 独立评审 / 无阻塞 TODO）
  - §2 Edit→Read-back 扩展：old_string 唯一性校验（`rg -cF` 必须 = 1）
  - §2 新段「大文档分批写入」：预估 > 200 行 → 先 touch 骨架，每轮 ≤ 200 行 + read-back
  - §3.2 / §3.4 Pre-release 后缀（alpha/beta/rc）+ GA 升级硬判据
  - §4 Pre-Release Gate 表新增 #0 前置三要素 / #7 install.sh 规范 / #8 git 历史脱敏
  - §5.5 / §5.6 git 历史脱敏 + 自动化工具（gitleaks / trufflehog / git-secrets / detect-secrets）
  - §6.10 install.sh 标准接口：`--dry-run/--force/--prefix/--no-backup/--help` + 禁止事项 + 退出码
  - §7.5 CHANGELOG 与 ROADMAP 分离（CHANGELOG 只写已发布）
  - §8.5 / §8.6 24h/72h/2 周观察期 + 人类验证（非作者读 README）
  - §10.1 扩展：备份路径反例（skills/.bak 被 Claude Code 当新 skill）+ dev/release 漂移 + 用户数据混放
  - §10.9 扩展：Edit old_string 非唯一 + 单次 Write 大文档两条新防呆
  - §11.5 Yank / 撤回流程（追加 `-yanked` tag，不 force-push 删 tag）
  - §12.5 附录「10 分钟速检清单」10 条 grep
  - 底部签名 v2.0 → v2.1
- `~/.claude/skills/handoff/` — 跑 `bash install.sh` 全局再装（源 skills/handoff/ 与目标 diff -rq = 0，属幂等操作，无实际文件变更）
- `~/.claude/commands/handoff.md`、`handoff-recall.md`、`handoff-tidy.md` — slash shim 刷新

**验证**:
- `wc -l TKX_Git_Release_policy_and_process.md` → 975 行；`grep -c 🆕` → 46
- `grep -nE "^## |^### "` 检视结构连贯，`§7.5` 正确落在 `§7.4` 之后（过程中曾误插到 §7.4 之前，已用 Edit 纠正）
- `diff -rq skills/handoff/ ~/.claude/skills/handoff/` → exit 0（完全一致）
- `bash install.sh` → "✅ Skill 安装到 ~/.claude/skills/handoff/"
- 本会话 system-reminder 的 skills 列表确认 `handoff` / `handoff-recall` / `handoff-tidy` 均在线

**关联**: 无（1by1 policy 是外部参考，不是本仓 Dev Log 延续；本次合入的 11 项未触及 Handoff skill 源码）

**待办变动**:
- 🆕 新增：按新 v2.1 §6.10 检查当前 `install.sh` 是否齐 `--dry-run/--force/--prefix/--no-backup/--help`（当前只有 `--global/--project/--template/--uninstall/--help`，接口不对齐）
- 🆕 新增：新增 `scripts/release-audit.sh` 骨架（v2.0 §8.2 引用但仓库未见该文件）
- 🆕 新增：policy v2.1 本身超 800 行，下次编辑必须按新规则「大文档分批写入 ≤ 200 行 + read-back」执行

