---
schema: 2
type: dev-log
date: 2026-05-11T19:15
number: 0045
title: v2.1.5 — 11 轮 superpowers 循环 code-review 收口（5 Critical + 16 Important + 2 structural guards）
---

### 2026-05-11 19:15 — v2.1.5 — 11 轮 superpowers 循环 code-review 收口（5 Critical + 16 Important + 2 structural guards）

**触发**: v2.1.4 hot-fix 之后 Boss 要求"调 superpowers 的 code reviewer 对项目进行整体循环 auditing。需要连续三轮 auditing 的 review 没有出现任何 bug 才可以停止"。CLAUDE.md §4 authoring/review 必须分离 — 我自己写的 4 个 patch（v2.1.1-v2.1.4）需要独立 reviewer 验证质量。每轮派 `general-purpose` subagent（独立 context，不见我作者侧思路），找 bug → 我修 → 再 review。3 连续 0-bug 才停。

**改动**（11 轮汇总）:

| Round | Subagent | Verdict | Counter | 主要发现 |
|-------|----------|---------|---------|---------|
| 1 | `af7ada24ff6ce6ddf` | 3C+5I | 0 | INSTALL/HANDOFF/README path drift / v2.1.4 Edit replace_all silently 0 替换 / K4 test fresh-clone leak / Decision 0017 Outcome 未回填 / 三 CHANGELOG copy 漂移 / install.sh both-exist 边角 / HANDOFF.md ASCII tree |
| 2 | `a4a8b2dc3e761bd70` | 1C+3I | 0 | `test_doc_freshness.sh:97` **silent-pass on dead path**（grep `2>/dev/null` 吞错误）/ TEST-SCENARIOS 7 个 suite 漏 + count drift（352→589 / 19→26）/ Mac Project Transfer 单数 `command/` 误导 |
| 3 | `aa618201a61774a04` | 1I + **+Test 15** | 0 | TEST-SCENARIOS count drift fix + **加 structural drift guard**（跨 5 doc 扫 `<N> 套件` 与实际一致；regex `^[1-9][0-9]*` 排除 `0` delta） |
| 4 | `af34841e5c9cabd35` | 2I | 0 | `doc-freshness 14/0` per-suite enum 漏更（Round 3 加 Test 15 → 总数 14→15，但 HANDOFF.md:37 没跟）+ `v2.1.5 commands→command-shims 兼容` 应是 `v2.1.3` (fat-finger 版本号) |
| 5 | `a21d5664b06898997` | 1I | 0 | HANDOFF.md:77 tautological arrow `command-shims/→command-shims/`（**Round 1 sed `commands/→command-shims/` over-applied，把 LHS 也替换了**）|
| 6 | `a48cba4ee6deb7e5a` | **0-bug** ✅ | **1** | 验证 Round 1-5 fix 全 ✅，2 个 Minor observation 与 established Minor 同类 |
| 7 | `a098ad913a1b3596a` | 1C+3I + **+Test 16** | 0 | Round 3 Test 15 **scope 漏 README.md**（最 user-facing doc 没扫到，`24 套件` stale）+ 3 处 `<N>/<N> ✅` stale (HANDOFF Linux/macOS + CHANGELOG v2.1.4) + Linux re-tested 26/26 + **加 Test 16** X==Y guard |
| 8 | `ad37f24a9ade42d13` | 1I | 0 | per-suite enum `doc-freshness 15/0` 漏更（Round 7 加 Test 16 → 总数 15→16，HANDOFF.md:37 又没跟，**同 Round 4 一类 bug recurrence**） |
| 9 | `af5c37b7a24642a99` | **0-bug** ✅ | 1 | 验证 Round 8 fix 干净，11 mechanical check 全 ✅ |
| 10 | `aae2fde0286f13a6c` | **0-bug** ✅ | 2 | 跑 install.sh 多 patch refactor 完整一致性 check + C10 bootstrap-rename 实际触发验证 |
| 11 | `a37a165140aca9bd0` | **0-bug** ✅ | **3 → STOP** | Linux container re-run 全绿 + 11 mechanical check + 推回 Round 10 CHANGELOG drift 分类（established Minor / Release frozen 不动） |

**累计 findings**: 5 Critical + 16 Important + 多 Minor（其中 4 项是真 Minor / 其余 observation-only 跟 established Minor 等价）。

**6 个 fix commit + 1 v2.1.5 release commit**:
- `87f4c77` (Round 1): 8 findings — path drift + Decision Outcome + K4 test + bootstrap-rename + dual-source sync
- `f04e54f` (Round 2): 4 findings — silent-pass + TEST-SCENARIOS + Mac Project Transfer  
- `3183fdd` (Round 3): 1 finding + **+Test 15**
- `357fe4c` (Round 4): 2 findings — per-suite enum + version typo
- `e260ad6` (Round 5): 1 finding — tautological arrow
- `10fc3ce` (Round 7): 4 findings + **+Test 16** + Linux re-tested
- `2727364` (Round 8): 1 finding — per-suite enum recurrence
- `c2dcd32` (Round 11 STOP → v2.1.5 release): bump VERSION + CHANGELOG + HANDOFF + tag

**关键 structural 沉淀**:
1. **Test 15** (`tests/test_doc_freshness.sh:194-220`): 跨 6 canonical doc（README + HANDOFF + INSTALL + CONTRIBUTING + TEST-SCENARIOS + Mac Project Transfer）扫 `<N> 套件` 与 `ls tests/test_*.sh | wc -l` 一致。`^[1-9][0-9]*` 排除 `0 套件` delta 描述
2. **Test 16** (`tests/test_doc_freshness.sh:222-241`): 扫 `<N>/<N> ✅` 平台兼容声称，X==Y 时必须等于实际 suite count；HANDOFF + Mac Project Transfer 覆盖
3. **Decision 0017 Outcome 段** (Round 1 I2 fix): plan-vs-actual drift 表 + 3 条 Outcome 教训
4. **install.sh:156-161 bootstrap-rename both-exist cleanup** (Round 1 I4 fix)
5. **K4 test CREATED_LINK flag** (Round 1 I1 fix): fresh-clone 边角

**跨轮 reviewer 沉淀的方法论**（这些是审视性收获，比任何一次具体修复更长远）:

1. **"每个 fix layer 揭露下一层 drift"** (Round 4 reviewer 提出，Round 5+7+8 反复验证)：
   - Round 1: content drift (path strings)
   - Round 2: dead-path drift (test references renamed file)
   - Round 3: aggregate count drift (`<N> 套件` mismatch)
   - Round 4: per-suite narrative drift (`doc-freshness 14/0` 自指)
   - Round 5: sed-collateral drift (remediation 脚本自己造的破坏)
   - Round 7: test-scope drift (Round 3 加的 Test 15 漏 README scope)
   - Round 8: per-suite enum recurrence (同 Round 4 类，靠 manual sync 不可持续)

   每轮 fix 后下一轮 reviewer 都找出新一层。**结论：structural test > 反复修同一类 bug**。Test 15+16 是模式 fix；遗留的 per-suite enum guard + rename-arrow guard 进 v2.2.0 backlog。

2. **同 context authoring/review 看不见盲点 — CLAUDE.md §4 第二次实证**：
   - v2.1.4 hot-fix 我自己写自测自审 → 自报 "INSTALL/README/CONTRIBUTING grep `skills/handoff/commands/` → 0 命中" verification PASS
   - 实际 Round 1 reviewer 5 分钟 grep → INSTALL.md 还有 **6 处**，HANDOFF.md 还有 **7 处**
   - 原因：Edit replace_all 报"success"但实际 0 替换（工具靜默失败）；同 context 看不见这种"显示 success 但实际没改"的 gap
   - **教训**：authoring/review 必须 mechanical 分离 — `git diff` / `grep` 验证不能由作者自己跑

3. **Recursive drift 模式**：reviewer 多次提到"Round N 加的 fix 自己就引入 Round N+1 的 bug"——典型 Round 3+Round 4（Test 15 → doc-freshness 14→15 → 自身 per-suite 没跟），Round 7+Round 8 重演（Test 16 → 15→16 → 自身 per-suite 没跟）。**靠 manual sync 不可持续，需 structural guard**

4. **established Minor 分类**：reviewer 在多轮间逐渐建立了"什么算 bug / 什么算 observation"的分类共识：
   - **Canonical living docs**（HANDOFF / README / INSTALL / CONTRIBUTING / CHANGELOG / Mac Project Transfer）的 current-state drift = bug
   - **Handoff_Logs/** 历史 session 记录 = immutable observation
   - **CHANGELOG 早期 release 段** 的 author-time 数据 = observation（不强制 forward-fix，但 canonical living 段必须修）
   - **Release/handoff-v2.1.x/** frozen artifact = observation（.gitignored 不在 commit 范围）
   - **v2.2.0 backlog items**（Recommendation 类） = NOT bug

**验证**:
- macOS bash 3.2 + arm64 M4 `bash tests/run_all.sh` → **26 suites / 591 assertions / 0 failed** ✅
- Ubuntu 22.04 mawk docker container 同上 ✅
- `bash tests/test_doc_freshness.sh` → **16 passed**（含 Test 15 + Test 16 structural guards）
- `bash tests/test_doc_freshness_k4_chicken_egg.sh` → 1/0 ✅
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → 5/5 ✅
- `diff -rq scripts/ skills/handoff/scripts/` → 0 deltas
- gitx-release v2.1.5 audit → **187/0/0 PASS**
- `git ls-remote origin refs/heads/main refs/tags/v2.1.5` → SHA 与 local 一致
- 跨平台兼容性 `26/26 ✅` claims 所有 canonical doc 同步

**关联**: 全 11 个 subagent IDs 见上表；Dev Log 0044（前置 — v2.1.4 hot-fix 由 review 触发，本次 11 轮循环是 §4 doctrine 的第二次 + 大规模实证）；Decision 0017 Outcome 段（Round 1 加）；Decision 0013（v2.2.0 race fix 推延继续有效，本周期纯 drift+docs+structural test 工作）；CLAUDE.md §4 doctrine（"authoring/review must separate / never self-approve in same context"）—— 第二次实证证明：单 reviewer 找出 21 个真 bug（5 Critical 用户面 + 16 Important plan-vs-actual + structural gaps）；v2.2.0 backlog 新增 6 项（per-suite enum guard / rename-arrow guard / Release CHANGELOG sync gate / Decision Outcome template / release.sh upstream-recalibration / .skill artifact sanity test）
