#!/bin/bash
# test_shellcheck.sh — 验证所有脚本通过 shellcheck 静态分析
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

SCRIPTS_DIR="$ROOT_DIR/scripts"

# ── Test 1: shellcheck 可用 ──
if command -v shellcheck >/dev/null 2>&1; then
    echo "  ✅ shellcheck 可用"
    PASS=$((PASS+1))
else
    echo "  ❌ shellcheck 未安装"
    FAIL=$((FAIL+1))
    summary
    exit 1
fi

# ── Test 2: 所有脚本通过 shellcheck (severity=warning) ──
# 用 --severity=warning 忽略 info 级别（如 trap handler 未被引用等误报）
shopt -s nullglob
SCRIPTS_GLOB=( "$SCRIPTS_DIR"/*.sh "$ROOT_DIR"/tools/*.sh "$ROOT_DIR"/tools/lib/*.sh )
shopt -u nullglob
if [ "${#SCRIPTS_GLOB[@]}" -eq 0 ]; then
    echo "  ❌ $SCRIPTS_DIR / $ROOT_DIR/tools / $ROOT_DIR/tools/lib 下均无 .sh 文件"
    FAIL=$((FAIL+1))
    summary
    exit 1
fi
SC_OUTPUT=$(shellcheck --severity=warning "${SCRIPTS_GLOB[@]}" 2>&1)
SC_EXIT=$?
if [ "$SC_EXIT" -eq 0 ]; then
    echo "  ✅ 所有脚本通过 shellcheck (severity=warning)"
    PASS=$((PASS+1))
else
    echo "  ❌ shellcheck 发现问题:"
    echo "$SC_OUTPUT" | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

# ── Test 3: scripts/ 与 skills/handoffx/scripts/ 同步脚本也通过 ──
BUNDLE_SCRIPTS="$ROOT_DIR/skills/handoffx/scripts"
if [ -d "$BUNDLE_SCRIPTS" ]; then
    shopt -s nullglob
    BUNDLE_GLOB=( "$BUNDLE_SCRIPTS"/*.sh )
    shopt -u nullglob
    if [ "${#BUNDLE_GLOB[@]}" -eq 0 ]; then
        echo "  ❌ bundle scripts 目录无 .sh 文件: $BUNDLE_SCRIPTS"
        FAIL=$((FAIL+1))
    else
        SC_BUNDLE_OUTPUT=$(shellcheck --severity=warning "${BUNDLE_GLOB[@]}" 2>&1)
        SC_BUNDLE_EXIT=$?
        if [ "$SC_BUNDLE_EXIT" -eq 0 ]; then
            echo "  ✅ bundle 脚本通过 shellcheck"
            PASS=$((PASS+1))
        else
            echo "  ❌ bundle 脚本 shellcheck 失败:"
            echo "$SC_BUNDLE_OUTPUT" | sed 's/^/    /'
            FAIL=$((FAIL+1))
        fi
    fi
else
    # fail-closed (Gotcha #12): a moved/renamed bundle dir used to make this
    # check skip silently and the suite stayed green with zero bundle coverage.
    echo "  ❌ bundle scripts 目录不存在: $BUNDLE_SCRIPTS"
    FAIL=$((FAIL+1))
fi

# ── Test 4: 无 $NAME 紧跟非 ASCII 字节 ──
# macOS bash 3.2 在 UTF-8 locale 下会把全角字符首字节吞进变量名，路径整段消失
# 且打出乱码（Gotcha #26）；shellcheck 不报这类问题，故按字节扫描，命中须写成 ${NAME}。
# 整行注释与 \$NAME（转义，不展开）不会被 bash 解析成变量，排除以免逼着改无害文字；
# 转义只剥掉 `\$` 两字节再匹配（不是剔整行），同一行里真正的 $NAME 仍会被抓
VARBYTE_HITS=$(cd "$ROOT_DIR" && LC_ALL=C command grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:space:]]' \
    install.sh release.sh scripts/*.sh scripts/lib/*.sh tools/*.sh tools/lib/*.sh \
    skills/handoffx/scripts/*.sh skills/handoffx/scripts/lib/*.sh \
    tests/*.sh 2>&1 \
    | LC_ALL=C command grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
    | LC_ALL=C sed 's/\\\$//g' \
    | LC_ALL=C command grep -E '\$[A-Za-z_][A-Za-z0-9_]*[^[:print:][:space:]]')
if [ -z "$VARBYTE_HITS" ]; then
    echo "  ✅ 无 \$NAME 紧跟非 ASCII 字节（bash 3.2 安全）"
    PASS=$((PASS+1))
else
    echo "  ❌ \$NAME 紧跟非 ASCII 字节，请改写为 \${NAME}:"
    echo "$VARBYTE_HITS" | sed 's/^/    /'
    FAIL=$((FAIL+1))
fi

summary
