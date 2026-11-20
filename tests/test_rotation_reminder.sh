#!/bin/bash
source "$(dirname "$0")/common.sh"
ROT="$SCRIPTS_DIR/rotation-reminder.sh"

# Portable date add (BSD macOS + GNU linux)
date_add() {
    local n="$1"
    if [ "$n" -lt 0 ]; then
        local a=${n#-}
        date -v-${a}d +%Y-%m-%d 2>/dev/null || date -d "-${a} days" +%Y-%m-%d
    else
        date -v+${n}d +%Y-%m-%d 2>/dev/null || date -d "+${n} days" +%Y-%m-%d
    fi
}

PAST=$(date_add -30)
SOON=$(date_add 3)
MID=$(date_add 15)
FAR=$(date_add 90)

mk_doc() {
    local f="$TMP_DIR/handoff_rot_$$_$RANDOM.md"
    cat > "$f" <<EOF
# Demo

## 🔐 Credentials & Access

| 服务 | 位置 | 过期 |
|------|------|------|
$1

## Next Section

nothing
EOF
    echo "$f"
}

# --- empty table, no output, exit 0 ---
empty=$(mk_doc "")
out=$("$ROT" "$empty" 2>&1); ex=$?
if [ -z "$out" ] && [ "$ex" = "0" ]; then
    echo "  ✅ empty credentials table → clean exit 0, no output"; PASS=$((PASS+1))
else
    echo "  ❌ empty table: output='$out' exit=$ex"; FAIL=$((FAIL+1))
fi

# --- expired cred, exit 1 ---
expired=$(mk_doc "| OpenAI | \$OPENAI | $PAST |")
out=$("$ROT" "$expired" 2>&1); ex=$?
assert_contains "reports expired"      "$out" "已过期"
assert_contains "expired names service" "$out" "OpenAI"
assert_exit "expired exits 1"           1 "$ex"

# --- soon (7d window), exit 1 ---
soonf=$(mk_doc "| Stripe | vault://s | $SOON |")
out=$("$ROT" "$soonf" 2>&1); ex=$?
assert_contains "reports 7-day warning" "$out" "Stripe"
assert_exit "7-day exits 1" 1 "$ex"

# --- mid (30d window), exit 1 ---
midf=$(mk_doc "| GitHub | \$GH_PAT | $MID |")
out=$("$ROT" "$midf" 2>&1); ex=$?
assert_contains "reports 30-day warning" "$out" "GitHub"
assert_exit "30-day exits 1" 1 "$ex"

# --- far future is quiet, exit 0 ---
farf=$(mk_doc "| AWS | \$AWS_KEY | $FAR |")
out=$("$ROT" "$farf" 2>&1); ex=$?
if echo "$out" | grep -q "AWS"; then
    echo "  ❌ far-future cred incorrectly reported: $out"; FAIL=$((FAIL+1))
else
    echo "  ✅ far-future cred stays quiet"; PASS=$((PASS+1))
fi
assert_exit "far-future exits 0" 0 "$ex"

# --- placeholder date handled gracefully, exit 0 ---
placef=$(mk_doc "| Foo | bar | — |")
out=$("$ROT" "$placef" 2>&1); ex=$?
if [ -z "$out" ]; then
    echo "  ✅ placeholder date ignored"; PASS=$((PASS+1))
else
    echo "  ❌ placeholder produced output: $out"; FAIL=$((FAIL+1))
fi
assert_exit "placeholder exits 0" 0 "$ex"

# --- missing file ---
ex=0; "$ROT" "/no/such.md" > /dev/null 2>&1 || ex=$?
assert_exit "missing file exits 2" 2 "$ex"

# --- template exposes expiry column used by rotation parser ---
tpl="$TEMPLATES_DIR/${HX_MAIN_FILE%.md}.template.md"
if awk '
    /^## [^A-Za-z]*Credentials & Access/ { in_sec=1; next }
    /^## / && in_sec { in_sec=0 }
    in_sec && /^\|/ && /过期/ { found=1 }
    END { exit found ? 0 : 1 }
' "$tpl"; then
    echo "  ✅ template Credentials table has expiry column"
    PASS=$((PASS+1))
else
    echo "  ❌ template Credentials table missing expiry column"
    FAIL=$((FAIL+1))
fi

# ─── v2 directory-arg mode (H2) ─────────────────────────────────────────────
SANDBOX=$(mktemp -d)
cat > "$SANDBOX/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 🔐 Credentials & Access

| 服务 | 用户 | 过期 | 备注 |
|------|------|------|------|
| OpenAI | acct | 2020-01-01 | 已过期 |
EOF

# Pass the project dir; resolves to $SANDBOX/$HX_MAIN_FILE
out=$("$ROT" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir arg → exit 1 (expired credential found)" 1 "$ec"
assert_contains "v2 dir arg reports expired" "$out" "已过期"

# Empty dir (no $HX_MAIN_FILE inside) → exit 2
EMPTY=$(mktemp -d)
"$ROT" "$EMPTY" >/dev/null 2>&1
ec=$?
assert_exit "v2 empty dir → exit 2" 2 "$ec"

rm -rf "$SANDBOX" "$EMPTY"

# R09：独立旧 exit 契约不变，编排显式 opt-in；每个分类独立 fixture。
for spec in "$empty:0" "$soonf:3" "$midf:3" "$expired:1" "$farf:0"; do
    f=${spec%:*}; expected=${spec##*:}
    ex=0; out=$(bash "$ROT" --classify "$f" 2>&1) || ex=$?
    assert_exit "R09 --classify 分类 $expected" "$expected" "$ex"
done
for date_value in not-a-date 2026-02-30 2026-13-01 0000-01-01 2026-1-01 '2026-01-01 尾注' 'YYYY-MM-DD / —'; do
    invalid=$(mk_doc "| 中文服务 | vault://safe | $date_value |")
    for mode in legacy classify; do
        ex=0
        if [ "$mode" = classify ]; then out=$(bash "$ROT" --classify "$invalid" 2>&1) || ex=$?
        else out=$(bash "$ROT" "$invalid" 2>&1) || ex=$?; fi
        assert_exit "R09 $mode 非法日期 $date_value → error" 2 "$ex"
        assert_contains "R09 非法日期明确诊断" "$out" "日期无法解析"
    done
done
mixed=$(mk_doc "| 近到期 | vault://safe | $SOON |
| 已过期 | vault://safe | $PAST |
| 坏日期 | vault://safe | not-a-date |")
ex=0; out=$(bash "$ROT" --classify "$mixed" 2>&1) || ex=$?
assert_exit "R09 混合状态 error 优先" 2 "$ex"
assert_contains "R09 混合仍报告过期" "$out" "已过期"
mixed=$(mk_doc "| 近到期 | vault://safe | $SOON |
| 过期服务 | vault://safe | $PAST |")
ex=0; out=$(bash "$ROT" --classify "$mixed" 2>&1) || ex=$?
assert_exit "R09 过期优先于 warning" 1 "$ex"
for offset in -1 0 7 30 31; do
    boundary=$(mk_doc "| 边界服务 | vault://safe | $(date_add "$offset") |")
    expected=3; [ "$offset" = -1 ] && expected=1; [ "$offset" = 31 ] && expected=0
    ex=0; out=$(bash "$ROT" --classify "$boundary" 2>&1) || ex=$?
    assert_exit "R09 本地日历日边界 $offset" "$expected" "$ex"
done
for spec in '2000-02-29:1' '1900-02-29:2' '2024-02-29:1' '2100-02-29:2'; do
    leap=$(mk_doc "| 闰年服务 | vault://safe | ${spec%:*} |")
    ex=0; bash "$ROT" --classify "$leap" >/dev/null 2>&1 || ex=$?
    assert_exit "R09 公历闰年 ${spec%:*}" "${spec##*:}" "$ex"
done
RB=$(mktemp -d)
trap 'rm -rf "$RB"' EXIT
mkdir "$RB/bin"
printf '#!/bin/sh\nexit 127\n' > "$RB/bin/awk"; chmod +x "$RB/bin/awk"
ex=0; out=$(PATH="$RB/bin:$PATH" bash "$ROT" --classify "$empty" 2>&1) || ex=$?
assert_exit "R09 解析器无法执行 → error" 2 "$ex"
assert_contains "R09 解析器错误诊断" "$out" "cannot check"
printf '#!/bin/sh\nexit 1\n' > "$RB/bin/date"; chmod +x "$RB/bin/date"
ex=0; out=$(PATH="$RB/bin:$PATH" bash "$ROT" --classify "$empty" 2>&1) || ex=$?
assert_exit "R09 date 执行失败 → error" 2 "$ex"
ex=0; bash "$ROT" --bogus "$empty" >/dev/null 2>&1 || ex=$?
assert_exit "R09 未知参数 → usage error" 2 "$ex"

summary
