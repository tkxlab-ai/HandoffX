#!/bin/bash
# test_release_artifact_content.sh — release tarball 不得泄露本地工作状态
# 历史故障：Round 5 codex adversarial review 发现 v1.2.5/v1.2.6 source tarball
# 包含主文件的 tidy 备份 `<main>.md.bak.tidy-20260430-2322`（<main> = 当时的 v4 前主文件名）（gitx-release wrapper 的 rsync exclude
# pattern 用 `<main>.md.bak` 字面无星号，匹配不到带后缀的 tidy 备份）。
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

# latest 指向的不是现存目录，不是任何合法状态（release.sh 只在产物目录存在后才翻转
# latest，且只写相对路径）；若放到下面的"版本不一致→跳过"，会被当成 release 进行中
# 静默放行（Gotcha #24）。
if [ ! -d "$REL_DIR" ]; then
    echo "  ❌ Release/latest 指向的不是现存目录：$(readlink "$LATEST")（悬空 / 绝对路径 / 普通文件——上次被中断的测试运行或手工误操作留下）"
    FAIL=$((FAIL+1))
    summary
    exit 1
fi

# 只在 Release/latest 与当前 dev VERSION 一致时才校验——release 进行中（VERSION
# 已 bump 但 Release/latest 还指向旧版）跳过，避免 preflight 被旧 artifact 卡住；
# release 完成后 Release/latest 切到新版，下一次跑测试自然校验新 artifact。
DEV_VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
LATEST_VERSION=$(basename "$REL_DIR" | sed 's/^[a-zA-Z_-]*-//')
if [ -n "$DEV_VERSION" ] && [ "$LATEST_VERSION" != "$DEV_VERSION" ]; then
    echo "  ➖ Release/latest=$LATEST_VERSION ≠ dev VERSION=${DEV_VERSION}，跳过（release 进行中或滞后）"
    summary
    exit 0
fi

# 版本一致却扫不到 tarball 同样不是合法状态（release.sh 第 5 步建 tarball、末步才翻转
# latest）；不可读目录在 glob 里与"无 tarball"无法区分，先单独判掉（Gotcha #24）。
if [ ! -r "$REL_DIR" ] || [ ! -x "$REL_DIR" ]; then
    echo "  ❌ ${REL_DIR} 不可读，无法扫描 tarball"
    FAIL=$((FAIL+1))
    summary
    exit 1
fi

# 必须扫的 tarball：source 与 full 都要查
TARBALLS=()
for f in "$REL_DIR"/*-source.tar.gz "$REL_DIR"/*-full.tar.gz; do
    [ -f "$f" ] && TARBALLS+=("$f")
done

if [ "${#TARBALLS[@]}" -eq 0 ]; then
    echo "  ❌ Release/latest 与 VERSION 一致但目录下无 *-source/*-full.tar.gz，产物缺失或被动过"
    FAIL=$((FAIL+1))
    summary
    exit 1
fi

# 禁止出现的路径（基于事实：项目本地工作状态，含开发上下文，绝不能进 release 分发）
# 四件套 / GOTCHAS / CLAUDE.md 只禁"剥掉唯一发布前缀后的根级"：tests/fixtures/ 与 evals/files/ 里
# 同名的输入数据是合法内容，旧的 (^|/) 任意深度匹配会把它们误报（也逼着打包侧把它们误排）。
# 名字取自常量（新旧两套都禁），改名不需要改这里。
_re() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
ROOT_FILES_RE="$(_re "$HX_GOTCHAS_FILE")|CLAUDE\\.md"
ROOT_DIRS_RE=""
for _n in "$HX_MAIN_FILE" "$HX_LEGACY_MAIN_FILE"; do
    ROOT_FILES_RE="$ROOT_FILES_RE|$(_re "$_n")([.]bak.*|[.]pre-v2-backup)?|$(_re "${_n%.md}.archive.md")"
done
for _n in "$HX_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_DEC_DIR" "$HX_LEGACY_DEC_DIR"; do
    ROOT_DIRS_RE="$ROOT_DIRS_RE|$(_re "$_n")([.]archive)?/"
done
FORBIDDEN_PATTERNS=(
    "^($ROOT_FILES_RE)\$"
    "^(${ROOT_DIRS_RE#|})"
    '(^|/)memory/'
    '\.tmp/'
    '\.DS_Store$'
    'Handoff_OldBackup_'
    'Handoff_planning_'
    '(^|/)docs/superpowers/'  # 内部规划文档不进分发；作为防守若被重新拉入项目树
)

for tarball in "${TARBALLS[@]}"; do
    base=$(basename "$tarball")
    # 剥掉唯一发布前缀（handoffx-vX.Y.Z/），后面的根级锚点才有意义
    contents=$(tar tzf "$tarball" 2>/dev/null | sed 's|^[^/]*/||')
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
            echo "  ❌ $base: 含禁止路径（pattern: ${pattern}）"
            echo "$matches" | head -3 | sed 's/^/      /'
            FAIL=$((FAIL+1))
            suite_clean=0
        fi
    done

    if [ "$suite_clean" = "1" ]; then
        echo "  ✅ $base: 无禁止路径"
        PASS=$((PASS+1))
    fi

    # W4a (v4.1.1, report 5 HX-08)：gitx 解包注入 CHANGELOG 后用 macOS tar 重打包，
    # 调用者环境没有 COPYFILE_DISABLE=1 时每个带 xattr 的文件都多一个 `._*` 成员（v4.1.0：
    # full 104 个里 52 个）。macOS 的 `tar tzf` 把它们藏起来，所以用 hx_tar_list_raw。
    ad_rc=0; ad=$(hx_ad_members "$tarball") || ad_rc=$?
    if [ "$ad_rc" -ne 0 ]; then
        echo "  ❌ $base: 无法列出归档（AppleDouble 检查未执行；归档损坏或列表器不支持？）"; FAIL=$((FAIL+1))
    elif [ -z "$ad" ]; then
        echo "  ✅ $base: 无 AppleDouble（._* / __MACOSX/）成员"; PASS=$((PASS+1))
    else
        echo "  ❌ $base: 含 $(printf '%s\n' "$ad" | grep -c .) 个 AppleDouble 成员（发版命令缺 COPYFILE_DISABLE=1？见 INSTALL.md §6）"
        printf '%s\n' "$ad" | head -3 | sed 's/^/      /'
        FAIL=$((FAIL+1))
    fi

    # 正向：合成 v2 夹具是迁移/dogfood 套件的输入数据，只看源码包——根级排除若写成未锚定，
    # 它会被一并吃掉，而上面的"无禁止路径"对此是盲的。夹具以中性名存放（gitx 深度审计在
    # 任意深度拒绝旧名，见 tests/common.sh p21_materialize），故此处断言的是中性名。
    case "$base" in
        *-source.tar.gz)
            # B1（fix wave 1）：镜像 gitx 深度审计的嵌套旧名正则——前缀之下任意深度出现旧主文件 /
            # GOTCHAS / 旧目录，真实发版即被 gitx 拒。上面剥了前缀的根级检查对嵌套是盲的。
            raw=$(tar tzf "$tarball" 2>/dev/null)
            nested_re=$(hx_gitx_nested_re "$(printf '%s\n' "$raw" | head -1 | cut -d/ -f1)")
            nested=$(printf '%s\n' "$raw" | grep -E -- "$nested_re" || true)
            if [ -z "$nested" ]; then
                echo "  ✅ $base: 无 gitx 嵌套旧名命中"; PASS=$((PASS+1))
            else
                echo "  ❌ $base: gitx 嵌套旧名命中 $(printf '%s\n' "$nested" | grep -c .) 条（真实发版会被 gitx 深度审计拒绝）"
                printf '%s\n' "$nested" | head -3 | sed 's/^/      /'
                FAIL=$((FAIL+1))
            fi
            fx="tests/fixtures/p2-1-synthetic-v2/legacy-main.md"
            if printf '%s\n' "$contents" | grep -qxF -- "$fx"; then
                echo "  ✅ $base: 含夹具 ${fx}"; PASS=$((PASS+1))
            else
                echo "  ❌ $base: 缺夹具 ${fx}（根级排除未锚定？）"; FAIL=$((FAIL+1))
            fi
            ;;
    esac
done

summary
