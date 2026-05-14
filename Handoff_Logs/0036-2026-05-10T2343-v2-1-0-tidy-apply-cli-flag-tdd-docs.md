---
schema: 2
type: dev-log
date: 2026-05-10T23:43
number: 0036
title: v2.1.0 UX 第 2 件 — tidy `--apply` CLI flag + 4 份用户文档同步（TDD + sub-agent review）
---

### 2026-05-10 23:43 — v2.1.0 UX 第 2 件 — tidy `--apply` CLI flag + 4 份用户文档同步（TDD + sub-agent review）

**触发**: v2.1.0 UX backlog 第 2 件——把 K5 真机暴露的隐性入口 `HANDOFF_TIDY_AUTO_MIGRATE=1` 升级为 first-class CLI flag `--apply`。CLI flag 是行业惯例（git/npm/brew 都是 `--yes`/`--force`/`--apply`），ENV var 是隐性入口、不可发现、用户文档没记录；UX #2 的目的就是让非交互 migrate 触发点**自我文档化**。

**改动**:
- **TDD 流程**:
  - RED：写 `tests/test_tidy_handoff.sh` Case 17a-e 5 个测试（flag-before-file / file-before-flag / 警告含 `--apply` / flag+env 共存 / `-h` help 含 `--apply`），跑 → 7 fail（17b 退出码意外为 0 因为 non-interactive 静默退出 0，但 v2 marker 断言 fail；其余符合预期）
  - GREEN：`scripts/tidy-handoff.sh` 头部新增 GNU 风格 flag parser（`for arg in "$@"` 循环，`--apply` / `-h` / 未知 `-*` / 位置参数分流）；migrate gate 新增 `if [ "$APPLY_FLAG" = "1" ]` 分支（优先级高于 ENV）；非交互 warning 三路提示（`Re-run interactively, pass --apply, or set HANDOFF_TIDY_AUTO_MIGRATE=1`）；`-h`/`--help` 输出多行含 `--apply` 说明
  - 验证：53 passed / 0 failed（v2.0.0 是 46/0，本次 +7）
- **dual-source 同步**：`cp` + `diff -q` 验 byte-equal
- **sub-agent 独立 review**（pr-review-toolkit:code-reviewer，agentId `ae678381434edc997`）找出 0 Critical + 5 Important，全部落实:
  - **I-1**：dead `--)` case 占位但永远到不了（loop 不进入 "rest-are-positional" 模式）→ 删 3 行
  - **I-2**：`skills/handoff/references/handoff-tidy.md` 用户面文档完全没提 v1 迁移路径 → 新增"步骤 0：v1 layout 自动检测"段，含触发场景表
  - **I-3**：`Mac Project Transfer.md` §7.4（runtime 消息 + 例子）+ §10（troubleshooting）+ §11（backlog 关闭）三处同步
  - **I-4**：`MIGRATION_GUIDE_v2.md` 触发表加 `--apply` 行（推荐位）+ ENV 行标"v2.0.0 旧路径，向后兼容"
  - **I-5**：`CHANGELOG.md` [Unreleased] v2.1.0 Key changes 加 UX #2 三条 bullet（脚本 / 测试 / 4 份文档）
- **架构原则继续**：每条 v2.1.0 改动 = 脚本 + 双副本 + 测试 + 用户文档 + CHANGELOG 五线同步，独立 reviewer 闭环
- 走过的弯路:
  - 第一版 flag parser 含 `--)` 占位 case，想着"留个口将来加 `--` 分隔符支持"——reviewer 标 I-1 指出这是 dead branch + 易误导，删掉。Karpathy#2 simplicity first：speculative case 不留
  - Case 17b（`HANDOFF.md --apply` 顺序）一开始我以为会自然 fail，但 RED 跑出 exit 0——原来 non-interactive 无 env 路径会 "warn + exit 0" 让退出码看起来对，必须配合 "v2 marker added" 断言才能捕到"看似过了但实际没迁移"的情况。教训：退出码不够，必须有副作用断言

**验证**:
- `bash tests/test_tidy_handoff.sh` → **53 passed / 0 failed**（v2.0.0 46/0；本次 +7 = 5 个新 Case 17 + 2 个变体绿）
- `bash tests/run_all.sh` → **22 套件全绿**（无回归）
- `diff -q scripts/tidy-handoff.sh skills/handoff/scripts/tidy-handoff.sh` → 一致
- 5 个 reviewer 发现物 100% 落实（含 dead code 清理 + 4 文档同步）
- bash 3.2 兼容性 reviewer 实测验证（`/bin/bash` 3.2.57 跑过）：`for arg in "$@"` + 空 `$@` + 空 `FILE` 全部 `set -u` 安全
- 向后兼容：`HANDOFF_TIDY_AUTO_MIGRATE=1` 旧调用方式 100% 工作（Case 17d 验证 flag+env 共存无冲突）

**关联**: Decision 0013（v2.1.0 scope = UX-only，race 推 v2.2.0，本条是 scope 内第 2 件）；Dev Log 0035（v2.1.0 #1 lint 同义词容忍）；sub-agent review thread `ae678381434edc997`（5 findings 全闭）；CHANGELOG.md `[Unreleased] — v2.1.0 in progress` 累计两条 UX 落地；v2.1.0 还剩 3 项（postflight 聚合脚本 / gitx-release v2 exclusion / Mac Project Transfer 最终收口）
