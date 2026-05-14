---
schema: 2
type: dev-log
date: 2026-05-06T02:19
number: 0025
title: v1.2.6 发版：OpenCode `commands/` → `command/` 路径修正 + 主命令 shim 例外（Gotcha #9）
---

### 2026-05-06 02:19 — v1.2.6 发版：OpenCode `commands/` → `command/` 路径修正 + 主命令 shim 例外（Gotcha #9）

**触发**: 跨机验证 v1.2.5 安装——目标机 OpenCode 用户报 `/handoff` 等命令面板里完全不出现，尽管 `~/.config/opencode/skills/handoff/VERSION` 显示 v1.2.5 已就位。诊断锁定两条互锁差异（OpenCode 用 `command/` 单数 + 不从 skill name 自动注册主命令），与 Claude Code（Gotcha #5）镜像相反。

**改动**:
- `install.sh` — `install_to_dir()` 用 `case "$cli_name" in *OpenCode*) cmds+=(handoff.md);; esac` 让 OpenCode 显式拷 `handoff.md`；其他 CLI 维持原逻辑（避免 Gotcha #5 palette 重复）
- `install.sh` — 全局 / 项目级 / uninstall 三处 OpenCode 路径 `commands/` → `command/`（lines 346 / 382 / 434）
- `install.sh` — 升级路径：每个 OpenCode 安装入口前加循环清理 `commands/`（复数）旧 shim 残留
- `tests/test_install.sh` Case 3 — 6 条断言改 `command/`（单数）；新增 `handoff.md` 必须存在断言；旧 `commands/` 无残留断言；TDD 先红（5 fail + 1 cruft）后绿
- `HANDOFF.md` — Gotcha #9 详细记录（OpenCode 命令注册差异，与 #5 镜像对称）
- `HANDOFF.md` / `README.md` — 当前版本字段 + Release/latest 引用，从 v1.2.4 经 v1.2.5 跳到 v1.2.6（v1.2.5 release 后 README/HANDOFF 没回头追平的预存在漂移一并修补）
- `CHANGELOG.md` + `Release/CHANGELOG.md` — v1.2.6 完整条目
- 走过的弯路:
  - 第一时间猜是 OpenCode CLI 没装；`command -v opencode` 在我本地确实空，但用户提示是另一台机——目标机 `which opencode` → `/Users/token/.opencode/bin/opencode`，PATH 没问题
  - 起初误判为 install.sh 漏拷 `handoff.md`（因为 commands/ 复数里只有 4 文件），后来发现 install.sh 原设计就**故意不拷**（Claude Code 自动注册主命令避免重复），而**不是漏拷**——核心问题是 OpenCode 不遵守 Claude Code 的 skill-name 自动注册约定
  - 一开始打算只在 install.sh 里 hard-code 一份"OpenCode 例外列表"，后来用 `case ... esac` 模式让 cli_name 字符串显式驱动 shim 集合，未来加新 CLI 时更容易扩展

**验证**:
- `bash tests/test_install.sh` → 77 passed（之前 75，C3 新增 2 条断言）
- `bash tests/run_all.sh` → **19 套件 / 354 passed / 0 failed**（v1.2.5 是 352；本次新增的 2 条 install 断言纳入）
- `PROJECT_ROOT=... bash ~/.claude/skills/gitx-release/scripts/gitx-release.sh --version v1.2.6` → 🎉 Deep Audit PASS（197 / 0 / 1 SKIP / 0 WARN，198 项总）
- `Release/handoff-v1.2.6/` 完整产物：`.skill` (52K) / `-source.tar.gz` (167K) / `-full.tar.gz` (288K) / SBOM / checksums
- `Release/latest` → `handoff-v1.2.6`（原子更新）
- 目标机已手动 patch（直接拷 5 文件到 `command/` 单数），命令面板出现确认

**关联**: 新 Gotcha #9（OpenCode 命令注册）；与 Gotcha #5（Claude Code 三处注册去重）镜像对称

