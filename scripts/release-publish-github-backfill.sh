#!/usr/bin/env bash
#
# release-publish-github-backfill.sh — 一次性把 v2.0.0–v2.2.0 全部回填到 GitHub
#
# 用法: bash scripts/release-publish-github-backfill.sh [--dry-run]
#
# 流程:
#   1. 按版本号升序遍历 8 个 release
#   2. 每个版本: wipe publish-wt → 解出 source.tar.gz → commit + tag（不 push）
#      → 8 个版本累成 8 个 commit + 8 个 tag 的链
#   3. 最后一次 push main + 所有 tags
#   4. 循环用 gh release create 把每版本的资产挂上（幂等：已存在则 skip）
#
# 详见 docs/GITHUB_RELEASE_SOP.md
#
set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && { DRY_RUN=1; echo "🟡 DRY RUN mode — 不 push 不创建 release"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="tkxlab-ai/HandoffX"
PUBLISH_WT=".github-publish-wt"
GITHUB_URL="https://github.com/${REPO}.git"

# 版本顺序（升序，最后是 latest）
VERSIONS=(v2.0.0 v2.1.0 v2.1.1 v2.1.2 v2.1.3 v2.1.4 v2.1.5 v2.2.0)
LATEST="${VERSIONS[-1]}"

echo "🚀 backfilling ${#VERSIONS[@]} versions → ${REPO}"
echo "    latest = $LATEST"
echo

# ----- 前置 -----
if [[ "$DRY_RUN" -eq 0 ]]; then
    gh auth status 2>&1 | grep -q "Logged in to github.com" \
        || { echo "❌ run: gh auth login"; exit 1; }
fi

# ----- 初始化 publish worktree -----
if [[ ! -d "$PUBLISH_WT/.git" ]]; then
    echo "── 🆕 init publish worktree"
    mkdir -p "$PUBLISH_WT"
    (cd "$PUBLISH_WT" && git init -b main -q && git remote add origin "$GITHUB_URL")
fi
(
    cd "$PUBLISH_WT"
    git config user.name "Handoff"
    git config user.email "noreply@github.com"
    if git remote -v | grep -qiE "gitea|43146|lax-team"; then
        echo "❌ remote 含 Gitea 字样，stop"
        exit 1
    fi
) || exit 1
echo "── ✅ worktree identity 配置"

# ----- Phase A: 循环建 commit + tag -----
echo
echo "── Phase A. 8 个 release 累成 commit chain"

for VER in "${VERSIONS[@]}"; do
    RELEASE_DIR="Release/handoff-${VER}"
    if [[ ! -d "$RELEASE_DIR" ]]; then
        echo "  ⚠ missing $RELEASE_DIR — skip $VER"
        continue
    fi

    echo "  📦 [${VER}]"

    # 凭证扫描
    bash scripts/scan-credentials.sh "$RELEASE_DIR" >/dev/null \
        || { echo "❌ credential leak in $RELEASE_DIR"; exit 1; }

    # 清空 worktree（保留 .git）
    find "$PUBLISH_WT" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

    # 解出本版源码
    tar xzf "${RELEASE_DIR}/handoff-${VER}-source.tar.gz" \
        -C "$PUBLISH_WT" --strip-components=1

    # 加 GitHub 公开仓元文件
    for f in SECURITY.md CODE_OF_CONDUCT.md; do
        [[ -f "$f" ]] && cp "$f" "$PUBLISH_WT/" || true
    done
    [[ -d .github ]] && cp -r .github "$PUBLISH_WT/" || true

    # 防御性 worktree 扫描
    bash scripts/scan-credentials.sh "$PUBLISH_WT" >/dev/null \
        || { echo "❌ worktree credential leak after extract"; exit 1; }

    # 🔴 脱敏 — Decision 0018 第 1 条硬约束
    bash scripts/release-sanitize-public.sh "$PUBLISH_WT" >/dev/null \
        || { echo "❌ sanitize failed for $VER"; exit 1; }

    # commit + tag
    (
        cd "$PUBLISH_WT"
        git add -A

        # inline staged-diff scan，排除 tests/（fixture）+ scripts/release-*（含 sanitize 自身 regex）
        LEAK=$(git diff --staged -- . ':!tests/' ':!scripts/release-*' | grep -cE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82,}|password[[:space:]]*=|api[_-]?key[[:space:]]*=|/Users/niu/' 2>/dev/null || true)
        [[ "$LEAK" -eq 0 ]] || { echo "❌ staged credential leak in $VER ($LEAK hits)"; exit 1; }

        git commit -q -m "release: handoff ${VER}

Snapshot of source tree at tag ${VER}.
This commit is a clean release snapshot — no WIP history."

        git tag -d "$VER" 2>/dev/null || true
        git tag -a "$VER" -m "Handoff ${VER}"

        AUTHOR=$(git log -1 --format="%an <%ae>" HEAD)
        [[ "$AUTHOR" == "Handoff <noreply@github.com>" ]] \
            || { echo "❌ author=$AUTHOR"; exit 1; }
    ) || exit 1

    echo "    ✅ commit + tag $VER"
done

# ----- Phase B: 一次推 main + 所有 tag -----
echo
echo "── Phase B. Push 全部"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "  🟡 DRY RUN — skip push"
else
    # publish-wt 是 per-release wipe-rewrite，main 单 commit chain 由本脚本独占维护——
    # --force 是设计意图（--force-with-lease 在 fresh worktree 上会因无 fetched info
    # 报 "stale info"，无意义）。token 临时嵌入 remote URL 让 git push 能认证
    # （gh CLI 的 token 只 gh 命令认，git push 不认）。
    [[ -n "${GH_TOKEN:-}" ]] || { echo "❌ GH_TOKEN unset — cannot push"; exit 1; }
    (
        cd "$PUBLISH_WT"
        ORIG_URL=$(git remote get-url origin)
        TOKEN_URL="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
        git remote set-url origin "$TOKEN_URL"
        # 用 trap 保证异常退出也还原 URL（防 token 落盘到 .git/config）
        trap 'git remote set-url origin "$ORIG_URL" 2>/dev/null || true' EXIT

        git push origin main --force 2>&1 | tail -3
        # tag 用 --force 因为 SHA 在每次重跑会变（per-release wipe-rewrite 设计意图）
        for VER in "${VERSIONS[@]}"; do
            git push origin "$VER" --force 2>&1 | tail -1
        done

        git remote set-url origin "$ORIG_URL"
        trap - EXIT
    )
    echo "  ✅ main + ${#VERSIONS[@]} tags pushed"
fi

# ----- Phase C: 创建每版本的 GitHub Release -----
echo
echo "── Phase C. 创建 ${#VERSIONS[@]} 个 GitHub Release"

for VER in "${VERSIONS[@]}"; do
    RELEASE_DIR="Release/handoff-${VER}"
    [[ -d "$RELEASE_DIR" ]] || continue

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  🟡 [${VER}] DRY RUN — would create release"
        continue
    fi

    # 幂等
    if gh release view "$VER" --repo "$REPO" >/dev/null 2>&1; then
        echo "  ⏭  [${VER}] release exists — skip"
        continue
    fi

    # 资产 — Decision 0018 E1: 不上传 source/full tarball（未脱敏 dev narrative）
    ASSETS=()
    for f in "handoff-${VER}.skill" "checksums.txt" "sbom.cyclonedx.json"; do
        [[ -f "$RELEASE_DIR/$f" ]] && ASSETS+=("$RELEASE_DIR/$f")
    done

    NOTES_ARG=(--generate-notes)
    [[ -f "$RELEASE_DIR/RELEASE_NOTES.md" ]] && NOTES_ARG=(--notes-file "$RELEASE_DIR/RELEASE_NOTES.md")

    LATEST_FLAG=(--latest=false)
    [[ "$VER" == "$LATEST" ]] && LATEST_FLAG=(--latest)

    echo "  📤 [${VER}] creating release with ${#ASSETS[@]} assets..."
    gh release create "$VER" --repo "$REPO" \
        --title "Handoff ${VER}" \
        --target main \
        "${LATEST_FLAG[@]}" \
        "${NOTES_ARG[@]}" \
        "${ASSETS[@]}" >/dev/null

    echo "    ✅ → https://github.com/${REPO}/releases/tag/${VER}"
done

echo
echo "🎉 backfill done"
[[ "$DRY_RUN" -eq 0 ]] && gh release list --repo "$REPO" | head -10 || true
