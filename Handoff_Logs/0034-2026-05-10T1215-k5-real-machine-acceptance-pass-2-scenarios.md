---
schema: 2
type: dev-log
date: 2026-05-10T12:15
number: 0034
title: K5 真机端到端验证 PASS：fresh project + v1 fixture auto-migrate 双场景全过
---

### 2026-05-10 12:15 — K5 真机端到端验证 PASS：fresh project + v1 fixture auto-migrate 双场景全过

**触发**: Mac mini 测试机 cleanup gate 通过（Dev Log 0033：985 个 `.syncthing.*.tmp` 全清 + `.gitignore` 加规则 + commit `5843cd0`+`ed7500c` 推到 private Git host）后启动 K5。K5 是 v2.0.0 发布后第一次在 fresh test machine 上跑端到端验证——验证已装 `~/.claude/skills/handoff/` 在真实场景能用，不只是测试套件全绿。

**改动**:
- 非代码改动；K5 acceptance 在 sandbox `/tmp/k5-test-2026-05-10/` 跑完即清，不留痕
- **Scenario A — fresh project init 闭环**:
  - `cp $SKILL/assets/HANDOFF.template.md → HANDOFF.md` + `cp $SKILL/assets/GOTCHAS.template.md → GOTCHAS.md` + `mkdir Handoff_Logs Handoff_Decisions`
  - v2 schema marker 在第一行 ✅
  - 后置 4 连：validate / scan / handoff-lint / archive-devlog 全 exit 0
  - 5 项结构断言（4 件套 + schema marker）全过
- **Scenario B — v1 fixture → tidy auto-migrate**:
  - 用 repo 内真实 v1 备份 `HANDOFF.md.pre-v2-backup`（121418 bytes / 1470 行 / 39 inline `### YYYY-MM-DD` entries）当 fixture
  - **第一次 `tidy-handoff.sh HANDOFF.md` 行为**：检测到 v1 layout，但**非交互式 shell 下拒绝迁移**，提示 "Re-run interactively, or set `HANDOFF_TIDY_AUTO_MIGRATE=1` to apply"——**这是预期的防误删护栏**，K5 第一次撞到才发现这个隐性入口没文档化
  - 第二次加 `HANDOFF_TIDY_AUTO_MIGRATE=1` 重跑，迁移成功：
    - Dev Log: 30 entries → `Handoff_Logs/0001-...md` ~ `0030-...md`
    - Decision: 9 entries → `Handoff_Decisions/0001-...md` ~ `0009-...md`
    - Gotchas: 13 → `GOTCHAS.md`（136 行）
    - Total 30+9 = 39 ✅ 与 fixture inline `### YYYY-MM-DD` 总数对齐（Dev Log 头 + Decision 头都匹配该 pattern）
  - HANDOFF.md.pre-v2-backup `cmp -s` byte-identical to 原 fixture ✅（121418 bytes 严格相等）
  - 迁移后 HANDOFF.md 顶部双行 `<!-- HANDOFF v2 schema -->` + `<!-- Migrated: 2026-05-10T19:13Z -->`
  - pointer block 自动生成 `共 13 条；最新：Gotcha #9 ...` + `共 9 条；最新：0009-2026-05-06...` + `共 30 条`
  - 抽样 `Handoff_Logs/0001-2026-04-20T0000-entry-79d8b9ae.md` frontmatter：`schema: 2 / type: dev-log / date: 2026-04-20T00:00 / number: 0001 / title: ...` ✅ 5 字段齐
  - 后置 5 连：validate / scan / handoff-lint / archive-devlog / rotation-reminder 全 exit 0
- 走过的弯路:
  - 第一次跑 tidy 的时候看到 "non-interactive shell; tidy will NOT migrate automatically" 一度以为是 bug——其实是设计意图的安全护栏。把对应 K5 测试改成两段：先验证护栏触发，再用 env var 显式越过
- **使用 INSTALLED skill 而非 repo source**：
  - 跑的脚本路径是 `~/.claude/skills/handoff/scripts/*.sh`、模板是 `~/.claude/skills/handoff/assets/*.template.md`——验证 install 后的运行时一致性
  - 反例（不用 repo `./skills/handoff/`）：因为 K5 验的是"fresh user clone + install 后能不能用"，repo dev 副本不算

**验证**:
- Scenario A 6 检查全过 / Scenario B 12 检查全过（含 non-interactive 护栏 + auto-migrate 路径）
- HANDOFF.md.pre-v2-backup 字节相等 = Migration **零数据丢失** 在真实 fixture 上得到证明
- 30+9 = 39 数字闭环说明 v1 inline header 解析逻辑覆盖完整
- 5 类后置脚本（validate / scan / lint / archive / rotation）在两种新 layout（fresh / migrated）上 all exit 0
- Sandbox 测后 `rm -rf` 干净退出，无痕

**关联**: Dev Log 0033（K5 cleanup gate 通过，本条的前置）；Decision 0012（K5 acceptance criteria + 选择停在 v2.0.0 不出 v2.0.1 的理由）；Mac Project Transfer.md §K5（待加 `HANDOFF_TIDY_AUTO_MIGRATE=1` 说明 + sandbox 范例）；v2.1.0 doc backlog（auto-migrate env var 应当成 first-class flag 文档化）
