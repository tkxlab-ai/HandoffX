---
schema: 2
type: decision
date: 2026-05-11
number: 0015
title: v2.1.1 — 修 K4 鸡蛋问题选 B（改测试真相源），拒 A（移除断言）/ C（procedural workflow）
---

### 2026-05-11 — v2.1.1 — 修 K4 鸡蛋问题选 B（改测试真相源），拒 A（移除断言）/ C（procedural workflow）

**背景**

v2.0.0（Dev Log 0031）和 v2.1.0（Dev Log 0039）两次 release 撞同一个 K4 doc-freshness 鸡蛋问题：root README/HANDOFF 引用 v-next（即将发的版本）但 `Release/latest` symlink 仍 → v-prev（上次发的版本）→ `tests/test_doc_freshness.sh` Test 4 + 5 判 stale → run_all fail → release 卡住。Workaround：暂时 revert root docs 回 v-prev → 跑 release → 升回 v-next → re-commit。后果（gitx-release audit v2.1.0 实测发现）：tarball 内 `Release/handoff-v2.1.0/README.md` 锁死 v2.0.0 snapshot，§3_sync 发现 root README ≠ flattened README。两次发版都中招，确认是设计层问题不是操作错。

**触发**

v2.1.0 发版后 Boss 选择实战观察期（Dev Log 0040），跑 `/gitx-release` → audit v2.1.0 揭穿 §3_sync 的 README drift 残留——根因是 K4 设计缺陷而非 v2.1.0 release 操作错。Boss 选项 C（发 v2.1.1 修 K4 设计），不愿继续靠手动 revert workaround 应付未来 v2.2.0 / v3.0.0。

**选项**

- **A**：从 `test_doc_freshness.sh` 移除 Test 4（`README.md Release/latest 引用`）+ Test 5（`HANDOFF.md Current State 版本号`）两条断言。**拒**——这两条本身是有价值的 gate（防止文档忘 bump），完全移除等于失去保护。Karpathy#3 surgical violation——把一个真问题（gate 真相源错位）当借口删掉合法保护。
- **B（选）**：改 `test_doc_freshness.sh` 的版本真相源——从 `readlink Release/latest`（产物状态，时间线滞后）切到读 root `VERSION` 文件（工作树状态，时间线对齐）。语义对齐："README 描述自己所在版本的发版状态"，不是"描述当前 deployed 状态"。
- **C**：procedural workflow 改造——禁止开发期把 root README/HANDOFF 直接 bump 到 v-next，要求 release.sh pipeline 自动在 `Release/latest` 翻转后再 bump root docs（让 `Release/latest` 永远领先或等于 root）。**拒**——
  1. 复杂度暴涨：release.sh 必须从只产物造作变成"既造产物又改源码"，违反 gitx-release skill 的"不改业务代码"约束（§关键约束 #2）
  2. 反直觉：开发期 root docs 自然引用即将发的版本，强制锁定上版反人类
  3. 仍有窗口期：release.sh 翻 `Release/latest` 与 bump root docs 之间也是异步的，要么需要全程锁，要么仍有不一致窗口

**理由（为何 B）**

1. **Linus #1 真问题**：K4 已撞两次（v2.0.0 + v2.1.0），第二次还把 cosmetic drift 锁进 release tarball。不是想象出来的，是反复发作的实际痛点。
2. **Linus #2 简单**：6 行代码改动（helper rename + 真相源切换 + 标签更新）+ 1 个 RED guard test。0 复杂度增量。
3. **Linus #3 不破坏**：稳态下（VERSION == Release/latest target，即 release 完毕后日常状态）行为字节一致；只在 release pipeline window 期改善。已有保护（防止文档忘 bump）100% 保留——README/HANDOFF 与 root VERSION 仍必须一致，root VERSION bump 时所有 doc 引用必须同步，否则 fail。
4. **Tacit#4 Why > How**：选 B 不只修了一次性 bug，还沉淀了 Gotcha #14 的设计教训"Pre-release gate 的真相源必须是项目当前状态，不能是 release pipeline 末端的产物状态"。这条教训跟 Gotcha #12 同根（闸门三准则），未来其他 gate 设计可复用。
5. **TDD enforcement**：新增 `test_doc_freshness_k4_chicken_egg.sh` 把"K4 不再回归"机械化——任何人未来把真相源改回 `Release/latest` 直接 RED fail。

**反方观点（为完整性记录）**

如果未来 `Release/latest` symlink 与 root VERSION 长期不一致（比如 release pipeline 中断在半途），test_doc_freshness 不再能捕获——但这是 release pipeline 自身的 invariant，应该由 gitx-release audit `§3_sync` 兜底（实测 v2.1.0 audit 确实捕获了 README drift，证明产物侧 gate 已经在工作）。pre-release（测试源）和 post-release（audit 产物）分层各司其职——这是 Gotcha #12 双层闸门思想的延续。

**结论**

选 B。落地：
- `tests/test_doc_freshness.sh`：`get_latest_release_version` → `get_project_version`，读 `$ROOT_DIR/VERSION`
- `tests/test_doc_freshness_k4_chicken_egg.sh`：新增 K4 regression guard
- `GOTCHAS.md`：+Gotcha #14
- `CHANGELOG.md`：v2.1.1 entry
- VERSION bump（root + skill）→ v2.1.1
- 跑 gitx-release v2.1.1 → 预期不再需要 K4 workaround → audit 209/0/0

**关联**：Gotcha #14；Dev Log 0041（本次实施）；Dev Log 0031（K4 第一次撞）；Dev Log 0039（K4 第二次撞）；Decision 0013（v2.1.0 scope）；Gotcha #12（闸门三准则同根）
