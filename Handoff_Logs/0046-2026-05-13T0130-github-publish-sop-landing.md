---
schema: 2
type: dev-log
date: 2026-05-13T01:30
number: 0046
title: GitHub publish SOP 落地 — Handoff 接入 tkxlab-ai/HandoffX（B 模式 per-release source-snapshot push）
---

### 2026-05-13 01:30 — GitHub publish SOP 落地 — Handoff 接入 tkxlab-ai/HandoffX

**触发**: Boss 决定把 Handoff Plugin 接入 GitHub `tkxlab-ai/HandoffX` 作为对外发布门面，要求规划 SOP 流程。private Git host 主仓继续承担私有开发，永不暴露。会话横跨 7 个决策点 + 1 次重要反转（publish-only → 完整推码 B 模式）。参考 Boss 在另一项目（MacAudit）实战过的 `github-upload-workflow.md` 8-Phase SOP。

**改动**:

- **决策推理（详见 Decision 0018）**:
  - 仓库：`tkxlab-ai/HandoffX` public ✅
  - 模式反转：A publish-only → **B per-release source-snapshot push**（触发：Boss 问 "完整推码 是否更符合 github 精神"，重审 Linus 三问后 A 改 B）
  - 回填范围：v2.0.0 → v2.2.0 共 8 个 v2.x（v1.2.x 无 tag 不回填）
  - 资产：全套 `.skill` + `source.tar.gz` + `full.tar.gz` + `checksums.txt` + `RELEASE_NOTES.md` + `sbom.cyclonedx.json`
  - CI：不启用 GitHub Actions
  - SOP 落位：Handoff 本地（暂不进 gitx-release 技能，等第 2 个 consumer 稳定再抽象）

- **新增文件**（8 个，纯 docs + scripts + GitHub 元文件，0 行 production code 改动）:
  - `docs/GITHUB_RELEASE_SOP.md`（~250 行）— 8 Phase SOP + 4 场景回滚 + AI 执行清单 + 4 附录；借用 MacAudit 框架，删 Swift 步骤改 bash/markdown 步骤
  - `scripts/release-publish-github.sh`（170 行）— 单版本 publish；含 identity check / 三层凭证扫描 / draft → 5s 预览 → 转正流程；幂等（`--clobber`）；支持 `--draft` 只创不转正
  - `scripts/release-publish-github-backfill.sh`（130 行）— 一次性回填 8 个 v2.x；累成 commit chain；最后批量 push main + 8 个 tag；逐个 `gh release create` 幂等跳已存在
  - `SECURITY.md` — 漏洞披露渠道（GitHub private advisory + email 占位符）；90 天 coordinated disclosure
  - `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1 短引用（不抄全文 — Anthropic content filter 拒 CC 全文里的触发词，转用官方 URL 链接 + 报告渠道）
  - `.github/ISSUE_TEMPLATE/config.yml` — 关闭 blank issues + 引导到 security advisory / INSTALL.md / README
  - `.github/ISSUE_TEMPLATE/bug.yml` — form 模板，含 version / CLI / OS / 复现步骤 / logs / pre-submission checks
  - `.github/PULL_REQUEST_TEMPLATE.md` — 政策声明 "本仓库不接受 PR — 通过 Issue 提 diff"

- **设计要点**:
  - **Per-release wipe-rewrite**：publish worktree（`.github-publish-wt/`）每次发版前完全清空（保留 `.git`），从 `Release/handoff-vX.Y.Z/handoff-vX.Y.Z-source.tar.gz` 解出本版源码 → 加 SECURITY/COC/.github 公开仓元文件 → commit + tag。下一版重复同样流程，commit chain 自然累成。
  - **git identity 隔离**（MacAudit v0.3.1 实战教训）：`git config user.name "Handoff"` + `user.email "noreply@github.com"` 在每次操作前重设；Phase 5 push 前用 `git log -1 --format=%an` 断言不是 `niu@*.local`
  - **三层凭证扫描**：(1) 发版前扫 `Release/handoff-vX.Y.Z/` (gitx-release 已扫一次，复扫) → (2) worktree 解出 + 元文件混合后再扫 → (3) `git diff --staged` 最终扫描，全部 0 hit 才放行
  - **Remote 字段防护**：脚本启动时 `git remote -v | grep -qiE "gitea|<private-port>|<private-org>"` 若命中立刻退出 — 防误把 private Git host remote 加到 publish worktree
  - **三道安全门**（防 force-push 误用）：worktree 是 per-release rewrite 模式，main 永远 force-with-lease push 是设计意图；force-with-lease 比 force 安全
  - **回滚 A/B/C/D 四场景**：tag 推但 release 没建 / release 建错 / commit 推错 / 凭证泄漏（含 git-filter-repo 抹除步骤）

- **走过的弯路**:
  - 最初推荐 A publish-only 模式（main 只有 README），Boss 反问 "完整推码 是否更符合 github 精神" — 触发我重新跑 Linus 三问，发现把"暴露 private Git host"和"暴露源码"混淆了：(a) private Git host 隐私是硬约束 / (b) 源码本来就准备在 release 里挂 source.tar.gz 公开，所以推 commit 不增加新暴露。改 B 模式。教训：用户重新质疑时不要急着维护原方案，先看自己之前的推理有没有混淆概念
  - 写 CODE_OF_CONDUCT.md 抄 Contributor Covenant 2.1 全文 → Anthropic 内容过滤器拒输出（CC 2.1 含大量 "harassment/sexualized/violence" 等反面引用词，filter 不区分上下文）→ 改用短引用 + 官方 URL 链接，绕过 filter 同时保持政策完整性。教训：政策类文档抄全文有风险，链接 + 短摘要更稳
  - 多次被 UserPromptSubmit hook 注入的 "Secure-by-Default Libraries" 安全库速查表干扰理解 — Boss 一度以为是 policy 阻塞，澄清后确认是无害的 hook 注入文本

**验证**:
- ✅ 8 个文件全部落盘
- ✅ 两个 bash 脚本通过 `bash -n` 语法检查
- ✅ `chmod +x` 已设
- ✅ Decision 0018 + Dev Log 0046 双链接
- ⏳ **未执行**任何 GitHub push / release create — 仅落 SOP，待 Boss 触发首次实战
- ⏳ HANDOFF.md Current State 待更新（下一步）

**Open items**（pending Boss）:
1. `security@tkxlab.ai` / `conduct@tkxlab.ai` 邮箱真实化（当前 TODO placeholder）
2. v2.2.0 何时跑 `release-publish-github.sh v2.2.0` 触发首发
3. 回填用一次跑通还是先 `--dry-run` 看一眼
4. README 双语化（v2.2.1+ backlog）
5. publish 流程提到 gitx（v2.3.0+ backlog，需 Handoff + MacAudit 都跑稳后）

**SOP 自身的迭代预期**（仿 MacAudit "文档是在真实发版事故中长出来的"）：v1 写完只是"纸面状态"，第一次跑 `release-publish-github.sh v2.2.0` 才会触发 v2 修订。如果首发一次跑通无 bug，本 SOP 才算成熟。

**关联**:
- Decision `0018-2026-05-13-github-publish-mode-b-per-release-source-snapshot.md`
- 参考：`<dev-home>/tkbox/Cloud_Coding/Coding_mac_system_audit/MacAudit/docs/github-upload-workflow.md`（MacAudit 8-Phase SOP，借框架）
- 新增 SOP：`docs/GITHUB_RELEASE_SOP.md`
- 新增脚本：`scripts/release-publish-github.sh` + `scripts/release-publish-github-backfill.sh`
