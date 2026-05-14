---
schema: 2
type: decision
date: 2026-05-13
number: 0018
title: GitHub 接入 — publish 模式选 B（per-release source-snapshot push），SOP 落 Handoff 本地
---

### 2026-05-13 — GitHub 接入 — publish 模式选 B（per-release source-snapshot push），SOP 落 Handoff 本地

**背景**

Boss 决定把 Handoff Plugin 接入 GitHub（`tkxlab-ai/HandoffX`，公开）作为对外发布门面。private Git host 主仓继续承担私有开发 + 完整历史 + WIP 分支，永不出现在 GitHub 任何 metadata。需要规划 SOP 流程 + 工具链。

讨论横跨 7 个决策点：(1) 仓库 + 可见性 / (2) private Git host↔GitHub 关系 / (3) 历史 tag 回填范围 / (4) Release 资产 / (5) CI / (5a) v2.x 子集 / (5b) v2.2.0 当首发。中途反转 1 次：原"publish-only 不推码"被 Boss 重新质疑"完整推码是否更符合 github 精神"，触发 Linus 三问重审。

参考资料：MacAudit `github-upload-workflow.md`（同 Boss 在另一项目实战过的 8-Phase SOP）。

**选项**

| 维度 | A · Publish-only | **B · Per-release source-snapshot push** | C · 完整镜像每个 commit |
|------|------|------|------|
| GitHub main 内容 | 仅 README | release 时刻完整源码快照 | 全部开发历史 |
| `git clone` 跑代码？ | ❌ | ✅ | ✅ |
| 暴露 private Git host URL/credentials？ | ❌ | ❌（git identity 隔离 + remote 不挂 private Git host） | ❌（需同样隔离） |
| 暴露开发 WIP / 中间 commit？ | ❌ | ❌（每 commit = release 快照） | ⚠️ 会 |
| GitHub 用户体验 | "下载站" | **"正常开源项目"** | 完整 |
| 每次发版工作量 | 1 步 | 2 步 | N+ 步 |

**选择 B**

**Linus 三问**

- **真问题吗**：是。GitHub 露脸不只是分发——`git clone` / code search / blame / star/fork / Issue 引用代码行 都是用户期望。publish-only 模式（A）只满足分发，舍弃其他价值。
- **更简单**：B 比 C 简单（每版本一次 wipe + commit，不维护跨版本工作流），同时拿到 C 的全部代码可见性收益。
- **会破坏什么**：理论上"完全神秘"被舍弃，但 Handoff 是 MIT 项目，神秘性不是价值。private Git host 隐私靠 git identity 隔离 + remote URL 不挂 private Git host，技术上完整保护。

**反方观点（投票 B 时的弱点）**

- B 每次发版多一步"同步 publish worktree"。但 MacAudit 实战 3 次发版（v0.3.0→v0.3.1→v0.3.2）已证明可机械化，单脚本搞定。
- B 的 main 是"每次 force-with-lease 重写"，不符合常规 "commit chain 即历史" 心智模型。但配合 tag 体系，每个 tag 仍永久指向当时的 snapshot，外部用户感知正常。
- 担心 `niu@*.local` author 泄漏到公开 commit。MacAudit v0.3.1 实战踩过这坑，方案沉淀为 Phase 2.2 强制 `git config user.name "Handoff" / user.email "noreply@github.com"` + Phase 5 push 前 author 校验。

**回填范围**：v2.0.0 → v2.2.0 共 8 个。理由：

- v1.2.x（11 个）是 pre-v2 架构，无 git tag，外部用户用不上 → 不回填
- v2.0.0 是 GA 起点；v2.2.0 是当前 latest（产物全在 `Release/handoff-vX.Y.Z/`，回填零重建成本）

**资产范围**：全套——`.skill` + `source.tar.gz` + `full.tar.gz` + `checksums.txt` + `RELEASE_NOTES.md` + `sbom.cyclonedx.json`。gitx-release 已生成的产物全推上，零取舍。

**CI**：不启用 GitHub Actions。GitHub 只是 publish target，不参与 build。private Git host 端的 `tests/run_all.sh` + macOS+Ubuntu 双绿已是真相源，重测冗余。

**SOP 落位**：Handoff 本地（`docs/GITHUB_RELEASE_SOP.md` + `scripts/publish-github*.sh`），暂不进 gitx-release 技能。

- 拒"进 gitx"的理由：Karpathy#2——抽象需要 2 个真实 consumer 才稳。Handoff 自己还没跑过一次 GitHub 发版，不算稳定 consumer
- v2.3.0 backlog 添加"Handoff + MacAudit 都跑稳后，提通用 70% 到 gitx 技能（新增 `gh-publish` 子命令）"
- 借用 MacAudit SOP 框架的 8 Phase 结构 + git identity 防泄漏 + draft → 预览 → publish 流程 + 4 场景回滚——通过 SOP 文档引用 / 抄结构方式，不引入跨项目代码依赖

**双语 README 决策**

参考 MacAudit (`README.md` EN 主 + `README_CN.md` zh 副)。Handoff 当前 `README.md` 是 zh 13K 字，翻译到 EN 4-6 小时工作量。**v2.2.0 接受 zh-only ship**，**v2.2.1+** 加 EN 版（避免阻塞当前接入）。

**当前 backlog（v2.2.1+ 触发条件）**：

- 翻译 EN README + 重命名当前 → README_CN.md
- 加 "What's New" 表（最近 5 版速览，仿 MacAudit）
- 决定是否加 token 投入 blockquote（仿 MacAudit "Live build metrics"）

**新增文件清单**（本次落地）

- `docs/GITHUB_RELEASE_SOP.md` — 8 Phase SOP + 4 场景回滚 + 4 个附录
- `scripts/release-publish-github.sh` — 单版本 publish（含 identity / scan / draft 流程）
- `scripts/release-publish-github-backfill.sh` — 一次性回填 8 个 v2.x
- `SECURITY.md` — 漏洞披露渠道（contact 用 placeholder）
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1 短引用（避 Anthropic content filter 触发）
- `.github/ISSUE_TEMPLATE/{config.yml, bug.yml}` — Issue form + 关闭 blank issues
- `.github/PULL_REQUEST_TEMPLATE.md` — 不接受 PR 政策声明

**开放项 / 等 Boss 决定**

1. `security@tkxlab.ai` / `conduct@tkxlab.ai` 邮箱是真实值还是别的？（当前是 TODO placeholder）
2. v2.2.0 何时跑 `release-publish-github.sh v2.2.0` 触发首发？（本次仅落 SOP，未执行任何 push）
3. 回填用一次跑通 `release-publish-github-backfill.sh`，还是先 dry-run 看一眼？

**Outcome（首次发版后回填）**

| 项 | 状态 |
|----|------|
| v2.2.0 首发到 GitHub | ⏳ pending Boss 触发 |
| 8 个 v2.x 回填 | ⏳ pending |
| SECURITY/COC 邮箱真实化 | ⏳ pending |
| README 双语化 | 📦 v2.2.1+ backlog |
| publish 流程提到 gitx | 📦 v2.3.0+ backlog |
