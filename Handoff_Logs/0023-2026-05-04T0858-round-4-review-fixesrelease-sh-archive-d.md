---
schema: 2
type: dev-log
date: 2026-05-04T08:58
number: 0023
title: Round 4 review fixes：release.sh 死引用 + archive-devlog 防御性退出（352 断言）
---

### 2026-05-04 08:58 — Round 4 review fixes：release.sh 死引用 + archive-devlog 防御性退出（352 断言）

**触发**: `superpowers:code-reviewer` 跑 Round 4 全项目审查，verdict Ship 但点出 2 处 Low：(a) `release.sh:254-256` 引用从未赋值的 `$SKILL_SRC`，靠 `set -u` 未开而静默工作；(b) `scripts/archive-devlog.sh` 的 `skip_until_anchor` 模式在源 anchor 缺失时会静默吞掉 Dev Log 之后的 `## ` 章节。Ship 不阻塞，但用户决定立即修。

**改动**:
- `release.sh:254-256` — 删除 `$SKILL_SRC` 引用，改为直接 `SKILL_MD_SRC="$ROOT/skills/handoff/SKILL.md"`，4 行 → 2 行
- `scripts/archive-devlog.sh:119-129` — `skip_until_anchor` 块新增 `^## ` 终止条件：遇下一章节标题时退出 skip 模式并 re-emit 该行，确保 anchor 缺失时下游章节字节保留
- `skills/handoff/scripts/archive-devlog.sh` — bundle 镜像同步（`diff -q` 零差）
- `tests/test_archive_devlog.sh` — Case 8（3 断言）：60 条 Dev Log + 故意省略 anchor + 末尾 `## 📌 PostScript` 章节，断言 archive 后 PostScript 标题与正文字节保留；先红后绿
- `HANDOFF.md` — Current State 覆盖更新；本条 Dev Log
- 走过的弯路: 一开始想把 `release.sh` 那段化简成 `[ -f path ] && cp path dest`（更短），但保留 `SKILL_MD_SRC` 中间变量与现有风格一致，便于以后从 staging dir 选源文件——所以只删死引用、不重写结构

**验证**:
- `bash tests/run_all.sh` → 19 套件 / **352 passed** / 0 failed（349 → +3 来自 Case 8）
- `bash scripts/scan-credentials.sh` 在 4 个改动文件 → clean
- `bash scripts/validate-handoff.sh --readiness HANDOFF.md` → ✅ structure OK
- `diff -q scripts/archive-devlog.sh skills/handoff/scripts/archive-devlog.sh` → 字节级一致
- 提交链：`5b4671d` (initial v1.2.2) → `8543559` (git init Dev Log) → `525214d` (SHA 更正) → `440be12` (Round 4 fixes)

**关联**: 无新 Decision、无新 Gotcha；Round 4 review 由 2026-05-01 三轮 review 之后追加进行

