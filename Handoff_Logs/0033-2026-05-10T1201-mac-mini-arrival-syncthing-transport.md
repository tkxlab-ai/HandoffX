---
schema: 2
type: dev-log
date: 2026-05-10T12:01
number: 0033
title: Mac mini 测试机到位：Syncthing-as-transport + 三家 v2.0.0 in-place + K5 cleanup gate
---

### 2026-05-10 12:01 — Mac mini 测试机到位：Syncthing-as-transport + 三家 v2.0.0 in-place + K5 cleanup gate

**触发**: Boss 切到 Mac mini 测试机（`TK-Kaufmann-Mac-mini.local` / macOS 26.4.1 / arm64）后命令"对项目下所有文件做一次全量读取，更新一下 handoff"。`/handoff-recall` 报告的 Current State 还是上次 dev 机 push private Git host 后那条（2026-05-09 02:26），跟当前测试机实际状态有结构性差异，必须刷一次。

**改动**:
- 非代码改动；本条 Dev Log 是搬迁后状态盘点的持久化记录
- **平台变化探测**:
  - arch arm64 / bash 5.3.9 (`aarch64-apple-darwin25.1.0`)：比 v2 baseline 假设的 bash 3.2 高很多，所有 fallback 路径都不用走也安全
  - date 仍是 BSD（不是 GNU），跨平台代码 `date -v+Nd` / fallback 链都按 macOS 路径执行
  - shellcheck 0.11.0 在 `/opt/homebrew/bin/shellcheck`（Apple Silicon 路径）
  - rsync / zip 都用 `/usr/bin/` 系统自带，没换 Homebrew
- **传输方式偏离 Mac Project Transfer.md §K5**:
  - 原计划：tarball 解压 + `bash install.sh --claude --opencode --codex`
  - 实际：Syncthing 整目录同步——`./skills/handoff/` / `Release/` / `~/.claude` / `~/.config` / `~/.agents` 全是 Syncthing 推过来的
  - 副作用：三家 skill（Claude `~/.claude/skills/handoff/` + OpenCode `~/.config/opencode/skills/handoff/` + Codex `~/.agents/skills/handoff/`）的 VERSION 全部已经是 v2.0.0，等于 install 阶段已被 Syncthing 间接完成
- **private Git host 远端连接重确认**（Mac mini 第一次实测）:
  - SSH 真实端口在 `~/.ssh/config` 配为 **<private-port>**（不是 22）；`nc -z 22` 会 false-negative 超时——后续测试机问题排查注意这一点
  - identityfile `~/.ssh/<private-ssh-key>`（已迁移到 Mac mini）
  - SSH 认证 key 名是 `kaufmann-macmini-20260509`（Boss 新机新加，原 dev 机的 `private Git host_Personal_TK` 在 private Git host 端仍可用，等同两把都接受）
  - `git ls-remote origin` → main `9ed6c8a` + v2.0.0 annotated `67c16440` + peeled `cfafef7`
  - `git fetch` 后 `HEAD...@{u}` = `0 0`（本地与远端严格相等，没有任何漂移）
  - HTTPS 443 也通（curl 200 nginx）
- **三家 skill in-place 与源仓库一致性比对**:
  - `diff -rq ./skills/handoff <CLI install dir>` 三家都只输出 `Only in ./skills/handoff: commands` + 一堆 `.syncthing.*.tmp`——`commands/` 本来就是 slash shim 编译源（不应该出现在 install dir，这是预期），`.syncthing.*.tmp` 全是 sync 中转 tmp（详见下条）
- **Syncthing 残留盘点（不删，仅记录）**:
  - 项目根 + 子目录共约 150 个 `.syncthing.*.tmp` 文件；每个对应一个 canonical 文件
  - 抽样 byte-equality 测试 6/6 全等于 canonical（HANDOFF.md / CHANGELOG.md / install.sh / LICENSE / GOTCHAS.md / skills/handoff/VERSION）
  - 还在 `.claude/worktrees/handoff-v2/` 镜像里再套了一份残留（worktree 本身也是 v2.1.0 backlog 要清的）
  - `.gitignore` 当前有 `*.sync-conflict-*` 但**缺 `.syncthing.*.tmp` 规则**，导致这些文件在 `git status` 里全部 untracked 噪声
- **新 untracked（与 handoff 无关，但要记入状态）**:
  - `.cursor/`（Cursor IDE）/ `.python-version`（pyenv local）/ `.claude/`（Claude Code 本机 settings.local 已 ignored，只露 worktrees）
- **后置 4 项 GREEN（Mac mini 第一次跑全部通过）**:
  - `bash tests/run_all.sh` → **22 套件全绿**（与 dev 机 push 前最后一次一致；arm64+bash 5.3.9 没引入回归）
  - `bash scripts/handoff-lint.sh HANDOFF.md` → exit 0
  - `bash scripts/validate-handoff.sh --readiness HANDOFF.md` → ✅ structure OK
  - `bash scripts/scan-credentials.sh HANDOFF.md` → exit 0
- 走过的弯路:
  - 一开始 `nc -zv <private-git-host> 22` 超时——以为 private Git host 挂了 / 防火墙变化。`ssh -G` 才看到 `~/.ssh/config` 把端口 remap 到 <private-port>。后续 Mac Project Transfer.md / GOTCHAS 应该提一句"private Git host SSH 端口非 22 是预期"

**验证**:
- 22 套件全绿；后置 4 连 GREEN（lint / validate / scan / archive 隐含）
- `git ls-remote origin` 真拉 ref + `git fetch --dry-run` 无更新 + `0 0` 同步 delta（不是 `BatchMode` 短路）
- Mac mini 实际 SSH 认证日志：`Hi tokenadmin! ... successfully authenticated with the key named kaufmann-macmini-20260509`
- `HANDOFF.md` schema marker `<!-- HANDOFF v2 schema -->` + Migrated `2026-05-08T10:27Z` 完整保留（Syncthing 没破坏 v2 元数据）
- 三家 skill VERSION 文件全部 = v2.0.0；source `./skills/handoff/VERSION` = v2.0.0；根 `VERSION` = v2.0.0（5 处一致）

**关联**: Dev Log 0032（private Git host push 前一步，本条的前置）；Mac Project Transfer.md §K5（原 K5 验证清单需要按 Syncthing-as-transport 实际改写）；Current State 待办里新增"Syncthing residue cleanup + 加 `.syncthing.*.tmp` 到 .gitignore"作为 K5 真测试前的 cleanup gate；K5 真测试本身（fresh project + v1 migration scenario）将作为本会话或下次会话独立块进行
