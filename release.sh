#!/bin/bash
# release.sh — package a versioned release into Release/<prefix>-<version>/
# usage: ./release.sh [--dry-run-audit] <vX.Y.Z>        e.g. ./release.sh v3.0.0
#        ./release.sh --sandbox <vX.Y.Z> <outdir>        contract-test producer only
# <prefix> comes from scripts/release-layout.sh (old prefix below v3.0.0, handoffx from it).
#
# Produces:
#   Release/<prefix>-<version>/<prefix>-<version>.skill           — 单文件分发
#   Release/<prefix>-<version>/<prefix>-<version>-source.tar.gz   — 完整源码
#   Release/<prefix>-<version>/RELEASE_NOTES.md                   — 该版本说明
#   Release/latest                                                — 指向最新的 symlink
#   Release/CHANGELOG.md                                          — 追加版本条目（需手动填说明）
# --sandbox writes only <outdir>/<prefix>-<version>/ (.skill, source tarball,
# RELEASE_NOTES.md, sbom.cyclonedx.json, checksums.txt): no tests, sanitize,
# audit, Release/, latest or CHANGELOG — the real producer is external gitx-release.

set -e

DRY_RUN_AUDIT=0
SANDBOX=0
case "${1:-}" in
    --dry-run-audit)
        DRY_RUN_AUDIT=1
        shift
        ;;
    --sandbox)
        SANDBOX=1
        shift
        ;;
esac

# explicit check, not ${1:?}: that exits 127 and the contract wants exit 1
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 [--dry-run-audit] <vX.Y.Z> | $0 --sandbox <vX.Y.Z> <outdir>"
    exit 1
fi

# Validate version format — the layout lib only understands vX.Y.Z
if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "❌ Invalid version: $VERSION (expected vX.Y.Z)"
    exit 1
fi

SANDBOX_OUT="${2:-}"
if [ "$SANDBOX" = "1" ] && [ -z "$SANDBOX_OUT" ]; then
    echo "Usage: $0 --sandbox <vX.Y.Z> <outdir>"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$ROOT/scripts/release-layout.sh"
# release_prefix returns 2 on a bad RENAME_FROM; under set -e that must be a message, not a silent abort
PREFIX=$(release_prefix "$VERSION") || { echo "❌ cannot derive release prefix for $VERSION (check RENAME_FROM)"; exit 1; }
RELEASE_DIR="$ROOT/$(release_dir_for "$VERSION")"
RELEASE_DATE=$(date +%Y-%m-%d)

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
        --exclude='/handoffx.skill' \
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
        --exclude='/skills/handoffx-workspace' \
        --exclude='/commands' \
        --exclude='/Handoff_OldBackup_0504' \
        --exclude='/.github-publish-wt' \
        --exclude='/.superpowers' \
        --exclude='/.cursor' \
        --exclude='/.sanitize-ignore' \
        --exclude='/.omc' \
        "$ROOT/" "$dest/"
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

    for cmd in handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md; do
        if [ ! -f "$staged/skills/handoffx/command-shims/$cmd" ]; then
            echo "❌ required command shim missing: skills/handoffx/command-shims/$cmd" >&2
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
        echo "source_root: ${PREFIX}-$VERSION"
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
        echo "  - skills/handoffx/command-shims/handoffx-recall.md"
        echo "  - skills/handoffx/command-shims/handoffx-tidy.md"
        echo "  - skills/handoffx/command-shims/handoffx-memory.md"
        echo "  - skills/handoffx/command-shims/handoffx-init.md"
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

# write_release_notes <dir> — shared by the real release and --sandbox, so the
# asset names users are told to unzip/untar always match what was built.
write_release_notes() {
    local dir="$1" skill src
    skill=$(release_asset "$VERSION" skill)
    src=$(release_asset "$VERSION" source)
    cat > "$dir/RELEASE_NOTES.md" <<EOF
# HandoffX $VERSION — Release Notes

Release date: $RELEASE_DATE

## 本目录包含

### 分发包
- \`${skill}\` — 单文件 zip 分发（适合快速安装）
- \`${src}\` — 完整源码包（含 install.sh + 测试 + 所有文档）

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

install.sh 会自动探测同目录的 \`${skill}\` 或 source tarball 做自举解压；装 skill 到 \`~/.claude/skills/handoffx/\`，装 slash 命令到 \`~/.claude/commands/\`。

### 方式 B：只装 skill（最精简，不装 slash 命令 shim）
> 在本目录下执行：

\`\`\`bash
mkdir -p ~/.claude/skills
unzip -o ./${skill} -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoffx/scripts/*.sh
\`\`\`

### 方式 C：完整解压 source tarball（含测试 / 开发工具）
\`\`\`bash
tar xzf ./${src}
cd ${PREFIX}-$VERSION
./install.sh
\`\`\`

完整安装 / 升级 / 卸载命令见 \`INSTALL.md\`。

## 验证

在 Claude Code 里输入 \`/handoffx\`，应自动触发 skill 提示。
验证场景见 \`TEST-SCENARIOS.md\`。

## 本版本变更

见 \`CHANGELOG.md\` 的 **$VERSION** 条目。
EOF
}

if [ "$DRY_RUN_AUDIT" = "1" ]; then
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT
    stage_source "$STAGE/${PREFIX}-$VERSION"
    audit_staged_source "$STAGE/${PREFIX}-$VERSION"
    emit_release_manifest "$STAGE/${PREFIX}-$VERSION"
    echo "✅ release dry-run audit passed"
    exit 0
fi

# --sandbox: same-shape artifacts for the layout contract test. The .skill is the
# plain zip (no skill-creator) so it needs nothing beyond zip/tar/sha tools.
if [ "$SANDBOX" = "1" ]; then
    # a scratch producer must never write into the repo (least of all Release/, the
    # real artifacts): resolve the deepest existing ancestor physically, refuse inside $ROOT
    sb_abs="$SANDBOX_OUT"
    case "$sb_abs" in /*) ;; *) sb_abs="$PWD/$sb_abs" ;; esac
    sb_tail=""
    while [ ! -d "$sb_abs" ]; do
        case "$(basename "$sb_abs")" in
            .|..) echo "❌ sandbox outdir must be outside the repository (no ./.. in its missing part): $SANDBOX_OUT"; exit 1 ;;
        esac
        sb_tail="/$(basename "$sb_abs")$sb_tail"
        sb_abs="$(dirname "$sb_abs")"
    done
    sb_abs="$(cd "$sb_abs" && pwd -P)$sb_tail"
    case "$sb_abs/" in
        "$(cd "$ROOT" && pwd -P)"/*)
            echo "❌ sandbox outdir must be outside the repository: $SANDBOX_OUT"
            exit 1 ;;
    esac
    SB_DIR="$SANDBOX_OUT/${PREFIX}-$VERSION"
    if [ -e "$SB_DIR" ]; then
        echo "❌ sandbox target already exists: $SB_DIR"
        exit 1
    fi
    mkdir -p "$SANDBOX_OUT"
    mkdir "$SB_DIR"
    SB_DIR="$(cd "$SB_DIR" && pwd)"
    STAGE=$(mktemp -d)
    SB_DONE=0
    # a half-built dir would make every rerun hit "already exists"; we created it, so drop it
    trap 'rm -rf "$STAGE"; [ "$SB_DONE" = "1" ] || rm -rf "$SB_DIR"' EXIT

    SKILL_NAME=$(release_asset "$VERSION" skill)
    SRC_NAME=$(release_asset "$VERSION" source)
    # zip root = prefix, as in the published .skill of each era (old-era fixtures
    # would otherwise carry the new root and prove nothing about the old layout)
    mkdir "$STAGE/skill"
    cp -R "$ROOT/skills/handoffx" "$STAGE/skill/$PREFIX"
    (cd "$STAGE/skill" && zip -rq "$SB_DIR/$SKILL_NAME" "$PREFIX/" \
        -x "$PREFIX/evals/*")

    stage_source "$STAGE/${PREFIX}-$VERSION"
    audit_staged_source "$STAGE/${PREFIX}-$VERSION"
    (cd "$STAGE" && tar czf "$SB_DIR/$SRC_NAME" "${PREFIX}-$VERSION")

    write_release_notes "$SB_DIR"
    "$ROOT/scripts/emit-sbom.sh" "$SB_DIR" "$PREFIX" "$VERSION" handoffx

    # if/else, never `a && b || c` — same dispatch as verify_release_integrity
    (cd "$SB_DIR" && for f in "$SKILL_NAME" "$SRC_NAME" sbom.cyclonedx.json; do
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$f"
        else
            shasum -a 256 "$f"
        fi
    done) > "$SB_DIR/checksums.txt"

    SB_DONE=1
    echo "✅ sandbox layout → $SB_DIR"
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
SKILL_OUT="$RELEASE_DIR/$(release_asset "$VERSION" skill)"
if [ -d "$SKILL_CREATOR" ]; then
    echo "📦 Building .skill via skill-creator..."
    rm -f "$SKILL_CREATOR/handoffx.skill" "$ROOT/handoffx.skill"
    (cd "$SKILL_CREATOR" && python -m scripts.package_skill "$ROOT/skills/handoffx" > /dev/null)
    mv "$SKILL_CREATOR/handoffx.skill" "$SKILL_OUT"
    echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" | cut -f1))"
else
    # Fallback: raw zip of skills/handoffx/
    echo "⚠️  skill-creator 不在，改用 zip 直接打包"
    (cd "$ROOT/skills" && zip -rq "$SKILL_OUT" handoffx/ \
        -x 'handoffx/evals/*')
    echo "   → $SKILL_OUT ($(du -h "$SKILL_OUT" | cut -f1))"
fi

# --- 2. Source tarball ---
TAR_OUT="$RELEASE_DIR/$(release_asset "$VERSION" source)"
echo "📦 Staging source..."
# Use temp staging dir so transform works on bsdtar + gnu tar
mkdir -p "$STAGE/${PREFIX}-$VERSION"
# 拷贝要发的文件，排除开发过程产物和项目私有状态
stage_source "$STAGE/${PREFIX}-$VERSION"
audit_staged_source "$STAGE/${PREFIX}-$VERSION"
emit_release_manifest "$STAGE/${PREFIX}-$VERSION" "$RELEASE_DIR/RELEASE_MANIFEST.txt"

# --- 2.5 Pre-release sanity：扫描个人信息 / 凭证 / 指纹 ---
echo "🔍 Running pre-release sanity scan..."
SANITIZE="$(locate_tool release-sanitize.sh)"
if [ -n "$SANITIZE" ]; then
    echo "   → 使用 $SANITIZE"
    # 扫 staged tarball 内容
    if ! bash "$SANITIZE" "$STAGE/${PREFIX}-$VERSION" 2>&1; then
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
(cd "$STAGE" && tar czf "$TAR_OUT" "${PREFIX}-$VERSION")
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
SKILL_MD_SRC="$ROOT/skills/handoffx/SKILL.md"
[ -f "$SKILL_MD_SRC" ] && cp "$SKILL_MD_SRC" "$RELEASE_DIR/SKILL.md"
echo "   → 已拷到 $RELEASE_DIR/（顶层）"

# --- 3. Per-version RELEASE_NOTES.md（简短版，区别于主 README）---
write_release_notes "$RELEASE_DIR"
echo "   → $RELEASE_DIR/RELEASE_NOTES.md"

# --- 4. Latest symlink ---
# target is the canonical dir name (<prefix>-<ver>), not the bare version
(cd "$ROOT/Release" && ln -sfn "$(basename "$RELEASE_DIR")" latest)
echo "✅ Release/latest → $(basename "$RELEASE_DIR")"

# --- 5. Top-level CHANGELOG (accumulate) ---
CHANGELOG="$ROOT/Release/CHANGELOG.md"
if [ ! -f "$CHANGELOG" ]; then
    cat > "$CHANGELOG" <<EOF
# HandoffX — Release History

记录各版本的关键变化。最新版本在最上面。

EOF
fi
if ! grep -q "^## $VERSION " "$CHANGELOG"; then
    TMP_CHANGELOG=$(mktemp)
    head -4 "$CHANGELOG" > "$TMP_CHANGELOG"
    cat >> "$TMP_CHANGELOG" <<EOF
## $VERSION — $RELEASE_DATE

<!-- TODO: 在此填写本版本要点，建议包括：新增 / 修复 / 破坏性变更 -->

Artifacts: \`$(release_dir_for "$VERSION")/\`

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
    # audit 脚本按仓根相对路径找产物（布局 Release/<prefix>-<version>，见 release_dir_for）——需要在仓根下执行
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
