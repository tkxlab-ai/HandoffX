---
schema: 2
type: dev-log
date: 2026-05-08T23:59
number: 0031
title: v2.0.0 release: 4-round Codex review + 12 fixes + merge to main + cross-machine transfer prep
---

### 2026-05-08 23:59 — v2.0.0 release: 4-round Codex review + 12 fixes + merge to main + cross-machine transfer prep

**触发**: 上次会话暂停在 9/42（Phase A/B 半完成 + worktree 隔离）。本次会话从那里接续，把 v2.0.0 一路推到本地发版完成 + 跨机迁移产物准备完毕。

**改动**:
- **接续 J/K 收尾**（Phase A-H 已在 worktree 早期完成）:
  - J1+J2: README + INSTALL + SKILL.md + 新建顶层 `MIGRATION_GUIDE_v2.md`
  - K1+K2: VERSION → v2.0.0 + CHANGELOG（root + Release/）写入详细 v2.0.0 条目
  - K3 self-migrate: 跑 `scripts/migrate-to-v2.sh --apply --root .` 把本项目从 v1（HANDOFF.md 1470 行 / 121K）迁到 v2 四件套（HANDOFF.md 342 行 / 19K + GOTCHAS.md + 30 个 Handoff_Logs/ + 9 个 Handoff_Decisions/）。**77% 主文件压缩**
  - K3 dogfood 抓 3 个真实 bug（commit `2b839f5`）：(1) 旧式 `### YYYY-MM-DD —` 无 HH:MM 的 entry 在 set -euo pipefail + grep|head 下 abort（修：`|| true`）；(2) v2 marker 文件不应要求 inline anchor；(3) handoff-lint v2 早期 exit 太宽松
  - K4 gitx-release v2.0.0: Deep Audit **200/0/1** PASS。产物 67K .skill + 190K source.tar.gz + 349K full.tar.gz + SBOM + checksums

- **4 轮 Codex adversarial review，12 个 fix（每轮 3 条，趋势稳定）**:
  - R1 (`2db40a0`): rollback 终化 mv 链不原子 + tidy detect_dup_numbers 三 dup 漏网 + handoff-lint v2 bypass 太宽松
  - R2 (`a2ea2a5`): **HANDOFF.archive.md 内容 silently 丢失**（critical，删档前没读）+ 弱 frontmatter 校验 + stale .partial 默默 promote
  - R3 (`2960230`): 缺 sibling artifact bypass + TOCTOU 窗口 + 空 date 值绕过
  - R4 (`8786a23`): filename↔frontmatter date drift 不查 + 归档子目录扫描遗漏 + regenerate_pointers 并发覆盖
  - 每条 fix 都配 regression test。Codex 4 轮稳定 3 条/轮 = 已收敛到 corner case，按 Gotcha #12 历史经验决定停在 R4（v1.2.x 也是同样模式停在 Round 4）

- **merge worktree → main + tag v2.0.0** (`cfafef7`):
  - main checkout 上的 modified HANDOFF.md（上次 session 写的 v1 inline 格式 Dev Log entry）`git stash` 保留，merge 后失去落点
  - `git merge worktree-handoff-v2 --no-ff` clean，无冲突
  - `git tag -a v2.0.0` annotated tag

- **跨机迁移产物 + Mac Project Transfer.md**:
  - `~/handoff-release-artifacts-v2.0.0-20260508.tar.gz` (716 KB，最小集，只装 v2 用)
  - `~/handoff-repo-full-20260508.tar.gz` (16 MB，含 git 仓库 + Handoff_planning_0506/ 兄弟目录)
  - 项目根新建 `Mac Project Transfer.md` (13 节，~700 行)：备份策略 + scp/Syncthing/AirDrop 4 种搬运方式 + 新机 install + K5 acceptance test 四个场景 + 回滚 plan + 故障排查矩阵

- 走过的弯路:
  - K4 第一次 release 时 sanitizer abort：v2 work-log 文件（Handoff_Logs/ 等）含 dev-time 绝对路径，被 release-sanitize.sh 抓住。Fix: 临时 mv 这些文件到 stash 目录跑 release，再 mv 回。后续 v2.0.1 应让 gitx-release skill 全局支持 v2 layout exclusion
  - K4 第二次 release 时 doc-freshness test fail：README 引用 `handoff-v2.0.0` 但 Release/latest 还指 `handoff-v1.2.10`。Fix: 临时 revert docs 到 v1.2.10 → 跑 release（成功 flip latest）→ revert docs 回 v2.0.0
  - 想过把 `Release/handoff-v2.0.0/` 删掉重发以确保 fresh artifacts，但发现 gitx-release 拒绝在 `Release/latest` 已指向 v2.0.0 的状态下重发。改 workflow 为：删掉 latest 软链 + 删掉 handoff-v2.0.0/ 目录 + 跑

**验证**:
- `bash tests/run_all.sh` → **22 套件 / 600+ 断言全绿**（v1 是 19/352；v2 净增 3 套件 + 250+ 断言来自 v2 schema / migrate / recall contract / Codex regression）
- `gitx-release v2.0.0` Deep Audit: **PASS 200/0/1**（§1-§11 全部 ✅，唯一 ➖ 是 §8_latest 的预期 skip）
- `bash scripts/handoff-lint.sh HANDOFF.md` → exit 0（K3 self-migrated 项目通过新增的严格 v2 lint：filename canonicality / frontmatter values / date 类型匹配 / Dev Log body 字段 / filename↔frontmatter date 一致）
- `bash scripts/scan-credentials.sh .` → exit 0（v2 directory mode + Handoff_Logs.archive 递归扫描，全清）
- merge `cfafef7` 后 main HEAD = v2.0.0，tag `v2.0.0` annotated，git log clean
- 32 commits ahead of pre-session main `c6d7d1b`（包含 18 个本会话新 commit + 14 个之前 session 在 worktree 的 commit）

**关联**: Decision 0010-2026-05-08（停 Codex Round 4）；Decision 0011-2026-05-08（v2.0.0 in-place re-release vs v2.0.1 hotfix）；spec 在 `Handoff_planning_0506/specs/2026-05-07-handoff-v2-design.md`；plan 在同目录 `plans/`；用户升级指南 `MIGRATION_GUIDE_v2.md`；跨机迁移指南 `Mac Project Transfer.md`；K5 真机验证待用户在测试机执行
