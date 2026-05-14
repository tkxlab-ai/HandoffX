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
SCRIPTS_GLOB=( "$SCRIPTS_DIR"/*.sh )
shopt -u nullglob
if [ "${#SCRIPTS_GLOB[@]}" -eq 0 ]; then
    echo "  ❌ $SCRIPTS_DIR 下无 .sh 文件"
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

# ── Test 3: scripts/ 与 skills/handoff/scripts/ 同步脚本也通过 ──
BUNDLE_SCRIPTS="$ROOT_DIR/skills/handoff/scripts"
if [ -d "$BUNDLE_SCRIPTS" ]; then
    shopt -s nullglob
    BUNDLE_GLOB=( "$BUNDLE_SCRIPTS"/*.sh )
    shopt -u nullglob
    if [ "${#BUNDLE_GLOB[@]}" -eq 0 ]; then
        echo "  ➖ bundle scripts 目录为空，跳过"
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
    echo "  ➖ bundle scripts 目录不存在，跳过"
fi

summary
