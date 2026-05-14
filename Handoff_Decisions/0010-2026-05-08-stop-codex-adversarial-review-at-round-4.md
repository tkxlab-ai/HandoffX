---
schema: 2
type: decision
date: 2026-05-08
number: 0010
title: Stop Codex adversarial review at Round 4
---

### 2026-05-08 — Stop Codex adversarial review at Round 4

- **背景**: 4 轮 Codex review 每轮稳定找 3 条 finding（R1-R4 = 3/3/3/3，共 12 条）。所有 critical / high 类已修；R4 末几条已是 corner case（filename↔frontmatter date drift、归档子目录扫描遗漏、regenerate_pointers mtime race）。Gotcha #12 历史经验：v1.2.6→v1.2.9 同样模式 4 轮没收敛，每修一轮引入新检测面，最终决定停在 v1.2.9 + 把剩余 finding 入 v1.3.0 backlog
- **选项**:
  - A. 继续 R5、R6...（每轮 3 条，无收敛迹象）
  - B. 停在 R4，剩余 corner case 入 v2.1.0 backlog
  - C. 重设计架构（引入 flock 全局锁，根除 race 类问题），然后再跑 review
- **选择**: B
- **拒绝 A 的原因**: 边际收益递减且发版窗口被持续拖延。Codex adversarial 是 asymptotic — 每修一条引入新检测面，停在哪轮都是判断题，不存在"修到无 finding"的终态
- **拒绝 C 的原因**: flock 重构是 spec 改动级别的工程量（需要把 /handoff write flow 整体加锁，影响 references docs + 所有调用方），不是 hotfix 范畴。强行塞 v2.0.0 会破坏发版节奏
- **反悔代价**: 低 — backlog 列表里清晰列了 R3 #8 + R4 #12 两条 race 项 + 任何 R5+ 可能发现的新 issue，未来 v2.1.0 一并解决
- **关联**: Gotcha #12（v1.2.x 4 轮停止决策的同源历史教训）；本次会话 Dev Log 0031（v2.0.0 release 收尾）；commit 8786a23（R4 三 fix 落地）
