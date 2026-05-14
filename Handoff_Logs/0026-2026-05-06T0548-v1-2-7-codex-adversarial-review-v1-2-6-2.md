---
schema: 2
type: dev-log
date: 2026-05-06T05:48
number: 0026
title: v1.2.7 发版：Codex adversarial review 揭示 v1.2.6 残留 2 高危——shim 文本 Claude-only + tarball 漏 .bak
---

### 2026-05-06 05:48 — v1.2.7 发版：Codex adversarial review 揭示 v1.2.6 残留 2 高危——shim 文本 Claude-only + tarball 漏 .bak

**触发**: v1.2.6 commit 后跑 codex adversarial review（base=`b973251`，scope=branch），verdict **needs-attention**。两条 high-severity 残留：(1) v1.2.6 修了 OpenCode shim 安装路径，但 5 个 shim **文本**仍写 `~/.claude/skills/handoff/references/handoff-XXX.md`，OpenCode AI 读了被指向不存在路径——形似神不似；(2) `Release/handoff-v1.2.5/` 与 `Release/handoff-v1.2.6/` source tarball 都漏 `HANDOFF.md.bak.tidy-20260430-2322`，gitx-release wrapper 的 rsync exclude pattern `'HANDOFF.md.bak'`（无星号）匹配不到带后缀的 tidy 备份，泄漏项目内部 dev 状态。

**改动**:
- `skills/handoff/commands/handoff*.md`（5 文件）—— shim 文本从硬编码 `~/.claude/skills/handoff/...` 改成 portable wording：枚举 Claude Code / OpenCode / Codex 三家 skill 路径 + 项目级 `<project>/.<cli>/skills/handoff/`
- `HANDOFF.md.bak.tidy-20260430-2322` —— 删除（4 月底旧 tidy 备份，已无引用；让上游 wrapper exclude 不完美也漏不出去）
- `tests/test_release_artifact_content.sh` —— 新增；扫 `Release/latest/*-{source,full}.tar.gz` 内容，禁路径含 `(^|/)HANDOFF\.md$` / `HANDOFF\.md\.bak` / `HANDOFF\.archive` / `(^|/)memory/` / `\.tmp/` / `\.DS_Store$` / `Handoff_OldBackup_`；用 `LATEST_VERSION != DEV_VERSION → skip` 模式避开 release 进行中的 preflight 误判
- `HANDOFF.md` Gotcha #10 —— shim 文本必须 portable + tarball artifact-content 兜底闸门；与 Gotcha #9 互补
- `HANDOFF.md` / `README.md` 当前版本字段 + Release/latest 引用 → v1.2.7
- `CHANGELOG.md` + `Release/CHANGELOG.md` —— v1.2.7 完整条目
- 走过的弯路:
  - codex 还误报了一个"`evals/files/sample-HANDOFF.md` 也被禁路径匹配"——我的 pattern `HANDOFF\.md(\.|$)` 没锚定路径起点，顺便误抓 `*-HANDOFF.md`；改成 `(^|/)HANDOFF\.md$` 才精准
  - 第一版 test 没考虑"release 进行中 Release/latest 还指向旧版本"场景，直接 fail preflight；加上 dev VERSION vs Release/latest 版本号比对 skip 机制才能在 release pipeline 里跑通
  - 想过去改 user-level wrapper `~/.claude/skills/gitx-release/scripts/release.sh:399` 的 `--exclude='HANDOFF.md.bak'` → `--exclude='HANDOFF.md.bak*'`——但这是越权改全局 skill，影响其他项目；最终选项目级 artifact-content 测试 + 删 .bak 双重防御，让上游不完美也兜得住

**验证**:
- `bash tests/run_all.sh` → **20 套件 / 356 passed / 0 failed**（v1.2.6 是 19/354；本次 +1 套件 / +2 断言 = artifact-content）
- `bash tests/test_release_artifact_content.sh` → 2 passed（v1.2.7 source + full tarball 都干净）
- `gitx-release --version v1.2.7` → 🎉 Deep Audit PASS（197/0/1 SKIP/0 WARN）
- `Release/handoff-v1.2.7/` 完整产物（.skill 52K / source.tar.gz 167K / full.tar.gz 287K / SBOM / checksums）
- `Release/latest` → `handoff-v1.2.7`（原子更新）
- `tar tzf Release/handoff-v1.2.7/handoff-v1.2.7-source.tar.gz | grep bak` → 空（确认 .bak 不再泄漏）

**关联**: 新 Gotcha #10（shim 文本 portable + artifact-content 兜底）；与 Gotcha #9 互补——前者管"安装路径对"，后者管"安装内容对 + 分发产物干净"

