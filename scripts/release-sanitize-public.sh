#!/usr/bin/env bash
#
# release-sanitize-public.sh — 把 publish worktree 脱敏为可公开内容
#
# 用法: bash scripts/release-sanitize-public.sh <publish-worktree-dir>
#
# 做两件事:
#   1. 删除完全不该公开的 dev-only 文件（Mac Project Transfer / NEXT_SESSION_NOTES / pre-v2-backup）
#   2. 对剩余 .md 文件做 sed 替换（Gitea 域名 / 端口 / org / SSH key / 本地用户路径 / 主机名）
#
# 最后做 verification grep — 如还有任何敏感 pattern 命中 → exit 1
#
# 由 release-publish-github.sh / release-publish-github-backfill.sh 在 Phase 4 之后、Phase 5 之前调用。
#
set -euo pipefail

DIR="${1:?usage: $0 <publish-worktree-dir>}"
[[ -d "$DIR" ]] || { echo "❌ $DIR 不是目录"; exit 2; }

# 在 cd 之前算 main repo 绝对路径（用于 Step 1b 覆盖 stale 文件）
MAIN_REPO="$(cd "$(dirname "$0")/.." && pwd)"

cd "$DIR"

echo "🧼 sanitize-for-public: $DIR"
echo "    main repo (覆盖源): $MAIN_REPO"

# ----- Step 1: 删除 dev-only 整文件 -----
DEV_ONLY=(
    "Mac Project Transfer.md"      # 整文件 = Gitea remote + SSH key + 真实路径迁机指南
    "NEXT_SESSION_NOTES.md"        # 内部 session 切换笔记
    "HANDOFF.md.pre-v2-backup"     # v1 内部叙述 1470 行
)
for f in "${DEV_ONLY[@]}"; do
    if [[ -e "$f" ]]; then
        rm -f -- "$f"
        echo "  🗑  removed: $f"
    fi
done

# 整目录删除（用 -rf）— 含 fake-but-realistic-looking secrets 的测试 fixture
# 这些 fixture 是 test_scan_credentials 的测试输入（fake Slack/AWS/GitHub/Anthropic
# tokens 用来验证扫描器能识别真 secret 格式）。GitHub Push Protection 不区分
# fixture vs 真 secret，会拦下整次 push。公开 mirror 不需要这些测试样本——
# private 仓 + dev 测试时仍可用。
DEV_ONLY_DIRS=(
    "tests/fixtures"
    # Decision 0018 #5: 公开 mirror 不启用 GitHub Actions——source tarball 自带 ci.yml
    # 推到 GitHub 会自动跑 + 失败（fixtures 已删 / 测试 paths 改 / shellcheck 流程
    # 在干净仓库环境下行为不同）。整个 workflows/ 目录删；issue/PR template 在
    # release-publish-github.sh Phase 4 单独 cp .github 时已保留
    ".github/workflows"
)
for d in "${DEV_ONLY_DIRS[@]}"; do
    if [[ -d "$d" ]]; then
        rm -rf -- "$d"
        echo "  🗑  removed dir: $d"
    fi
done

# ----- Step 1b: 已知 stale 文件用 main repo 当前版本覆盖 -----
# 适用：tarball 内置了历史版本，新版 main 已修；publish 要用新版避免 sed 破坏。
# 例：tests/test_encode_cc_path.sh 历史用 /Users/jarvis/ fixture；main 改成
# /Users/example/。若让 sed 处理 .sh，断言一致性会被破坏；改用整文件 cp。
OVERWRITE_FROM_MAIN=(
    'tests/test_encode_cc_path.sh'
)
for relpath in "${OVERWRITE_FROM_MAIN[@]}"; do
    src="$MAIN_REPO/$relpath"
    if [[ -f "$src" && -f "$relpath" ]]; then
        cp "$src" "$relpath"
        echo "  🔁 overwrote with main: $relpath"
    fi
done

# ----- Step 2: sed 替换敏感字符串 -----
# 用 sed -i.bak（macOS BSD + Linux GNU 通用），再删 .bak
# 范围：所有 .md 文件（递归）
# 注意：sed 表达式里有正则字符需转义；用 | 作分隔符避免 / 冲突

REPLACEMENTS=(
    # Gitea 主机域名 → 占位符
    's|git\.lax\.cdn\.tokenx\.com|<private-git-host>|g'
    # 自定义 SSH 端口 → 占位符
    # 注意：BSD sed 不支持 \b 词边界；用裸替换。43146 五位数 + 我们语境唯一，无误伤
    's|43146|<private-port>|g'
    # Gitea 仓库 owner → 占位符
    's|lax-team/Handoff|<private-org>/Handoff|g'
    's|lax-team|<private-org>|g'
    # SSH key 文件名 → 占位符
    's|id_gitea_lax|<private-ssh-key>|g'
    # Gitea 字样（在我们语境里都指那台私有 host） → 通用化
    's|Gitea|private Git host|g'
    # 本地开发用户路径
    's|/Users/jarvis/|<dev-home>/|g'
    's|/Users/niu/|<dev-home>/|g'
    # 历史主机名（MacAudit 实战教训里出现过 JARVIS-MBP.local 类）
    's|JARVIS-MBP\.local|<dev-host>|g'
    's|JARVIS-MBP|<dev-host>|g'
)

REDACTED_COUNT=0
while IFS= read -r -d '' f; do
    CHANGED=0
    for expr in "${REPLACEMENTS[@]}"; do
        # 仅在文件里有命中时才动；避免每次都写盘
        # 用 grep -E 测试（兼容 BSD/GNU sed regex 子集）
        # 简化：直接尝试 sed in-place，写盘是幂等的
        sed -i.bak -E "$expr" "$f"
    done
    # 检测是否真改了（diff bak）
    if ! cmp -s "$f" "$f.bak"; then
        CHANGED=1
        REDACTED_COUNT=$((REDACTED_COUNT + 1))
    fi
    rm -f "$f.bak"
    [[ "$CHANGED" -eq 1 ]] && echo "  ✏  redacted: $f"
done < <(find . -type f -name '*.md' -print0)

echo "  → $REDACTED_COUNT 个文件被改"

# ----- Step 3: Verification grep — 不允许任何剩余命中 -----
echo
echo "🔍 post-sanitize verification..."

PATTERNS=(
    'git\.lax\.cdn\.tokenx\.com'
    '43146'
    'lax-team'
    'id_gitea_lax'
    'JARVIS-MBP'
    '/Users/jarvis/'
    '/Users/niu/'
)

LEAK_TOTAL=0
# 临时关 pipefail — grep 无匹配会退 1，正常情况；只要 wc 出数字就行
set +o pipefail
for p in "${PATTERNS[@]}" '\bGitea\b'; do
    HITS=$(grep -rnE "$p" --include='*.md' . 2>/dev/null | wc -l | tr -d ' ')
    HITS=${HITS:-0}
    if [[ "$HITS" -gt 0 ]]; then
        echo "  ❌ pattern still found ($HITS hits): $p"
        grep -rnE "$p" --include='*.md' . 2>/dev/null | head -3 || true
        LEAK_TOTAL=$((LEAK_TOTAL + HITS))
    fi
done
set -o pipefail

if [[ "$LEAK_TOTAL" -gt 0 ]]; then
    echo
    echo "❌ sanitize failed — $LEAK_TOTAL pattern hits remain"
    exit 1
fi

echo "  ✅ 0 leaks remain"
echo
echo "✅ sanitize-for-public done"
