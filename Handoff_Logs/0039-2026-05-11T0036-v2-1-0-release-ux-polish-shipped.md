---
schema: 2
type: dev-log
date: 2026-05-11T00:36
number: 0039
title: v2.1.0 release — UX polish shipped (Deep Audit 203/0/1 PASS + tag pushed)
---

### 2026-05-11 00:36 — v2.1.0 release — UX polish shipped (Deep Audit 203/0/1 PASS + tag pushed)

**触发**: v2.1.0 UX backlog 全 5 项完成（Dev Log 0035-0038）后发版收口。

**改动**:
- **版本号 bump**：根 `VERSION` + `skills/handoff/VERSION` → `v2.1.0`
- **CHANGELOG 收尾**：根 `CHANGELOG.md` `[Unreleased] — v2.1.0 in progress` 改成 `v2.1.0 — 2026-05-11`；`Release/CHANGELOG.md` + `Release/handoff-v2.1.0/CHANGELOG.md` 的 gitx-auto-entry placeholder 替换成真实 release notes（Theme / Why / Key changes / Backward compat / Not in v2.1.0）
- **gitx-release v2.1.0 跑过**：`PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/gitx-release.sh --version v2.1.0`
  - Deep Audit **203 ✅ / 0 ❌ / 1 ➖** PASS（§8_latest skip 是预期）
  - 产物：`Release/handoff-v2.1.0/` 含 `.skill` (72K) + source.tar.gz (290K) + full.tar.gz (450K) + checksums + SBOM + RELEASE_NOTES
  - `Release/latest → handoff-v2.1.0` 原子翻转
- **README.md / HANDOFF.md 同步**：`当前版本` 字段 + `Release/latest →` 引用刷到 v2.1.0；项目阶段更新到 "v2.1.0 released (UX polish)"
- **走过的弯路**:
  - 第一次 release 跑 fail：`test_doc_freshness.sh` 报 HANDOFF.md "当前版本" 写 v2.1.0 但 Release/latest 还指 v2.0.0（K4 同款鸡蛋问题）。修法：暂时 revert HANDOFF.md 字段回 v2.0.0 → 跑 release（成功翻转 latest）→ 升 HANDOFF.md + README.md 回 v2.1.0 → 再跑 run_all 全过
  - PROJECT_NAME 自动检测会拿目录名 `Handoff`（首字母大写），gitx-release 期望全小写 `handoff` → 必须 `PROJECT_NAME=handoff` env 显式 override（与 K4 v2.0.0 一致）

**验证**:
- `bash tests/run_all.sh` → 23 套件全绿（v2.0.0 是 22，本次 +1 = test_handoff_postflight.sh）
- gitx-release Deep Audit: §2_docs 10/0 / §2b_quality 28/0 / §3_sync 7/0 / §4_changelog 3/0 / §5_tarball 15/0 / §6_skill 90/0 / §7_sanity 1/0 / §9_dual 1/0 / §10_notes 2/0 / §11_compliance 43/0 = TOTAL 203/0/1
- `Release/handoff-v2.1.0/handoff-v2.1.0.skill` 72421 bytes / SHA256 在 checksums.txt
- `Release/latest` 软链 → `handoff-v2.1.0` 字符串
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → 5/5 ✅
- annotated tag `v2.1.0` 已 push 到 private Git host origin

**关联**: Dev Log 0035-0038（v2.1.0 5 件 UX 工作）；Decision 0013（v2.1.0 scope）+ Decision 0014（项目本地 .sanitize-ignore）；Dev Log 0032（v2.0.0 push private Git host，本条对照）；commit + tag 是本会话最终 anchor — 下次接手直接从 `git pull origin main` + `git fetch --tags` 拿到所有内容
