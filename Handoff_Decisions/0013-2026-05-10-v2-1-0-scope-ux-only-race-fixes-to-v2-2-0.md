---
schema: 2
type: decision
date: 2026-05-10
number: 0013
title: v2.1.0 scope = UX polish only；race 修复推延 v2.2.0
---

### 2026-05-10 — v2.1.0 scope = UX polish only；race 修复推延 v2.2.0

- **背景**: K5 PASS 后 v2.1.0 backlog 共 6 项，4 项 UX（lint 同义词 / `HANDOFF_TIDY_AUTO_MIGRATE` CLI flag / Mac Project Transfer 补丁 / gitx-release v2 exclusion）+ 2 项 race（migration flock / pointer-regen flock，Codex Round 3 #8 + Round 4 #12 未完成）。Boss 明确"用户做起来用起来更顺手很重要，越简单越舒适越方便越好"——把发布范围裁到只对用户感知友好的项是个 explicit 选择，要不要把 race fix 一起带上是要权衡的
- **选项**:
  - A. v2.1.0 = 全部 6 项（4 UX + 2 race），一次发齐
  - B. v2.1.0 = 4 UX only；2 race 推延 v2.2.0
  - C. v2.1.0 = 2 race only（"稳定性优先"——race condition 听起来严重）
- **选择**: **B**
- **拒绝 A 的原因**:
  - (i) race fix 真做对（flock 包整体 migration / 包整体 pointer regen）改动面比 UX 大得多——加 lock 还要测在 macOS BSD flock + Linux util-linux flock 两套语义下都对，比同义词容忍的"加 OR 分支 + 错误消息双语"工作量大 5-10 倍
  - (ii) 发布主题混杂——"UX + race"两个不同性质的改动混进同一版，CHANGELOG 难写、用户 release notes 难读、回滚粒度变粗
  - (iii) v2.1.0 时机紧（K5 刚 PASS，Mac mini 即将作为 dev 机用），把 race fix 这种 1-2 周工作量塞进来会大幅延迟 UX 收益落地
- **拒绝 C 的原因**:
  - (i) race 实战触发概率 ≈ 0——`/handoff` 是人手单线触发；`migrate-to-v2.sh` 是 one-shot 升级（永远不会两个用户并发跑同一项目）。Codex 找出 race 不代表实战痛
  - (ii) 现有缓解（`assert_dest_clear` 缩 TOCTOU 到 rename(2) syscall + `regenerate_pointers` mtime-check 把 silent-loss 变 deterministic-failure）已把"用户感知失败"前置——不会丢数据，只会 deterministic refuse
  - (iii) 用户感知 = 0 的发布违背 Boss 的"用户方便越好"主导原则——release 应该有用户感知意义
- **反悔代价**: 低 — race fix backlog 项已在 HANDOFF.md 列着不会丢；v2.2.0 主题就叫 robustness release，逻辑自洽。任何时候如果 Codex 找出 race 真的可被实战触发（比如 CI 矩阵跑多机并发测试），可以紧急拉 v2.1.1 hotfix
- **延伸推论**:
  - v2.1.0 4 项 UX 之间没显著耦合，可以按"用户感知频率"分别先后做：lint 同义词（每次写 Dev Log 摸到）→ tidy `--apply` CLI flag（每次 CI/sandbox 摸到）→ Mac Project Transfer 补丁（迁机才摸到）→ gitx-release v2 exclusion（release 才摸到）
  - 每项做完独立 commit + push，K3 self-dogfood 节奏继续保持
- **关联**: Decision 0012（v2.0.0 in-place re-release，相同的"已发布的版本号不轻易动"精神）；Dev Log 0035（v2.1.0 第 1 件 lint 同义词容忍完成）；v2.1.0 还剩 4 项在 HANDOFF.md 待办；v2.2.0 = robustness release（race fix 主体）
