---
schema: 2
type: dev-log
date: 2026-05-11T00:02
number: 0038
title: v2.1.0 UX 第 4 件 + 第 5 件收口 — `.sanitize-ignore` v2 layout 豁免 + SSH 端口 <private-port> doc，v2.1.0 backlog 全清
---

### 2026-05-11 00:02 — v2.1.0 UX 第 4 件 + 第 5 件收口 — `.sanitize-ignore` v2 layout 豁免 + SSH 端口 <private-port> doc，v2.1.0 backlog 全清

**触发**: v2.1.0 UX backlog 最后两项一并收口：(#5) Mac Project Transfer §10 SSH 端口 <private-port> 故障排查行；(#4) gitx-release v2 layout 豁免。**关键发现**：#4 不需要改全局 skill——调研发现 gitx-release 已存在 `.sanitize-ignore` 项目级 escape hatch，加 6 行项目本地配置就解决（详见 Decision 0014）。是 CLAUDE.md "先调研再动" 原则的典型收益。

**改动**:
- **#5 — Mac Project Transfer §10**（已先 commit `15ad1c0`）:
  - 故障排查表加一行：`nc -z host 22` / `ssh -p 22` 超时 → 真实端口 <private-port> 在 `~/.ssh/config`；reachability 用 `ssh -T` 或 `nc -z host <private-port>`
  - §11 backlog item 4 关闭标记 `~~SSH 端口非默认 22~~ ✅ closed in v2.1.0`
- **#4 — `.sanitize-ignore` v2 layout 豁免（本次 commit）**:
  - 调研结论：gitx-release 自带 `.sanitize-ignore` 项目级白名单（`release-sanitize.sh:71-100`）；语义"项目相对路径 glob pattern；豁免该路径的 sanitize 检测"
  - 项目根 `.sanitize-ignore` 新增 v2 layout 段：
    - `Handoff_Logs/*` `Handoff_Decisions/*` `GOTCHAS.md`
    - `HANDOFF.md.pre-v2-backup` `NEXT_SESSION_NOTES.md` `Mac Project Transfer.md`
  - 这些文件**有意嵌入** dev-time 绝对路径作为历史记录（Dev Log narrate / 迁移指南 / v1 备份），不是 deployed config
  - 验证：直接跑 `bash ~/.claude/skills/gitx-release/scripts/release-sanitize.sh .` → v2 layout 文件**全部从 findings 消失**；剩 noise (`Release/`、`.claude/settings.local.json`、`Release/handoff-v1.2.x/TEST-SCENARIOS.md`) 是 gitx-release staging 阶段 rsync `--exclude='Release'` 等会自动排掉的，不进 release 流程
- **Decision 0014**：写下"项目本地 vs 上游 skill 改" 决策推理（拒绝 A：全局 patch 污染通用工具；拒绝 C：wrapper 是把 K4 手动 mv 痛苦自动化，没真解决；选 B：用现有 escape hatch，0 全局副作用、0 跨项目影响）
- **HANDOFF.md Current State** 刷到 v2.1.0 全完成（5/5）；backlog 全部 ✅
- **CHANGELOG.md `[Unreleased]`** 加 UX#4 三条 bullet：`.sanitize-ignore` 加 v2 patterns / 用现有 escape hatch 不动上游 skill（Decision 0014）/ Mac Project Transfer §10 troubleshooting 加 SSH <private-port> 行（#5）
- 走过的弯路:
  - 原 backlog 写法："给上游 gitx-release 提 patch"——按字面读会去改 `~/.claude/skills/gitx-release/scripts/release.sh`。Linus#1 "先问真问题？" 触发调研，发现现有机制完全够用。教训：backlog 写法是当时的解法假设，开工前要先调研当前状态
  - 一开始试图直接跑 `release-sanitize.sh .` 验证，得到一堆 `Release/*` + `.claude/settings.local.json` findings——以为修不完。仔细看 release.sh staging 流程才发现这些在 staging 阶段就被 `rsync --exclude` 排掉了，sanitize 实际只对 staging 目录跑，不是项目原生树

**验证**:
- `bash tests/run_all.sh` → 23 套件全绿无回归
- `bash ~/.claude/skills/gitx-release/scripts/release-sanitize.sh .` → 6 个 v2 layout pattern 100% 豁免成功（这些文件不出现在 findings 里）
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → ✅ all 5 checks passed
- `.sanitize-ignore` 文法合规：所有新加 pattern 都带 literal path 前缀（不以 `*`/`?`/`[` 开头，避免 release-sanitize.sh:93 的硬阻断）

**关联**: Decision 0014（项目本地 vs 上游 skill 选择推理）；Dev Log 0035/0036/0037（v2.1.0 前 3 件 UX 工作）；commit `15ad1c0`（#5 SSH port 已先单独 push）；K4 原手动 workaround 文档（Dev Log 0031）；v2.1.0 backlog 全 5 项 ✅ 完结——可以考虑 v2.1.0 release tag 时机
