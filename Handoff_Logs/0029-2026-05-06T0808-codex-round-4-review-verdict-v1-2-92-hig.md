---
schema: 2
type: dev-log
date: 2026-05-06T08:08
number: 0029
title: Codex Round 4 review verdict + 决策停在 v1.2.9，2 条新 high 入 v1.3.0 backlog
---

### 2026-05-06 08:08 — Codex Round 4 review verdict + 决策停在 v1.2.9，2 条新 high 入 v1.3.0 backlog

**触发**: v1.2.9 commit 后跑第四轮 codex adversarial review（base=`b973251`）。verdict needs-attention，**2 条新 high**：(1) `tests/test_project_tree_forbidden.sh` 用 `[ -e "$m" ]` 过滤——dangling symlink（指向不存在目标的悬空软链）-e 返回 false，但软链本身在 project tree 里、rsync `-a` 会保留，闸门有理论 false negative；(2) `HANDOFF.md.bak*` 类**故意不在** project_tree_forbidden 里（避免每次 tidy 后测试红），但 artifact-content 测试在 release preflight 又被 skip（Round 3 主因），等于 Round 1 v1.2.6 leak class 在 v1.2.5 → v1.2.9 直接升级路径下没被自动闸门覆盖。

四轮 review 趋势：2 → 2 → 1 → 2。**没收敛**——每次修补都引入新检测面，codex adversarial 模式会持续找。决策停止迭代。

**改动**:
- `HANDOFF.md` Current State 待办区——追加两条 v1.3.0 候选 + 新增"🔬 Codex Round 4 finding (2026-05-06)"段落，记录 4 轮趋势、两条 finding 性质、修补选项、停止理由（codex log 留作下次起点）
- 无代码改动、无 release、无 commit-of-fix——本条 Dev Log + 即将追加的 Decision Log 是唯一持久化产物
- 走过的弯路: 一开始想发 v1.2.10 把 dangling symlink 1 行 fix（`[ -e ] || [ -L ]`）+ regression test 一并修——但 Finding 2 是 v1.2.6 同类 leak 的延续，半修不如不修，且改 tidy 备份位置 / 改上游 wrapper 都属于结构重设计，应该集中到 v1.3.0 独立做

**验证**:
- 无代码改动；`bash tests/run_all.sh` → 21 套件 / 359 passed / 0 failed（与 v1.2.9 一致）
- `bash scripts/validate-handoff.sh --readiness HANDOFF.md` → ✅ structure OK
- 4 轮 codex review 全部日志保留在 codex companion 内部（thread IDs `019dfce3-...` / `019dfd0f-...` / `019dfd80-...` / `019dfda1-...` / `019dfdbe-...`），下次需要可重检
- Git 历史：`b973251` (v1.2.4 init) → `87e0326` (Dev Log) → `9d14a43` (v1.2.6) → `feb1229` (v1.2.7) → `74f1b61` (v1.2.8) → `3dba6bc` (v1.2.9) → `4812bb2` (Round 4 backlog)

**关联**: Decision 2026-05-06（停止 codex iteration）；v1.3.0 backlog 两条 finding 已进 Current State 待办

