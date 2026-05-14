---
schema: 2
type: dev-log
date: 2026-05-06T22:53
number: 0030
title: v1.2.10 发版：install.sh fresh-Codex install bug 修复 + 三家成功安装到本机
---

### 2026-05-06 22:53 — v1.2.10 发版：install.sh fresh-Codex install bug 修复 + 三家成功安装到本机

**触发**: 用户问"是否安装到本机"，跑 `bash install.sh --claude --opencode --codex` → Claude + OpenCode 成功，**Codex 段 abort**。诊断锁定 `cleanup_codex_legacy_mirrors` 函数末尾 `[ "$removed" -gt 0 ] && echo "..."` 在 `removed=0` 时返回 1，set -e 触发整脚本 abort。Pre-existing bug 从初版就在；触发条件：用户装过 Codex CLI（`~/.codex/skills/` 已存在）但**没装过旧版 handoff**——任何 fresh Codex 用户首次装 handoff 都踩。本会话之前没在 fresh Codex 机器跑过 `--codex` 才漏掉。

**改动**:
- `install.sh` `cleanup_codex_legacy_mirrors`：改 `if [ ... ]; then echo; fi` 形式 + 显式 `return 0`，避免末尾条件测试为假时函数返回 1
- `tests/test_install.sh` Case 4b：新增 regression sandbox 测试——预先 `mkdir -p $SANDBOX/.codex/skills/some-other-skill` 模拟"目录存在但无 legacy handoff*"场景，断言 `--codex` exit 0 + agents/skills/handoff 真存在 + cleanup 没误删非 handoff 的其他 skill；TDD 先红（3 fail）后绿（3 pass）
- `HANDOFF.md` Gotcha #13：cleanup 函数末尾"条件输出"是 set -e 隐式陷阱（Gotcha #6 的孪生，触发面在函数级而非语句级）
- `HANDOFF.md` / `README.md` 当前版本字段、Release/latest 引用、Milestone → v1.2.10
- `CHANGELOG.md` + `Release/CHANGELOG.md` v1.2.10 完整条目
- 走过的弯路:
  - 第一次 install 看到 Codex 段 abort 时，输出被截断没显示具体错。靠 `bash -x install.sh --codex` trace 才看到 cleanup 函数末尾的 `[ 0 -gt 0 ]` 返回 1
  - 顺手检查 `cleanup_legacy`（line 312）是否同类 bug——它有显式 `return 0`，没问题。只 `cleanup_codex_legacy_mirrors` 一处漏

**验证**:
- `bash tests/test_install.sh` → 80 passed（v1.2.9 是 77；本次 +3 条 C4b 断言）
- `bash tests/run_all.sh` → **21 套件 / 362 passed / 0 failed**
- `gitx-release --version v1.2.10` → 🎉 Deep Audit PASS（197/0/1）
- `Release/handoff-v1.2.10/` 完整产物（.skill / source.tar.gz / full.tar.gz / SBOM / checksums）
- `Release/latest` → `handoff-v1.2.10`
- **真机端到端验证**：本机重跑 `bash install.sh --claude --opencode --codex` 三家全 ✅；`~/.claude/skills/handoff/VERSION = ~/.config/opencode/skills/handoff/VERSION = ~/.agents/skills/handoff/VERSION = v1.2.10`；OpenCode 5 个 command shim + Codex 5 个 alias 都就位

**关联**: 新 Gotcha #13；与 Gotcha #6 同根 set -e + 条件返回类陷阱；本会话 v1.2.4 → v1.2.10 链路真闭环（本机 + 三家 CLI 真装上）

