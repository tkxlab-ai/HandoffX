---
schema: 2
type: dev-log
date: 2026-05-01T14:00
number: 0021
title: 13-issue fix batch: release gate, scanner, tidy anchor, CI matrix (v1.2.1)
---

### 2026-05-01 14:00 — 13-issue fix batch: release gate, scanner, tidy anchor, CI matrix (v1.2.1)

**触发**: 全量 code review 发现 13 个问题，用户要求 TDD + subagent 方式全部修复，3 轮独立 code review 验收。

**改动**:
- `.sanitize-ignore` — 加 `tests/fixtures/` 白名单，防 release sanitizer 误报测试 fixtures
- `release.sh` — rsync exclude 改为 `--exclude='/HANDOFF.md.bak*'`（通配）；`RELEASE_LOG`+`STAGE`+`SKILL_STAGE` 三个 mktemp 统一到单个 EXIT trap，消除泄漏窗口
- `README.md` / `HANDOFF.md` — 全部 `v1.2.0` 引用更新为 `v1.2.1`
- `scripts/scan-credentials.sh` + bundle 镜像 — 新增 `github_pat_` 和 `hf_` 两条 pattern，fixture 文件 + 测试断言一并添加
- `scripts/tidy-handoff.sh` + bundle 镜像 — anchor 插入位置 bug 修复（原来追加到 EOF，现在插到 Dev Log 内的下一个 `## ` 之前）；Auto-fix 执行顺序对调（anchor 先于空行归并，一次 pass 完成）；awk pattern 从 `/Development Log/` 收窄为 `/Development Log[[:space:]]*$/`，防止 composite heading 触发双 anchor
- `skills/handoff/references/handoff-write.md` — 删除失效的 `.claude/handoff-scripts/` 覆盖路径说明；在 Execution 节开头补充 `<skill-path>` 定义
- `tests/test_bundle_sync.sh` — 删除 `DEV_REFS` 死变量、`DEV_CMDS` 死别名，以及重复的 `BUNDLE_REFS` 赋值
- `scripts/handoff-lint.sh` + bundle 镜像 — awk END 块 `log_sections` 强制数值转型 `(log_sections+0)`
- `install.sh` — 在 `.skill` 解压前加 `command -v unzip` guard，missing 时输出可操作的安装提示
- `skills/handoff/SKILL.md` — section count 表述改为非硬编码，指向 validate-handoff.sh 和模板文件
- `.github/workflows/ci.yml` — matrix 加 `macos-latest`，`fail-fast: false`，各 OS 的 shellcheck 按需安装

**验证**:
- `bash tests/run_all.sh` × 3 轮：330 个非 shellcheck 测试全绿，稳定（shellcheck 本地未安装，CI 会安装）
- `diff -r scripts/ skills/handoff/scripts/` → 零 diff（byte-identical）
- 3 轮独立 code review：Round 1（tidy/scanner/trap）、Round 2（CI/lint/bundle）、Round 3（ship-readiness）均通过，最终裁定 **Ship**

**关联**: design spec `docs/superpowers/specs/2026-05-01-issue-resolution-design.md`；plan `docs/superpowers/plans/2026-05-01-issue-resolution.md`

