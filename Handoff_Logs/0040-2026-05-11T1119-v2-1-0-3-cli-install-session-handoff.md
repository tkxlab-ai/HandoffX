---
schema: 2
type: dev-log
date: 2026-05-11T11:19
number: 0040
title: v2.1.0 三家 CLI install 完成 + 全链路就绪 + 会话 hand off（实战观察期）
---

### 2026-05-11 11:19 — v2.1.0 三家 CLI install 完成 + 全链路就绪 + 会话 hand off（实战观察期）

**触发**: v2.1.0 release commit + tag 已 push 到 private Git host（Dev Log 0039），但本机三家 CLI installed skill 还停留在 v2.0.0——`gitx-release` 只造 `Release/` 产物，不自动 install。Boss 要求确认装载最新版本 + 跑 install 收尾 + hand off。

**改动**:
- **`bash install.sh --claude --opencode --codex`** 在 Mac mini 全跑：
  - Claude Code `~/.claude/skills/handoff/` v2.0.0 → v2.1.0；旧版残留自动清理
  - OpenCode `~/.config/opencode/skills/handoff/` v2.0.0 → v2.1.0
  - Codex `~/.agents/skills/handoff/` v2.0.0 → v2.1.0 + 5 个 alias `$handoff-*` 注册
- **三家验证**：每家都 print `[XX] 安装验证通过`；`diff -rq ./skills/handoff <installed>` 全 byte-equal（仅 `commands/` 编译源差异是预期）
- **end-to-end 实跑**：`bash ~/.claude/skills/handoff/scripts/handoff-postflight.sh --quiet HANDOFF.md` → 5/5 ✅，证明 installed skill 真能跑通完整后置链路
- **本机最终状态盘点**：
  - 工作树 clean（`git status --short` 空）
  - `HEAD...@{u} = 0 0`（本地 = 远端 private Git host `<private-org>/Handoff`）
  - Local HEAD = Remote `refs/heads/main` = `1e97cb95eb5d2cd8ab6979c61effca348c5a7c43`
  - Tag `refs/tags/v2.1.0` = `55c7c1b4c84b5c7c0367258921e299ea7be4601e`（annotated）
  - `git fetch --dry-run` 无输出（远端无新东西）
  - 三家 installed VERSION 全 v2.1.0
- **会话决策（不写 Decision，因没真权衡）**：Boss 选 **E — 实战观察期**（recall 推荐项）。理由：v2.2.0 race fix 用户感知 = 0（Decision 0013 显式 defer），长期 roadmap 全 YAGNI；先实战用 v2.1.0 攒真实痛点，由痛点驱动下一周期，比凭空编 race fixture ROI 高。备选 B（跨 CLI 真机闭环）在 backlog 待命
- 走过的弯路（提早出现的小坑）:
  - Boss 问"是否最新版本"时第一反应想直接说"是"——但记得 gitx-release 只造产物不 install 才避免误报；养成 release ≠ install 的肌肉记忆很重要
  - 一开始 v2.1.0 release 跑挂在 test_doc_freshness（K4 鸡蛋问题），同 K4 v2.0.0 路径（revert→release→restore）解决——可在 Mac Project Transfer / GOTCHAS 加一条 "release 前最后一刻不要把 HANDOFF.md/README.md 的版本号先升上去" 作为知识资产，未来 v2.2.0 / v2.x.0 都会撞到

**验证**:
- `bash tests/run_all.sh` → 23 套件全绿（最近一次跑过）
- `bash ~/.claude/skills/handoff/scripts/handoff-postflight.sh --quiet HANDOFF.md` → 5/5 ✅ (installed skill 路径)
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → 5/5 ✅ (repo source 路径)
- 三家 installed VERSION + diff -rq 全 byte-equal repo（除 commands/ 编译源）
- `git ls-remote origin` 真拉 main + v2.1.0 tag 双 SHA 一致

**关联**: Dev Log 0039（v2.1.0 release，本条的前置）；Dev Log 0035-0038（v2.1.0 5 件 UX 工作）；Decision 0013（v2.1.0 scope = UX-only / race 推 v2.2.0）+ Decision 0014（项目本地 `.sanitize-ignore`）；下次会话从 `/handoff-recall` 接续——状态完全可由 private Git host clone 重建，本机 dev 副本只是缓存；K4 鸡蛋问题可作 v2.x.0 release 前 checklist 项（不发版前不要把 HANDOFF/README "当前版本" 字段先升）
