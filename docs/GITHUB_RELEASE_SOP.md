# GitHub Release SOP — Handoff Plugin

> **触发词**：Boss 说 `推 GitHub` / `发版到 GitHub` / `release to GitHub` / `publish vX.Y.Z` 时，AI 按本文档 **8 阶段** 顺序执行。
>
> **原则**：
> - `gitx-release` 负责"生成发布产物到 `Release/handoff-vX.Y.Z/`"（不动）
> - 本 SOP 接管"把 release 推到 GitHub"
> - 每个版本生成一个独立 commit + tag，**只快照不漏开发历史**
> - private Git host 主仓**永远不出现**在 GitHub 任何 metadata（URL / commit author / config）
>
> **最后更新**：2026-05-13 · v1
> **参考**：MacAudit `github-upload-workflow.md`（本 SOP 借用框架 + 删 Swift 特有步骤 + 加 Handoff 特有步骤）

---

## 0. 仓库结构认知

| 层 | 位置 | 用途 | git 状态 |
|----|------|------|----------|
| 私有主仓 | `<dev-home>/tkbox/Cloud_Coding/Handoff/` | 开发 + HANDOFF + Dev Log + 测试 | private private Git host remote（SSH <private-port>）|
| Publish worktree | `<project-root>/.github-publish-wt/` | 推 GitHub 的快照（per-release rewrite） | **独立 .git**，origin = `https://github.com/tkxlab-ai/HandoffX.git` |
| Release 产物 | `<project-root>/Release/handoff-vX.Y.Z/` | gitx-release 生成的 .skill + tarball + SBOM + 源码副本 | 不进 git |

**关键事实**：
1. **GitHub 上的源码 source of truth 来自 `Release/handoff-vX.Y.Z/*-source.tar.gz`**（gitx-release 已扫凭证 + 清 sanitize-ignore 内容）
2. **publish worktree 每次发版被 wipe + 重建**（不维护跨版本工作历史）
3. **private Git host remote 永不加到 publish worktree 的 .git/config**

---

## ⚙️ 变量约定（AI 替换前必读）

| 变量 | 含义 | 示例 |
|------|------|------|
| `${VER}` | 本次发版版本号（**带 v 前缀**） | `v2.2.0` |
| `${VER_BARE}` | 去掉 v 前缀的纯数字 | `2.2.0` |
| `${REPO}` | GitHub 仓库 slug | `tkxlab-ai/HandoffX` |
| `${RELEASE_DIR}` | 本版 release 产物目录 | `Release/handoff-${VER}` |
| `${PUBLISH_WT}` | publish worktree 路径 | `.github-publish-wt` |

```bash
# 跑 SOP 前必导
export VER=v2.2.0
export VER_BARE="${VER#v}"
export REPO=tkxlab-ai/HandoffX
export RELEASE_DIR="Release/handoff-${VER}"
export PUBLISH_WT=".github-publish-wt"

# 验证
echo "VER=$VER / VER_BARE=$VER_BARE / REPO=$REPO"
# ✅ 期望: VER=v2.2.0 / VER_BARE=2.2.0 / REPO=tkxlab-ai/HandoffX
```

---

## Phase 1. 前置检查（全部通过才进 Phase 2）

```bash
cd <dev-home>/tkbox/Cloud_Coding/Handoff

# 1.1 gitx-release 产物已生成
[ -d "$RELEASE_DIR" ] && ls "$RELEASE_DIR"/handoff-${VER}.skill >/dev/null 2>&1 \
    && echo "✅ gitx 产物 OK" \
    || { echo "❌ 跑 /gitx-release ${VER} 先生成产物"; exit 1; }

# 1.2 git tag 存在（gitx-release 已打）
git tag --list | grep -qx "${VER}" && echo "✅ tag ${VER} 存在" \
    || { echo "❌ 本地无 tag ${VER}"; exit 1; }

# 1.3 测试全绿（gitx-release 已扫过，本步是 publish 前最后一道闸）
bash tests/run_all.sh 2>&1 | tail -3
# ✅ 期望: 26 套件 / 591+ 断言 / 0 failures

# 1.4 凭证扫描（双护栏）
bash scripts/scan-credentials.sh "$RELEASE_DIR" \
    && echo "✅ 凭证扫描通过" \
    || { echo "❌ 凭证泄漏，aborting"; exit 1; }

# 1.5 gh CLI 已认证
gh auth status 2>&1 | grep -q "Logged in to github.com" \
    && echo "✅ gh 已登录" \
    || { echo "❌ 跑 gh auth login"; exit 1; }
```

**任何一项失败 → 停，等修复。**

---

## Phase 2. 创建 / 复用 Publish Worktree

```bash
cd <dev-home>/tkbox/Cloud_Coding/Handoff

# 2.1 publish worktree 不存在 → 一次性 setup
if [ ! -d "$PUBLISH_WT/.git" ]; then
    echo "🆕 首次 setup publish worktree..."
    mkdir -p "$PUBLISH_WT"
    cd "$PUBLISH_WT"
    git init -b main
    git remote add origin "https://github.com/${REPO}.git"
    cd ..
else
    echo "♻  复用现有 publish worktree"
fi

# 2.2 🔴 设 git identity（防 niu@*.local 泄漏到公开仓）
#
# MacAudit v0.3.1 实战教训：cp -r 继承的 .git 没 local config，
# 系统默认落回 whoami@hostname，author 被记 "jarvis <jarvis@<dev-host>>"。
# Handoff 同样必须设 local identity。
cd "$PUBLISH_WT"
git config user.name "Handoff"
git config user.email "noreply@github.com"

# 验证
git config user.name   # ✅ 期望: Handoff
git config user.email  # ✅ 期望: noreply@github.com

# 2.3 确认 remote 不含 private Git host 字样
git remote -v | grep -qiE "gitea|<private-port>|<private-org>" \
    && { echo "❌ remote 含 private Git host 字样，stop"; exit 1; } \
    || echo "✅ remote 干净（仅 github.com）"

cd ..
```

---

## Phase 3. 清空 Worktree（保留 .git）

```bash
cd "$PUBLISH_WT"

# 3.1 删除所有非 .git 内容（per-release rewrite 策略）
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

# 3.2 验证只剩 .git
ls -la
# ✅ 期望: 只有 . .. .git 三项

cd ..
```

---

## Phase 4. 解出本版源码到 Worktree

```bash
cd <dev-home>/tkbox/Cloud_Coding/Handoff

# 4.1 用 gitx-release 生成的 source tarball 解出（保证内容 = 已通过 sanitize-ignore 的版本）
tar xzf "${RELEASE_DIR}/handoff-${VER}-source.tar.gz" \
    -C "$PUBLISH_WT" \
    --strip-components=1

# 4.2 加上 GitHub 公开仓特有的元文件（私仓不需要，但公开仓必备）
cp SECURITY.md            "$PUBLISH_WT/" 2>/dev/null || true
cp CODE_OF_CONDUCT.md     "$PUBLISH_WT/" 2>/dev/null || true
cp -r .github             "$PUBLISH_WT/" 2>/dev/null || true

# 4.3 验证关键文件都到位
cd "$PUBLISH_WT"
for f in README.md LICENSE CHANGELOG.md INSTALL.md install.sh skills/handoff/SKILL.md SECURITY.md; do
    [ -e "$f" ] && echo "✅ $f" || echo "⚠ $f missing"
done

# 4.4 防御性凭证再扫一次（worktree 已组合后）
cd ..
bash scripts/scan-credentials.sh "$PUBLISH_WT" \
    && echo "✅ worktree 凭证扫描通过" \
    || { echo "❌ worktree 有凭证泄漏"; exit 1; }

# 4.5 🔴 脱敏（Decision 0018 第 1 条硬约束）
#
# gitx-release 产物（source.tar.gz）允许 dev-time absolute paths + private Git host 字样
# （`.sanitize-ignore` 故意 allowlist 这些），是 release tarball 给开发者读的设计。
# 但**公开 GitHub 仓库**不能含 private Git host host/port/org/SSH key/本地路径——所以解
# 出后必须再过一次脱敏：
#
#   1. 删除 3 个 dev-only 文件:
#      - Mac Project Transfer.md（整文件 = 迁机指南，含 private Git host remote + SSH key）
#      - NEXT_SESSION_NOTES.md（内部 session 切换笔记）
#      - HANDOFF.md.pre-v2-backup（v1 内部叙述 1470 行）
#   2. sed 替换敏感字符串（8 类 pattern → 占位符）:
#      <private-git-host> → <private-git-host>
#      <private-port>                  → <private-port>
#      <private-org>               → <private-org>
#      <private-ssh-key>           → <private-ssh-key>
#      private Git host                  → private Git host
#      <dev-home>/         → <dev-home>/
#      <dev-home>/            → <dev-home>/
#      <dev-host>             → <dev-host>
#   3. Verification grep — 任何剩余命中 → exit 1
bash scripts/release-sanitize-public.sh "$PUBLISH_WT" \
    && echo "✅ 脱敏完成" \
    || { echo "❌ 脱敏失败"; exit 1; }
```

---

## Phase 5. Commit + Tag

```bash
cd "$PUBLISH_WT"

# 5.1 全量 add
git add -A

# 5.2 push 前 staged diff 凭证扫描（第三道闸）
LEAK=$(git diff --staged | grep -cE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82,}|password\s*=|api[_-]?key\s*=|<dev-home>/' 2>/dev/null || true)
[ "$LEAK" -eq 0 ] && echo "✅ staged diff 干净" \
    || { echo "❌ staged 有 $LEAK 处凭证嫌疑，stop"; exit 1; }

# 5.3 commit
git commit -m "release: handoff ${VER}

Snapshot of source tree at tag ${VER}.
Source-of-truth: private dev tree (not exposed).
This commit is a clean release snapshot — no WIP history."

# 5.4 tag
git tag -a "${VER}" -m "Handoff ${VER}"

# 5.5 🔴 push 前身份校验
AUTHOR=$(git log -1 --format="%an <%ae>" HEAD)
echo "Commit author: $AUTHOR"
[ "$AUTHOR" = "Handoff <noreply@github.com>" ] \
    && echo "✅ author OK" \
    || { echo "❌ author=$AUTHOR — 修 git config 后 git commit --amend --reset-author --no-edit + 重打 tag"; exit 1; }

cd ..
```

---

## Phase 6. Push 到 GitHub

```bash
cd "$PUBLISH_WT"

# 6.1 首次 push 要 --force（publish worktree 是 per-release rewrite，main 是单 commit）
# 之后每次 push 也是 force-with-lease（每次都新 commit 替换 main）
git push origin main --force-with-lease 2>&1 | tail -5

# 6.2 push tag（tag 是 immutable，不需要 force）
git push origin "${VER}"

# 6.3 验证 GitHub 可见
gh repo view "$REPO" --json url -q .url
gh api "repos/${REPO}/tags" -q ".[] | select(.name==\"${VER}\") | .name"
# ✅ 期望: 输出 ${VER}

cd ..
```

**Why force-with-lease**：publish worktree 是"每次 wipe + rewrite"模式，main 永远只有一个 commit（最新版本）。这是设计意图，不是误用 force。`--force-with-lease` 比 `--force` 安全（防别人在你不知情时 push 了别的 commit）。

---

## Phase 7. 创建 GitHub Release

```bash
cd <dev-home>/tkbox/Cloud_Coding/Handoff

# 7.1 收集 release 资产
ASSETS=(
    "${RELEASE_DIR}/handoff-${VER}.skill"
    "${RELEASE_DIR}/handoff-${VER}-source.tar.gz"
    "${RELEASE_DIR}/handoff-${VER}-full.tar.gz"
    "${RELEASE_DIR}/checksums.txt"
    "${RELEASE_DIR}/sbom.cyclonedx.json"
)

# 验证所有资产存在
for f in "${ASSETS[@]}"; do
    [ -f "$f" ] && echo "✅ $f" || echo "⚠ $f missing (skipping)"
done

# 7.2 幂等检查
if gh release view "${VER}" --repo "$REPO" >/dev/null 2>&1; then
    echo "⚠ Release ${VER} 已存在 GitHub。重发用 release-publish-github.sh --clobber"
    exit 1
fi

# 7.3 创建 draft（先不发布，便于预览）
gh release create "${VER}" --repo "$REPO" \
    --title "Handoff ${VER}" \
    --notes-file "${RELEASE_DIR}/RELEASE_NOTES.md" \
    --target main \
    --draft \
    "${ASSETS[@]}"

# 7.4 浏览器预览
gh release view "${VER}" --repo "$REPO" --web
# 🔍 人审：标题 / 描述 / 资产清单 / tag 正确

# 7.5 确认无误 → 转正
gh release edit "${VER}" --repo "$REPO" --draft=false --latest

# 7.6 验证 latest 指针
gh release view --repo "$REPO" | head -5
# ✅ 期望: latest = ${VER}
```

---

## Phase 8. 收尾

```bash
cd <dev-home>/tkbox/Cloud_Coding/Handoff

# 8.1 更新 HANDOFF Current State + 加 Dev Log
# 由 /handoff 命令完成；本 SOP 不直接编辑

# 8.2 在本 SOP 附录 A 追加一行
# 格式: | ${VER} | YYYY-MM-DD | <主要改动> | https://github.com/${REPO}/releases/tag/${VER} |

# 8.3 私仓 push（如有 SOP 自身改动 / HANDOFF 更新）
git push gitea main --tags
```

---

## 🚨 回滚流程

### 场景 A：tag 推了但 release 没建
```bash
cd "$PUBLISH_WT"
git tag -d "${VER}"
git push origin ":refs/tags/${VER}"
# 修完后重新 tag + push
```

### 场景 B：Release 已建但内容有误
```bash
# 整删
gh release delete "${VER}" --repo "$REPO" --yes
# 或局部修
gh release edit "${VER}" --repo "$REPO" --notes-file new_notes.md
gh release upload "${VER}" --repo "$REPO" new-asset --clobber
```

### 场景 C：main commit 推错
```bash
cd "$PUBLISH_WT"
# publish worktree 每次都 force-rewrite，直接重跑 Phase 3-6
# 不用 revert，因为根本没有"开发历史"概念
```

### 场景 D：敏感信息泄漏（PAT / 密钥推到远端）
1. **立即 revoke** 泄漏的 token（GitHub Settings → Developer settings → Tokens）
2. 从 publish worktree 历史抹除：
   ```bash
   cd "$PUBLISH_WT"
   git filter-repo --path <leaked-file> --invert-paths
   git remote add origin "https://github.com/${REPO}.git"
   git push origin main --force-with-lease
   git push origin --tags --force-with-lease
   ```
3. 通知所有 clone 者重新 clone
4. **同时**检查私仓 private Git host 是否也泄漏（双源都得清）

---

## 📋 AI 执行检查清单

每个 Phase 完成必须输出对应行：

```
✅ Phase 1 前置检查 — gitx 产物 OK / 测试 NN/NN / 凭证扫 0 / gh 已登录
✅ Phase 2 worktree 就绪 — identity=Handoff <noreply@github.com> / remote 无 private Git host
✅ Phase 3 worktree 清空 — 只剩 .git
✅ Phase 4 源码解出 — N 个关键文件验证到位 / 凭证再扫 0 / **脱敏通过 0 leaks**
✅ Phase 5 Commit + Tag — author=Handoff / SHA=<...> / tag ${VER}
✅ Phase 6 Push — main + tag 已上 GitHub
✅ Phase 7 Release — draft 预览 → 转正 → latest=${VER}
✅ Phase 8 收尾 — HANDOFF/Dev Log 更新 / 附录 A 添行 / 私仓 push
```

**任何 Phase 失败 → 立刻停，报告。**

---

## 附录 A：发版历史索引

| 版本 | 日期 | 主要改动 | Release URL |
|------|------|----------|-------------|
| _(首次发版后由 Phase 8 追加)_ | | | |

---

## 附录 B：决策摘要

| # | 决策 | 详见 |
|---|------|------|
| 1 | 仓库 `tkxlab-ai/HandoffX` public | Decision 0018 |
| 2 | Publish 模式：per-release source-snapshot push（B 模式）| Decision 0018 |
| 3 | 回填范围：v2.0.0 → v2.2.0 共 8 个 | Decision 0018 |
| 4 | 资产：`.skill` + source.tar.gz + full.tar.gz + checksums + RELEASE_NOTES + SBOM | Decision 0018 |
| 5 | CI：不启用 GitHub Actions | Decision 0018 |
| 6 | README 双语：当前 zh-only 接受；v2.2.1+ 加 EN | Decision 0018 + backlog |
| 7 | SOP 落位：Handoff 本地（本文档），暂不进 gitx | Decision 0018 |

---

## 附录 C：开放项 / Backlog

- [ ] **SECURITY.md 联络邮箱**：当前是占位符；Boss 决定后替换
- [ ] **README 双语化**（v2.2.1+）：当前 README.md (zh) → README_CN.md；新写 EN README.md
- [ ] **README "What's New" 表**：加最近 5 版速览（仿 MacAudit）
- [ ] **mock 测试 `tests/test_publish_github.sh`**：断言 release-publish-github.sh 调用形态
- [ ] **gitx-release 抽象**：Handoff + MacAudit 都跑稳后，提通用 70% 到 gitx 技能
- [ ] **publish worktree gitignore**：当前 SOP 没设；首次 setup 时 add `.github-publish-wt/` 到根 .gitignore

---

## 附录 D：SOP 迭代日志

| 版本 | 日期 | 触发 | 改动 |
|------|------|------|------|
| v1 | 2026-05-13 | 首次制定（接入 tkxlab-ai/HandoffX，v2.2.0 准备发版） | 8 Phase 框架；4 场景回滚；附录 A/B/C/D；变量约定；借用 MacAudit 框架但删 Swift 步骤 |
