---
schema: 2
type: dev-log
date: 2026-05-11T13:54
number: 0043
title: v2.1.3 — Skill spec compliance polish + OpenCode dir drift fix（4 case study 沉淀）
---

### 2026-05-11 13:54 — v2.1.3 — Skill spec compliance polish + OpenCode dir drift fix（4 case study 沉淀）

**触发**: 实战观察期当天发完 v2.1.2 后 Boss 让对照官方 Skill 文档检查 handoff 架构合规性，并紧接 OpenCode 用户报告 "commands/ 目录为空"——两条独立线索同根：项目对照官方现行规范缺乏周期性校准。Boss 先选 C（迁复数发 v2.1.3），随后追加 A（skill spec compliance polish 一起做）。共 5 phase 计划。

**改动**:
- **Phase 1 — 机械验证 OpenCode v1.14.41 复数路径**:
  - `orb start` → OrbStack engine ready
  - `mkdir ~/.config/opencode/commands` + 拷 test probe → `opencode debug config` 显示 probe register
  - **确认**：v1.14.41 同时读 `command/` + `commands/`，**但不去重**（双写 = palette 重复）
  - 清 probe；保持单数 command/ 不动直到 install.sh 切复数
- **Phase 2 — install.sh + dir rename**:
  - OpenCode target `command/` → `commands/`（全局 line 481 + 项目级 line 424）跟随 `opencode.ai/docs/commands`
  - 双路径残留 install-time 清理（防 5+5=10 palette 重复）；uninstall 也双清
  - `git mv skills/handoff/commands → skills/handoff/command-shims`（5 个 .md）+ install.sh 5 处引用 + test_install.sh / test_bundle_sync.sh / release.sh dry-run-audit 同步
  - **install.sh bootstrap-time 自动 `commands → command-shims` rename**（line 141-148）→ 旧 .skill 包（v2.1.2-）向后兼容
  - SKILL.md description 扩展（中英双语，≤160 chars 项目 budget）
- **Phase 3 — 双平台 24/24 ✅**:
  - macOS bash 3.2 + Ubuntu 22.04 mawk 双绿
  - 端到端实跑：`bash install.sh --opencode` → 5 个 shim 写入 commands/ + command/ 残留清空
  - `opencode debug config` 显示 5 个 /handoff* commands 全 register
- **Phase 4 — 知识资产**:
  - Gotcha #9 加 **OBSOLETE since v2.1.3** 标记 + 引用 #16
  - +Gotcha #16（**四个 case study**）:
    1. OpenCode dir convention drift（v1.2.6 单数 → v1.14+ 复数）
    2. Skill spec 偏离累积（commands/ 命名误导 / agents/ 误用 / frontmatter 单字段）
    3. **docs.claude.com vs skill-creator validator 矛盾** — `code.claude.com/docs/en/skills` 列 ~12 frontmatter 字段（含 `when_to_use`），`gitx-release` 调的 `skill-creator/scripts/package_skill.py` validator 只认 6 字段（`name/description/license/allowed-tools/metadata/compatibility`）。**跨工具分发 skill 必须按 6 字段子集约束**
    4. **gitx-release `agents/` 是项目 Codex 契约非通用 spec** — 初始计划把 `skills/handoff/agents/codex-commands.txt` 移到 `assets/`（理由：Anthropic Skills docs 不识别 skill 内 agents/）→ gitx-release `release-audit.sh:561,614` 强制要求 `.skill 含 agents/codex-commands.txt` 作 Codex \$ selector manifest → audit fail → **revert**，agents/ 保留原位
  - +Decision 0017（完整推理：拒 B 仅文档 / C 不动，选 D 全套 polish；含 4th case 反方观点 — 改动前必须 grep 内部 release tool 是否引用此路径）
- **Phase 5 — gitx-release v2.1.3 + push**:
  - 第一次跑 → skill-creator validator 拒 `when_to_use` 字段（case study #3 发现）
  - 撤掉 `when_to_use`，trigger 关键词压回 description body markdown
  - 第二次跑 → audit `❌ .skill 含 agents/` + `❌ agents/codex-commands.txt 存在`（case study #4 发现 — 我误以为 agents/ 是误用，实际是 gitx-release 硬契约）
  - 撤 B2 revert agents/codex-commands.txt 到原位 + 4th case 入 Gotcha #16
  - 第三次跑 → **Deep Audit 186/0/0 PASS** ✅
  - `Release/handoff-v2.1.3/` 含 `.skill` + source.tar.gz + full.tar.gz + checksums + SBOM + RELEASE_NOTES
  - commit `0e11a47` push 到 private Git host（17 files changed，251+/68-）；annotated tag `v2.1.3` push
- 走过的弯路（每条都是 case study 的源）:
  - 想加 `when_to_use` 字段——docs 说支持，validator 拒。先调研 docs ≠ tooling
  - 想把 agents/codex-commands.txt 挪 assets/ "命名澄清"——撤了，因为 gitx-release 内部硬依赖此路径。Karpathy#3 surgical 警告：**改动前 grep 内部依赖**而不是凭"看起来 misleading"判断
  - 想做 frontmatter `disable-model-invocation` —— 同 case #3 被 validator 拒，撤
  - bootstrap-time `commands → command-shims` rename 不加 → C10 .skill bootstrap 测试挂（旧 .skill 解出来是 commands/，新 install.sh 要 command-shims/）；加 6 行 fallback 解决

**验证**:
- `bash tests/run_all.sh` (macOS bash 3.2 arm64 M4) → **24/24 ✅**
- `docker run --rm -v ... -e LANG=C.UTF-8 ubuntu:22.04 ... bash tests/run_all.sh` → **24/24 ✅**
- `bash tests/test_doc_freshness.sh` → 14/0
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → ✅ 5/5
- `PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/release-audit.sh v2.1.3` → **186/0/0 PASS**
- `opencode debug config` → 5 个 /handoff* cmds register
- `bash install.sh --opencode` 端到端：写入 `~/.config/opencode/commands/` ✅；`command/` 单数残留清空 ✅
- `git ls-remote origin refs/heads/main refs/tags/v2.1.3` → SHA 与 local 一致

**关联**: Dev Log 0042（v2.1.2 Linux compat，本条紧随其后第三个 patch 同日）；Decision 0017（D 全套 polish vs B 仅文档 / C 不动推理）；Gotcha #16（对照官方现行规范定期校准 + 4 case study + 跨 CLI 双路径迁移模板 + skill spec compliance 模板）；Gotcha #9（OBSOLETE since v2.1.3）；Decision 0013（v2.2.0 race fix 推延保持有效）；实战观察期理念证实——找到真实痛点（OpenCode 报告 + spec 偏离 + docs↔tooling 矛盾）就该发，不是"凭空发版"
