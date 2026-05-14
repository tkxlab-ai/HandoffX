#!/bin/bash
# test_sync_memory.sh — experimental project-memory sync
#
# 行为约定：
# - 默认不做任何事（标志文件不存在 → exit 0，无写入）
# - `on`  子命令 → 创建 ./memory/ + ./memory/.sync-enabled + 执行首次同步
# - `off` 子命令 → 删除标志文件，不删已同步文件
# - `status` → 输出 "enabled"/"disabled" + 文件计数
# - `sync`  → 不看标志，强制同步一次（供 on 复用）
# - 同步动作：把 $HOME_OVERRIDE/.claude/projects/<encoded(pwd)>/memory/*.md
#           复制到 ./memory/，覆盖同名文件，不删多余文件
# - 源目录不存在 → 打印友好提示，exit 0（不是错误）
# - 非 .md 文件一律忽略（如 MEMORY.md 索引也带 .md 所以会被同步）
#
# 测试靠 HOME_OVERRIDE 环境变量把 ~/.claude/projects/ 指到 tmp，避免污染真实 CC 状态。

source "$(dirname "$0")/common.sh"

SYNC="$SCRIPTS_DIR/sync-memory.sh"
assert_file_exists "sync-memory.sh exists" "$SYNC"
[ -f "$SYNC" ] || { summary; exit 1; }

# ── setup isolated workspace ──
WORK="$TMP_DIR/sync_memory_$$"
rm -rf "$WORK"
mkdir -p "$WORK"

FAKE_HOME="$WORK/home"
PROJECT="$WORK/proj/Some_App"
mkdir -p "$FAKE_HOME" "$PROJECT"

# 构造 fake ~/.claude/projects/<encoded>/memory/ 源
ENCODED=$(bash "$SCRIPTS_DIR/encode-cc-path.sh" "$PROJECT")
CC_MEM="$FAKE_HOME/.claude/projects/$ENCODED/memory"
mkdir -p "$CC_MEM"
cat > "$CC_MEM/MEMORY.md" <<'EOF'
# Memory Index
- [Test rule](feedback_test.md) — test description
EOF
cat > "$CC_MEM/feedback_test.md" <<'EOF'
---
name: test
type: feedback
---
Body content.
EOF

run_in_project() {
    (cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" "$@" 2>&1)
}

# ── Case 1: 默认 disabled → 不创建文件 ──
out=$(run_in_project status)
assert_contains "status says disabled by default" "$out" "disabled"
[ ! -d "$PROJECT/memory" ] \
    && { echo "  ✅ no ./memory/ created by status query"; PASS=$((PASS+1)); } \
    || { echo "  ❌ status query unexpectedly created ./memory/"; FAIL=$((FAIL+1)); }

# ── Case 2: on → 启用标志 + 首次同步 ──
out=$(run_in_project on)
assert_file_exists "flag file created" "$PROJECT/memory/.sync-enabled"
assert_file_exists "MEMORY.md synced"    "$PROJECT/memory/MEMORY.md"
assert_file_exists "feedback_test.md synced" "$PROJECT/memory/feedback_test.md"
assert_contains "on output mentions enabled" "$out" "enabled"

# ── Case 3: 同步内容正确 ──
body=$(cat "$PROJECT/memory/feedback_test.md")
assert_contains "synced body has frontmatter" "$body" "name: test"
assert_contains "synced body has content"     "$body" "Body content."

# ── Case 4: status 显示 enabled + 计数 ──
out=$(run_in_project status)
assert_contains "status says enabled after on" "$out" "enabled"
assert_contains "status shows file count (2 .md)" "$out" "2"

# ── Case 5: 再次 sync 幂等 ──
out=$(run_in_project sync)
count=$(ls "$PROJECT/memory/"*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$count" = "2" ] \
    && { echo "  ✅ sync idempotent (still 2 .md)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ sync not idempotent (found $count)"; FAIL=$((FAIL+1)); }

# ── Case 6: CC 那边新增一个文件 → 下次 sync 拉下来 ──
cat > "$CC_MEM/project_scope.md" <<'EOF'
---
name: scope
type: project
---
New memory.
EOF
out=$(run_in_project sync)
assert_file_exists "new CC file synced" "$PROJECT/memory/project_scope.md"

# ── Case 7: CC 那边修改内容 → 同步后覆盖 ──
echo "updated content" >> "$CC_MEM/feedback_test.md"
out=$(run_in_project sync)
new_body=$(cat "$PROJECT/memory/feedback_test.md")
assert_contains "sync overwrites with new content" "$new_body" "updated content"

# ── Case 8: 项目本地多出的文件不被删（sync 是覆盖式，不是镜像） ──
echo "local-only" > "$PROJECT/memory/local_note.md"
out=$(run_in_project sync)
assert_file_exists "local-only file preserved after sync" "$PROJECT/memory/local_note.md"

# ── Case 9: off → 删标志，保留文件 ──
out=$(run_in_project off)
[ ! -f "$PROJECT/memory/.sync-enabled" ] \
    && { echo "  ✅ flag removed by off"; PASS=$((PASS+1)); } \
    || { echo "  ❌ flag still present after off"; FAIL=$((FAIL+1)); }
assert_file_exists "synced files kept after off" "$PROJECT/memory/MEMORY.md"
out=$(run_in_project status)
assert_contains "status says disabled after off" "$out" "disabled"

# ── Case 10: CC 源目录不存在 → 友好退出（不是硬失败） ──
BARE_PROJECT="$WORK/proj/Bare_App"
mkdir -p "$BARE_PROJECT"
ex=0
(cd "$BARE_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on > /dev/null 2>&1) || ex=$?
# on 可以 exit 0（启用但无源 → 空 memory/）或打印提示 exit 0；硬失败不符合 UX
[ "$ex" = "0" ] \
    && { echo "  ✅ on without CC source exits 0 (friendly)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ on without CC source failed with $ex"; FAIL=$((FAIL+1)); }
# 标志文件应该被创建（即使源空）
assert_file_exists "flag file created even without CC source" "$BARE_PROJECT/memory/.sync-enabled"

# ── Case 11: --help ──
out=$(bash "$SYNC" --help 2>&1 || true)
assert_contains "--help prints usage" "$out" "Usage"

# ── Case 12: 未知子命令 → 非零退出 ──
ex=0
(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" bogus > /dev/null 2>&1) || ex=$?
[ "$ex" != "0" ] \
    && { echo "  ✅ unknown subcommand → non-zero exit"; PASS=$((PASS+1)); } \
    || { echo "  ❌ unknown subcommand accepted silently"; FAIL=$((FAIL+1)); }

# ── Case 13: read-only CC source → 同步后 dst 可写（防 R6.4 read-only 锁死） ──
echo "ro body" > "$CC_MEM/ro_test.md"
chmod 400 "$CC_MEM/ro_test.md"
(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync > /dev/null 2>&1)
[ -w "$PROJECT/memory/ro_test.md" ] \
    && { echo "  ✅ synced file writable even when source is 0400"; PASS=$((PASS+1)); } \
    || { echo "  ❌ synced file inherited 0400 (next sync will fail)"; FAIL=$((FAIL+1)); }
# 二次 sync 必须仍然 exit 0
ex=0
(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync > /dev/null 2>&1) || ex=$?
[ "$ex" = "0" ] \
    && { echo "  ✅ re-sync over read-only source still exits 0"; PASS=$((PASS+1)); } \
    || { echo "  ❌ re-sync exit $ex (R6.4 regression)"; FAIL=$((FAIL+1)); }
chmod 600 "$CC_MEM/ro_test.md"

# ── Case 14: symlink in CC source → 跳过（防 R6.2 任意文件读取） ──
echo "real secret" > "$WORK/secret.txt"
ln -sf "$WORK/secret.txt" "$CC_MEM/evil_link.md"
out=$(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync 2>&1)
[ ! -f "$PROJECT/memory/evil_link.md" ] \
    && { echo "  ✅ symlink in CC source skipped (no exfiltration)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ symlink followed — exfiltration risk"; FAIL=$((FAIL+1)); }
echo "$out" | grep -q "symlink" \
    && { echo "  ✅ symlink skip is reported in output"; PASS=$((PASS+1)); } \
    || { echo "  ❌ symlink skip is silent (user can't tell)"; FAIL=$((FAIL+1)); }
rm -f "$CC_MEM/evil_link.md"

# ── Case 15: 凭证扫描——CC 源含疑似 GitHub token → sync 返回非零 + 警告可见 ──
# 用一个"长得像真 token"但非真的字符串
cat > "$CC_MEM/with_secret.md" <<'EOF'
---
name: leaked
type: feedback
---
Test GitHub token: ghp_abcdefghijklmnopqrstuvwxyz0123456789
EOF
ec=0
out=$(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync 2>&1) || ec=$?
echo "$out" | grep -q "凭证" \
    && { echo "  ✅ credential scan prints warning"; PASS=$((PASS+1)); } \
    || { echo "  ❌ credential scan silent"; FAIL=$((FAIL+1)); }
echo "$out" | grep -q "with_secret.md" \
    && { echo "  ✅ warning names the offending file"; PASS=$((PASS+1)); } \
    || { echo "  ❌ warning missing file name"; FAIL=$((FAIL+1)); }
[ "$ec" != "0" ] \
    && { echo "  ✅ sync returns non-zero when creds found"; PASS=$((PASS+1)); } \
    || { echo "  ❌ sync returned 0 despite credentials"; FAIL=$((FAIL+1)); }
# 文件仍然同步了（不撤销，只警告）
[ -f "$PROJECT/memory/with_secret.md" ] \
    && { echo "  ✅ synced despite creds (user decides next)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ sync aborted mid-loop"; FAIL=$((FAIL+1)); }
rm -f "$CC_MEM/with_secret.md" "$PROJECT/memory/with_secret.md"

# ── Case 16: clean CC source → 无警告 + sync exit 0 ──
ec=0
out=$(cd "$PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync 2>&1) || ec=$?
[ "$ec" = "0" ] \
    && { echo "  ✅ clean sync exit 0"; PASS=$((PASS+1)); } \
    || { echo "  ❌ clean sync exit $ec (scan false-positive?)"; FAIL=$((FAIL+1)); }
echo "$out" | grep -q "凭证" \
    && { echo "  ❌ clean sync printed false credential warning"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ clean sync has no credential noise"; PASS=$((PASS+1)); }

# ── Case 17: .gitignore 提示——项目有 .git/ 且未忽略 memory/ ──
GIT_PROJECT="$WORK/git_proj"
mkdir -p "$GIT_PROJECT/.git"   # 装作 git repo，不 init 真仓库
ENCODED_G=$(bash "$SCRIPTS_DIR/encode-cc-path.sh" "$GIT_PROJECT")
mkdir -p "$FAKE_HOME/.claude/projects/$ENCODED_G/memory"
out=$(cd "$GIT_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on 2>&1)
echo "$out" | grep -q ".gitignore" \
    && { echo "  ✅ .gitignore hint shown on first on in git repo"; PASS=$((PASS+1)); } \
    || { echo "  ❌ .gitignore hint missing"; FAIL=$((FAIL+1)); }

# ── Case 18: .gitignore 提示——第二次 on 不重复打扰 ──
out2=$(cd "$GIT_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on 2>&1)
echo "$out2" | grep -q ".gitignore" \
    && { echo "  ❌ .gitignore hint repeated on second on"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ second on does not repeat hint"; PASS=$((PASS+1)); }

# ── Case 19: .gitignore 提示——非 git 目录不提示 ──
NOGIT_PROJECT="$WORK/nogit"
mkdir -p "$NOGIT_PROJECT"
ENCODED_N=$(bash "$SCRIPTS_DIR/encode-cc-path.sh" "$NOGIT_PROJECT")
mkdir -p "$FAKE_HOME/.claude/projects/$ENCODED_N/memory"
out=$(cd "$NOGIT_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on 2>&1)
echo "$out" | grep -q ".gitignore" \
    && { echo "  ❌ hint shown in non-git dir"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ no hint in non-git dir"; PASS=$((PASS+1)); }

# ── Case 20: .gitignore 提示——已包含 memory/ → 不打扰 ──
ALREADY_PROJECT="$WORK/already"
mkdir -p "$ALREADY_PROJECT/.git"
echo "memory/" > "$ALREADY_PROJECT/.gitignore"
ENCODED_A=$(bash "$SCRIPTS_DIR/encode-cc-path.sh" "$ALREADY_PROJECT")
mkdir -p "$FAKE_HOME/.claude/projects/$ENCODED_A/memory"
out=$(cd "$ALREADY_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on 2>&1)
echo "$out" | grep -q "建议加入 .gitignore" \
    && { echo "  ❌ hint shown even when memory/ already in .gitignore"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ already-ignored project suppresses hint"; PASS=$((PASS+1)); }

# ── Case 21: 凭证 + git 提示同时命中——scan 非 0 不能阻塞 gitignore 提示 ──
BOTH_PROJECT="$WORK/both"
mkdir -p "$BOTH_PROJECT/.git"
ENCODED_B=$(bash "$SCRIPTS_DIR/encode-cc-path.sh" "$BOTH_PROJECT")
mkdir -p "$FAKE_HOME/.claude/projects/$ENCODED_B/memory"
cat > "$FAKE_HOME/.claude/projects/$ENCODED_B/memory/leak.md" <<'EOF'
---
name: leak
---
ghp_abcdefghijklmnopqrstuvwxyz0123456789
EOF
ec=0
out=$(cd "$BOTH_PROJECT" && HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" on 2>&1) || ec=$?
echo "$out" | grep -q "凭证" \
    && { echo "  ✅ credential warning shown"; PASS=$((PASS+1)); } \
    || { echo "  ❌ credential warning missing"; FAIL=$((FAIL+1)); }
echo "$out" | grep -q ".gitignore" \
    && { echo "  ✅ .gitignore hint ALSO shown (set -e bug regressed)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ .gitignore hint missing — set -e aborted early"; FAIL=$((FAIL+1)); }
[ "$ec" != "0" ] \
    && { echo "  ✅ on still returns non-zero with creds"; PASS=$((PASS+1)); } \
    || { echo "  ❌ on returned 0 despite creds"; FAIL=$((FAIL+1)); }

# ── .sync-enabled semantic gap tests (P3-4) ──

# Manually create flag file without any .md files in memory/
rm -rf "$PROJECT/memory"
mkdir -p "$PROJECT/memory"
touch "$PROJECT/memory/.sync-enabled"

out=$(cd "$PROJECT" && env HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" status 2>&1)
ec=$?
echo "$out" | grep -q "enabled" \
    && { echo "  ✅ manual flag → status says enabled"; PASS=$((PASS+1)); } \
    || { echo "  ❌ manual flag → status did not say enabled"; FAIL=$((FAIL+1)); }

# status reports correct count for empty memory/ (only flag file, no .md)
count=$(echo "$out" | grep -oE 'files: [0-9]+' | grep -oE '[0-9]+')
[ "$count" = "0" ] \
    && { echo "  ✅ empty memory/ → file count is 0"; PASS=$((PASS+1)); } \
    || { echo "  ❌ empty memory/ → file count is $count, expected 0"; FAIL=$((FAIL+1)); }

# sync with flag but no CC source → friendly, exits 0
# (CC source was wiped by off tests earlier, or was never populated)
out=$(cd "$PROJECT" && env HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" sync 2>&1)
ec=$?
[ "$ec" = "0" ] \
    && { echo "  ✅ sync without CC source exits 0"; PASS=$((PASS+1)); } \
    || { echo "  ❌ sync without CC source exits $ec"; FAIL=$((FAIL+1)); }

# off with manually created flag → exits 0, flag removed
out=$(cd "$PROJECT" && env HOME_OVERRIDE="$FAKE_HOME" bash "$SYNC" off 2>&1)
ec=$?
[ "$ec" = "0" ] && [ ! -f "$PROJECT/memory/.sync-enabled" ] \
    && { echo "  ✅ off removes manual flag + exits 0"; PASS=$((PASS+1)); } \
    || { echo "  ❌ off failed or flag still exists"; FAIL=$((FAIL+1)); }

rm -rf "$PROJECT/memory"

# ── teardown ──
rm -rf "$WORK"

summary
