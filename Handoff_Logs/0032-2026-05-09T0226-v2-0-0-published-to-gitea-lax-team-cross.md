---
schema: 2
type: dev-log
date: 2026-05-09T02:26
number: 0032
title: v2.0.0 published to private Git host <private-org> + cross-machine clone migration prep
---

### 2026-05-09 02:26 — v2.0.0 published to private Git host <private-org> + cross-machine clone migration prep

**触发**: 用户决定 v2.0.0 不走"测试机先验证、再上 upstream"的传统路径，改成"先 push 到 private Git host <private-org> 建立 source-of-truth，然后整机克隆迁移到测试机进行 K5 真机验证"。这台 dev 机即将被作为 source 整机克隆走（含 ~/.claude/.config/.ssh 等所有配置 + sessions），所以要确保 git 远端是 final、所有非 git 产物有书面迁移指南。

**改动**:
- **首次 push 到 private Git host**（首次外部发布；按用户给的 playbook 执行）：
  - SSH auth verify：`ssh -T git@<private-git-host>` → `Hi tokenadmin! ...successfully authenticated with the key named private Git host_Personal_TK`
  - `git remote add origin git@<private-git-host>:<private-org>/Handoff.git`
  - `git push -u origin main` → `* [new branch] main -> main`，44 个 commit 全部上传
  - `git push origin --tags` → `* [new tag] v2.0.0 -> v2.0.0`（annotated tag, type=tag, tagger=TKXLAB）
- **10 维度 push 完整性回测**全过：
  - main HEAD SHA `24a7da7b...` 本地 vs 远端字节相等
  - v2.0.0 tag object SHA `67c16440...` 一致
  - tag peeled commit SHA `cfafef7d...` 一致
  - `git fetch` 后 `rev-list --left-right --count` = `0 0`（无单边 commit）
  - 总 commit 数 44 = 44
  - working tree `--porcelain` 空
  - 树根 SHA `7cbd25e9...` 一致 = Merkle 全树（149 文件）每个 blob 字节相等
  - `git ls-tree -r HEAD` vs `origin/main` 逐行 diff 空
  - `git fsck` 通过无 dangling
  - `git log` 本地 vs 远端逐行 SHA 列表完全一致
- **预 push 工作树清理**:
  - 删 5 个 sync-conflict 文件（4 个根目录 + 1 个 `Release/`）；mtime 确认全部 stale（早于 canonical）
  - 加 `*.sync-conflict-*` 到 `.gitignore` 防未来 Syncthing 残留进 git
  - commit `24a7da7 docs: cross-machine transfer guide + /handoff Dev Log 0031 + Decisions 0010/0011`（含 Mac Project Transfer.md / 0031 Dev Log / 2 Decisions / .gitignore）
- **整机克隆迁移给后续 session 的 watch-list**（口头给出，未写入文档；详见本会话对话记录）:
  - 4 块 §一 git 已 push 不用拷 / §二 git 不带的 `Release/` + `Handoff_planning_0506/` 必拷 / §三 `~/.ssh` `~/.claude` `~/.config` `~/.codex` `~/.agents` 必迁 / §四 5 个陷阱（SSH 私钥 chmod 600 / Syncthing device ID 必须新机重生成 / settings.local.json 删掉重建 / projects/ 目录名编码源机路径要看用户名是否同 / Apple Silicon vs Intel 路径 / Keychain 单独迁移）
  - 目标机首次启动验证清单 8 步（ssh-T / clone / 测试 / lint / 后置 4 连 / 装 skill / 升级 v2.0.0）
- 走过的弯路:
  - 第一步 push 前发现 working tree 有 8 项未提交（HANDOFF.md modified + 4 v2 新文件 + 4 sync-conflict）；按 playbook 必须 `git status -s` 空。先做 §1 sync-conflict 清理 + commit /handoff 0031 产出，才进入 push
  - 跑 SHA 对比的脚本里 grep 没区分 annotated tag object SHA vs peeled commit SHA，第一次输出看着像是 mismatch；分开查 `refs/tags/v2.0.0` 和 `refs/tags/v2.0.0^{}` 才看清两个 SHA 都对得上

**验证**:
- Remote `https://<private-git-host>/<private-org>/Handoff` 已包含 main + v2.0.0 tag + 31 Handoff_Logs/ + 11 Handoff_Decisions/ + GOTCHAS.md + MIGRATION_GUIDE_v2.md + Mac Project Transfer.md
- VERSION 远端值 `v2.0.0`；skills/handoff/VERSION 远端值 `v2.0.0`
- `git fetch origin` 后 main 与 origin/main 完全同步，`@{u}..HEAD` 空
- `bash tests/run_all.sh` → 22 套件全绿（push 前最后一次跑）
- `bash scripts/handoff-lint.sh HANDOFF.md` → exit 0（K3 self-migrated 项目通过严格 v2 lint）
- worktree-handoff-v2 分支没意外推到远端（按设计——已合 main 不需要单独推）

**关联**: Dev Log 0031（v2.0.0 release 收尾，本条的前置工作）；Decision 0010/0011（停 Codex R4 + v2.0.0 in-place re-release）；Mac Project Transfer.md（跨机迁移 user-facing 指南，已在 commit `24a7da7`）；MIGRATION_GUIDE_v2.md（v1→v2 升级指南）；K5 真机验证将在测试机克隆完成后由用户启动，本会话不再继续；本 session 即将关闭，下次接手从 private Git host clone + 读 HANDOFF.md（recall）即可全状态接续
