---
schema: 2
type: dev-log
date: 2026-05-11T13:21
number: 0042
title: v2.1.2 — Linux compat 实测 + mawk regex POSIX 化（理论推断 → 机械验证）
---

### 2026-05-11 13:21 — v2.1.2 — Linux compat 实测 + mawk regex POSIX 化（理论推断 → 机械验证）

**触发**: v2.1.1 实战观察期决策刚定（Dev Log 0041），Boss 问"是否支持 Linux 安装"。读现场结论：代码层声称支持（install.sh 五平台分支 + XDG 路径 + 跨平台 date fallback）+ 测试层零 Linux 真机覆盖（"靠 fallback 代码 + 理论推断"）+ 用户文档完全静音。Boss 选 b "做虚拟机真机测试"——先检查系统资源 + 工具栈，授权启 OrbStack。

**改动**:
- **环境就绪（M4 Mac mini 24GB / 800GB free）**:
  - `orb start` 启 OrbStack 引擎（1 秒 ready）；docker context → orbstack（不是 Docker Desktop）
  - `docker pull ubuntu:22.04` 拉 aarch64 镜像（M4 原生）
- **第一轮裸跑（仅装 shellcheck）**：8 套件挂 / 多 exit 127 = command not found
- **第二轮加 deps（+ruby +unzip）**：6 套件挂——`test_skill_metadata_budget` 还卡 UTF-8 token count
- **第三轮 locale `C.UTF-8`**：5 套件挂 / 38 断言
- **第四轮 +rsync**：5 套件挂 / 38 断言（rsync 修了 `test_release_dry_run_audit` exit 127）
- **诊断单一根因**: `which awk → /usr/bin/mawk`（`/etc/alternatives/awk -> mawk`，Ubuntu 默认）。`echo "### 2026-05-11" | awk '/^### [0-9]{4}-[0-9]{2}-[0-9]{2}/'` 在 mawk 失配（macOS BSD awk + gawk 都匹配）——mawk 不支持 POSIX regex interval `{N}` quantifier，14 处 awk 内部 regex literal 全坏掉
- **Phase 2 修复**:
  - 4 个 awk-heavy 脚本 + 双副本：`scripts/{archive-devlog,handoff-lint,migrate-to-v2,tidy-handoff}.sh` 内部 awk regex literal `[0-9]{4}-[0-9]{2}-[0-9]{2}` → `[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]`；`[0-9]{2}:[0-9]{2}` → `[0-9][0-9]:[0-9][0-9]`；bare `[0-9]{4}` → `[0-9][0-9][0-9][0-9]`；bare `[0-9]{2}` → `[0-9][0-9]`。POSIX 显式重复在 BSD awk / gawk / mawk 三家一致行为
  - **不动 sed -E / grep -E**：这两个工具 `-E` 所有平台支持 `{N}`
  - **不动 scan-credentials.sh shell-level `{20,}`**：grep -E 跨平台兼容
  - `tests/test_migrate_to_v2.sh` B7-a：`[ "$EUID" -eq 0 ]` 检测 root → SKIPPED 并标注"B7-b 已用路径冲突机制覆盖 rollback contract，对 root 免疫"。Linux 容器默认 root，CAP_DAC_OVERRIDE 让 chmod 555 失效；B7-b 用 `touch Handoff_Decisions.partial` 占用 mkdir 路径，root 也无法 mkdir 同名文件——所以 root-immune
- **Phase 3 双绿验证**:
  - `bash tests/run_all.sh`（macOS bash 3.2 / arm64 M4）→ 24/24 ✅
  - `docker run ubuntu:22.04 + run_all`（mawk）→ 24/24 ✅
- **Phase 4 docs + 知识资产**:
  - VERSION + skill/VERSION → v2.1.2
  - README.md Release 目录树 `latest → handoff-v2.1.2` + tarball/skill 命名
  - HANDOFF.md：当前版本 / 项目阶段 / 目标平台（从"理论推断"升级"实测 Ubuntu 22.04 容器 24/24 ✅"）/ 构建状态（拆分 lint/tidy/postflight/doc-freshness/k4-chicken-egg/migrate-to-v2 + 18 其他）/ Milestones 表加 v2.1.2 行 / 当前 Milestone 段 / Gotcha 14 → 15 + Decision 15 → 16 pointer 同步
  - CHANGELOG.md v2.1.2 entry（Theme + Why + Key changes + Linux deps 表格 + Backward compat + Not in v2.1.2）prepend 顶部
  - GOTCHAS.md **+Gotcha #15**（mawk regex 限制 + Linux deps 清单 + 跨平台 awk 通用规则 "看起来 POSIX 的 regex ≠ 真 POSIX"）
  - `Handoff_Decisions/0016-2026-05-11-v2-1-2-linux-compat-fix-all-vs-docs-only.md`：完整决策推理（拒 A 仅文档化 / B 部分修，选 C 全修）+ 反方观点（C 代价工时+ patch 版本号）+ 实战观察期理念一致辩护
- **gitx-release v2.1.2 一次过**:
  - Deep Audit 一次跑 208/0/1（§8_latest 翻转前 skip 预期）；CHANGELOG placeholder 替换为真实 release notes 后**再跑 audit → 209/0/0**
  - `Release/handoff-v2.1.2/` 含 `.skill` + source.tar.gz + full.tar.gz + checksums + SBOM + RELEASE_NOTES
  - `Release/latest → handoff-v2.1.2` 原子翻转
- **Git 状态**:
  - commit `41eb300` 单条 push 到 private Git host `<private-org>/Handoff` main（f3105a3 → 41eb300，16 files changed，220+/93-）
  - annotated tag `v2.1.2` 已 push
- 走过的弯路:
  - 第一轮裸跑漏装 shellcheck/ruby/unzip → 多个 exit 127；不是脚本 bug 是测试环境缺 deps。教训：跨平台测试前先 audit 测试自身依赖（shellcheck/ruby/yaml/unzip/rsync/locale）
  - 第三轮以为修了 locale 一切搞定 → 还剩 5 套件 38 断言。仔细看才发现是 mawk regex 内部一致性问题，不是 locale 影响。教训：失败信号要追到原始 regex 测试再下结论，不要中途换工具
  - 想过加 `[ -x /usr/bin/gawk ] && AWK=gawk` 这种 fallback，但太复杂——直接 POSIX 化 14 处 regex 比维护 awk 选择逻辑简单。Karpathy#2 simplicity-first
  - 一开始想测 B7-a 在 root 下"修脚本让 root 也无法 chmod 555 绕开"——发现这违反 Linux 内核语义（CAP_DAC_OVERRIDE 是 root 设计性能力）。改为测试侧 SKIP 是正确解，不是脚本侧改

**验证**:
- `bash tests/run_all.sh`（macOS）→ **24 套件全绿**
- `docker run --rm -v ... -e LANG=C.UTF-8 ubuntu:22.04 bash -c 'apt-get install -y shellcheck ruby unzip rsync locales; locale-gen C.UTF-8; cp -r /src /work; cd /work; bash tests/run_all.sh'` → **24 套件全绿**
- `bash tests/test_doc_freshness.sh` → 14/0（root VERSION = README "latest →" = HANDOFF "当前版本" = handoff-v2.1.2 一致）
- `bash tests/test_doc_freshness_k4_chicken_egg.sh` → 1/0（K4 regression guard 长青）
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → ✅ all 5 checks passed
- `PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/release-audit.sh v2.1.2` → **209/0/0 PASS**
- `git ls-remote origin refs/heads/main refs/tags/v2.1.2` → SHA 与 local 一致
- `diff -q scripts/ skills/handoff/scripts/` → 无差异（dual-source byte-equal）

**关联**: Dev Log 0041（v2.1.1 K4 root-cause fix，本条紧随其后第二个 patch）；Decision 0016（C 全修 vs A 仅文档化 vs B 部分修 推理）；Gotcha #15（mawk regex 限制 + 跨平台 awk 通用规则 + Linux deps 清单）；Decision 0013（v2.2.0 race fix 推延保持有效）；下次跨平台兼容性声明都该 docker run 一次再说——这是 Gotcha #15 沉淀的方法论
