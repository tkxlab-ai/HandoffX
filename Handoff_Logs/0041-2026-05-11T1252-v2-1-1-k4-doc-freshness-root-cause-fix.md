---
schema: 2
type: dev-log
date: 2026-05-11T12:52
number: 0041
title: v2.1.1 — K4 chicken-egg root-cause fix（audit 一次过 209/0/0，K4 manual workaround retired）
---

### 2026-05-11 12:52 — v2.1.1 — K4 chicken-egg root-cause fix（audit 一次过 209/0/0，K4 manual workaround retired）

**触发**: 上一会话 /handoff-recall 完汇报实战观察期；Boss 改主意调 `/gitx-release`。我按 Linus 三问拦下默认 patch bump（无新改动 → 会造空 release），surface 三选项 → Boss 选 `audit v2.1.0` 复核已发产物。Audit 208 ✅ / 1 ❌ 卡 §3_sync："Release/handoff-v2.1.0/README.md 内 v2.0.0 残留"，根因正是 0040 已标记的 K4 鸡蛋问题——v2.0.0 + v2.1.0 两次发版用同样手动 revert workaround 把 v-prev snapshot 锁进了 v-next tarball。Boss 选 **C — 发 v2.1.1 修 K4 设计**，不再容忍未来 v2.2.0 / v3.0.0 继续 workaround。

**改动**:
- **TDD RED→GREEN**（Karpathy#4 + Tacit#5 真流程）:
  - RED：写 `tests/test_doc_freshness_k4_chicken_egg.sh` 用 `ln -sfn handoff-v0.0.1-stale Release/latest`（trap 恢复）+ subprocess 跑 `test_doc_freshness.sh`，断言全 14/0 绿。第一次跑 → exit 1，2 个 fail（Test 4 README + Test 5 HANDOFF 都把 `Release/latest = handoff-v0.0.1-stale` 当真相 → judge stale）——证明 K4 真实可复现
  - GREEN：改 `tests/test_doc_freshness.sh` 把 `get_latest_release_version()` 改为 `get_project_version()`，真相源从 `readlink "$ROOT_DIR/Release/latest"` 切到 `tr -d '[:space:]' < "$ROOT_DIR/VERSION"`，前缀加 `handoff-`。变量 `$LATEST_VERSION` 改名 `$PROJECT_VERSION`，Test 4/5 标签从"与实际一致"改"与 root VERSION 一致"
  - 验证：RED test → 1/0 GREEN；test_doc_freshness 本体 → 14/0 GREEN；run_all → 24 套件全绿（v2.1.0 是 23，本次 +1 = k4-chicken-egg guard）
- **v2.1.1 文档收口（含语义反转后的真正 doc bump）**:
  - `VERSION` + `skills/handoff/VERSION` → `v2.1.1`
  - `README.md` § 7 目录树：`latest → handoff-v2.1.1` + tarball/skill 命名 + "23 套件" → "24 套件"
  - `HANDOFF.md` Project Overview：当前版本 + 项目阶段 + 构建状态（23 → 24 + 拆 lint/tidy/postflight/doc-freshness/k4-chicken-egg/其他）
  - `HANDOFF.md` Milestones 表：新增 v2.1.1 行（顶部时间倒序）+ 当前 Milestone 段从 "Stable v2.1.0" 换 "Stable v2.1.1"
  - `HANDOFF.md` Pointer stats：Gotcha 13 → 14，Decision 14 → 15
  - `CHANGELOG.md`：v2.1.1 entry（Theme + Why + Key changes + Backward compat + Not in v2.1.1）prepend 到顶部
  - `GOTCHAS.md`：+Gotcha #14（K4 chicken-egg 完整诊断 + 设计教训"Pre-release gate 真相源必须是项目当前状态，不是 release pipeline 末端的产物状态"，与 #12 闸门三准则同根）
  - `Handoff_Decisions/0015-2026-05-11-v2-1-1-k4-doc-freshness-source-from-version-not-release-latest.md`：完整决策推理（拒 A 移除断言 / 拒 C procedural workflow / 选 B 改测试真相源）
- **gitx-release v2.1.1 一次过**:
  - `PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/gitx-release.sh --version v2.1.1` 跑完，**完全没有用 K4 manual revert workaround**——这就是修对了的最强证据
  - 产物 `Release/handoff-v2.1.1/` 含 `.skill` + source.tar.gz + full.tar.gz + checksums + SBOM + RELEASE_NOTES
  - `Release/latest → handoff-v2.1.1` 原子翻转成功
  - Deep Audit 一次跑 208/0/1（§8_latest 翻转前 skip 是预期）；CHANGELOG placeholder 替换为真实 release notes 后**再跑 audit → 209/0/0**（v2.1.0 当时 203/0/1，被 K4 drift 永久卡在 208/1 直到 fixed）
- **Git 状态**:
  - commit `03d644d` 单条 push 到 private Git host `<private-org>/Handoff` main（1f2b95f → 03d644d，9 files changed，189+/34-）
  - annotated tag `v2.1.1` 已 push（git tag `-a v2.1.1 -m "..."` + `git push origin v2.1.1`）
- 走过的弯路:
  - Boss 一开始调 `/gitx-release` 时我差点直接跑（default = patch bump）。Linus#1 "真问题吗"触发——发现"无新改动"+"实战观察期"，停下来 surface 三选项。教训：slash command 默认行为不总是用户意图，遇到状态突变（刚发版完又调发版）先停问意图
  - 写 Edit 时几个文件没用 Read tool 先读（用 Bash grep 读了），edit 报错"file has not been read yet"。Bash 读 ≠ Read 工具状态登记，必须 Read 后 Edit。教训：Read tool 是状态机的一部分，不是文本读取的随便工具
  - 想过把 Test 4/5 完全移除（选项 A），仔细 weighed 后拒——这两条本身是合法 gate（防止文档忘 bump），完全移除等于关闘。Karpathy#3 surgical：fix 错位的真相源就够了，别牵连合法保护

**验证**:
- `bash tests/test_doc_freshness_k4_chicken_egg.sh` → 1/0（K4 regression guard 长青）
- `bash tests/test_doc_freshness.sh` → 14/0（Test 4 + Test 5 跟 root VERSION 一致）
- `bash tests/run_all.sh` → **24 套件全绿**（v2.1.0 是 23 + k4-chicken-egg = 24）
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → ✅ all 5 checks passed
- `PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/release-audit.sh v2.1.1` → **209/0/0 PASS**（v2.1.0 是 208/1，§3_sync 卡 K4 drift；v2.1.1 直接全过）
- `git ls-remote origin refs/heads/main refs/tags/v2.1.1` → SHA 与 local 一致；远端 private Git host 收到 v2.1.1 tag

**关联**: Dev Log 0040（实战观察期决策被 audit 改写）；Dev Log 0039（v2.1.0 release，K4 第二次撞）；Dev Log 0031（v2.0.0 release，K4 第一次撞）；Gotcha #14（设计教训沉淀，与 Gotcha #12 同根）；Decision 0015（B vs A vs C 推理）；Decision 0013（v2.2.0 race fix 推延决策保持有效，本次只动 doc-freshness 设计层）；下次 release pipeline 应一次过——K4 是最后一个手动 workaround 退役
