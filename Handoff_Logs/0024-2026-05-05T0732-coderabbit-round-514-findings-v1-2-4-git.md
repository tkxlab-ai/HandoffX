---
schema: 2
type: dev-log
date: 2026-05-05T07:32
number: 0024
title: CodeRabbit Round 5（14 findings）+ v1.2.4 文档漂移 + git 仓库重建（352 断言）
---

### 2026-05-05 07:32 — CodeRabbit Round 5（14 findings）+ v1.2.4 文档漂移 + git 仓库重建（352 断言）

**触发**: 用户跑 `/coderabbit:coderabbit-review`，意图审 Round 4 改的 3 个文件（`release.sh` / `scripts/archive-devlog.sh` / `tests/test_archive_devlog.sh`）。两条意外发现：(1) `.git/` 实际不存在——HANDOFF.md Dev Log 2026-05-01 13:19 记的初始提交 `5b4671d` + 后续 SHA 链全是孤立记录，文件系统已无对应 git 历史；(2) `.gitignore` 缺 Dev Log 声明过的 `Release/` / `memory/` / `HANDOFF.md.bak*` 排除规则。CodeRabbit 跑完审了全工作树共 14 处 finding（1 Critical / 1 Major / 12 Minor）；同时 test_doc_freshness 暴露另一条预存在漂移 v1.2.3 → v1.2.4。一次性全部修补。

**改动**:
- **临时仓库**: `git init` + 本地 `user.name=TKXLAB / user.email=dev@tkxlab.ai`（沿用 2026-05-04 那次 rebase 身份）；`.gitignore` 补 `Release/` / `memory/` / `HANDOFF.md.bak*` / `Handoff_OldBackup_0504/`；初始 commit `b973251`（93 files / +11,837 行）
- **Critical**: `tests/test_shellcheck.sh:14-23` shellcheck 缺失分支补 `exit 1`，避免 summary 后继续走到 Test 2 崩溃
- **Major + Minor**: `scripts/emit-sbom.sh` + bundle — 加 `json_escape()` bash 参数展开实现，对 `SKILL_NAME` / `VERSION` / `art` 全量 JSON 转义（`\\ \" \b \f \n \r \t`），消除 SBOM heredoc 注入风险
- **Minor 健壮性**: `tests/test_shellcheck.sh:19/33` `nullglob` + 数组检测；`install.sh:168-169` `--project` / `--template` 拒绝空值或 `-*` 开头；`scripts/emit-token-usage.sh` + bundle `${f#"$SKILL_DIR/"}` 保留嵌套子目录
- **Minor 测试**: `tests/test_release_dry_run_audit.sh:21-29` awk 改 brace-depth 计数器；`tests/test_bundle_sync.sh:20` 注释 "4 shims" → "5 shims"
- **Minor 文档漂移**: `HANDOFF.md` 覆盖率日期 04-30 → 05-04 / "18 suites" → "19 suites" / "335 assertions" → "352"；`TEST-SCENARIOS.md` "346 断言" → "352"；`docs/superpowers/plans/2026-05-01-issue-resolution.md` 硬编码绝对路径 → `./.sanitize-ignore`
- **Minor 杂项**: `tests/fixtures/placeholder.md` `AWS_SECRET` → `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`；`skills/handoff/SKILL.md:107` license badge 改 shields.io 图片 URL
- **v1.2.4 漂移**: `HANDOFF.md` 当前版本 + Milestone v1.2.3 → v1.2.4；`README.md` Release/latest 引用与 .skill 文件名 4 处 + tests "346 断言" → "352"
- 走过的弯路:
  - 第一次 CodeRabbit run 报 "6471 files exceeds 150 limit"——`Handoff_OldBackup_0504/`（35M）+ `Release/`（6.2M）等 untracked 目录全被 CodeRabbit 当成审查范围；先补 `.gitignore` 才把文件数压到 93
  - CodeRabbit 又报 "ambiguous argument 'HEAD'"——fresh `git init` 还没 HEAD；用 `git commit --allow-empty` 建空 baseline 让 HEAD 落地，最后用 `git commit --amend` 把空 baseline 吸收进正经初始 commit
  - 免费档 13 分钟 rate-limit 单次后台 bash 跑不下来（10 分钟硬上限）——拆成两段 `sleep 580` + `sleep 240 && coderabbit review`，靠 task 完成通知衔接
  - emit-sbom.sh 的 json_escape 一开始想用 sed pipeline 链，但 `\n` / `\b` / `\f` 在 sed `s/...` 里跨平台行为不稳；改用 bash 参数展开 `${s//pat/repl}`（bash 3.2+ 兼容，无外部进程开销）

**验证**:
- `bash tests/run_all.sh` → **19 套件 / 352 passed / 0 failed**（修 v1.2.4 漂移前是 350/2 失败，全是预存在 doc_freshness 失败）
- `diff -q scripts/ skills/handoff/scripts/` → 零 diff（bundle parity 保持）
- `bash scripts/validate-handoff.sh --readiness HANDOFF.md` → ✅ structure OK
- `shellcheck --severity=warning scripts/*.sh` → 0 warning
- `bash scripts/scan-credentials.sh tests/fixtures/placeholder.md` → clean（新 AWS_* 变量名未触发 placeholder）
- `bash tests/test_release_dry_run_audit.sh` → 12 passed（含新 brace-depth awk 验证 audit_staged_source 正确截取）
- `git log --oneline` → `b973251 feat: initial commit — Handoff Plugin v1.2.4 + Round 5 review fixes`；working tree clean

**关联**: 无新 Decision；无新 Gotcha（CodeRabbit free-tier rate-limit 与 HEAD 要求是工具特性，非项目级雷区；`.git/` 神秘缺失是一次性历史事故，重建后稳定）

