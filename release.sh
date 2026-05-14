#!/bin/bash
# release.sh — package a versioned release into Release/<version>/
# usage: ./release.sh [--dry-run-audit] <version>     e.g. ./release.sh v0.8
#
# Produces:
#   Release/<version>/handoff-<version>.skill           — 单文件分发
#   Release/<version>/handoff-<version>-source.tar.gz   — 完整源码
#   Release/<version>/README.md                         — 该版本说明
#   Release/latest                                      — 指向最新的 symlink
#   Release/CHANGELOG.md                                — 追加版本条目（需手动填说明）

set -e

DRY_RUN_AUDIT=0
case "${1:-}" in
    --dry-run-audit)
        DRY_RUN_AUDIT=1
        shift
        ;;
esac

VERSION="${1:?Usage: $0 [--dry-run-audit] <version>, e.g. $0 v0.8}"

# Validate version format
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "❌ Invalid version: $VERSION (expected vX.Y or vX.Y.Z)"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$ROOT/Release/$VERSION"

# --- Pipeline 工具链定位：先找本地 scripts/，回落到 Release_pipeline ---
# Handoff 仓不再维护 release-{audit,sanitize}.sh 副本，以 Release_pipeline 为单一真源。
# 仅当本仓 scripts/ 保留旧副本时就近使用；否则自动回落。
PIPELINE_FALLBACK="${PIPELINE_DIR:-$HOME/tkbox/Cloud_Coding/Github-Learning/Release_pipeline}"

locate_tool() {
    local name="$1"
    if [ -x "$ROOT/scripts/$name" ]; then
        echo "$ROOT/scripts/$name"
    elif [ -x "$PIPELINE_FALLBACK/scripts/$name" ]; then
        echo "$PIPELINE_FALLBACK/scripts/$name"
    else
        echo ""
    fi
}

stage_source() {
    local dest="$1"
    mkdir -p "$dest"
    rsync -a \
        --exclude='/.git' \
        --exclude='/Release' \
        --exclude='/handoff.skill' \
        --exclude='/tests/.tmp' \
        --exclude='/.claude' \
        --exclude='/.DS_Store' \
        --exclude='/HANDOFF.md' \
        --exclude='/HANDOFF.archive.md' \
        --exclude='/HANDOFF.md.bak*' \
        --exclude='/HANDOFF.md.pre-v2-backup' \
        --exclude='/GOTCHAS.md' \
        --exclude='/Handoff_Logs' \
        --exclude='/Handoff_Logs.archive' \
        --exclude='/Handoff_Decisions' \
        --exclude='/NEXT_SESSION_NOTES.md' \
        --exclude='/memory/' \
        --exclude='*.pyc' \
        --exclude='__pycache__' \
        --exclude='/skills/handoff-workspace' \
        --exclude='/commands' \
        --exclude='/Handoff_OldBackup_0504' \
        "$ROOT/" "$dest/" 2>/dev/null
}

audit_staged_source() {
    local staged="$1"
    local fail=0

    # v1 + v2 work-log files must not appear in distribution tarballs.
    for path in HANDOFF.md HANDOFF.archive.md memory \
                GOTCHAS.md Handoff_Logs Handoff_Logs.archive Handoff_Decisions \
                HANDOFF.md.pre-v2-backup NEXT_SESSION_NOTES.md; do
        if [ -e "$staged/$path" ]; then
            echo "❌ forbidden release path present: $path" >&2
            fail=1
        fi
    done
    for bak in "$staged"/HANDOFF.md.bak*; do
        [ -e "$bak" ] || continue
        echo "❌ forbidden release path present: $(basename "$bak")" >&2
        fail=1
    done
    [ "$fail" = "0" ] && echo "✅ forbidden paths absent"

    for cmd in handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
        if [ ! -f "$staged/skills/handoff/commands/$cmd" ]; then
            echo "❌ required command shim missing: skills/handoff/commands/$cmd" >&2
            fail=1
        fi
    done
    [ "$fail" = "0" ] && echo "✅ required command shims present"

    return "$fail"
}

sha256_file() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo "sha256-unavailable"
    fi
}

emit_release_manifest() {
    local staged="$1"
    local out="${2:-}"
    local tmp=""

    if [ -n "$out" ]; then
        tmp="$out.tmp"
        exec 3>"$tmp"
    else
        exec 3>&1
    fi

    {
        echo "release manifest preview"
        echo "version: $VERSION"
        echo "generated_at: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "source_root: handoff-$VERSION"
        echo "forbidden_paths:"
        echo "  - HANDOFF.md"
        echo "  - HANDOFF.archive.md"
        echo "  - HANDOFF.md.bak*"
        echo "  - HANDOFF.md.pre-v2-backup"
        echo "  - GOTCHAS.md"
        echo "  - Handoff_Logs/"
        echo "  - Handoff_Logs.archive/"
        echo "  - Handoff_Decisions/"
        echo "  - NEXT_SESSION_NOTES.md"
        echo "  - memory/"
        echo "required_command_shims:"
        echo "  - skills/handoff/commands/handoff-recall.md"
        echo "  - skills/handoff/commands/handoff-tidy.md"
        echo "  - skills/handoff/commands/handoff-memory.md"
        echo "  - skills/handoff/commands/handoff-init.md"
        echo "sha256:"
        (cd "$staged" && find . -type f | LC_ALL=C sort | while IFS= read -r file; do
            file=${file#./}
            printf "  %s  %s\n" "$(sha256_file "$staged/$file")" "$file"
        done)
    } >&3

    if [ -n "$out" ]; then
        exec 3>&-
        mv "$tmp" "$out"
    else
        exec 3>&-
    fi
}

if [ "$DRY_RUN_AUDIT" = "1" ]; then
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    stage_source "$STAGE/handoff-$VERSION"
    audit_staged_source "$STAGE/handoff-$VERSION"
    emit_release_manifest "$STAGE/handoff-$VERSION"
    echo "✅ release dry-run audit passed"
    exit 0
fi

# 前置：跑测试，失败就不发布
echo "🧪 Running regression..."
RELEASE_LOG=$(mktemp)
STAGE=$(mktemp -d)
SKILL_STAGE=""
trap 'rm -rf "$STAGE" "${SKILL_STAGE:-}"; rm -f "$RELEASE_LOG"' EXIT
if ! bash "$ROOT/tests/run_all.sh" > "$RELEASE_LOG" 2>&1; then
    echo "❌ Tests failed — release aborted"
    tail -20 "$RELEASE_LOG"
    exit 1
fi
echo "✅ Tests passed"

mkdir -p "$RELEASE_DIR"

# --- 1. .skill single-file package ---
SKILL_CREATOR="$HOME/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator"
SKILL_OUT="$RELEASE_DIR/handoff-$VERSION.skill"
if [ -d "$SKILL_CREATOR" ]; then
    echo "📦 Building .skill via skill-creator..."
    rm -f "$SKILL_CREATOR/handoff.skill" "$ROOT/handoff.skill"
    (cd "$SKILL_CREATOR" && python -m scripts.package_skill "$ROOT/skills/handoff" > /dev/null)
    mv "$SKILL_CREATOR/handoff.skill" "$SKILL_OUT"
    echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" | cut -f1))"
else
    # Fallback: raw zip of skills/handoff/
    echo "⚠️  skill-creator 不在，改用 zip 直接打包"
    (cd "$ROOT/skills" && zip -rq "$SKILL_OUT" handoff/ \
        -x 'handoff/evals/*')
    echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" | cut -f1))"
fi

# --- 2. Source tarball ---
TAR_OUT="$RELEASE_DIR/handoff-$VERSION-source.tar.gz"
echo "📦 Staging source..."
# Use temp staging dir so transform works on bsdtar + gnu tar
mkdir -p "$STAGE/handoff-$VERSION"
# 拷贝要发的文件，排除开发过程产物和项目私有状态
stage_source "$STAGE/handoff-$VERSION"
audit_staged_source "$STAGE/handoff-$VERSION"
emit_release_manifest "$STAGE/handoff-$VERSION" "$RELEASE_DIR/RELEASE_MANIFEST.txt"

# --- 2.5 Pre-release sanity：扫描个人信息 / 凭证 / 指纹 ---
echo "🔍 Running pre-release sanity scan..."
SANITIZE="$(locate_tool release-sanitize.sh)"
if [ -n "$SANITIZE" ]; then
    echo "   → 使用 $SANITIZE"
    # 扫 staged tarball 内容
    if ! bash "$SANITIZE" "$STAGE/handoff-$VERSION" 2>&1; then
        echo ""
        echo "❌ Release aborted: 发现敏感信息"
        echo "   修复上述文件后再跑 ./release.sh $VERSION"
        echo "   安全门不可绕过：不得发布含敏感信息的交接工具"
        exit 1
    fi
    # 同时扫 .skill 内容（解压到临时目录再扫）
    if [ -f "$SKILL_OUT" ]; then
        SKILL_STAGE=$(mktemp -d)
        unzip -q "$SKILL_OUT" -d "$SKILL_STAGE"
        if ! bash "$SANITIZE" "$SKILL_STAGE" 2>&1; then
            echo ""
            echo "❌ .skill 文件内容有敏感信息"
            rm -rf "$SKILL_STAGE"
            echo "   安全门不可绕过：不得发布含敏感信息的 .skill"
            exit 1
        fi
        rm -rf "$SKILL_STAGE"
    fi
else
    echo "❌ 找不到 release-sanitize.sh（本仓 scripts/ 无 + Release_pipeline 也无）"
    echo "   检查 \$PIPELINE_DIR 或确认 $PIPELINE_FALLBACK 存在"
    echo "   Release aborted — sanity gate 是必需的，不是 optional"
    exit 1
fi

echo "📦 Building source tarball..."
(cd "$STAGE" && tar czf "$TAR_OUT" "handoff-$VERSION")
echo "   → $TAR_OUT ($(du -h "$TAR_OUT" | cut -f1))"

# --- 2.6 Flatten key docs to Release/<version>/ top level ---
# 用户下载后不解压也能看到 README/INSTALL/CHANGELOG/TEST-SCENARIOS/LICENSE/SKILL
echo "📄 Copying top-level docs to release dir..."
for doc in README.md INSTALL.md CHANGELOG.md TEST-SCENARIOS.md LICENSE CONTRIBUTING.md; do
    if [ -f "$ROOT/$doc" ]; then
        cp "$ROOT/$doc" "$RELEASE_DIR/$doc"
    fi
done
# install.sh 同样平摊，并保留可执行位——让 source 用户可以 `cd Release/<ver>/ && ./install.sh`
# 不必先解压 tarball
if [ -f "$ROOT/install.sh" ]; then
    cp "$ROOT/install.sh" "$RELEASE_DIR/install.sh"
    chmod +x "$RELEASE_DIR/install.sh"
fi
# SKILL.md 从 skill bundle 拷出来（方便直接浏览）
SKILL_MD_SRC="$ROOT/skills/handoff/SKILL.md"
[ -f "$SKILL_MD_SRC" ] && cp "$SKILL_MD_SRC" "$RELEASE_DIR/SKILL.md"
echo "   → 已拷到 $RELEASE_DIR/（顶层）"

# --- 3. Per-version RELEASE_NOTES.md（简短版，区别于主 README）---
RELEASE_DATE=$(date +%Y-%m-%d)
cat > "$RELEASE_DIR/RELEASE_NOTES.md" <<EOF
# Handoff $VERSION — Release Notes

Release date: $RELEASE_DATE

## 本目录包含

### 分发包
- \`handoff-$VERSION.skill\` — 单文件 zip 分发（适合快速安装）
- \`handoff-$VERSION-source.tar.gz\` — 完整源码包（含 install.sh + 测试 + 所有文档）

### 平摊文档（用户不解压即可浏览）
- \`README.md\` — 项目主文档（哲学 / 逻辑 / 工作原理 / 概念）
- \`INSTALL.md\` — 完整安装 / 升级 / 卸载 / 维护命令参考
- \`CHANGELOG.md\` — 全版本历史
- \`TEST-SCENARIOS.md\` — 验证场景手册
- \`SKILL.md\` — Skill 入口（参考阅读）
- \`LICENSE\` — MIT 许可
- \`CONTRIBUTING.md\` — 贡献约定（如要二次开发）
- \`install.sh\` — 平摊安装脚本（可直接在本目录运行，无需先解压 tarball）

## 快速安装

### 方式 A（推荐）：直接跑本目录 install.sh
> 在本目录下执行：

\`\`\`bash
./install.sh
\`\`\`

install.sh 会自动探测同目录的 \`handoff-$VERSION.skill\` 或 source tarball 做自举解压；装 skill 到 \`~/.claude/skills/handoff/\`，装 slash 命令到 \`~/.claude/commands/\`。

### 方式 B：只装 skill（最精简，不装 slash 命令 shim）
> 在本目录下执行：

\`\`\`bash
mkdir -p ~/.claude/skills
unzip -o ./handoff-$VERSION.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
\`\`\`

### 方式 C：完整解压 source tarball（含测试 / 开发工具）
\`\`\`bash
tar xzf ./handoff-$VERSION-source.tar.gz
cd handoff-$VERSION
./install.sh
\`\`\`

完整安装 / 升级 / 卸载命令见 \`INSTALL.md\`。

## 验证

在 Claude Code 里输入 \`/handoff\`，应自动触发 skill 提示。
验证场景见 \`TEST-SCENARIOS.md\`。

## 本版本变更

见 \`CHANGELOG.md\` 的 **$VERSION** 条目。
EOF
echo "   → $RELEASE_DIR/RELEASE_NOTES.md"

# --- 4. Latest symlink ---
(cd "$ROOT/Release" && rm -f latest && ln -s "$VERSION" latest)
echo "✅ Release/latest → $VERSION"

# --- 5. Top-level CHANGELOG (accumulate) ---
CHANGELOG="$ROOT/Release/CHANGELOG.md"
if [ ! -f "$CHANGELOG" ]; then
    cat > "$CHANGELOG" <<EOF
# Handoff — Release History

记录各版本的关键变化。最新版本在最上面。

EOF
fi
if ! grep -q "^## $VERSION " "$CHANGELOG"; then
    TMP_CHANGELOG=$(mktemp)
    head -4 "$CHANGELOG" > "$TMP_CHANGELOG"
    cat >> "$TMP_CHANGELOG" <<EOF
## $VERSION — $RELEASE_DATE

<!-- TODO: 在此填写本版本要点，建议包括：新增 / 修复 / 破坏性变更 -->

Artifacts: \`Release/$VERSION/\`

---

EOF
    tail -n +5 "$CHANGELOG" >> "$TMP_CHANGELOG" 2>/dev/null || true
    mv "$TMP_CHANGELOG" "$CHANGELOG"
    echo "✅ CHANGELOG.md 加入 $VERSION 条目（记得填说明）"
else
    echo "➖ CHANGELOG.md 已有 $VERSION 条目，跳过"
fi

# --- Summary + Post-release Deep Audit (TKX policy v2.0 §8) ---
echo ""
echo "📦 Release $VERSION 产物已就绪："
ls -lh "$RELEASE_DIR"
echo ""

AUDIT="$(locate_tool release-audit.sh)"
if [ -n "$AUDIT" ]; then
    echo "🔍 Running post-release deep audit..."
    echo "   → 使用 $AUDIT"
    echo ""
    # audit 脚本内部用相对路径 $ROOT/Release/$VERSION——需要在 Handoff 仓根下执行
    if ! (cd "$ROOT" && bash "$AUDIT" "$VERSION"); then
        echo ""
        echo "❌ Deep audit 未通过。修复后：rm -rf $RELEASE_DIR && ./release.sh $VERSION"
        exit 1
    fi
else
    echo "❌ 找不到 release-audit.sh（本仓 scripts/ 无 + Release_pipeline 也无）"
    echo "   检查 \$PIPELINE_DIR 或确认 $PIPELINE_FALLBACK 存在"
    echo "   Release aborted — deep audit 是必需的，不是 optional"
    exit 1
fi

echo ""
echo "下一步："
echo "  1. 确认 CHANGELOG $VERSION 条目真实完整（非 TODO）"
echo "  2. 若推 GitHub：git tag $VERSION && git push --tags"
echo "  3. 若要分发：把 $RELEASE_DIR/ 下文件发给同事"
