#!/bin/bash
# test_release_artifact_content.sh — release tarball 不得泄露本地工作状态
# 历史故障：Round 5 codex adversarial review 发现 v1.2.5/v1.2.6 source tarball
# 包含 `HANDOFF.md.bak.tidy-20260430-2322`（gitx-release wrapper 的 rsync exclude
# pattern 用 `'HANDOFF.md.bak'` 字面无星号，匹配不到带后缀的 tidy 备份）。
# 本测试在 release 完成后扫产物 tarball 内容，作为兜底闸门。
source "$(dirname "$0")/common.sh"

LATEST="$ROOT_DIR/Release/latest"
if [ ! -L "$LATEST" ] && [ ! -d "$LATEST" ]; then
    echo "  ➖ Release/latest 不存在，跳过（CI 或 fresh checkout）"
    summary
    exit 0
fi

REL_DIR="$LATEST"
[ -L "$LATEST" ] && REL_DIR="$ROOT_DIR/Release/$(readlink "$LATEST")"

# 只在 Release/latest 与当前 dev VERSION 一致时才校验——release 进行中（VERSION
# 已 bump 但 Release/latest 还指向旧版）跳过，避免 preflight 被旧 artifact 卡住；
# release 完成后 Release/latest 切到新版，下一次跑测试自然校验新 artifact。
DEV_VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
LATEST_VERSION=$(basename "$REL_DIR" | sed 's/^[a-zA-Z_-]*-//')
if [ -n "$DEV_VERSION" ] && [ "$LATEST_VERSION" != "$DEV_VERSION" ]; then
    echo "  ➖ Release/latest=$LATEST_VERSION ≠ dev VERSION=$DEV_VERSION，跳过（release 进行中或滞后）"
    summary
    exit 0
fi

# 必须扫的 tarball：source 与 full 都要查
TARBALLS=()
for f in "$REL_DIR"/*-source.tar.gz "$REL_DIR"/*-full.tar.gz; do
    [ -f "$f" ] && TARBALLS+=("$f")
done

if [ "${#TARBALLS[@]}" -eq 0 ]; then
    echo "  ➖ Release/latest 下无 *.tar.gz，跳过"
    summary
    exit 0
fi

# 禁止出现的路径（基于事实：项目本地工作状态，含开发上下文，绝不能进 release 分发）
# 锚点 (^|/) 是为了只匹配路径末段叫 HANDOFF.md 的，不误匹配 evals/files/sample-HANDOFF.md 这类合法 fixture
FORBIDDEN_PATTERNS=(
    '(^|/)HANDOFF\.md$'
    '(^|/)HANDOFF\.md\.bak'
    '(^|/)HANDOFF\.archive'
    '(^|/)memory/'
    '\.tmp/'
    '\.DS_Store$'
    'Handoff_OldBackup_'
    'Handoff_planning_'
    '(^|/)docs/superpowers/'  # 内部规划文档不进分发；作为防守若被重新拉入项目树
)

for tarball in "${TARBALLS[@]}"; do
    base=$(basename "$tarball")
    contents=$(tar tzf "$tarball" 2>/dev/null)
    if [ -z "$contents" ]; then
        echo "  ❌ $base: tar 列表为空 / 读取失败"
        FAIL=$((FAIL+1))
        continue
    fi

    suite_clean=1
    for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
        # `-- "$pattern"` 防止以 `-` 起始的 pattern 被当 grep flag (Gotcha #1)
        matches=$(echo "$contents" | grep -E -- "$pattern" || true)
        if [ -n "$matches" ]; then
            echo "  ❌ $base: 含禁止路径（pattern: $pattern）"
            echo "$matches" | head -3 | sed 's/^/      /'
            FAIL=$((FAIL+1))
            suite_clean=0
        fi
    done

    if [ "$suite_clean" = "1" ]; then
        echo "  ✅ $base: 无禁止路径"
        PASS=$((PASS+1))
    fi
done

summary
