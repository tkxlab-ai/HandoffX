#!/bin/bash
source "$(dirname "$0")/common.sh"
ARCHIVE="$SCRIPTS_DIR/archive-devlog.sh"

# 生成一个有 N 条 Dev Log 条目的合法 $HX_MAIN_FILE
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
cat > "$SANDBOX_V2/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo
EOF
mkdir -p "$SANDBOX_V2/$HX_LOGS_DIR"
this_year=$(date +%Y)
last_year=$((this_year - 1))
two_year=$((this_year - 2))
echo "old1" > "$SANDBOX_V2/$HX_LOGS_DIR/0001-2023-04-18T1000-old.md"
echo "old2" > "$SANDBOX_V2/$HX_LOGS_DIR/0002-${two_year}-12-31T2359-old.md"
echo "kept1" > "$SANDBOX_V2/$HX_LOGS_DIR/0010-${last_year}-04-18T1000-recent.md"
echo "kept2" > "$SANDBOX_V2/$HX_LOGS_DIR/0020-${this_year}-04-18T1000-fresh.md"

"$ARCHIVE" "$SANDBOX_V2" >/dev/null 2>&1
ec=$?
assert_exit "v2 dir mode: yearly archive exits 0" 0 "$ec"

[ ! -f "$SANDBOX_V2/$HX_LOGS_DIR/0001-2023-04-18T1000-old.md" ] && { echo "  ✅ v2 archive: 2023 entry moved out"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: 2023 entry still in main"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/$HX_LOGS_DIR.archive/2023/0001-2023-04-18T1000-old.md" ] && { echo "  ✅ v2 archive: 2023 entry under archive/2023/"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: 2023 entry not under archive/2023"; FAIL=$((FAIL+1)); }
[ ! -f "$SANDBOX_V2/$HX_LOGS_DIR/0002-${two_year}-12-31T2359-old.md" ] && { echo "  ✅ v2 archive: ${two_year} entry archived"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: ${two_year} entry not archived"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/$HX_LOGS_DIR/0010-${last_year}-04-18T1000-recent.md" ] && { echo "  ✅ v2 archive: ${last_year} entry kept"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: ${last_year} entry wrongly archived"; FAIL=$((FAIL+1)); }
[ -f "$SANDBOX_V2/$HX_LOGS_DIR/0020-${this_year}-04-18T1000-fresh.md" ] && { echo "  ✅ v2 archive: this-year entry kept"; PASS=$((PASS+1)); } || { echo "  ❌ v2 archive: this-year entry wrongly archived"; FAIL=$((FAIL+1)); }

"$ARCHIVE" "$SANDBOX_V2" >/dev/null 2>&1
assert_exit "v2 idempotent second run → exit 0" 0 $?

# Codex stop-time（2026-10-29）：显式传一个带 v2 marker 的*文件*也必须按年归档
# 兄弟目录（以前文件模式只数内联条目 → 0 → 静默 no-op），且文件名不必是默认名。
SANDBOX_F=$(mktemp -d)
printf '<!-- HANDOFF v2 schema -->\n# Demo\n\n## 📜 Development Log\n\n最近一条：0001-2023-04-18T1000-old.md\n最早一条：0001-2023-04-18T1000-old.md\n共 2 条\n' > "$SANDBOX_F/MY_$HX_MAIN_FILE"
mkdir -p "$SANDBOX_F/$HX_LOGS_DIR"
echo "old" > "$SANDBOX_F/$HX_LOGS_DIR/0001-2023-04-18T1000-old.md"
echo "new" > "$SANDBOX_F/$HX_LOGS_DIR/0002-${this_year}-04-18T1000-fresh.md"
"$ARCHIVE" "$SANDBOX_F/MY_$HX_MAIN_FILE" >/dev/null 2>&1; ec=$?
assert_exit "v2 file mode (explicit non-default name) → exit 0" 0 "$ec"
assert_file_exists "v2 file mode: sibling Logs archived by year" "$SANDBOX_F/$HX_LOGS_DIR.archive/2023/0001-2023-04-18T1000-old.md"
# Codex stop-time round 2: the *selected* file's stats must be refreshed (the
# first fix refreshed <dir>/$HX_MAIN_FILE, which here does not even exist)
assert_contains "v2 file mode: MY_$HX_MAIN_FILE 共 N 条 refreshed to the remaining 1" "$(grep -E '^共 [0-9]+ 条$' "$SANDBOX_F/MY_$HX_MAIN_FILE")" "共 1 条"
# retry path: stats stale but nothing left to move (a previous run archived and
# then failed to refresh) — a rerun must repair them, not report success as-is
sed -i.bak 's/^共 1 条$/共 7 条/' "$SANDBOX_F/MY_$HX_MAIN_FILE"; rm -f "$SANDBOX_F/MY_$HX_MAIN_FILE.bak"
"$ARCHIVE" "$SANDBOX_F/MY_$HX_MAIN_FILE" >/dev/null 2>&1; ec=$?
assert_exit "v2 retry with stale stats and nothing to move → exit 0" 0 "$ec"
assert_contains "v2 retry repairs the stale 共 N 条 even though nothing moved" "$(grep -E '^共 [0-9]+ 条$' "$SANDBOX_F/MY_$HX_MAIN_FILE")" "共 1 条"
rm -rf "$SANDBOX_F"

EMPTY_V2=$(mktemp -d)
cat > "$EMPTY_V2/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
EOF
mkdir -p "$EMPTY_V2/$HX_LOGS_DIR"
"$ARCHIVE" "$EMPTY_V2" >/dev/null 2>&1
assert_exit "v2 empty $HX_LOGS_DIR/ → exit 0" 0 $?

# ── unreadable input ≠ nothing to do (2026-06-07 audit MEDIUM-F, Gotcha #24) ──
# v2 marker probe used `grep … 2>/dev/null`: an unreadable $HX_MAIN_FILE read as
# "not v2" and fell into the v1 count path; an unreadable $HX_LOGS_DIR/ walked
# zero files and exited 0 ("nothing to archive"). Both must exit 2.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unreadable-input controls SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$EMPTY_V2/$HX_MAIN_FILE"
    out=$("$ARCHIVE" "$EMPTY_V2" 2>&1); ec=$?
    chmod 644 "$EMPTY_V2/$HX_MAIN_FILE"
    assert_exit "v2 dir: unreadable $HX_MAIN_FILE → exit 2 (cannot tell schema)" 2 "$ec"
    # the later v1 gates also exit 2, so prove this gate *stopped* execution:
    # a dropped `exit` would fall through and the v1 readability gate would speak
    assert_not_contains "v2 dir: unreadable $HX_MAIN_FILE stops at the schema gate (v1 gate silent)" "$out" "entry count unknown"
    chmod 000 "$EMPTY_V2/$HX_LOGS_DIR"
    "$ARCHIVE" "$EMPTY_V2" >/dev/null 2>&1; ec=$?
    chmod 755 "$EMPTY_V2/$HX_LOGS_DIR"
    assert_exit "v2 dir: unreadable $HX_LOGS_DIR/ → exit 2 (not 'nothing to archive')" 2 "$ec"
    UNREAD_V1=$(mktemp)
    printf '## 📜 Development Log\n' > "$UNREAD_V1"; chmod 000 "$UNREAD_V1"
    out=$("$ARCHIVE" "$UNREAD_V1" 2>&1); ec=$?
    chmod 644 "$UNREAD_V1"; rm -f "$UNREAD_V1"
    assert_exit "v1 file: unreadable → exit 2 (count unknown is not ≤ threshold)" 2 "$ec"
    assert_not_contains "v1 file: unreadable stops at the readability gate (awk count guard silent)" "$out" "could not count"
fi

rm -rf "$SANDBOX_V2" "$EMPTY_V2"

# R11：非法阈值必须在任何写入前拒绝，显式空值也不是默认值。
for threshold in abc -1 1.5 '' '+1' ' 1' 999999999999999999999999999999; do
    bad="$TMP_DIR/archive_bad_threshold_$$.md"
    make_handoff 3 "$bad"
    printf '已有历史\n' > "${bad%.md}.archive.md"
    before=$(shasum "$bad" "${bad%.md}.archive.md")
    ec=0; out=$(bash "$ARCHIVE" "$bad" "$threshold" 2>&1) || ec=$?
    assert_exit "非法阈值 [$threshold] 返回用法错误" 2 "$ec"
    assert_exit "非法阈值 [$threshold] 保持主文件和历史不变" "$before" "$(shasum "$bad" "${bad%.md}.archive.md")"
    rm -f "$bad" "${bad%.md}.archive.md"
done
for threshold in 0 000; do
    zero="$TMP_DIR/archive_zero_$$.md"
    make_handoff 3 "$zero"
    ec=0; bash "$ARCHIVE" "$zero" "$threshold" >/dev/null 2>&1 || ec=$?
    assert_exit "阈值 $threshold 仍允许归档全部条目" 0 "$ec"
    assert_exit "阈值 $threshold 主文件不留条目" 0 "$(grep -c '^### 2026-' "$zero")"
    assert_exit "阈值 $threshold 历史保留全部三条" 3 "$(grep -c '^### 2026-' "${zero%.md}.archive.md")"
    rm -f "$zero" "${zero%.md}.archive.md"
done

# R03：后面的目标冲突也必须阻止前面的条目移动。
SAFE=$(mktemp -d)
printf '<!-- HANDOFF v2 schema -->\n## 📜 Development Log\n共 2 条\n' > "$SAFE/$HX_MAIN_FILE"
mkdir -p "$SAFE/$HX_LOGS_DIR" "$SAFE/$HX_LOGS_DIR.archive/2020"
a=0001-2020-01-01T0000-first.md
b=0002-2020-01-01T0000-last.md
printf '第一条原文\n' > "$SAFE/$HX_LOGS_DIR/$a"
printf '第二条原文\n' > "$SAFE/$HX_LOGS_DIR/$b"
printf '不能覆盖的历史\n' > "$SAFE/$HX_LOGS_DIR.archive/2020/$b"
before=$(shasum "$SAFE/$HX_MAIN_FILE" "$SAFE/$HX_LOGS_DIR/$a" "$SAFE/$HX_LOGS_DIR/$b" "$SAFE/$HX_LOGS_DIR.archive/2020/$b")
ec=0; out=$(bash "$ARCHIVE" "$SAFE" 2>&1) || ec=$?
assert_exit "归档同名异文返回冲突" 4 "$ec"
assert_exit "全部目标预检：冲突时所有原文和指针不变" "$before" "$(shasum "$SAFE/$HX_MAIN_FILE" "$SAFE/$HX_LOGS_DIR/$a" "$SAFE/$HX_LOGS_DIR/$b" "$SAFE/$HX_LOGS_DIR.archive/2020/$b" 2>/dev/null)"
[ ! -e "$SAFE/$HX_LOGS_DIR.archive/2020/$a" ]; assert_exit "预检冲突不产生前序归档" 0 $?
# 修复冲突为同文后，应可恢复；目标 inode 不变（不做覆盖）。
printf '第一条原文\n' > "$SAFE/$HX_LOGS_DIR/$a"
printf '第二条原文\n' > "$SAFE/$HX_LOGS_DIR/$b"
cp "$SAFE/$HX_LOGS_DIR/$b" "$SAFE/$HX_LOGS_DIR.archive/2020/$b"
ln "$SAFE/$HX_LOGS_DIR.archive/2020/$b" "$SAFE/history-link"
ec=0; bash "$ARCHIVE" "$SAFE" >/dev/null 2>&1 || ec=$?
assert_exit "同名同文幂等完成归档" 0 "$ec"
[ "$SAFE/history-link" -ef "$SAFE/$HX_LOGS_DIR.archive/2020/$b" ]; assert_exit "同文目标不被替换" 0 $?
[ ! -e "$SAFE/$HX_LOGS_DIR/$b" ]; assert_exit "同文源条目完成归档" 0 $?
before=$(shasum "$SAFE/$HX_MAIN_FILE" "$SAFE/$HX_LOGS_DIR.archive/2020/"*.md)
ec=0; bash "$ARCHIVE" "$SAFE" >/dev/null 2>&1 || ec=$?
assert_exit "归档再次执行成功" 0 "$ec"
assert_exit "归档再次执行保持字节不变" "$before" "$(shasum "$SAFE/$HX_MAIN_FILE" "$SAFE/$HX_LOGS_DIR.archive/2020/"*.md)"

# 中途移动失败：已归档的内容保留，失败项留在源，报告部分进度，重试可恢复。
printf '第一条原文\n' > "$SAFE/$HX_LOGS_DIR/$a"
printf '第二条原文\n' > "$SAFE/$HX_LOGS_DIR/$b"
rm -f "$SAFE/$HX_LOGS_DIR.archive/2020/$a" "$SAFE/$HX_LOGS_DIR.archive/2020/$b"
mkdir "$SAFE/bin"
REAL_MV=$(command -v mv)
cat > "$SAFE/bin/mv" <<'EOF'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in */0002-2020-*) exit 71 ;; esac
done
exec "$REAL_MV" "$@"
EOF
chmod +x "$SAFE/bin/mv"
ec=0; out=$(PATH="$SAFE/bin:$PATH" REAL_MV="$REAL_MV" bash "$ARCHIVE" "$SAFE" 2>&1) || ec=$?
assert_exit "中途移动失败返回非零" 5 "$ec"
assert_file_exists "中途失败保留已归档文件" "$SAFE/$HX_LOGS_DIR.archive/2020/$a"
assert_file_exists "中途失败保留未移动原文" "$SAFE/$HX_LOGS_DIR/$b"
assert_contains "中途失败明确记录部分进度" "$out" "after 1 entries"
ec=0; bash "$ARCHIVE" "$SAFE" >/dev/null 2>&1 || ec=$?
assert_exit "中途失败后可重试" 0 "$ec"
assert_contains "重试后第二条内容完整" "$(cat "$SAFE/$HX_LOGS_DIR.archive/2020/$b")" "第二条原文"
# 目标不是普通文件（目录、symlink、断链）时，同样不得移动其它条目。
for target_kind in directory symlink dangling; do
    printf '第一条原文\n' > "$SAFE/$HX_LOGS_DIR/$a"
    printf '第二条原文\n' > "$SAFE/$HX_LOGS_DIR/$b"
    rm -f "$SAFE/$HX_LOGS_DIR.archive/2020/$a" "$SAFE/$HX_LOGS_DIR.archive/2020/$b"
    case "$target_kind" in
        directory) mkdir "$SAFE/$HX_LOGS_DIR.archive/2020/$b" ;;
        symlink) ln -s "$SAFE/$HX_LOGS_DIR/$b" "$SAFE/$HX_LOGS_DIR.archive/2020/$b" ;;
        dangling) ln -s "$SAFE/missing" "$SAFE/$HX_LOGS_DIR.archive/2020/$b" ;;
    esac
    ec=0; bash "$ARCHIVE" "$SAFE" >/dev/null 2>&1 || ec=$?
    assert_exit "归档目标 $target_kind 拒绝写入" 4 "$ec"
    assert_file_exists "目标 $target_kind 冲突不移动前序源" "$SAFE/$HX_LOGS_DIR/$a"
    assert_file_exists "目标 $target_kind 冲突不移动当前源" "$SAFE/$HX_LOGS_DIR/$b"
    [ ! -e "$SAFE/$HX_LOGS_DIR.archive/2020/$a" ]; assert_exit "目标 $target_kind 冲突不产生前序归档" 0 $?
    rm -rf "$SAFE/$HX_LOGS_DIR.archive/2020/$b"
done
# 在预检后模拟其它写入者创建目标；mv -n 返回成功但未移动也不能误删源。
cat > "$SAFE/bin/mv" <<'EOF'
#!/bin/bash
last=''
for arg in "$@"; do last=$arg; done
case "$last" in */0001-2020-*) printf '并发创建的历史\n' > "$last" ;; esac
exec "$REAL_MV" "$@"
EOF
ec=0; out=$(PATH="$SAFE/bin:$PATH" REAL_MV="$REAL_MV" bash "$ARCHIVE" "$SAFE" 2>&1) || ec=$?
assert_exit "预检后出现异文目标仍拒绝覆盖" 4 "$ec"
assert_exit "并发创建的历史不被覆盖" "并发创建的历史" "$(cat "$SAFE/$HX_LOGS_DIR.archive/2020/$a")"
assert_exit "无覆盖移动被跳过时原文保留" "第一条原文" "$(cat "$SAFE/$HX_LOGS_DIR/$a")"
assert_contains "首次移动失败不伪报进度" "$out" "after 0 entries"
# v2 仍忽略阈值；不把 v1 校验错误扩散到按年归档。
rm -f "$SAFE/$HX_LOGS_DIR.archive/2020/$a"
ec=0; bash "$ARCHIVE" "$SAFE" abc >/dev/null 2>&1 || ec=$?
assert_exit "v2 保持忽略阈值契约" 0 "$ec"
rm -rf "$SAFE"

leading="$TMP_DIR/archive_leading_zero_$$.md"
make_handoff 10 "$leading"
ec=0; bash "$ARCHIVE" "$leading" 08 >/dev/null 2>&1 || ec=$?
assert_exit "前导零阈值按十进制处理" 0 "$ec"
assert_exit "08 保留八条" 8 "$(grep -c '^### 2026-' "$leading")"
assert_exit "08 归档两条" 2 "$(grep -c '^### 2026-' "${leading%.md}.archive.md")"
rm -f "$leading" "${leading%.md}.archive.md"

summary
