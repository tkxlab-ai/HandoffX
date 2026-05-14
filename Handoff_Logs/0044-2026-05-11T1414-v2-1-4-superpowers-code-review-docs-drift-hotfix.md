---
schema: 2
type: dev-log
date: 2026-05-11T14:14
number: 0044
title: v2.1.4 — superpowers code-review 触发的 v2.1.3 docs drift hot-fix（authoring/review 分离首次实证）
---

### 2026-05-11 14:14 — v2.1.4 — superpowers code-review 触发的 v2.1.3 docs drift hot-fix（authoring/review 分离首次实证）

**触发**: 同日发完 v2.1.1 / v2.1.2 / v2.1.3 三个 patch 后，Boss 问"需要再进行 review 吗"——按 CLAUDE.md §4「authoring/review must separate — never self-approve in same context」，我自己写代码 + 自己测 + 自己 audit + 自己 push 全程零独立 review，是公开承认的 §4 违规。Boss 选 A 全量 code review + 调 superpowers code-reviewer 执行。

**改动**:
- **Phase 0 — 独立 review**:
  - 跑 `Skill: superpowers:requesting-code-review` skill 取 protocol
  - 用 `Task tool (general-purpose)` 派 subagent，范围 BASE=v2.1.0 (55c7c1b4) → HEAD=ea7e76b（覆盖 3 个 patch + 4 个 Dev Log + 3 个 Decision + Gotcha #14/15/16/9-obsolete）
  - prompt 含完整 template（DESCRIPTION / REQUIREMENTS / SHA / 高悬念区域 + 强调"You are the only independent eye"）
  - subagent 跑 ~4.5 分钟 / 47 tool uses / 98K tokens；返回 5-section findings
  - **verdict**: `With fixes` — 1 Critical + 4 Important + 4 Minor + 3 Recommendations
- **Phase 1 — 1 Critical 修复**（用户面 bug）:
  - reviewer 发现 INSTALL.md / README.md / CONTRIBUTING.md 共 10 处 `skills/handoff/commands/` 引用（v2.1.3 改名 `command-shims/` 后 docs 未同步）
  - v2.1.3 .skill 用户解包后按 docs 手动 `cp skills/handoff/commands/*.md` 会撞 `No such file or directory`（install.sh 路径正常，因为有 bootstrap-time rename；但手动安装路径绕过 install.sh）
  - 4 处文件全替换 `commands/` → `command-shims/`（+ 兼容性注释"v2.1.3 起改名，原 commands/"）
- **Phase 2 — 4 Important 修复**（plan-vs-actual drift）:
  - **HANDOFF.md:36 项目阶段**：去掉错误的 `frontmatter when_to_use 扩展` 字样（实际被 skill-creator validator 拒，shipped 是 description-only 扩展）
  - **Decision 0017**：加 **Outcome（v2.1.4 hot-fix 时回填）** 表格段落 — 逐项 ✅/❌/🔶 标记 B2 + when_to_use 两项反转；+ 3 条 Outcome 教训（改动前 grep 内部 release pipeline / 跨工具分发用 validator 验 / Decision 模板加 Outcome 必填字段）
  - **CHANGELOG.md v2.1.3 §Why**：原"3 项 Skill spec 偏离"段重写为"初版怀疑 3 项里 2 项 release-gate 反转"
  - **CHANGELOG.md v2.1.3 §目录改名**：B2 加 ❌ **撤回** 标记 + 引用 release-audit.sh 路径
  - **CONTRIBUTING.md:76**：contributor checklist 命令定义路径同步
- **Phase 3 — Minor 修复**:
  - **K4 trap SIGKILL 注释**（reviewer Minor #6）：`tests/test_doc_freshness_k4_chicken_egg.sh:25` 加注释 acknowledge "trap EXIT 不覆盖 SIGKILL，OOM-killer / kill -9 会留 Release/latest 污染。概率极低，as-is acceptable"
- **Phase 4 — v2.1.4 release pipeline**:
  - VERSION + skill/VERSION → v2.1.4
  - HANDOFF "当前版本" / "项目阶段" / Milestones（加 v2.1.4 row）/ 当前 Milestone "Stable v2.1.4"
  - CHANGELOG.md prepend v2.1.4 entry（Theme + Why + Key changes + Audit trail + Backward compat）
  - README.md 引用 `handoff-v2.1.4`
  - gitx-release v2.1.4 → audit **186/0/0** PASS ✅
  - commit `929f4c7` push 到 private Git host；annotated tag `v2.1.4` push
- 走过的弯路:
  - 第一反应想"review 是 nice-to-have"——但 §4 明文是 should，且 v2.1.3 自己撞过两次 release-gate fail（when_to_use validator 拒 / agents/ revert）。这两次 fail 本质就是缺独立 review，机械验证（audit/validator）兜住了功能但 docs 没人 audit
  - 不知道 superpowers code-reviewer 的具体调用名——查 Available Skills 发现 `superpowers:requesting-code-review`（不是 reviewer 本身，是 protocol skill 教 Claude 怎么 request review）。invoke 后给出 Task tool 模板。从此学会：superpowers/ 命名空间下"requesting-X"是 protocol，"X-skill"是 implementation
  - 担心 reviewer 太严苛找 false positive——实际 5/5 findings 全是真问题。Subagent 独立 context 比同 context 自审高出一个 quality 等级，**值回 review 工时**

**验证**:
- `bash tests/run_all.sh` (macOS bash 3.2) → **24/24 ✅**
- `bash tests/test_doc_freshness.sh` → 14/0
- `bash scripts/handoff-postflight.sh --quiet HANDOFF.md` → ✅ 5/5
- `diff -q scripts/ skills/handoff/scripts/` → 0 deltas
- `PROJECT_NAME=handoff bash ~/.claude/skills/gitx-release/scripts/release-audit.sh v2.1.4` → **186/0/0 PASS**
- `git ls-remote origin refs/heads/main refs/tags/v2.1.4` → SHA 与 local 一致
- INSTALL.md / README.md / CONTRIBUTING.md grep `skills/handoff/commands/` → 0 命中

**reviewer 完整 findings 归档**:
- **Strengths** (8 条): K4 fix 结构正确 / mawk POSIX 化无遗漏 + 没误改 sed-E grep-E / B7-a EUID=0 skip 理由清楚 / install.sh dual-path cleanup 正确 / bootstrap rename guard 安全 / dual-source byte-identical / Dev Log 0043 honest 记录 revert / 24 套件 386+ 断言全过
- **Critical** (1): INSTALL/README 手动 install 路径 ❌ → 修
- **Important** (4): Decision 0017 plan-vs-actual + HANDOFF 项目阶段 + CHANGELOG agents 行 + CONTRIBUTING ❌ → 修
- **Minor** (4): K4 trap SIGKILL 加注释 ✅；其余 3 项（SKILL.md 描述 byte vs char 措辞 / Bootstrap rename 不可扩展 / Gotcha #16 4 case 偏大）defer 到 v2.2.0+ 真需要再做
- **Recommendations** (3): release.sh 加 upstream-recalibration check / .skill 内容 sanity test / Decision Outcome 模板必填字段——全部沉淀进 v2.2.0 backlog

**关联**: review subagent agent ID `a6f9d1e1509131945`（superpowers:requesting-code-review）；Dev Log 0043（被 review 的 v2.1.3 patch）；Dev Log 0042（v2.1.2 Linux compat）；Dev Log 0041（v2.1.1 K4 fix）；Decision 0017（hot-fix 加 Outcome 段）；Gotcha #16（4 case study + Outcome 教训沉淀）；CLAUDE.md §4「authoring/review must separate」首次实证落地——证明 §4 的 ROI（5/5 真问题，全是同 context 自审看不见的盲点）；v2.2.0 backlog 增项："Decision template 加 Outcome 必填字段" + "release.sh 加 upstream-recalibration check" + ".skill artifact 内容 sanity test"
