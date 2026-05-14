#!/bin/bash
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"
FIXTURES_DIR="$ROOT_DIR/tests/fixtures"
TEMPLATES_DIR="$ROOT_DIR/skills/handoff/assets"
TMP_DIR="$ROOT_DIR/tests/.tmp"
mkdir -p "$TMP_DIR"

PASS=0
FAIL=0

assert_exit() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: expected exit $expected, got $actual"
        FAIL=$((FAIL+1))
    fi
}

assert_contains() {
    # `-- "$needle"` 必须保留：Gotcha #1——grep pattern 以 `-` 开头会被当成选项
    local name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: missing '$needle'"
        FAIL=$((FAIL+1))
    fi
}

assert_not_contains() {
    local name="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "  ❌ $name: unexpectedly contains '$needle'"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ $name"
        PASS=$((PASS+1))
    fi
}

assert_file_exists() {
    local name="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name: file missing: $path"
        FAIL=$((FAIL+1))
    fi
}

summary() {
    echo "  ─── $PASS passed, $FAIL failed"
    [ "$FAIL" = "0" ]
}
