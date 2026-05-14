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
tpl="$TEMPLATES_DIR/HANDOFF.template.md"
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
cat > "$SANDBOX/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 🔐 Credentials & Access

| 服务 | 用户 | 过期 | 备注 |
|------|------|------|------|
| OpenAI | acct | 2020-01-01 | 已过期 |
EOF

# Pass the project dir; resolves to $SANDBOX/HANDOFF.md
out=$("$ROT" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir arg → exit 1 (expired credential found)" 1 "$ec"
assert_contains "v2 dir arg reports expired" "$out" "已过期"

# Empty dir (no HANDOFF.md inside) → exit 2
EMPTY=$(mktemp -d)
"$ROT" "$EMPTY" >/dev/null 2>&1
ec=$?
assert_exit "v2 empty dir → exit 2" 2 "$ec"

rm -rf "$SANDBOX" "$EMPTY"

summary
