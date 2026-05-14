---
schema: 2
type: dev-log
date: 2026-04-30T23:54
number: 0017
title: GitX release 发版：handoff-v1.2.1 产物与 audit 全绿
---

### 2026-04-30 23:54 — GitX release 发版：handoff-v1.2.1 产物与 audit 全绿

**触发**: 用户要求使用 `$git-release-pipeline` 发新版；本仓仍是旧 release 布局，需要适配新版 GitX release gate 后完成本地发版。

**改动**:
- `VERSION` / `skills/handoff/VERSION` — 新增并更新到 `v1.2.1`，满足 GitX sidecar 契约
- `scripts/emit-sbom.sh` / `scripts/emit-token-usage.sh` 及 bundle 副本 — 补齐 release attestation 生成脚本并保持双源一致
- `.sanitize-ignore` — 白名单 intentional test fixture 和文档示例文件，避免 release sanitizer 把测试用假 token 当成真实泄漏
- `scripts/encode-cc-path.sh` / bundle 副本 — 把分发脚本中的真实 `<dev-home>/...` 示例改为 `/Users/<user>/...`
- `skills/handoff/agents/codex-commands.txt` — 新增 Codex `$` selector manifest，满足 deep audit §6
- `install.sh` — 声明并处理 `--dry-run` / `--force` 参数；补齐 release audit §6.10 接口契约
- `scripts/sync-codex-skills.sh` / `scripts/sync-memory.sh` / `scripts/validate-skill-metadata.sh` 及 bundle 副本 — 补 usage 注释，满足 skill bundle 质量 gate
- `README.md` / `HANDOFF.md` / `tests/test_doc_freshness.sh` — 更新到 `Release/latest -> handoff-v1.2.1` 新布局
- `tests/test_install.sh` — bootstrap 测试优先使用有效 `Release/latest`，避免重建当前 release 时 dangling symlink 影响测试
- `Release/handoff-v1.2.1/` — 生成 `.skill`、source tarball、checksums、SBOM、TOKEN_USAGE、RELEASE_NOTES、release-scoped log 与 sha256
- 走过的弯路: 直接使用新版 `gitx-release.sh --dry-run` 会因 dry-run 不写 `VERSION` sidecar 而触发下游版本一致性失败；正式 wrapper 会先写 sidecar，因此改走正式 release
- 走过的弯路: 初次选择 `.sanitize-ignore` 只覆盖 source staging，但 `.skill` 解压后二扫不带根白名单；最终把分发脚本里的真实用户路径改成占位符，从源头消除泄漏
- 走过的弯路: 删除当前 `Release/handoff-v1.2.1` 后重跑 release 时，`Release/latest` 短暂指向不存在目录，暴露 bootstrap 测试对 release artifact 选择不稳；已修复测试选择逻辑

**验证**:
- `bash tests/run_all.sh` → All suites passed，18 suites / 337 assertions / 0 failed
- GitX release deep audit → `196/196 PASS`
- `bash tests/test_doc_freshness.sh` → 12 passed, 0 failed
- `Release/latest` → `handoff-v1.2.1`
- Release-scoped log: `Release/handoff-v1.2.1/gitx-release-20260430T154616Z-v1.2.1.log`

**关联**: Gotcha #8

