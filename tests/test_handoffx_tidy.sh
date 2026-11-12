#!/bin/bash
# P2.1 /handoffx-tidy schema 迁移器测试。
# Spec: docs/2026-05-21-p2-1-handoffx-tidy-migrator-plan.md Task 1。
# 注：assert_contains 签名为 (name, haystack, needle)（见 tests/common.sh + 全套件
# 既有用法），故下方调用以「描述 → 输出 → 期望片段」顺序传参（Tacit#2 repo idiom）。
source "$(dirname "$0")/common.sh"
SCRIPT="$SCRIPTS_DIR/tidy-handoff.sh"
SHIM="$ROOT_DIR/skills/handoffx/command-shims/handoffx-tidy.md"

assert_file_exists "tidy-handoff.sh 存在" "$SCRIPT"

# 1. subcommand 识别 + --help 输出
out=$("$SCRIPT" schema-upgrade --help 2>&1) || true
assert_contains "subcommand --help 自报 schema-upgrade" "$out" "schema-upgrade"
assert_contains "help 文案引用 handoffx schema" "$out" "handoffx"

# 2. command-shim 存在
assert_file_exists "handoffx-tidy shim 存在" "$SHIM"

# 3. shim 指向 schema-upgrade subcommand
assert_contains "shim 调用 subcommand" "$(cat "$SHIM")" "tidy-handoff.sh schema-upgrade"

# Task 2: dry-run on synthetic v2 fixture reports 4 rename loci, no side effects.
# Why: copy fixture out to a writable tmp before exercising preflight 的 -w 校验
# 与未来 --apply 改文件路径；fixture 树本身应保持只读源真相。
FX=$(mktemp -d)
cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FX/"
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX" 2>&1); rc=$?
assert_exit "dry-run exit 0 on v2 fixture" 0 "$rc"
assert_contains "dry-run 报 HANDOFF rename" "$out" "HANDOFF.md → HANDOFFX.md"
assert_contains "dry-run 报 Logs rename" "$out" "Handoff_Logs/ → Handoffx_Logs/"
assert_contains "dry-run 报 Decisions rename" "$out" "Handoff_Decisions/ → Handoffx_Decisions/"
assert_contains "dry-run 标 GOTCHAS LEAVE" "$out" "GOTCHAS.md: LEAVE"
# dry-run 不应改 fixture：HANDOFF.md 仍在 / Handoffx_Logs 未建
[ -f "$FX/HANDOFF.md" ] \
    && { echo "  ✅ dry-run 保持 HANDOFF.md 不动"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dry-run 删了 HANDOFF.md"; FAIL=$((FAIL+1)); }
[ ! -d "$FX/Handoffx_Logs" ] \
    && { echo "  ✅ dry-run 未建 Handoffx_Logs/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dry-run 误建了 Handoffx_Logs/"; FAIL=$((FAIL+1)); }
rm -rf "$FX"

# Idempotency: already-handoffx tree → no-op
FX2=$(mktemp -d)
mkdir -p "$FX2/Handoffx_Logs" "$FX2/Handoffx_Decisions"
echo '<!-- HANDOFFX v3 schema -->' > "$FX2/HANDOFFX.md"
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX2" 2>&1); rc=$?
assert_exit "已 handoffx schema dry-run exit 0" 0 "$rc"
assert_contains "幂等：已 handoffx 报 no-op" "$out" "no-op"
rm -rf "$FX2"

# UNKNOWN schema (空目录 / 无 v2 marker) → 显式拒绝（区别于 preflight fail）
FX3=$(mktemp -d)
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX3" 2>&1); rc=$?
assert_exit "空目录 → UNKNOWN exit 1" 1 "$rc"
assert_contains "UNKNOWN 错误自报 v2 marker 缺失" "$out" "does not contain a v2 handoff schema"
rm -rf "$FX3"

# M1 自校验：unknown arg 给出独立错误（区别于 preflight 的 1）
out=$("$SCRIPT" schema-upgrade --bogus 2>&1); rc=$?
assert_exit "unknown arg exit 1" 1 "$rc"
assert_contains "unknown arg 错误自报" "$out" "unknown arg"

# Task 3: apply on synthetic fixture → HANDOFFX.md + Handoffx_*/ all created, source removed
FXA=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FXA/"
out=$("$SCRIPT" schema-upgrade --apply --root "$FXA" 2>&1); rc=$?
assert_exit "apply on v2 fixture exit 0" 0 "$rc"
[ -f "$FXA/HANDOFFX.md" ] \
    && { echo "  ✅ HANDOFFX.md present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md missing after apply"; FAIL=$((FAIL+1)); }
[ -d "$FXA/Handoffx_Logs" ] \
    && { echo "  ✅ Handoffx_Logs/ present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Handoffx_Logs/ missing"; FAIL=$((FAIL+1)); }
[ -d "$FXA/Handoffx_Decisions" ] \
    && { echo "  ✅ Handoffx_Decisions/ present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Handoffx_Decisions/ missing"; FAIL=$((FAIL+1)); }
[ ! -f "$FXA/HANDOFF.md" ] \
    && { echo "  ✅ source HANDOFF.md removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source HANDOFF.md leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$FXA/Handoff_Logs" ] \
    && { echo "  ✅ source Handoff_Logs/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source Handoff_Logs/ leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$FXA/Handoff_Decisions" ] \
    && { echo "  ✅ source Handoff_Decisions/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source Handoff_Decisions/ leaked"; FAIL=$((FAIL+1)); }
[ ! -e "$FXA/HANDOFFX.md.partial" ] && [ ! -e "$FXA/Handoffx_Logs.partial" ] && [ ! -e "$FXA/Handoffx_Decisions.partial" ] \
    && { echo "  ✅ no .partial residue after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ .partial residue after apply"; FAIL=$((FAIL+1)); }
rm -rf "$FXA"

# Task 3: rollback on injected preflight collision → sources intact, no half-migration.
# Why: preflight is the first failure-injection vector — pre-existing target dir trips
# `target ... already exists` check before migrate_apply enters, so the EXIT trap is
# never installed and the verbatim-fixture sources stay put. This also doubles as
# the "preflight fail does NOT trigger spurious rollback" assertion (trap not yet armed).
FXB=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FXB/"
mkdir -p "$FXB/Handoffx_Decisions"; touch "$FXB/Handoffx_Decisions/_collision"
out=$("$SCRIPT" schema-upgrade --apply --root "$FXB" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ rollback: collision exit non-zero"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: collision should exit non-zero"; FAIL=$((FAIL+1)); }
[ -f "$FXB/HANDOFF.md" ] \
    && { echo "  ✅ rollback: source HANDOFF.md preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: source HANDOFF.md missing"; FAIL=$((FAIL+1)); }
[ -d "$FXB/Handoff_Logs" ] \
    && { echo "  ✅ rollback: source Handoff_Logs/ preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: source Handoff_Logs/ missing"; FAIL=$((FAIL+1)); }
[ ! -f "$FXB/HANDOFFX.md" ] \
    && { echo "  ✅ rollback: no half-migrated HANDOFFX.md"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: HANDOFFX.md leaked"; FAIL=$((FAIL+1)); }
[ ! -e "$FXB/HANDOFFX.md.partial" ] && [ ! -e "$FXB/Handoffx_Logs.partial" ] \
    && { echo "  ✅ rollback: no .partial residue"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: .partial residue"; FAIL=$((FAIL+1)); }
rm -rf "$FXB"

# HIGH-D (2026-06-07 audit): 真实 mid-migration 失败注入 → 验 EXIT-trap pre-commit
# 回滚这条关键路径。上一块（preflight collision）走 preflight 拒绝——trap 从未安装
# （注释自陈），覆盖不到 migrate_apply 内 cp/mv 中途失败的回滚。此前该路径零
# load-bearing 覆盖：把整个 pre-commit 回滚换成 return 0 旧测试仍全绿（Gotcha #25）。
# 注入手段：令 Handoff_Logs 内一个文件不可读 → migrate_apply 的 `cp -r Handoff_Logs`
# 失败 return 2 → trap 触发。root(EUID=0) 绕权限位，skip（Gotcha #15 / B7-a 范式）。
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ HIGH-D mid-migration rollback: skipped on root（chmod 不约束 root，Gotcha #15）"
else
    FXR=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FXR/"
    chmod 000 "$FXR/Handoff_Logs/0001-2026-04-20T0000-foo.md"
    out=$("$SCRIPT" schema-upgrade --apply --root "$FXR" 2>&1); rc=$?
    chmod 644 "$FXR/Handoff_Logs/0001-2026-04-20T0000-foo.md" 2>/dev/null  # 复权便于断言/清理
    [ "$rc" -eq 2 ] \
        && { echo "  ✅ HIGH-D: cp 中途失败 → exit 2（trap 回滚路径触发）"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 期望 exit 2 得 $rc"; FAIL=$((FAIL+1)); }
    # 源四件套完整保留（cp 非 mv → 回滚不丢源）
    { [ -f "$FXR/HANDOFF.md" ] && [ -d "$FXR/Handoff_Logs" ] && [ -d "$FXR/Handoff_Decisions" ] && [ -f "$FXR/GOTCHAS.md" ]; } \
        && { echo "  ✅ HIGH-D: 源四件套完整保留"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 源被破坏"; FAIL=$((FAIL+1)); }
    # 半建目标 + 全部 .partial 被 trap 清除（无残留——HIGH-C 诚实回滚的实证）
    { [ ! -e "$FXR/HANDOFFX.md" ] && [ ! -e "$FXR/Handoffx_Logs" ] && [ ! -e "$FXR/Handoffx_Decisions" ] \
        && [ ! -e "$FXR/HANDOFFX.md.partial" ] && [ ! -e "$FXR/Handoffx_Logs.partial" ] \
        && [ ! -e "$FXR/Handoffx_Decisions.partial" ] && [ ! -e "$FXR/GOTCHAS.md.partial" ]; } \
        && { echo "  ✅ HIGH-D: 半建目标 + .partial 全清，无残留"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 回滚后有半建/.partial 残留"; FAIL=$((FAIL+1)); }
    # 回滚消息诚实（clean rollback 文案，非「迁移成功」）
    echo "$out" | grep -qF "rolled back" \
        && { echo "  ✅ HIGH-D: 回滚消息诚实声明 rolled back"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 回滚消息缺失 rolled back"; FAIL=$((FAIL+1)); }
    rm -rf "$FXR"
fi

# Task 4: apply with full .md sweep → 所有 .partial 内字面路径串改写为 handoffx 形态。
# Q2 全扫范围（Boss 2026-05-21 拍板）：HANDOFFX.md prose + Handoffx_Logs/*.md +
# Handoffx_Decisions/*.md 全部覆盖；GOTCHAS.md（ADR-0005 LEAVE）保留原名。
FX5=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FX5/"
"$SCRIPT" schema-upgrade --apply --root "$FX5" >/dev/null 2>&1
[ -f "$FX5/HANDOFFX.md" ] \
    && { echo "  ✅ Task4 happy: HANDOFFX.md present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Task4 happy: HANDOFFX.md missing"; FAIL=$((FAIL+1)); }
grep -q "Handoffx_Logs/0001-2026-04-20T0000-foo.md" "$FX5/HANDOFFX.md" \
    && { echo "  ✅ HANDOFFX.md prose 内 Handoffx_Logs/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md prose 漏改 Handoffx_Logs/"; FAIL=$((FAIL+1)); }
grep -q "Handoffx_Decisions/0001-2026-04-20-baz.md" "$FX5/HANDOFFX.md" \
    && { echo "  ✅ HANDOFFX.md prose 内 Handoffx_Decisions/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md prose 漏改 Handoffx_Decisions/"; FAIL=$((FAIL+1)); }
grep -q "HANDOFFX.archive.md" "$FX5/HANDOFFX.md" \
    && { echo "  ✅ HANDOFFX.md prose 内 archive 形态已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md prose 漏改 archive 形态"; FAIL=$((FAIL+1)); }
! grep -q "Handoff_Logs/" "$FX5/HANDOFFX.md" \
    && { echo "  ✅ HANDOFFX.md 无残留 Handoff_Logs/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md 仍含 Handoff_Logs/ 残留"; FAIL=$((FAIL+1)); }
! grep -q "Handoff_Decisions/" "$FX5/HANDOFFX.md" \
    && { echo "  ✅ HANDOFFX.md 无残留 Handoff_Decisions/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ HANDOFFX.md 仍含 Handoff_Decisions/ 残留"; FAIL=$((FAIL+1)); }
# Dev Log 文件内容也被扫到（Q2 全扫范围验证）
devlog_residue=0
for f in "$FX5/Handoffx_Logs/"*.md; do
    [ -r "$f" ] || { echo "  ❌ Dev Log $f 不可读，负断言无法成立"; FAIL=$((FAIL+1)); break; }
    if grep -q "Handoff_Logs/" "$f" 2>/dev/null; then
        echo "  ❌ Dev Log $f 仍含 Handoff_Logs/ 残留"; FAIL=$((FAIL+1)); devlog_residue=1; break
    fi
done
[ "$devlog_residue" = "0" ] \
    && { echo "  ✅ Dev Log 全扫干净（无 Handoff_Logs/ 残留）"; PASS=$((PASS+1)); }
# Decision 文件内容也被扫到
dec_residue=0
for f in "$FX5/Handoffx_Decisions/"*.md; do
    [ -r "$f" ] || { echo "  ❌ Decision $f 不可读，负断言无法成立"; FAIL=$((FAIL+1)); break; }
    if grep -q "Handoff_Decisions/" "$f" 2>/dev/null; then
        echo "  ❌ Decision $f 仍含 Handoff_Decisions/ 残留"; FAIL=$((FAIL+1)); dec_residue=1; break
    fi
done
[ "$dec_residue" = "0" ] \
    && { echo "  ✅ Decision 全扫干净（无 Handoff_Decisions/ 残留）"; PASS=$((PASS+1)); }
# GOTCHAS.md 保留原名（ADR-0005 LEAVE）
[ -f "$FX5/GOTCHAS.md" ] \
    && { echo "  ✅ GOTCHAS.md 原名保留（ADR-0005 LEAVE）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ GOTCHAS.md 缺失"; FAIL=$((FAIL+1)); }
rm -rf "$FX5"

# Task 5: real-repo 拷贝快照 dogfood (Gotcha #20 真产物对抗 mandate; 不动 live)
# Why: synthetic fixture 单证不够——只有真产物量级 (60 Dev Logs + 25+ Decisions +
# 真 HANDOFF.md prose + 真 GOTCHAS.md) 才能暴露 sed sweep / count drift / xref 残留
# 类母题。snapshot 至 mktemp 沙箱，live repo 永不触碰。
DOGFOOD=$(mktemp -d)
# Snapshot only the four-piece (avoid binary / unrelated big files)
cp "$ROOT_DIR/HANDOFF.md" "$DOGFOOD/"
cp "$ROOT_DIR/GOTCHAS.md" "$DOGFOOD/"
cp -r "$ROOT_DIR/Handoff_Logs" "$DOGFOOD/"
cp -r "$ROOT_DIR/Handoff_Decisions" "$DOGFOOD/"
# Sanity precondition
[ -f "$DOGFOOD/HANDOFF.md" ] \
    || { echo "  ❌ dogfood precondition: HANDOFF.md missing in snapshot"; FAIL=$((FAIL+1)); }
src_logs=$(ls "$DOGFOOD/Handoff_Logs" 2>/dev/null | wc -l | tr -d ' ')
src_dec=$(ls "$DOGFOOD/Handoff_Decisions" 2>/dev/null | wc -l | tr -d ' ')
[ "$src_logs" -gt 0 ] \
    && { echo "  ✅ dogfood precondition: $src_logs Dev Logs snapshotted"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: 0 Dev Logs in snapshot"; FAIL=$((FAIL+1)); }
[ "$src_dec" -gt 0 ] \
    && { echo "  ✅ dogfood precondition: $src_dec Decisions snapshotted"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: 0 Decisions in snapshot"; FAIL=$((FAIL+1)); }

# Apply: real-repo dogfood
out=$("$SCRIPT" schema-upgrade --apply --root "$DOGFOOD" 2>&1); rc=$?
assert_exit "real-repo dogfood --apply exit 0" 0 "$rc"

# Post-apply structural assertions
[ -f "$DOGFOOD/HANDOFFX.md" ] \
    && { echo "  ✅ dogfood: HANDOFFX.md present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: HANDOFFX.md missing"; FAIL=$((FAIL+1)); }
[ -d "$DOGFOOD/Handoffx_Logs" ] \
    && { echo "  ✅ dogfood: Handoffx_Logs/ present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Handoffx_Logs/ missing"; FAIL=$((FAIL+1)); }
[ -d "$DOGFOOD/Handoffx_Decisions" ] \
    && { echo "  ✅ dogfood: Handoffx_Decisions/ present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Handoffx_Decisions/ missing"; FAIL=$((FAIL+1)); }
[ -f "$DOGFOOD/GOTCHAS.md" ] \
    && { echo "  ✅ dogfood: GOTCHAS.md preserved (ADR-0005 LEAVE)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: GOTCHAS.md missing"; FAIL=$((FAIL+1)); }
[ ! -f "$DOGFOOD/HANDOFF.md" ] \
    && { echo "  ✅ dogfood: source HANDOFF.md removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source HANDOFF.md leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$DOGFOOD/Handoff_Logs" ] \
    && { echo "  ✅ dogfood: source Handoff_Logs/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source Handoff_Logs/ leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$DOGFOOD/Handoff_Decisions" ] \
    && { echo "  ✅ dogfood: source Handoff_Decisions/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source Handoff_Decisions/ leaked"; FAIL=$((FAIL+1)); }

# Count equivalence (no file loss)
moved_logs=$(ls "$DOGFOOD/Handoffx_Logs" 2>/dev/null | wc -l | tr -d ' ')
moved_dec=$(ls "$DOGFOOD/Handoffx_Decisions" 2>/dev/null | wc -l | tr -d ' ')
[ "$src_logs" = "$moved_logs" ] \
    && { echo "  ✅ dogfood: Dev Log count preserved ($src_logs == $moved_logs)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Dev Log count drift ($src_logs → $moved_logs)"; FAIL=$((FAIL+1)); }
[ "$src_dec" = "$moved_dec" ] \
    && { echo "  ✅ dogfood: Decision count preserved ($src_dec == $moved_dec)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Decision count drift ($src_dec → $moved_dec)"; FAIL=$((FAIL+1)); }

# Xref rewrite 完整: HANDOFFX.md 不应残留任何 Handoff_Logs/ 或 Handoff_Decisions/ 字面
! grep -qE 'Handoff_Logs/|Handoff_Decisions/' "$DOGFOOD/HANDOFFX.md" \
    && { echo "  ✅ dogfood: HANDOFFX.md no stale Handoff_*/ literal"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: HANDOFFX.md stale Handoff_*/ literal remains"; FAIL=$((FAIL+1)); }

# Dev Log content swept — 遍历全部 moved 文件（HIGH-E 2026-06-07 audit：原 head -1
# 采样恰中无字面的 0001 文件 → 假完整恒绿；真产物 13/60 Dev Log 含 Handoff_*/ 字面，
# 全遍历才 load-bearing，sweep 漏任一文件即 RED）。
dogfood_log_residue=0
for f in "$DOGFOOD/Handoffx_Logs/"*.md; do
    [ -e "$f" ] || continue
    if grep -qE 'Handoff_Logs/|Handoff_Decisions/' "$f" 2>/dev/null; then
        echo "  ❌ dogfood: Dev Log $f 仍含 stale Handoff_*/ 字面"; FAIL=$((FAIL+1)); dogfood_log_residue=1; break
    fi
done
[ "$dogfood_log_residue" = "0" ] \
    && { echo "  ✅ dogfood: 全部 Dev Log content swept clean（全遍历）"; PASS=$((PASS+1)); }
# Decision content swept — 同样全遍历
dogfood_dec_residue=0
for f in "$DOGFOOD/Handoffx_Decisions/"*.md; do
    [ -e "$f" ] || continue
    if grep -qE 'Handoff_Logs/|Handoff_Decisions/' "$f" 2>/dev/null; then
        echo "  ❌ dogfood: Decision $f 仍含 stale Handoff_*/ 字面"; FAIL=$((FAIL+1)); dogfood_dec_residue=1; break
    fi
done
[ "$dogfood_dec_residue" = "0" ] \
    && { echo "  ✅ dogfood: 全部 Decision content swept clean（全遍历）"; PASS=$((PASS+1)); }

# No .partial residue
[ ! -e "$DOGFOOD/HANDOFFX.md.partial" ] && [ ! -e "$DOGFOOD/Handoffx_Logs.partial" ] && [ ! -e "$DOGFOOD/Handoffx_Decisions.partial" ] \
    && { echo "  ✅ dogfood: no .partial residue"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: .partial residue"; FAIL=$((FAIL+1)); }

# Cleanup
rm -rf "$DOGFOOD"

# Fix E (Source 1 Important): GOTCHAS.md 文件名 LEAVE（ADR-0005），但内容里的
# 字面路径串需随 sweep 改写——Q2 拍板「全扫所有 .md」明确包含 GOTCHAS.md 内容。
# fixture 的 GOTCHAS.md 不含 Handoff_*/ 字面，测试时主动注入以验真。
FX_G=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FX_G/"
# 注入一行带 Handoff_Logs/ 与 Handoff_Decisions/ 字面的历史踩坑文本
echo "历史踩坑：见 Handoff_Logs/0001-foo.md 与 Handoff_Decisions/0001-bar.md" >> "$FX_G/GOTCHAS.md"
"$SCRIPT" schema-upgrade --apply --root "$FX_G" >/dev/null 2>&1
# 文件名仍为 GOTCHAS.md（ADR-0005 LEAVE）
[ -f "$FX_G/GOTCHAS.md" ] \
    && { echo "  ✅ Fix E: GOTCHAS.md 保留原名（ADR-0005 LEAVE）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: GOTCHAS.md missing"; FAIL=$((FAIL+1)); }
# 内容里的字面路径串已改写为 handoffx 形态
grep -qF "Handoffx_Logs/0001-foo.md" "$FX_G/GOTCHAS.md" \
    && { echo "  ✅ Fix E: GOTCHAS.md 内 Handoffx_Logs/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: GOTCHAS.md 漏改 Handoffx_Logs/"; FAIL=$((FAIL+1)); }
grep -qF "Handoffx_Decisions/0001-bar.md" "$FX_G/GOTCHAS.md" \
    && { echo "  ✅ Fix E: GOTCHAS.md 内 Handoffx_Decisions/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: GOTCHAS.md 漏改 Handoffx_Decisions/"; FAIL=$((FAIL+1)); }
# 无残留 Handoff_*/ 字面（Q2 全扫范围验证）
! grep -qE 'Handoff_Logs/|Handoff_Decisions/' "$FX_G/GOTCHAS.md" \
    && { echo "  ✅ Fix E: GOTCHAS.md 无 Handoff_*/ 残留"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: GOTCHAS.md 仍含 Handoff_*/ 残留"; FAIL=$((FAIL+1)); }
# 无 .partial 残留（cleanup 已扩展覆盖 GOTCHAS.partial）
[ ! -e "$FX_G/GOTCHAS.md.partial" ] \
    && { echo "  ✅ Fix E: 无 GOTCHAS.md.partial 残留"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: GOTCHAS.md.partial 残留"; FAIL=$((FAIL+1)); }
rm -rf "$FX_G"

# Fix A (Source 2 S2-A Critical + S2-B High): MIXED schema state — old four-piece
# 与 new handoffx 同存即 split-brain，必须 fail-loud 拒绝（不可静默 no-op）。
# 旧版只看 new-side 三件齐 → 误判 ALREADY-HANDOFFX → 数据孤儿。
FX_M=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FX_M/"
# 在 v2 fixture 顶上再撒一颗 new-side 残屑（模拟上次迁移半失败留下的目标）
mkdir -p "$FX_M/Handoffx_Logs"; touch "$FX_M/HANDOFFX.md"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX_M" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ MIXED state: refused with exit non-zero"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: should refuse but succeeded"; FAIL=$((FAIL+1)); }
echo "$out" | grep -qF -- "split-brain" \
    && { echo "  ✅ MIXED state: error message names split-brain"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: message missing 'split-brain' keyword"; FAIL=$((FAIL+1)); }
# 源 HANDOFF.md 必须未被触碰（MIXED 是 detect-only 拒绝，未进入 migrate_apply）
[ -f "$FX_M/HANDOFF.md" ] \
    && { echo "  ✅ MIXED state: source HANDOFF.md preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: source HANDOFF.md damaged"; FAIL=$((FAIL+1)); }
# new-side 残屑也未被触碰（detect 不动任何数据）
[ -f "$FX_M/HANDOFFX.md" ] \
    && { echo "  ✅ MIXED state: pre-existing HANDOFFX.md preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: HANDOFFX.md damaged"; FAIL=$((FAIL+1)); }
rm -rf "$FX_M"

# MEDIUM-G (2026-06-07 audit): detect_schema_state 计数用 [ -e ] 而非 [-f]/[-d]——
# 类型不符的同名 new 工件（HANDOFFX.md 建成目录）也须计入 has_new → 触 MIXED。
# 区分修复的 load-bearing 键 = 「split-brain」消息：旧 [-f] 漏计目录 → 落 OLD-V2 →
# preflight 报「target already exists」（亦非零但非 split-brain）；新 [-e] → MIXED。
FX_DT=$(mktemp -d); cp -r "$ROOT_DIR/tests/fixtures/p2-1-synthetic-v2/." "$FX_DT/"
mkdir -p "$FX_DT/HANDOFFX.md"; touch "$FX_DT/HANDOFFX.md/blocker"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX_DT" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ MEDIUM-G: 目录型 HANDOFFX.md → 拒绝 exit 非零"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 目录型 new 工件应拒绝但成功了"; FAIL=$((FAIL+1)); }
echo "$out" | grep -qF -- "split-brain" \
    && { echo "  ✅ MEDIUM-G: 判为 MIXED split-brain（非 OLD-V2 误迁；detect -e 计数生效）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 未判 MIXED（detect 漏计目录型工件 → -e 修复失效）"; FAIL=$((FAIL+1)); }
[ -f "$FX_DT/HANDOFF.md" ] \
    && { echo "  ✅ MEDIUM-G: 源 HANDOFF.md 未被触碰"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 源 HANDOFF.md 被破坏"; FAIL=$((FAIL+1)); }
rm -rf "$FX_DT"

# P2.2 tidy 合并（plan §4）：默认 = 结构整理；schema-upgrade 仅显式子命令。
# Why: 合并后若 schema-upgrade 混入默认流程，/handoffx-tidy 会静默迁移四件套（P2.4 前禁止）。
# 默认段 = frontmatter 之后、`## schema-upgrade` 之前的正文（frontmatter description 合法提及子命令）。
shim_default=$(awk '/^## schema-upgrade/ { exit } fm >= 2 { print } /^---$/ { fm++ }' "$SHIM")
shim_upgrade=$(awk '/^## schema-upgrade/ { on = 1 } on { print }' "$SHIM")
assert_contains "合并 shim 默认段 = 结构整理" "$shim_default" "执行**整理**流程"
assert_contains "合并 shim 默认段跑 tidy-handoff.sh HANDOFF.md" "$shim_default" "tidy-handoff.sh HANDOFF.md"
assert_contains "合并 shim 有显式 schema-upgrade 段" "$shim_upgrade" "## schema-upgrade（显式子命令，不自动触发）"
assert_contains "schema-upgrade 段声明仅显式运行" "$shim_upgrade" "仅在用户显式要求时运行；默认整理流程不会调用它"
echo "$shim_default" | grep -q 'schema-upgrade' \
    && { echo "  ❌ 默认整理段提到 schema-upgrade（不得自动触发）"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ 默认整理段不触发 schema-upgrade"; PASS=$((PASS+1)); }
echo "$shim_upgrade" | grep -qE '自动(运行|执行|迁移|调用)|automatic' \
    && { echo "  ❌ schema-upgrade 被描述为自动"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ schema-upgrade 未被描述为自动"; PASS=$((PASS+1)); }

summary
