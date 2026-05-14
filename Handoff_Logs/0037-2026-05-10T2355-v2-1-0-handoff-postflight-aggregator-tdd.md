---
schema: 2
type: dev-log
date: 2026-05-10T23:55
number: 0037
title: v2.1.0 UX 第 3 件 — handoff-postflight.sh 聚合脚本（5-check 超集 + TDD + sub-agent review）
---

### 2026-05-10 23:55 — v2.1.0 UX 第 3 件 — handoff-postflight.sh 聚合脚本（5-check 超集 + TDD + sub-agent review）

**触发**: v2.1.0 UX backlog 第 3 件。本会话至少手动散装跑 6 次 4-5 个后置脚本——每次 `/handoff` 写完都重复一遍。UX 摩擦点：5 个独立脚本 → 5 个 exit code 检查 → 用户 / CI / sandbox 都要写胶水逻辑判断哪个 fail。聚合脚本一行跑 + 一行 PASS/FAIL 汇总，干掉这个摩擦。

**改动**:
- **TDD 真流程（先 RED 再 GREEN）**:
  - RED：写 `tests/test_handoff_postflight.sh` 8 个 test group / 20 个断言，跑 → exit 127 / "command not found"（脚本真不存在）→ 19/1 fail。是真 TDD 第一步
  - GREEN：写 `scripts/handoff-postflight.sh`（112 行）：GNU 风格 flag parser（`--quiet` 任意位置）+ `run_check` helper（mktemp 收输出 + 三态 ✅/❌/缩进失败 detail）+ 顺序跑 5 检查 + 汇总块（exit max + 失败列表）
  - 验证：20/0
- **5 检查范围**（实际是 4 连 backlog 的**超集**）:
  1. `scan-credentials.sh <project-root>`（v2 directory mode 扫 HANDOFF.md + GOTCHAS + Handoff_Logs + Handoff_Decisions）
  2. `validate-handoff.sh --readiness HANDOFF.md`
  3. `handoff-lint.sh HANDOFF.md` ← v2 新增检查，原 backlog 4-script 列表没含；postflight 一并纳入
  4. `rotation-reminder.sh HANDOFF.md`
  5. `archive-devlog.sh HANDOFF.md`
- **dual-source 同步 + run_all 自发现**：双副本 byte-equal（test_scripts_sync.sh 自动验）；run_all.sh `test_*.sh` glob 自动 picks up 新测试套件，无需手动注册
- **sub-agent 独立 review**（pr-review-toolkit:code-reviewer，agentId `a678f49ebf1dbfdd1`）找 0 Critical + 2 Important + 3 Nit，关键发现并落实:
  - **命名约定违反** (Tacit#3)：脚本目录 13 个 hyphenated（archive-devlog / scan-credentials / handoff-lint / tidy-handoff 等）vs 1 outlier `postflight.sh`。**改名为 `handoff-postflight.sh`**——namespace prefix 跟 handoff-lint 一组，符合 `ls scripts/handoff-*` 自然分组。改名最便宜在 push 前，已执行（mv 脚本 + mv 测试 + 修 test 内 POSTFLIGHT 变量 + 修脚本 header + 修 --help text）
  - **5 处文档 drift**（reviewer 列点对点）：原文档把 4-script 后置检查写死 → 现在改为 "推荐 `handoff-postflight.sh` + 调试用 5-script fallback" 模式。更新点：
    - `skills/handoff/SKILL.md` §写入步骤 9 + §整理步骤 4
    - `skills/handoff/references/handoff-write.md` §后置（章节名 "四连" → "五连"）
    - `skills/handoff/references/handoff-tidy.md` 步骤 3
    - `Mac Project Transfer.md` §7.5
    - `HANDOFF.md` Current State 待办：本任务自身标 ✅（reviewer 指出"open checklist item is literally this task"）
    - `CHANGELOG.md` [Unreleased] v2.1.0 Key changes 加 UX#3 三条
  - **`--quiet` 隐含语义文档化**：reviewer 指出 quiet 不只压制 per-step 还压制失败 detail，可能让 CI 用户失去诊断窗口 → --help 新增一行"Re-run without --quiet to diagnose"自我文档化
- **Self-dogfood**：跑 `bash scripts/handoff-postflight.sh HANDOFF.md` 在本项目上 → 5/5 ✅ all checks passed exit 0
- 走过的弯路:
  - 初版命名 `postflight.sh`——单词无前缀，跟项目 13 个 hyphenated 脚本不一致。reviewer 标 Tacit#3 违反，改名前未 push 成本最低
  - 想过加 `mktemp` 失败防护（reviewer Nit #3：空 path 会让 `>"$out_file"` 失败但 exit code 仍对，但失败 detail 缺失，误导诊断）；reviewer 自己建议 defer，确实 macOS/Linux mktemp 极少失败，按 Karpathy#2 simplicity-first 不做
  - 想过加 `mktemp` 失败的 test case——TDD 应覆盖所有路径吗？回答：不。tactical TDD（覆盖用户路径）vs strategic（覆盖故障树）有边界，rare-path defense 在没有真实触发证据前不写

**验证**:
- `bash tests/test_handoff_postflight.sh` → **20 passed / 0 failed**（RED 19→GREEN 20，真 TDD）
- `bash tests/run_all.sh` → **23 套件全绿无回归**（v2.0.0 是 22，本次 +1 = 新增的 test_handoff_postflight.sh 被 run_all glob 自动发现）
- `bash scripts/handoff-postflight.sh HANDOFF.md` 在本项目 dogfood → 5/5 ✅
- `diff -q scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh` → 一致
- bash 3.2 兼容（reviewer 实测过）：`for arg in "$@"`、`local out_file ec=0`、`shift 2`、`"$@"` exec 全部 3.2 native
- 向后兼容：5 个底层脚本仍独立可调用 100%（聚合脚本是新增 entry point，没移除任何已有路径）
- 5 处文档更新全落实，reviewer 找到的 doc drift 全闭环

**关联**: Decision 0013（v2.1.0 scope = UX-only，本条是 scope 内第 3 件）；Dev Log 0035（UX #1 同义词容忍）；Dev Log 0036（UX #2 tidy --apply CLI flag）；sub-agent review thread `a678f49ebf1dbfdd1`（5 findings 全闭含 Tacit#3 命名违反 + 5 doc drift）；CHANGELOG.md `[Unreleased] — v2.1.0 in progress` 三条 UX 累计落地；v2.1.0 还剩 2 项（gitx-release v2 exclusion / Mac Project Transfer §10 SSH 端口 <private-port> 收口）
