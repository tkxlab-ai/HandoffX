---
schema: 2
type: decision
date: 2026-05-06
number: 0009
title: Codex adversarial review iteration 停在 v1.2.9
---

### 2026-05-06 — Codex adversarial review iteration 停在 v1.2.9
- **背景**: 本会话从 v1.2.4 走到 v1.2.9，跑了 4 轮 codex adversarial review，共修 5 high + 13 minor。Round 4 verdict 仍 needs-attention 含 2 条新 high（dangling symlink + HANDOFF.md.bak 类）。趋势 2 → 2 → 1 → 2 没收敛，每次修补都引入新检测面。
- **选项**:
  - A. 修两条 + 发 v1.2.10 + 跑 Round 5（追极限）
  - B. 只修 Finding 1（symlink 1 行 `[ -e ] || [ -L ]`）+ 发 v1.2.10
  - C. 停在 v1.2.9 + 把两条 finding 写 v1.3.0 backlog
- **选择**: C
- **拒绝 A 的原因**: codex adversarial 模式会持续找——Round 5 大概率仍有 1-2 条。继续修补只是消耗时间不解决"是否能 ship"，且会让"修补链"越来越深、越来越难维护。已经发了 4 个 patch 版本（v1.2.6→v1.2.9），价值边际递减明显
- **拒绝 B 的原因**: Finding 1（dangling symlink）是理论 corner case，实际开发中罕见；Finding 2（.bak 类）才是真实风险但需要结构重设计（tidy 备份位置 / 上游 wrapper 修补 / 显式手动清理 三选一）。半修（只闭 corner case）会留尾巴误以为已经 fix 而忽略真问题
- **反悔代价**: 低——Finding 1 和 Finding 2 都已记入 v1.3.0 backlog；下次开会读 HANDOFF.md Current State 待办区即可起点。codex thread IDs 在 Dev Log 2026-05-06 08:08 留档可重检

