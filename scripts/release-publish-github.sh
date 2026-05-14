#!/usr/bin/env bash
#
# release-publish-github.sh — Handoff Plugin GitHub publish (single version)
#
# 用法:
#   bash scripts/release-publish-github.sh v2.2.0           # 正常发布（draft → 转正）
#   bash scripts/release-publish-github.sh v2.2.0 --clobber # 已存在则覆盖
#   bash scripts/release-publish-github.sh v2.2.0 --draft   # 只创建 draft，不转正
#   bash scripts/release-publish-github.sh v2.2.0 --no-prerelease-check
#
# 详见 docs/GITHUB_RELEASE_SOP.md
#
set -euo pipefail

# ---------- 参数 ----------
VER="${1:-}"
shift || true
[[ -z "$VER" ]] && { echo "usage: $0 vX.Y.Z [--clobber] [--draft]"; exit 2; }
[[ "$VER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "❌ VER must match v<N>.<N>.<N>, got: $VER"; exit 2; }

CLOBBER=0
DRAFT_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --clobber) CLOBBER=1 ;;
        --draft)   DRAFT_ONLY=1 ;;
        *) echo "❌ unknown flag: $arg"; exit 2 ;;
    esac
done

# ---------- 常量 ----------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="tkxlab-ai/HandoffX"
RELEASE_DIR="Release/handoff-${VER}"
PUBLISH_WT=".github-publish-wt"
GITHUB_URL="https://github.com/${REPO}.git"

echo "🚀 publishing Handoff ${VER} → ${REPO}"
echo "    release dir : $RELEASE_DIR"
echo "    publish wt  : $PUBLISH_WT"
echo "    clobber=$CLOBBER / draft_only=$DRAFT_ONLY"
echo

# =====================================================================
# Phase 1. 前置检查
# =====================================================================
echo "── Phase 1. 前置检查"

[[ -d "$RELEASE_DIR" ]] || { echo "❌ missing $RELEASE_DIR — run /gitx-release $VER first"; exit 1; }
[[ -f "$RELEASE_DIR/handoff-${VER}.skill" ]] || { echo "❌ missing .skill in $RELEASE_DIR"; exit 1; }
echo "  ✅ gitx 产物 OK"

git tag --list | grep -qx "$VER" || { echo "❌ tag $VER not found locally"; exit 1; }
echo "  ✅ tag $VER 存在"

bash scripts/scan-credentials.sh "$RELEASE_DIR" >/dev/null \
    || { echo "❌ credential scan failed on $RELEASE_DIR"; exit 1; }
echo "  ✅ 凭证扫描通过"

gh auth status 2>&1 | grep -q "Logged in to github.com" \
    || { echo "❌ not logged in to github.com — run: gh auth login"; exit 1; }
echo "  ✅ gh 已登录"

# =====================================================================
# Phase 2. 创建/复用 publish worktree
# =====================================================================
echo "── Phase 2. publish worktree 就绪"

if [[ ! -d "$PUBLISH_WT/.git" ]]; then
    echo "  🆕 首次 setup..."
    mkdir -p "$PUBLISH_WT"
    (cd "$PUBLISH_WT" && git init -b main -q && git remote add origin "$GITHUB_URL")
else
    echo "  ♻ 复用现有 worktree"
fi

(
    cd "$PUBLISH_WT"
    git config user.name "Handoff"
    git config user.email "noreply@github.com"

    # 防 Gitea 字样（已正确：if cmd; then exit）
    if git remote -v | grep -qiE "gitea|43146|lax-team"; then
        echo "❌ remote 含 Gitea 字样，stop"
        exit 1
    fi
)
echo "  ✅ identity=Handoff <noreply@github.com> / remote 干净"

# =====================================================================
# Phase 3. 清空 worktree
# =====================================================================
echo "── Phase 3. 清空 worktree"
find "$PUBLISH_WT" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
echo "  ✅ 只剩 .git"

# =====================================================================
# Phase 4. 解出源码 + 加 public-only 元文件
# =====================================================================
echo "── Phase 4. 解出源码"
tar xzf "${RELEASE_DIR}/handoff-${VER}-source.tar.gz" \
    -C "$PUBLISH_WT" \
    --strip-components=1

# 加 GitHub 公开仓特有元文件（私仓不需要）
for f in SECURITY.md CODE_OF_CONDUCT.md; do
    [[ -f "$f" ]] && cp "$f" "$PUBLISH_WT/" || true
done
[[ -d .github ]] && cp -r .github "$PUBLISH_WT/" || true
echo "  ✅ 源码 + 公开仓元文件解出"

# 防御性凭证扫描（worktree 组合后）
bash scripts/scan-credentials.sh "$PUBLISH_WT" >/dev/null \
    || { echo "❌ worktree credential scan failed"; exit 1; }
echo "  ✅ worktree 凭证扫描通过"

# 🔴 脱敏（Gitea host/port/org/SSH key/dev path） — Decision 0018 第 1 条硬约束
bash scripts/release-sanitize-public.sh "$PUBLISH_WT" \
    || { echo "❌ sanitize failed"; exit 1; }
echo "  ✅ 脱敏完成 (Gitea / dev path 全清)"

# =====================================================================
# Phase 5. Commit + Tag
# =====================================================================
echo "── Phase 5. Commit + Tag"
(
    cd "$PUBLISH_WT"
    git add -A

    # staged diff 凭证最终扫描（排除 tests/，含 scanner fixture false-positive 源）
    LEAK=$(git diff --staged -- . ':!tests/' | grep -cE 'ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82,}|password[[:space:]]*=|api[_-]?key[[:space:]]*=|/Users/niu/' 2>/dev/null || true)
    if [[ "$LEAK" -gt 0 ]]; then
        echo "❌ staged diff 有 $LEAK 处凭证嫌疑，stop"
        exit 1
    fi

    git commit -q -m "release: handoff ${VER}

Snapshot of source tree at tag ${VER}.
This commit is a clean release snapshot — no WIP history."

    # 删旧 tag 重打（如已存在）
    git tag -d "$VER" 2>/dev/null || true
    git tag -a "$VER" -m "Handoff ${VER}"

    AUTHOR=$(git log -1 --format="%an <%ae>" HEAD)
    if [[ "$AUTHOR" != "Handoff <noreply@github.com>" ]]; then
        echo "❌ author=$AUTHOR — 修 git config 后重跑"
        exit 1
    fi
)
echo "  ✅ author OK / tag $VER 已打"

# =====================================================================
# Phase 6. Push 到 GitHub
# =====================================================================
echo "── Phase 6. Push"
(
    cd "$PUBLISH_WT"
    git push origin main --force-with-lease 2>&1 | tail -3
    git push origin "$VER" 2>&1 | tail -3
)
echo "  ✅ main + tag pushed"

# =====================================================================
# Phase 7. GitHub Release
# =====================================================================
echo "── Phase 7. GitHub Release"

# 幂等检查
if gh release view "$VER" --repo "$REPO" >/dev/null 2>&1; then
    if [[ "$CLOBBER" -eq 1 ]]; then
        echo "  ♻ deleting existing release $VER..."
        gh release delete "$VER" --repo "$REPO" --yes
    else
        echo "❌ release $VER 已存在 — 用 --clobber 重发"
        exit 1
    fi
fi

# 收集资产 — Decision 0018 E1: 不上传 source/full tarball（含未脱敏 dev narrative，
# 公开不合规）。用户拿源码靠 git clone（main 已脱敏过）。仅传 .skill + checksums + SBOM
ASSETS=()
for f in "handoff-${VER}.skill" "checksums.txt" "sbom.cyclonedx.json"; do
    [[ -f "$RELEASE_DIR/$f" ]] && ASSETS+=("$RELEASE_DIR/$f")
done

NOTES_ARG=(--generate-notes)
[[ -f "$RELEASE_DIR/RELEASE_NOTES.md" ]] && NOTES_ARG=(--notes-file "$RELEASE_DIR/RELEASE_NOTES.md")

DRAFT_FLAG=(--draft)
gh release create "$VER" --repo "$REPO" \
    --title "Handoff ${VER}" \
    --target main \
    "${DRAFT_FLAG[@]}" \
    "${NOTES_ARG[@]}" \
    "${ASSETS[@]}"

echo "  ✅ draft release created with ${#ASSETS[@]} assets"

if [[ "$DRAFT_ONLY" -eq 1 ]]; then
    echo
    echo "🟡 draft created — preview & manually flip to non-draft:"
    echo "   gh release view $VER --repo $REPO --web"
    echo "   gh release edit $VER --repo $REPO --draft=false --latest"
    exit 0
fi

# 自动转正（默认）
echo "  🔍 preview URL:"
gh release view "$VER" --repo "$REPO" --json url -q .url

# Boss 可在此 prompt 是否转正；为不让脚本卡死，默认 5s 后自动转正（可被 ctrl-c 拦）
echo "  ⏳ 5s 后自动转正 (Ctrl-C 取消保持 draft)..."
sleep 5

gh release edit "$VER" --repo "$REPO" --draft=false --latest
echo "  ✅ released → latest=$VER"

# =====================================================================
# Phase 8. 收尾提示（不自动 commit）
# =====================================================================
echo
echo "── Phase 8. 收尾提示"
echo "  📝 手动 / 通过 /handoff 完成:"
echo "     - HANDOFF.md Current State 加 GitHub release 链接"
echo "     - 新增 Dev Log 0046+: 接入 GitHub publish SOP"
echo "     - docs/GITHUB_RELEASE_SOP.md 附录 A 追加本版行"
echo
echo "🎉 done — https://github.com/${REPO}/releases/tag/${VER}"
