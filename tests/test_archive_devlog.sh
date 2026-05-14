#!/bin/bash
source "$(dirname "$0")/common.sh"
ARCHIVE="$SCRIPTS_DIR/archive-devlog.sh"

# 生成一个有 N 条 Dev Log 条目的合法 HANDOFF.md
make_handoff() {
    local n="$1" outfile="$2"
    {
        cat <<EOF
# Sample Project — Handoff

## 📦 Project Overview
placeholder.

## 🏗 Architecture
placeholder.

## 🎯 Current State
placeholder.

## 🐛 Known Gotchas
placeholder.

## 📜 Development Log

> 最新在最上面。

---

EOF
        # 倒序生成 n 条条目（最新在上）
        for i in $(seq "$n" -1 1); do
            printf "### 2026-01-%02d 10:00 — Entry %d\n\n" "$((i % 28 + 1))" "$i"
            printf "**触发**: mock\n**改动**: file-%d.md\n**验证**: ok\n**关联**: 无\n\n---\n\n" "$i"
        done
        echo '<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->'
    } > "$outfile"
}

# Case 1: < 50 条 → 脚本不动文件，退出 0
f1="$TMP_DIR/archive_small_$$.md"
make_handoff 10 "$f1"
sha_before=$(shasum "$f1" | cut -d' ' -f1)
"$ARCHIVE" "$f1" >/dev/null 2>&1
exit_code=$?
sha_after=$(shasum "$f1" | cut -d' ' -f1)
assert_exit "small file exits 0" 0 "$exit_code"
assert_exit "small file unchanged" "$sha_before" "$sha_after"
[ ! -f "${f1%.md}.archive.md" ]
assert_exit "no archive file created for small" 0 $?

# Case 2: 超过 50 条 → 主文件留 50 条，剩余去 archive
f2="$TMP_DIR/archive_big_$$.md"
make_handoff 60 "$f2"
"$ARCHIVE" "$f2" >/dev/null 2>&1
exit_code=$?
assert_exit "big file exits 0" 0 "$exit_code"

kept=$(grep -c "^### 2026-01-" "$f2")
assert_exit "main file keeps exactly 50 entries" 50 "$kept"

arch="${f2%.md}.archive.md"
assert_file_exists "archive file created" "$arch"
if [ -f "$arch" ]; then
    archived=$(grep -c "^### 2026-01-" "$arch")
    assert_exit "archive file has 10 entries" 10 "$archived"
fi

# 主文件仍含锚点
grep -q "🚨 AI 注意" "$f2"
assert_exit "anchor comment preserved" 0 $?

# 主文件最老保留那条和最老归档那条不是同一条（边界正确）
main_oldest=$(grep "^### 2026-01-" "$f2" | tail -1)
arch_newest=$(grep "^### 2026-01-" "$arch" | head -1)
[ "$main_oldest" != "$arch_newest" ]
assert_exit "no overlap between main oldest and archive newest" 0 $?

# 主文件含指向归档的提示（归档文件的 basename）
grep -qF "$(basename "$arch")" "$f2"
assert_exit "main file has pointer to archive" 0 $?

# Case 3: 幂等——再跑一次不应改变任何东西
sha_main=$(shasum "$f2" | cut -d' ' -f1)
sha_arch=$(shasum "$arch" | cut -d' ' -f1)
"$ARCHIVE" "$f2" >/dev/null 2>&1
assert_exit "idempotent: main unchanged" "$sha_main" "$(shasum "$f2" | cut -d' ' -f1)"
assert_exit "idempotent: archive unchanged" "$sha_arch" "$(shasum "$arch" | cut -d' ' -f1)"

# Case 4: 再加 20 条到已归档过的文件，再次归档应追加到 archive 开头（最新在上）
f3="$TMP_DIR/archive_append_$$.md"
make_handoff 60 "$f3"
"$ARCHIVE" "$f3" >/dev/null 2>&1  # 首轮归档：60 → 主 50 + 归档 10
# 在主文件顶部再插入 20 条新的（编号 100-81）
tmp="$TMP_DIR/tmp_$$.md"
awk '
    /^## 📜 Development Log/ { print; in_log=1; next }
    in_log && /^---$/ && !started {
        print
        started=1
        # 插入新 20 条
        for (i=100; i>=81; i--) {
            printf "### 2026-02-%02d 10:00 — Entry %d\n\n", (i % 28 + 1), i
            printf "**触发**: mock\n**改动**: file-%d.md\n**验证**: ok\n**关联**: 无\n\n---\n\n", i
        }
        next
    }
    { print }
' "$f3" > "$tmp"
mv "$tmp" "$f3"

"$ARCHIVE" "$f3" >/dev/null 2>&1
main_count=$(grep -c "^### " "$f3")
arch_count=$(grep -c "^### " "${f3%.md}.archive.md")
assert_exit "after append+archive: main has 50" 50 "$main_count"
# 10 from first round + 20 newly pushed out
assert_exit "after append+archive: archive has 30" 30 "$arch_count"

# Case 5: 不是文件 → 退出非 0
"$ARCHIVE" /nonexistent/path.md >/dev/null 2>&1
assert_exit "missing file exits non-zero" 2 $?

# Case 6: 自定义阈值
f4="$TMP_DIR/archive_threshold_$$.md"
make_handoff 20 "$f4"
"$ARCHIVE" "$f4" 5 >/dev/null 2>&1  # 用 5 作阈值
main_count=$(grep -c "^### 2026-01-" "$f4")
assert_exit "custom threshold 5: main keeps 5" 5 "$main_count"

# Case 7: 已有 archive 时，同 header 不同正文的条目都必须保留
f5="$TMP_DIR/archive_duplicate_header_$$.md"
cat > "$f5" <<'EOF'
# Sample Project — Handoff

## 📦 Project Overview
x

## 🏗 Architecture
x

## 🎯 Current State
x

## 📜 Development Log

### 2026-04-30 10:00 — Keep

**触发**: keep
**改动**: keep.md
**验证**: ok
**关联**: 无

---

### 2026-04-29 10:00 — Same Header

**触发**: first distinct body
**改动**: first.md
**验证**: ok
**关联**: 无

---

### 2026-04-29 10:00 — Same Header

**触发**: second distinct body
**改动**: second.md
**验证**: ok
**关联**: 无

---

<!-- 🚨 AI 注意：下一次 handoff 追加在此分隔符之上 -->
EOF
cat > "${f5%.md}.archive.md" <<'EOF'
# existing archive

### 2026-04-01 10:00 — Existing

**触发**: old
**改动**: old.md
**验证**: ok
**关联**: 无
EOF
"$ARCHIVE" "$f5" 1 >/dev/null 2>&1
assert_contains "duplicate header archive keeps first body" "$(cat "${f5%.md}.archive.md")" "first.md"
assert_contains "duplicate header archive keeps second body" "$(cat "${f5%.md}.archive.md")" "second.md"

# Case 8: defensive — section after Dev Log is preserved when source anchor is missing
# Why: tidy/validate normally enforce anchor invariant, but archive-devlog must not
# silently swallow downstream sections if invariant is violated.
f6="$TMP_DIR/archive_section_after_$$.md"
{
    cat <<'EOF'
# Sample Project — Handoff

## 📦 Project Overview
x

## 🏗 Architecture
x

## 🎯 Current State
x

## 🐛 Known Gotchas
x

## 📜 Development Log

> 最新在最上面。

---

EOF
    for i in $(seq 60 -1 1); do
        printf "### 2026-01-%02d 10:00 — Entry %d\n\n" "$((i % 28 + 1))" "$i"
        printf "**触发**: mock\n**改动**: file-%d.md\n**验证**: ok\n**关联**: 无\n\n---\n\n" "$i"
    done
    # No anchor here on purpose — a downstream section follows
    cat <<'EOF'
## 📌 PostScript

This section follows Dev Log and must survive archiving.
Sentinel: post-devlog-content-keepme
EOF
} > "$f6"
"$ARCHIVE" "$f6" >/dev/null 2>&1
assert_exit "section-after-devlog: archive succeeds" 0 $?
assert_contains "section-after-devlog: PostScript heading preserved" "$(cat "$f6")" "## 📌 PostScript"
assert_contains "section-after-devlog: PostScript content preserved" "$(cat "$f6")" "post-devlog-content-keepme"

# ─── v2 yearly archive (H4) ─────────────────────────────────────────────────
SANDBOX_V2=$(mktemp -d)
cat > "$SANDBOX_V2/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
EOF
mkdir -p "$SANDBOX_V2/Handoff_Logs"
this_year=$(date +%Y)
last_year=$((this_year - 1))
two_year=$((this_year - 2))
echo "old1" > "$SANDBOX_V2/Handoff_Logs/0001-2023-04-18T1000-old.md"
echo "old2" > "$SANDBOX_V2/Handoff_Logs/0002-${two_year}-12-31T2359-old.md"
echo "kept1" > "$SANDBOX_V2/Handoff_Logs/0010-${last_year}-04-18T1000-recent.md"
echo "kept2" > "$SANDBOX_V2/Handoff_Logs/0020-${this_year}-04-18T1000-fresh.md"

"$ARCHIVE" "$SANDBOX_V2" >/dev/null 2>&1
ec=$?
assert_exit "v2 dir mode: yearly archive exits 0" 0 "$ec"

[ ! -f "$SANDBOX_V2/Handoff_Logs/0001-2023-04-18T1000-old.md" ] && { echo "  ✅ v2 archive: 2023 entry moved out"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: 2023 entry still in main"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/Handoff_Logs.archive/2023/0001-2023-04-18T1000-old.md" ] && { echo "  ✅ v2 archive: 2023 entry under archive/2023/"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: 2023 entry not under archive/2023"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_V2/Handoff_Logs/0002-${two_year}-12-31T2359-old.md" ] && { echo "  ✅ v2 archive: ${two_year} entry archived"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: ${two_year} entry not archived"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/Handoff_Logs/0010-${last_year}-04-18T1000-recent.md" ] && { echo "  ✅ v2 archive: ${last_year} entry kept"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: ${last_year} entry wrongly archived"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/Handoff_Logs/0020-${this_year}-04-18T1000-fresh.md" ] && { echo "  ✅ v2 archive: this-year entry kept"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: this-year entry wrongly archived"; FAIL=$((FAIL+1)); }

"$ARCHIVE" "$SANDBOX_V2" >/dev/null 2>&1
assert_exit "v2 idempotent second run → exit 0" 0 $?

EMPTY_V2=$(mktemp -d)
cat > "$EMPTY_V2/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$EMPTY_V2/Handoff_Logs"
"$ARCHIVE" "$EMPTY_V2" >/dev/null 2>&1
assert_exit "v2 empty Handoff_Logs/ → exit 0" 0 $?

rm -rf "$SANDBOX_V2" "$EMPTY_V2"

summary
