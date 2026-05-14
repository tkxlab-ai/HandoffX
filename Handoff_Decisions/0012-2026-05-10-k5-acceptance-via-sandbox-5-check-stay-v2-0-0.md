---
schema: 2
type: decision
date: 2026-05-10
number: 0012
title: K5 acceptance 用 sandbox 5-check + 停在 v2.0.0 不出 v2.0.1
---

### 2026-05-10 — K5 acceptance 用 sandbox 5-check + 停在 v2.0.0 不出 v2.0.1

- **背景**: Mac mini 测试机首次跑 K5 真机验证。两个相关权衡同时摆上桌：(1) K5 PASS 判据到什么粒度——只跑脚本层 sandbox 还是连同 Claude Code 内的 `/handoff-init` / `/handoff-tidy` slash command 行为也验？(2) K5 跑通后发现一个隐性入口 `HANDOFF_TIDY_AUTO_MIGRATE=1` 没在用户文档里出现，**这要不要 ship 一个 v2.0.1 docs hotfix**？
- **选项**:
  - A. K5 = sandbox 脚本层 5-check 全过即 PASS；docs gap 进 v2.1.0 backlog，不动 v2.0.0
  - B. K5 = sandbox + Claude Code 真跑 slash command；docs gap 立刻 ship v2.0.1（仅 docs 更新，不动代码）
  - C. K5 = sandbox 5-check（同 A），但 docs gap 立刻 ship v2.0.1（混合）
- **选择**: **A**
- **拒绝 B 的原因**:
  - (i) Slash command 是 AI 模型行为层，不可复现——同一个 prompt 在不同 model snapshot 上输出可能不同，"测过的 slash command" 等于"测过这一次 AI 调用"，不是发布层可断言的事实
  - (ii) sandbox 5-check 已覆盖 slash command 背后所有 deterministic substrate（template / migrate / 4 后置脚本 / pointer regen / frontmatter 验证），AI mediated layer 只是个 thin adapter
  - (iii) 真跑 slash command 在 CI / 其他人 review 时不可重现，没法当 release gate
- **拒绝 C 的原因（也是拒绝整体 v2.0.1 hotfix）**:
  - (i) `HANDOFF_TIDY_AUTO_MIGRATE=1` 这个 flag 在 runtime 已经会 print 出来——用户首次撞到 non-interactive 拒绝时**就在 stdout 看到了**，不是 silent 黑盒。文档化是 nice-to-have 不是 must-have
  - (ii) docs gap ≠ code defect，跟 Decision 0011 一致："已发布即不可撤"的精神适用于功能行为，不适用于纯文档收尾
  - (iii) ship v2.0.1 的成本不只是 docs：要走完整 release gate / tag / push / artifact 重发 / CHANGELOG 双向同步——为单条 ENV 变量加几句文档不值这个开销
  - (iv) v2.1.0 doc backlog 已经积了多条（race-free migration / gitx-release v2 exclusion / lint 同义词容忍 / SSH 端口非 22 说明），统一发是更符合 SemVer 节奏的发布节
- **反悔代价**: 低 — 选 A 后若实战中真的有用户被 non-interactive 护栏卡住反馈 confusion，仍可随时拉 v2.0.1 docs hotfix。当前没有真实痛点
- **关联**: Dev Log 0034（K5 PASS 事实记录）；Decision 0011（v2.0.0 in-place re-release 时的相同 SemVer 精神）；v2.1.0 backlog 新增项"`HANDOFF_TIDY_AUTO_MIGRATE=1` 文档化 + sandbox K5 范例"
