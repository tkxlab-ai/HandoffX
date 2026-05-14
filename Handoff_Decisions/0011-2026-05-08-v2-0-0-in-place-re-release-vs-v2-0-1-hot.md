---
schema: 2
type: decision
date: 2026-05-08
number: 0011
title: v2.0.0 in-place re-release vs v2.0.1 hotfix
---

### 2026-05-08 — v2.0.0 in-place re-release vs v2.0.1 hotfix

- **背景**: 本会话 K4 第一次 gitx-release v2.0.0 通过后，Codex Round 1-4 又找出 12 个 fix。问题：fix 应该重发 v2.0.0（替换本地未上传的 artifacts）还是 ship v2.0.1 紧跟其后？发布节奏 vs 版本号洁净度的权衡
- **选项**:
  - A. 每轮 fix ship 新版本（v2.0.0 → v2.0.1 → v2.0.2 → v2.0.3 → v2.0.4 → v2.0.5）
  - B. 每轮 fix 重发 v2.0.0（替换 Release/handoff-v2.0.0/ artifacts），最终发出去的"v2.0.0"已含所有 12 fix
  - C. fix 全部进 v2.0.0，但只做最后一次 gitx-release（不每轮重发）
- **选择**: B + C 混合 — Round 1 后重发一次（commit `37f2bea`），Round 2-4 只在最后整体重发一次
- **拒绝 A 的原因**: v2.0.0 还没 push 到 GitHub、还没真机装、还没分发给任何人。"v2.0.0 → v2.0.5 跨 4 小时" 会暗示重大问题，违背语义版本"已发布即不可撤"的精神。私下未发布的版本号洁净度优先
- **拒绝 C 的原因**: Round 1 fix 是发现 K4 已发的 v2.0.0 artifacts 来自有 bug 的代码，至少要确保**有过一次干净 release** 作为 sanity check。Round 2-4 就放心累积一次性重发
- **反悔代价**: 低 — 都是本地操作，没有任何外部副作用。万一新发现的 finding 严重到不能重发 v2.0.0（罕见），可以转发 v2.0.1
- **关联**: Decision 0010（停 Codex Round 4）；本次会话 Dev Log 0031；K4 release 流程在 `Mac Project Transfer.md` §6
