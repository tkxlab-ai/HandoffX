---
schema: 2
type: dev-log
date: 2026-04-21T21:27
number: 0004
title: Release 模拟循环 Round 2：捕获并修复 Git_Release_Skill 3 个 bug
---

### 2026-04-21 21:27 — Release 模拟循环 Round 2：捕获并修复 Git_Release_Skill 3 个 bug

**触发**: Round 1（v0.9.3）完成后继续执行 Round 2（v0.9.4），对 release 结果做原子级回审，发现 3 个新 bug 并即时修正。

**改动**:
- `Git_Release_Skill/scripts/release.sh` — **Bug #3 修复**：CHANGELOG gate 从步骤 5 移至 pre-flight 0（步骤 1 之前）
  - 原位置：在 .skill 打包、tarball、文档平摊、symlink 之后才做 gate，abort 会留下大量残留产物
  - 修复：gate 移至 `mkdir -p "$RELEASE_DIR"` 之前执行；`Release/CHANGELOG.md` 不存在则先创建空模板文件；无条目或含 TODO 则 abort，此时只有父目录 `Release/` 存在，version 子目录完全未创建
  - 同步移动 `RELEASE_DATE` / `PROJECT_TITLE` 变量初始化到 pre-flight 0
  - 步骤 5 简化为单纯 `cp`（gate 在前面已通过，无需重复检查）
  - 移除步骤 3 中重复的 `RELEASE_DATE` / `PROJECT_TITLE` 赋值
- `Git_Release_Skill/scripts/release-audit.sh` — **Bug #5 修复**：§4 "顶部版本号" 检查从存在性检查升级为位置检查
  - 原逻辑：`grep -q "^## $VERSION "` — 只验证版本号存在于 CHANGELOG，不验证它是第一个条目
  - 修复：`grep "^## " | head -1` 取第一个版本行，再验证是否等于 `$VERSION`；旧版本排在前面会被正确检出
- `Git_Release_Skill/scripts/release-sanitize.sh` — **Bug #6 修复**：移除 `find_text_files()` 中的 `! -path '*/Release/*'` 排除
  - 原逻辑：find 排除所有含 `/Release/` 的路径；当 audit §7 以 `Release/v0.9.4/` 作为 `$DIR` 调用时，目录下所有文件均被排除，扫描变成空操作（zero-finding vacuous pass）
  - 修复：移除该排除规则；staging 阶段依赖 rsync 的 `--exclude=Release` 排除；audit 阶段必须真正扫描 Release 子目录
  - 添加注释说明 Bug #6 修复背景

**验证**:
- Bug #3 修复验证：手动确认 abort 时 `Release/v0.9.4/` 目录不存在（zero residue）
- Bug #5 原子分析：构造 CHANGELOG 含旧版本排在前面的测试场景，确认新逻辑会 FAIL
- Bug #6 验证：`find Release/v0.9.4/ -type f ! -path '*/Release/*'` → 0 files（原 bug 复现）；修复后正常返回文件列表
- v0.9.4 完整 release + audit：`🎉 Deep Audit PASS (42/42)` ✅
- 走过的弯路：Bug #3 最初只把 gate 移到 step 2 之前，但 mkdir RELEASE_DIR 已在 step 2 之前执行，仍会留下空目录残留；最终必须移到 `mkdir -p "$RELEASE_DIR"` 本行之前

**关联**: `Git_Release_Skill/scripts/release.sh` + `release-audit.sh` + `release-sanitize.sh`；Handoff Release/v0.9.4 产物已就绪

**待办变动**:
- 🆕 新增：进行 Round 3 模拟 release（v0.9.5），目标连续两轮无 bug（Round 2 是第一个 clean 轮次）
- ✅ 关闭：Round 2 模拟 release 完成

