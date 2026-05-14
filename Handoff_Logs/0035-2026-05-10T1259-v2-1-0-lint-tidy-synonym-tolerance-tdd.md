---
schema: 2
type: dev-log
date: 2026-05-10T12:59
number: 0035
title: v2.1.0 UX 第 1 件 — handoff-lint + tidy 同义词容忍（TDD + sub-agent review）
---

### 2026-05-10 12:59 — v2.1.0 UX 第 1 件 — handoff-lint + tidy 同义词容忍（TDD + sub-agent review）

**触发**: Boss 明确 v2.1.0 主题为 UX polish（"用户越方便越好"），race 修复推延 v2.2.0（详见 Decision 0013）。从 backlog 6 项里挑用户感知最广的"lint 同义词容忍"先做——34 个现有 Dev Log + 未来每条手写都受益。

**改动**:
- **TDD 流程**：
  - RED：先写 3 个 fixture 测试（C-v2-en-aliases-ok / C-v2-mixed-aliases-ok / C-v2-typo-rejected），跑 `bash tests/test_handoff_lint.sh` → 2 fail（"Trigger" 被 strict 中文 check 拒）+ 1 已 GREEN（typo `Tigger` 本来就该拒）
  - GREEN：在 `scripts/handoff-lint.sh` 加 `has_any_body_field` helper + 替换 strict 4-field loop 为同义词对（触发≡Trigger / 改动≡Changes / 验证≡Verification / 关联≡Related）+ v1 awk regex OR-pattern 同步更新
  - 错误消息双语提示："missing body field: **触发** (or **Trigger**)" —— 自我文档化，用户不用 grep 源码就知道接受的别名
  - 验证：43 passed / 0 failed（v2.0.0 是 41/0，新增 2 个绿测试）
- **dual-source 同步**：`cp scripts/handoff-lint.sh skills/handoff/scripts/handoff-lint.sh` + `diff -q` 验 byte-equal
- **sub-agent 独立 review**（pr-review-toolkit:code-reviewer，agentId `ace7f3696ab793a98`）找出 1 Critical + 3 Important，全部落实：
  - **Critical**: `scripts/tidy-handoff.sh` 同样在 line 284-287 有 4 字段 awk check，没同步会导致 "lint 通过但 tidy 报缺字段" 矛盾 UX → 修复（含双副本）
  - **Important**: `skills/handoff/references/handoff-write.md` 用户文档没说英文别名合法 → 加段落（让 AI agent 知道两种写法都接受）
  - **Important**: `skills/handoff/references/handoff-tidy.md` 缺字段补 stub 应维持原条目语言风格 → 加说明（避免 split-personality 中英混塞）
  - **Important**: `CHANGELOG.md` 没 v2.1.0 条目 → 加 `[Unreleased] — v2.1.0 in progress` 章节，含 Why / Key changes / Backward compat / Not-in-v2.1.0 段
- **同义词字典**：
  - `**触发**` ≡ `**Trigger**`
  - `**改动**` ≡ `**Changes**`
  - `**验证**` ≡ `**Verification**`
  - `**关联**` ≡ `**Related**`
- **架构原则**：每条 v2.1.0 改动必须 lint + tidy 锁步同步（两者本来就在enforce 同一 invariant，misalignment 立刻露出来）
- 走过的弯路:
  - 一开始想用 bash associative arrays 做 synonym dict，注意到 CLAUDE.md 要求 bash 3.2 兼容性，改用 `has_any_body_field(file, syn1, syn2, ...)` 函数 + variadic `"$@"` 迭代——3.2 safe
  - reviewer 发现的 Critical "tidy 漏同步" 在我设计阶段没考虑到——只想着 lint。教训：dual-enforcer 场景（lint + tidy）必须把"两边一致性"加进 RED 检查清单
  - false-positive 风险（用户在 body 里写 `**Trigger**` 当 inline-bold token 而非 field marker）reviewer 标为 pre-existing class（中文 `**触发**` 也有同样问题），不在本次 scope

**验证**:
- `bash tests/test_handoff_lint.sh` → **43 passed / 0 failed**（v2.0.0 是 41/0；本次 +2 = synonym tolerance 双向覆盖）
- `bash tests/run_all.sh` → **22 套件全绿**（无回归）
- `diff -q scripts/handoff-lint.sh skills/handoff/scripts/handoff-lint.sh` → 一致
- `diff -q scripts/tidy-handoff.sh skills/handoff/scripts/tidy-handoff.sh` → 一致
- `bash scripts/handoff-lint.sh HANDOFF.md` → exit 0（项目内 34 个 Dev Log + 12 Decision 全过 backward-compat 检查）
- 同义词 fixture 抽样：full-EN body / mixed CN+EN body 都过 lint；`**Tigger**` typo 正确 reject 且消息指向 canonical `**触发**`
- 4 个 reviewer 发现物 100% 落实

**关联**: Decision 0013（v2.1.0 scope = UX-only，race 推 v2.2.0）；Decision 0012（不发 v2.0.1 hotfix，docs gap 一起进 v2.1.0）；Dev Log 0034（K5 PASS，本次工作的前置条件）；sub-agent review thread `ace7f3696ab793a98`（可 SendMessage 继续）；CHANGELOG.md `[Unreleased] — v2.1.0 in progress`；v2.1.0 backlog 还剩 4 项（HANDOFF_TIDY_AUTO_MIGRATE CLI flag / Mac Project Transfer 补丁 / gitx-release v2 exclusion / postflight 聚合脚本）
