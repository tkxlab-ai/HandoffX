#!/bin/bash
# test_encode_cc_path.sh — verify Claude Code project-path encoding rule
source "$(dirname "$0")/common.sh"

ENC="$SCRIPTS_DIR/encode-cc-path.sh"

assert_file_exists "encode-cc-path.sh exists" "$ENC"
[ -f "$ENC" ] || { summary; exit 1; }

# ── 规则 ──
# 已知映射（从 ~/.claude/projects/ 反推）：
#   /Users/example/Cloud_Coding/Handoff
#     → -Users-jarvis-tkbox-Cloud-Coding-Handoff
# 即：`/` → `-`，`_` → `-`，`.` → `-`（保险起见一并替换）

# case 1: 已知真实路径
out=$(bash "$ENC" "/Users/example/Cloud_Coding/Handoff")
assert_contains "encode /Users/example/Cloud_Coding/Handoff" \
    "$out" "-Users-example-Cloud-Coding-Handoff"

# case 2: 简单路径
out=$(bash "$ENC" "/a/b/c")
assert_contains "encode /a/b/c" "$out" "-a-b-c"

# case 3: 含下划线
out=$(bash "$ENC" "/foo/bar_baz")
assert_contains "encode /foo/bar_baz (underscore → dash)" "$out" "-foo-bar-baz"

# case 4: 含点（罕见但防御）
out=$(bash "$ENC" "/foo/bar.d")
assert_contains "encode /foo/bar.d (dot → dash)" "$out" "-foo-bar-d"

# case 5: 无前导斜杠（相对路径）—— 应原样把非分隔符保留，分隔符替换
out=$(bash "$ENC" "foo/bar")
assert_contains "encode relative foo/bar" "$out" "foo-bar"

# case 6: 空参数 → 非零退出
ex=0; bash "$ENC" "" > /dev/null 2>&1 || ex=$?
[ "$ex" != "0" ] \
    && { echo "  ✅ empty arg → non-zero exit"; PASS=$((PASS+1)); } \
    || { echo "  ❌ empty arg did not fail"; FAIL=$((FAIL+1)); }

# case 7: --help
out=$(bash "$ENC" --help 2>&1 || true)
assert_contains "--help prints usage" "$out" "Usage"

# case 8: 单次输出只有一行（无 trailing 杂质）
out=$(bash "$ENC" "/a/b")
line_count=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
[ "$line_count" = "1" ] \
    && { echo "  ✅ output is exactly one line"; PASS=$((PASS+1)); } \
    || { echo "  ❌ output has $line_count lines (expected 1)"; FAIL=$((FAIL+1)); }

# case 9: 末尾斜杠必须与无斜杠等价（否则 PWD 带 `/` 时会错过 CC 记忆源）
a=$(bash "$ENC" "/foo/bar")
b=$(bash "$ENC" "/foo/bar/")
[ "$a" = "$b" ] \
    && { echo "  ✅ trailing slash normalized"; PASS=$((PASS+1)); } \
    || { echo "  ❌ trailing slash mismatch ('$a' vs '$b')"; FAIL=$((FAIL+1)); }

# case 10: 多个末尾斜杠也要归一
c=$(bash "$ENC" "/foo/bar///")
[ "$a" = "$c" ] \
    && { echo "  ✅ multiple trailing slashes normalized"; PASS=$((PASS+1)); } \
    || { echo "  ❌ multi-slash mismatch ('$a' vs '$c')"; FAIL=$((FAIL+1)); }

summary
