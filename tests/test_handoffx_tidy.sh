#!/bin/bash
# P2.1 /handoffx-tidy schema 迁移器测试。
# Spec: docs/2026-05-21-p2-1-handoffx-tidy-migrator-plan.md Task 1。
# 注：assert_contains 签名为 (name, haystack, needle)（见 tests/common.sh + 全套件
# 既有用法），故下方调用以「描述 → 输出 → 期望片段」顺序传参（Tacit#2 repo idiom）。
source "$(dirname "$0")/common.sh"
SCRIPT="$SCRIPTS_DIR/tidy-handoff.sh"
SHIM="$ROOT_DIR/skills/handoffx/command-shims/handoffx-tidy.md"

assert_file_exists "tidy-handoff.sh 存在" "$SCRIPT"

# B1 (fix wave 1): the fixture ships under neutral names; p21_materialize lays
# it out under the legacy names and must fail closed on a missing piece.
PM=$(mktemp -d); mkdir "$PM/ok" "$PM/src" "$PM/bad"
p21_materialize "$PM/ok"; rc=$?
assert_exit "p21_materialize: exit 0 on the shipped fixture" 0 "$rc"
assert_exit "p21_materialize: result classifies as a v3 legacy layout" 0 "$([ "$(hx_legacy_layout_kind "$PM/ok")" = v3 ] && [ -f "$PM/ok/$HX_GOTCHAS_FILE" ] && echo 0 || echo 1)"
cp -R "$FIXTURES_DIR/p2-1-synthetic-v2/." "$PM/src/"; rm -rf "$PM/src/legacy-logs"
rc=0; out=$(p21_materialize "$PM/bad" "$PM/src" 2>&1) || rc=$?
assert_exit "p21_materialize: missing source piece → return 1" 1 "$rc"
assert_contains "p21_materialize: names the missing piece" "$out" "fixture piece missing: $PM/src/legacy-logs"
assert_exit "p21_materialize: nothing written on refusal" 0 "$([ -z "$(ls -A "$PM/bad")" ] && echo 0 || echo 1)"
rm -rf "$PM"

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
p21_materialize "$FX" || FAIL=$((FAIL+1))
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX" 2>&1); rc=$?
assert_exit "dry-run exit 0 on v2 fixture" 0 "$rc"
assert_contains "dry-run 报 HANDOFF rename" "$out" "${HX_LEGACY_MAIN_FILE} → ${HX_MAIN_FILE}"
assert_contains "dry-run 报 Logs rename" "$out" "${HX_LEGACY_LOGS_DIR}/ → ${HX_LOGS_DIR}/"
assert_contains "dry-run 报 Decisions rename" "$out" "${HX_LEGACY_DEC_DIR}/ → ${HX_DEC_DIR}/"
assert_contains "dry-run 标 GOTCHAS LEAVE" "$out" "${HX_GOTCHAS_FILE}: LEAVE"
# dry-run 不应改 fixture：${HX_LEGACY_MAIN_FILE} 仍在 / ${HX_LOGS_DIR} 未建
[ -f "$FX/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ dry-run 保持 ${HX_LEGACY_MAIN_FILE} 不动"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dry-run 删了 ${HX_LEGACY_MAIN_FILE}"; FAIL=$((FAIL+1)); }
[ ! -d "$FX/${HX_LOGS_DIR}" ] \
    && { echo "  ✅ dry-run 未建 ${HX_LOGS_DIR}/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dry-run 误建了 ${HX_LOGS_DIR}/"; FAIL=$((FAIL+1)); }
rm -rf "$FX"

# Idempotency: already-handoffx tree → no-op
FX2=$(mktemp -d)
mkdir -p "$FX2/${HX_LOGS_DIR}" "$FX2/${HX_DEC_DIR}"
echo '<!-- HANDOFFX v3 schema -->' > "$FX2/${HX_MAIN_FILE}"; : > "$FX2/${HX_GOTCHAS_FILE}"
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX2" 2>&1); rc=$?
assert_exit "已 handoffx schema dry-run exit 0" 0 "$rc"
assert_contains "幂等：已 handoffx 报 no-op" "$out" "no-op"
rm -rf "$FX2"

# UNKNOWN schema (空目录 / 无 v2 marker) → 显式拒绝（区别于 preflight fail）
# P2.4 三态：旧 = $HX_LEGACY_*，新 = $HX_*。常量翻转后若迁移器仍从 $HX_* 派生旧名，
# 这三态会全错（ALREADY-HANDOFFX 读成 UNKNOWN / 新旧并存漏判 MIXED）。直接调用
# detect_schema_state，断言精确状态字而非间接的 exit code。
detect_on() { ( . "$SCRIPTS_DIR/lib/handoffx-tidy-migrate.sh" && detect_schema_state "$1" ); }
FX_S=$(mktemp -d); p21_materialize "$FX_S" || FAIL=$((FAIL+1))
st=$(detect_on "$FX_S")
assert_exit "三态: legacy 四件套 → OLD-V2 [got: $st]" 0 "$([ "$st" = "OLD-V2" ] && echo 0 || echo 1)"
mkdir -p "$FX_S/$HX_LOGS_DIR"
st=$(detect_on "$FX_S")
assert_exit "三态: $HX_LEGACY_LOGS_DIR 与 $HX_LOGS_DIR 并存 → MIXED [got: $st]" 0 "$([ "$st" = "MIXED" ] && echo 0 || echo 1)"
rm -rf "$FX_S"
FX_S=$(mktemp -d); mkdir -p "$FX_S/$HX_LOGS_DIR" "$FX_S/$HX_DEC_DIR"; : > "$FX_S/$HX_MAIN_FILE"; : > "$FX_S/$HX_GOTCHAS_FILE"
st=$(detect_on "$FX_S")
assert_exit "三态: 新名四件 → ALREADY-HANDOFFX [got: $st]" 0 "$([ "$st" = "ALREADY-HANDOFFX" ] && echo 0 || echo 1)"
rm -rf "$FX_S"
# fix wave 2 (Codex N1): "already migrated" is a claim about usable pieces, not
# about names merely present — a dangling new main beside two dirs used to be
# reported as an idempotent no-op (rc 0). Odd or incomplete new-only trees are
# UNKNOWN, refused, and the message names the odd entry.
for kind in dangling-main main-is-dir logs-is-file no-gotchas; do
    FX_S=$(mktemp -d); mkdir -p "$FX_S/$HX_LOGS_DIR" "$FX_S/$HX_DEC_DIR"; : > "$FX_S/$HX_MAIN_FILE"; : > "$FX_S/$HX_GOTCHAS_FILE"
    case "$kind" in
        dangling-main) rm -f "$FX_S/$HX_MAIN_FILE"; ln -s "$FX_S/nowhere" "$FX_S/$HX_MAIN_FILE"; odd="$HX_MAIN_FILE" ;;
        main-is-dir)   rm -f "$FX_S/$HX_MAIN_FILE"; mkdir "$FX_S/$HX_MAIN_FILE"; odd="$HX_MAIN_FILE" ;;
        logs-is-file)  rmdir "$FX_S/$HX_LOGS_DIR"; : > "$FX_S/$HX_LOGS_DIR"; odd="$HX_LOGS_DIR" ;;
        no-gotchas)    rm -f "$FX_S/$HX_GOTCHAS_FILE"; odd="$HX_GOTCHAS_FILE" ;;
    esac
    st=$(detect_on "$FX_S")
    assert_exit "N1[$kind]: not ALREADY-HANDOFFX [got: $st]" 0 "$([ "$st" != "ALREADY-HANDOFFX" ] && echo 0 || echo 1)"
    rc=0; out=$("$SCRIPT" schema-upgrade --apply --root "$FX_S" 2>&1) || rc=$?
    assert_exit "N1[$kind]: schema-upgrade refuses (rc 1)" 1 "$rc"
    assert_contains "N1[$kind]: names the odd entry" "$out" "$odd"
    assert_not_contains "N1[$kind]: never reports an idempotent no-op" "$out" "no-op"
    rm -rf "$FX_S"
done
FX3=$(mktemp -d)
out=$("$SCRIPT" schema-upgrade --dry-run --root "$FX3" 2>&1); rc=$?
assert_exit "空目录 → UNKNOWN exit 1" 1 "$rc"
assert_contains "UNKNOWN 错误自报 v2 marker 缺失" "$out" "does not contain a v2 handoff schema"
rm -rf "$FX3"

# M1 自校验：unknown arg 给出独立错误（区别于 preflight 的 1）
out=$("$SCRIPT" schema-upgrade --bogus 2>&1); rc=$?
assert_exit "unknown arg exit 1" 1 "$rc"
assert_contains "unknown arg 错误自报" "$out" "unknown arg"

# Task 3: apply on synthetic fixture → ${HX_MAIN_FILE} + Handoffx_*/ all created, source removed
FXA=$(mktemp -d); p21_materialize "$FXA" || FAIL=$((FAIL+1))
out=$("$SCRIPT" schema-upgrade --apply --root "$FXA" 2>&1); rc=$?
assert_exit "apply on v2 fixture exit 0" 0 "$rc"
[ -f "$FXA/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ ${HX_MAIN_FILE} present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} missing after apply"; FAIL=$((FAIL+1)); }
[ -d "$FXA/${HX_LOGS_DIR}" ] \
    && { echo "  ✅ ${HX_LOGS_DIR}/ present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_LOGS_DIR}/ missing"; FAIL=$((FAIL+1)); }
[ -d "$FXA/${HX_DEC_DIR}" ] \
    && { echo "  ✅ ${HX_DEC_DIR}/ present after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_DEC_DIR}/ missing"; FAIL=$((FAIL+1)); }
[ ! -f "$FXA/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ source ${HX_LEGACY_MAIN_FILE} removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source ${HX_LEGACY_MAIN_FILE} leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$FXA/${HX_LEGACY_LOGS_DIR}" ] \
    && { echo "  ✅ source ${HX_LEGACY_LOGS_DIR}/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source ${HX_LEGACY_LOGS_DIR}/ leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$FXA/${HX_LEGACY_DEC_DIR}" ] \
    && { echo "  ✅ source ${HX_LEGACY_DEC_DIR}/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ source ${HX_LEGACY_DEC_DIR}/ leaked"; FAIL=$((FAIL+1)); }
[ ! -e "$FXA/${HX_MAIN_FILE}.partial" ] && [ ! -e "$FXA/${HX_LOGS_DIR}.partial" ] && [ ! -e "$FXA/${HX_DEC_DIR}.partial" ] \
    && { echo "  ✅ no .partial residue after apply"; PASS=$((PASS+1)); } \
    || { echo "  ❌ .partial residue after apply"; FAIL=$((FAIL+1)); }
rm -rf "$FXA"

# Task 3: rollback on injected preflight collision → sources intact, no half-migration.
# Why: preflight is the first failure-injection vector — pre-existing target dir trips
# `target ... already exists` check before migrate_apply enters, so the EXIT trap is
# never installed and the verbatim-fixture sources stay put. This also doubles as
# the "preflight fail does NOT trigger spurious rollback" assertion (trap not yet armed).
FXB=$(mktemp -d); p21_materialize "$FXB" || FAIL=$((FAIL+1))
mkdir -p "$FXB/${HX_DEC_DIR}"; touch "$FXB/${HX_DEC_DIR}/_collision"
out=$("$SCRIPT" schema-upgrade --apply --root "$FXB" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ rollback: collision exit non-zero"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: collision should exit non-zero"; FAIL=$((FAIL+1)); }
[ -f "$FXB/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ rollback: source ${HX_LEGACY_MAIN_FILE} preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: source ${HX_LEGACY_MAIN_FILE} missing"; FAIL=$((FAIL+1)); }
[ -d "$FXB/${HX_LEGACY_LOGS_DIR}" ] \
    && { echo "  ✅ rollback: source ${HX_LEGACY_LOGS_DIR}/ preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: source ${HX_LEGACY_LOGS_DIR}/ missing"; FAIL=$((FAIL+1)); }
[ ! -f "$FXB/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ rollback: no half-migrated ${HX_MAIN_FILE}"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: ${HX_MAIN_FILE} leaked"; FAIL=$((FAIL+1)); }
[ ! -e "$FXB/${HX_MAIN_FILE}.partial" ] && [ ! -e "$FXB/${HX_LOGS_DIR}.partial" ] \
    && { echo "  ✅ rollback: no .partial residue"; PASS=$((PASS+1)); } \
    || { echo "  ❌ rollback: .partial residue"; FAIL=$((FAIL+1)); }
rm -rf "$FXB"

# HIGH-D (2026-06-07 audit): 真实 mid-migration 失败注入 → 验 EXIT-trap pre-commit
# 回滚这条关键路径。上一块（preflight collision）走 preflight 拒绝——trap 从未安装
# （注释自陈），覆盖不到 migrate_apply 内 cp/mv 中途失败的回滚。此前该路径零
# load-bearing 覆盖：把整个 pre-commit 回滚换成 return 0 旧测试仍全绿（Gotcha #25）。
# 注入手段：令 ${HX_LEGACY_LOGS_DIR} 内一个文件不可读 → migrate_apply 的 `cp -r ${HX_LEGACY_LOGS_DIR}`
# 失败 return 2 → trap 触发。root(EUID=0) 绕权限位，skip（Gotcha #15 / B7-a 范式）。
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ HIGH-D mid-migration rollback: skipped on root（chmod 不约束 root，Gotcha #15）"
else
    FXR=$(mktemp -d); p21_materialize "$FXR" || FAIL=$((FAIL+1))
    chmod 000 "$FXR/${HX_LEGACY_LOGS_DIR}/0001-2026-04-20T0000-foo.md"
    out=$("$SCRIPT" schema-upgrade --apply --root "$FXR" 2>&1); rc=$?
    chmod 644 "$FXR/${HX_LEGACY_LOGS_DIR}/0001-2026-04-20T0000-foo.md" 2>/dev/null  # 复权便于断言/清理
    [ "$rc" -eq 2 ] \
        && { echo "  ✅ HIGH-D: cp 中途失败 → exit 2（trap 回滚路径触发）"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 期望 exit 2 得 $rc"; FAIL=$((FAIL+1)); }
    # 源四件套完整保留（cp 非 mv → 回滚不丢源）
    { [ -f "$FXR/${HX_LEGACY_MAIN_FILE}" ] && [ -d "$FXR/${HX_LEGACY_LOGS_DIR}" ] && [ -d "$FXR/${HX_LEGACY_DEC_DIR}" ] && [ -f "$FXR/${HX_GOTCHAS_FILE}" ]; } \
        && { echo "  ✅ HIGH-D: 源四件套完整保留"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 源被破坏"; FAIL=$((FAIL+1)); }
    # 半建目标 + 全部 .partial 被 trap 清除（无残留——HIGH-C 诚实回滚的实证）
    { [ ! -e "$FXR/${HX_MAIN_FILE}" ] && [ ! -e "$FXR/${HX_LOGS_DIR}" ] && [ ! -e "$FXR/${HX_DEC_DIR}" ] \
        && [ ! -e "$FXR/${HX_MAIN_FILE}.partial" ] && [ ! -e "$FXR/${HX_LOGS_DIR}.partial" ] \
        && [ ! -e "$FXR/${HX_DEC_DIR}.partial" ] && [ ! -e "$FXR/${HX_GOTCHAS_FILE}.partial" ]; } \
        && { echo "  ✅ HIGH-D: 半建目标 + .partial 全清，无残留"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 回滚后有半建/.partial 残留"; FAIL=$((FAIL+1)); }
    # 回滚消息诚实（clean rollback 文案，非「迁移成功」）
    echo "$out" | grep -qF "rolled back" \
        && { echo "  ✅ HIGH-D: 回滚消息诚实声明 rolled back"; PASS=$((PASS+1)); } \
        || { echo "  ❌ HIGH-D: 回滚消息缺失 rolled back"; FAIL=$((FAIL+1)); }
    rm -rf "$FXR"
fi

# Task 4: apply with full .md sweep → 所有 .partial 内字面路径串改写为 handoffx 形态。
# Q2 全扫范围（Boss 2026-05-21 拍板）：${HX_MAIN_FILE} prose + ${HX_LOGS_DIR}/*.md +
# ${HX_DEC_DIR}/*.md 全部覆盖；${HX_GOTCHAS_FILE}（ADR-0005 LEAVE）保留原名。
FX5=$(mktemp -d); p21_materialize "$FX5" || FAIL=$((FAIL+1))
"$SCRIPT" schema-upgrade --apply --root "$FX5" >/dev/null 2>&1
[ -f "$FX5/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ Task4 happy: ${HX_MAIN_FILE} present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Task4 happy: ${HX_MAIN_FILE} missing"; FAIL=$((FAIL+1)); }
grep -q "${HX_LOGS_DIR}/0001-2026-04-20T0000-foo.md" "$FX5/${HX_MAIN_FILE}" \
    && { echo "  ✅ ${HX_MAIN_FILE} prose 内 ${HX_LOGS_DIR}/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} prose 漏改 ${HX_LOGS_DIR}/"; FAIL=$((FAIL+1)); }
grep -q "${HX_DEC_DIR}/0001-2026-04-20-baz.md" "$FX5/${HX_MAIN_FILE}" \
    && { echo "  ✅ ${HX_MAIN_FILE} prose 内 ${HX_DEC_DIR}/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} prose 漏改 ${HX_DEC_DIR}/"; FAIL=$((FAIL+1)); }
grep -q "${HX_MAIN_FILE%.md}.archive.md" "$FX5/${HX_MAIN_FILE}" \
    && { echo "  ✅ ${HX_MAIN_FILE} prose 内 archive 形态已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} prose 漏改 archive 形态"; FAIL=$((FAIL+1)); }
! grep -q "${HX_LEGACY_LOGS_DIR}/" "$FX5/${HX_MAIN_FILE}" \
    && { echo "  ✅ ${HX_MAIN_FILE} 无残留 ${HX_LEGACY_LOGS_DIR}/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} 仍含 ${HX_LEGACY_LOGS_DIR}/ 残留"; FAIL=$((FAIL+1)); }
! grep -q "${HX_LEGACY_DEC_DIR}/" "$FX5/${HX_MAIN_FILE}" \
    && { echo "  ✅ ${HX_MAIN_FILE} 无残留 ${HX_LEGACY_DEC_DIR}/"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_MAIN_FILE} 仍含 ${HX_LEGACY_DEC_DIR}/ 残留"; FAIL=$((FAIL+1)); }
# Dev Log 文件内容也被扫到（Q2 全扫范围验证）
devlog_residue=0
for f in "$FX5/${HX_LOGS_DIR}/"*.md; do
    [ -r "$f" ] || { echo "  ❌ Dev Log $f 不可读，负断言无法成立"; FAIL=$((FAIL+1)); break; }
    if grep -q "${HX_LEGACY_LOGS_DIR}/" "$f" 2>/dev/null; then
        echo "  ❌ Dev Log $f 仍含 ${HX_LEGACY_LOGS_DIR}/ 残留"; FAIL=$((FAIL+1)); devlog_residue=1; break
    fi
done
[ "$devlog_residue" = "0" ] \
    && { echo "  ✅ Dev Log 全扫干净（无 ${HX_LEGACY_LOGS_DIR}/ 残留）"; PASS=$((PASS+1)); }
# Decision 文件内容也被扫到
dec_residue=0
for f in "$FX5/${HX_DEC_DIR}/"*.md; do
    [ -r "$f" ] || { echo "  ❌ Decision $f 不可读，负断言无法成立"; FAIL=$((FAIL+1)); break; }
    if grep -q "${HX_LEGACY_DEC_DIR}/" "$f" 2>/dev/null; then
        echo "  ❌ Decision $f 仍含 ${HX_LEGACY_DEC_DIR}/ 残留"; FAIL=$((FAIL+1)); dec_residue=1; break
    fi
done
[ "$dec_residue" = "0" ] \
    && { echo "  ✅ Decision 全扫干净（无 ${HX_LEGACY_DEC_DIR}/ 残留）"; PASS=$((PASS+1)); }
# ${HX_GOTCHAS_FILE} 保留原名（ADR-0005 LEAVE）
[ -f "$FX5/${HX_GOTCHAS_FILE}" ] \
    && { echo "  ✅ ${HX_GOTCHAS_FILE} 原名保留（ADR-0005 LEAVE）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ ${HX_GOTCHAS_FILE} 缺失"; FAIL=$((FAIL+1)); }
rm -rf "$FX5"

# Task 5: real-repo 拷贝快照 dogfood (Gotcha #20 真产物对抗 mandate; 不动 live)
# Why: synthetic fixture 单证不够——只有真产物量级 (60 Dev Logs + 25+ Decisions +
# 真主文件 prose + 真 ${HX_GOTCHAS_FILE}) 才能暴露 sed sweep / count drift / xref 残留
# 类母题。snapshot 至 mktemp 沙箱，live repo 永不触碰。
#
# P2.4 (design §4b-5)：活仓自迁移之后不再有旧布局可拷，迁移器却仍是所有 v3 用户的
# 升级路径——故按存在性二选一：活仓仍旧名 → 直接拷；活仓已新名 → 反向合成旧布局
# （改名 + 反向改写内容）。反向合成只在自迁移后才会走到，所以下面先用小型合成新布局
# 单测它，免得它第一次真跑就是在自迁移之后。

# reverse_synthesize_legacy <src-root> <dst-dir> — copy a NEW-layout four-piece
# into <dst-dir> under the legacy names and rewrite new-name path strings back
# to legacy ones (the inverse of the migrator's content sweep). Only the four
# pieces are rewritten; anything else in <dst-dir> is left alone.
reverse_synthesize_legacy() {
    local src="$1" dst="$2" f
    cp "$src/$HX_MAIN_FILE" "$dst/$HX_LEGACY_MAIN_FILE" || return 1
    cp "$src/$HX_GOTCHAS_FILE" "$dst/$HX_GOTCHAS_FILE" || return 1
    cp -r "$src/$HX_LOGS_DIR" "$dst/$HX_LEGACY_LOGS_DIR" || return 1
    cp -r "$src/$HX_DEC_DIR" "$dst/$HX_LEGACY_DEC_DIR" || return 1
    local arc_new_re="${HX_MAIN_FILE%.md}" main_new_re="${HX_MAIN_FILE//./\\.}"
    arc_new_re="${arc_new_re}\\.archive\\.md"
    while IFS= read -r -d '' f; do
        sed -e "s|${arc_new_re}|${HX_LEGACY_MAIN_FILE%.md}.archive.md|g" \
            -e "s|${HX_LOGS_DIR}/|${HX_LEGACY_LOGS_DIR}/|g" \
            -e "s|${HX_DEC_DIR}/|${HX_LEGACY_DEC_DIR}/|g" \
            -e "s|${main_new_re}|${HX_LEGACY_MAIN_FILE}|g" \
            "$f" > "$f.rev.tmp" && mv "$f.rev.tmp" "$f" || return 1
    done < <(find "$dst/$HX_LEGACY_MAIN_FILE" "$dst/$HX_GOTCHAS_FILE" "$dst/$HX_LEGACY_LOGS_DIR" "$dst/$HX_LEGACY_DEC_DIR" -type f -name '*.md' -print0)
}

# has_new_refs / has_legacy_refs <files…> — path-string probes shared by the
# helper unit test and the dogfood run.
has_new_refs()    { grep -qE "${HX_LOGS_DIR}/|${HX_DEC_DIR}/|${HX_MAIN_FILE//./\\.}" "$@" 2>/dev/null; }
has_legacy_refs() { grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/|${HX_LEGACY_MAIN_FILE//./\\.}" "$@" 2>/dev/null; }

# Helper unit test on a tiny synthetic NEW-layout tree (under tests/.tmp).
RS="$TMP_DIR/rev-synth-$$"; rm -rf "$RS"; mkdir -p "$RS/src/$HX_LOGS_DIR" "$RS/src/$HX_DEC_DIR" "$RS/dst"
printf '<!-- HANDOFF v2 schema -->\nsee %s/0001-x.md, %s/0001-y.md, %s and %s\n' \
    "$HX_LOGS_DIR" "$HX_DEC_DIR" "${HX_MAIN_FILE%.md}.archive.md" "$HX_MAIN_FILE" > "$RS/src/$HX_MAIN_FILE"
printf 'log refs %s/0001-y.md\n' "$HX_DEC_DIR" > "$RS/src/$HX_LOGS_DIR/0001-x.md"
printf 'dec refs %s/0001-x.md\n' "$HX_LOGS_DIR" > "$RS/src/$HX_DEC_DIR/0001-y.md"
printf 'gotcha refs %s/0001-x.md\n' "$HX_LOGS_DIR" > "$RS/src/$HX_GOTCHAS_FILE"
printf 'sentinel names %s/ and %s\n' "$HX_LOGS_DIR" "$HX_MAIN_FILE" > "$RS/dst/SENTINEL.md"
cp "$RS/dst/SENTINEL.md" "$RS/sentinel.orig"
reverse_synthesize_legacy "$RS/src" "$RS/dst"; rc=$?
assert_exit "reverse-synth: helper exit 0" 0 "$rc"
{ [ -f "$RS/dst/$HX_LEGACY_MAIN_FILE" ] && [ -d "$RS/dst/$HX_LEGACY_LOGS_DIR" ] && [ -d "$RS/dst/$HX_LEGACY_DEC_DIR" ] && [ -f "$RS/dst/$HX_GOTCHAS_FILE" ] \
  && [ ! -e "$RS/dst/$HX_MAIN_FILE" ] && [ ! -e "$RS/dst/$HX_LOGS_DIR" ] && [ ! -e "$RS/dst/$HX_DEC_DIR" ]; } \
    && { echo "  ✅ reverse-synth: snapshot carries only the legacy names"; PASS=$((PASS+1)); } \
    || { echo "  ❌ reverse-synth: legacy names missing or new names present"; FAIL=$((FAIL+1)); }
rs_pieces="$RS/dst/$HX_LEGACY_MAIN_FILE $RS/dst/$HX_GOTCHAS_FILE $RS/dst/$HX_LEGACY_LOGS_DIR/0001-x.md $RS/dst/$HX_LEGACY_DEC_DIR/0001-y.md"
# shellcheck disable=SC2086
{ has_legacy_refs $rs_pieces && ! has_new_refs $rs_pieces; } \
    && { echo "  ✅ reverse-synth: content rewritten to legacy references"; PASS=$((PASS+1)); } \
    || { echo "  ❌ reverse-synth: content still holds new-name references"; FAIL=$((FAIL+1)); }
grep -qF "${HX_LEGACY_MAIN_FILE%.md}.archive.md" "$RS/dst/$HX_LEGACY_MAIN_FILE" \
    && { echo "  ✅ reverse-synth: archive form reversed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ reverse-synth: archive form not reversed"; FAIL=$((FAIL+1)); }
cmp -s "$RS/sentinel.orig" "$RS/dst/SENTINEL.md" \
    && { echo "  ✅ reverse-synth: non-four-piece sentinel untouched"; PASS=$((PASS+1)); } \
    || { echo "  ❌ reverse-synth: sentinel was rewritten"; FAIL=$((FAIL+1)); }
rm -rf "$RS"

DOGFOOD=$(mktemp -d)
# Dogfood source root. Test-only override HANDOFFX_TEST_DOGFOOD_ROOT lets each
# branch below be exercised on demand; normally it is the live tree.
DF_SRC="${HANDOFFX_TEST_DOGFOOD_ROOT:-$ROOT_DIR}"
# D2 (fix wave 1): a complete layout of either kind is the real corpus; the
# synthetic fallback is taken ONLY when no piece of either layout exists. A
# partial or mixed source is ❌ and the dogfood body is skipped — falling back
# there ran an all-green migration on the small corpus and hid the damaged real
# one this dogfood exists to catch.
df_leg=$(_hx_present "$DF_SRC" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR")
df_new=$(_hx_present "$DF_SRC" "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR")
# The gotchas file belongs to both layouts (fix wave 2, Codex N2): a complete
# layout needs it, and its presence alone rules the "no corpus" fallback out.
df_got=$(_hx_present "$DF_SRC" "$HX_GOTCHAS_FILE")
DF_OK=1
# Snapshot only the four-piece (avoid binary / unrelated big files)
if [ -n "$df_leg" ] && [ -n "$df_new" ]; then
    echo "  ❌ dogfood: source holds a partial or mixed layout (legacy [$df_leg ] new [$df_new ] gotchas [$df_got ]) in $DF_SRC — refusing the synthetic fallback"
    FAIL=$((FAIL+1)); DF_OK=0
elif [ -f "$DF_SRC/$HX_LEGACY_MAIN_FILE" ] && [ -d "$DF_SRC/$HX_LEGACY_LOGS_DIR" ] && [ -d "$DF_SRC/$HX_LEGACY_DEC_DIR" ] && [ -f "$DF_SRC/$HX_GOTCHAS_FILE" ]; then
    echo "  ℹ️  dogfood: live tree still legacy-named → direct copy"
    cp "$DF_SRC/${HX_LEGACY_MAIN_FILE}" "$DOGFOOD/"
    cp "$DF_SRC/${HX_GOTCHAS_FILE}" "$DOGFOOD/"
    cp -r "$DF_SRC/${HX_LEGACY_LOGS_DIR}" "$DOGFOOD/"
    cp -r "$DF_SRC/${HX_LEGACY_DEC_DIR}" "$DOGFOOD/"
elif [ -f "$DF_SRC/$HX_MAIN_FILE" ] && [ -d "$DF_SRC/$HX_LOGS_DIR" ] && [ -d "$DF_SRC/$HX_DEC_DIR" ] && [ -f "$DF_SRC/$HX_GOTCHAS_FILE" ]; then
    echo "  ℹ️  dogfood: live tree already new-named → reverse-synthesized legacy snapshot"
    reverse_synthesize_legacy "$DF_SRC" "$DOGFOOD" \
        || { echo "  ❌ dogfood: reverse synthesis failed"; FAIL=$((FAIL+1)); }
elif [ -z "$df_leg" ] && [ -z "$df_new" ] && [ -z "$df_got" ]; then
    # Neither layout (e.g. an extracted package without the project's own
    # four-piece): still run a real migration, on the synthetic corpus — smaller
    # scale, same migrate-and-assert sequence below.
    echo "  ℹ️  dogfood: source holds neither layout → synthetic corpus (tests/fixtures/p2-1-synthetic-v2)"
    p21_materialize "$DOGFOOD" || { FAIL=$((FAIL+1)); DF_OK=0; }
else
    echo "  ❌ dogfood: source holds a partial or mixed layout (legacy [$df_leg ] new [$df_new ] gotchas [$df_got ]) in $DF_SRC — refusing the synthetic fallback"
    FAIL=$((FAIL+1)); DF_OK=0
fi
if [ "$DF_OK" = 1 ]; then
# Product-doc sentinel: a file unrelated to the four pieces must survive the
# migration byte-for-byte (the content sweep is scoped to the four pieces).
cp "$ROOT_DIR/README.md" "$DOGFOOD/README.md"
# Sanity precondition
[ -f "$DOGFOOD/${HX_LEGACY_MAIN_FILE}" ] \
    || { echo "  ❌ dogfood precondition: ${HX_LEGACY_MAIN_FILE} missing in snapshot"; FAIL=$((FAIL+1)); }
# Without legacy references in the snapshot the zero-residue checks below would pass vacuously.
has_legacy_refs "$DOGFOOD/$HX_LEGACY_MAIN_FILE" "$DOGFOOD/$HX_GOTCHAS_FILE" "$DOGFOOD/$HX_LEGACY_LOGS_DIR/"*.md "$DOGFOOD/$HX_LEGACY_DEC_DIR/"*.md \
    && { echo "  ✅ dogfood precondition: snapshot holds legacy path references"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood precondition: snapshot holds no legacy references (residue checks would be vacuous)"; FAIL=$((FAIL+1)); }
src_logs=$(ls "$DOGFOOD/${HX_LEGACY_LOGS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
src_dec=$(ls "$DOGFOOD/${HX_LEGACY_DEC_DIR}" 2>/dev/null | wc -l | tr -d ' ')
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
[ -f "$DOGFOOD/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ dogfood: ${HX_MAIN_FILE} present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_MAIN_FILE} missing"; FAIL=$((FAIL+1)); }
[ -d "$DOGFOOD/${HX_LOGS_DIR}" ] \
    && { echo "  ✅ dogfood: ${HX_LOGS_DIR}/ present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_LOGS_DIR}/ missing"; FAIL=$((FAIL+1)); }
[ -d "$DOGFOOD/${HX_DEC_DIR}" ] \
    && { echo "  ✅ dogfood: ${HX_DEC_DIR}/ present"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_DEC_DIR}/ missing"; FAIL=$((FAIL+1)); }
[ -f "$DOGFOOD/${HX_GOTCHAS_FILE}" ] \
    && { echo "  ✅ dogfood: ${HX_GOTCHAS_FILE} preserved (ADR-0005 LEAVE)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_GOTCHAS_FILE} missing"; FAIL=$((FAIL+1)); }
[ ! -f "$DOGFOOD/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ dogfood: source ${HX_LEGACY_MAIN_FILE} removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source ${HX_LEGACY_MAIN_FILE} leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$DOGFOOD/${HX_LEGACY_LOGS_DIR}" ] \
    && { echo "  ✅ dogfood: source ${HX_LEGACY_LOGS_DIR}/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source ${HX_LEGACY_LOGS_DIR}/ leaked"; FAIL=$((FAIL+1)); }
[ ! -d "$DOGFOOD/${HX_LEGACY_DEC_DIR}" ] \
    && { echo "  ✅ dogfood: source ${HX_LEGACY_DEC_DIR}/ removed"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: source ${HX_LEGACY_DEC_DIR}/ leaked"; FAIL=$((FAIL+1)); }

# Count equivalence (no file loss)
moved_logs=$(ls "$DOGFOOD/${HX_LOGS_DIR}" 2>/dev/null | wc -l | tr -d ' ')
moved_dec=$(ls "$DOGFOOD/${HX_DEC_DIR}" 2>/dev/null | wc -l | tr -d ' ')
[ "$src_logs" = "$moved_logs" ] \
    && { echo "  ✅ dogfood: Dev Log count preserved ($src_logs == $moved_logs)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Dev Log count drift ($src_logs → $moved_logs)"; FAIL=$((FAIL+1)); }
[ "$src_dec" = "$moved_dec" ] \
    && { echo "  ✅ dogfood: Decision count preserved ($src_dec == $moved_dec)"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: Decision count drift ($src_dec → $moved_dec)"; FAIL=$((FAIL+1)); }

# Xref rewrite 完整: ${HX_MAIN_FILE} 不应残留任何 ${HX_LEGACY_LOGS_DIR}/ 或 ${HX_LEGACY_DEC_DIR}/ 字面
! grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/" "$DOGFOOD/${HX_MAIN_FILE}" \
    && { echo "  ✅ dogfood: ${HX_MAIN_FILE} no stale Handoff_*/ literal"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_MAIN_FILE} stale Handoff_*/ literal remains"; FAIL=$((FAIL+1)); }

# Dev Log content swept — 遍历全部 moved 文件（HIGH-E 2026-06-07 audit：原 head -1
# 采样恰中无字面的 0001 文件 → 假完整恒绿；真产物 13/60 Dev Log 含 Handoff_*/ 字面，
# 全遍历才 load-bearing，sweep 漏任一文件即 RED）。
dogfood_log_residue=0
for f in "$DOGFOOD/${HX_LOGS_DIR}/"*.md; do
    [ -e "$f" ] || continue
    if grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/" "$f" 2>/dev/null; then
        echo "  ❌ dogfood: Dev Log $f 仍含 stale Handoff_*/ 字面"; FAIL=$((FAIL+1)); dogfood_log_residue=1; break
    fi
done
[ "$dogfood_log_residue" = "0" ] \
    && { echo "  ✅ dogfood: 全部 Dev Log content swept clean（全遍历）"; PASS=$((PASS+1)); }
# Decision content swept — 同样全遍历
dogfood_dec_residue=0
for f in "$DOGFOOD/${HX_DEC_DIR}/"*.md; do
    [ -e "$f" ] || continue
    if grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/" "$f" 2>/dev/null; then
        echo "  ❌ dogfood: Decision $f 仍含 stale Handoff_*/ 字面"; FAIL=$((FAIL+1)); dogfood_dec_residue=1; break
    fi
done
[ "$dogfood_dec_residue" = "0" ] \
    && { echo "  ✅ dogfood: 全部 Decision content swept clean（全遍历）"; PASS=$((PASS+1)); }

# No .partial residue
[ ! -e "$DOGFOOD/${HX_MAIN_FILE}.partial" ] && [ ! -e "$DOGFOOD/${HX_LOGS_DIR}.partial" ] && [ ! -e "$DOGFOOD/${HX_DEC_DIR}.partial" ] \
    && { echo "  ✅ dogfood: no .partial residue"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: .partial residue"; FAIL=$((FAIL+1)); }
! grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/" "$DOGFOOD/${HX_GOTCHAS_FILE}" \
    && { echo "  ✅ dogfood: ${HX_GOTCHAS_FILE} no stale legacy dir literal"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: ${HX_GOTCHAS_FILE} stale legacy dir literal remains"; FAIL=$((FAIL+1)); }
cmp -s "$ROOT_DIR/README.md" "$DOGFOOD/README.md" \
    && { echo "  ✅ dogfood: product-doc sentinel (README.md) byte-unchanged"; PASS=$((PASS+1)); } \
    || { echo "  ❌ dogfood: product-doc sentinel (README.md) was rewritten"; FAIL=$((FAIL+1)); }

fi  # DF_OK

# Cleanup
rm -rf "$DOGFOOD"

# Fix E (Source 1 Important): ${HX_GOTCHAS_FILE} 文件名 LEAVE（ADR-0005），但内容里的
# 字面路径串需随 sweep 改写——Q2 拍板「全扫所有 .md」明确包含 ${HX_GOTCHAS_FILE} 内容。
# fixture 的 ${HX_GOTCHAS_FILE} 不含 Handoff_*/ 字面，测试时主动注入以验真。
FX_G=$(mktemp -d); p21_materialize "$FX_G" || FAIL=$((FAIL+1))
# 注入一行带 ${HX_LEGACY_LOGS_DIR}/ 与 ${HX_LEGACY_DEC_DIR}/ 字面的历史踩坑文本
echo "历史踩坑：见 ${HX_LEGACY_LOGS_DIR}/0001-foo.md 与 ${HX_LEGACY_DEC_DIR}/0001-bar.md" >> "$FX_G/${HX_GOTCHAS_FILE}"
"$SCRIPT" schema-upgrade --apply --root "$FX_G" >/dev/null 2>&1
# 文件名仍为 ${HX_GOTCHAS_FILE}（ADR-0005 LEAVE）
[ -f "$FX_G/${HX_GOTCHAS_FILE}" ] \
    && { echo "  ✅ Fix E: ${HX_GOTCHAS_FILE} 保留原名（ADR-0005 LEAVE）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: ${HX_GOTCHAS_FILE} missing"; FAIL=$((FAIL+1)); }
# 内容里的字面路径串已改写为 handoffx 形态
grep -qF "${HX_LOGS_DIR}/0001-foo.md" "$FX_G/${HX_GOTCHAS_FILE}" \
    && { echo "  ✅ Fix E: ${HX_GOTCHAS_FILE} 内 ${HX_LOGS_DIR}/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: ${HX_GOTCHAS_FILE} 漏改 ${HX_LOGS_DIR}/"; FAIL=$((FAIL+1)); }
grep -qF "${HX_DEC_DIR}/0001-bar.md" "$FX_G/${HX_GOTCHAS_FILE}" \
    && { echo "  ✅ Fix E: ${HX_GOTCHAS_FILE} 内 ${HX_DEC_DIR}/ 路径已改写"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: ${HX_GOTCHAS_FILE} 漏改 ${HX_DEC_DIR}/"; FAIL=$((FAIL+1)); }
# 无残留 Handoff_*/ 字面（Q2 全扫范围验证）
! grep -qE "${HX_LEGACY_LOGS_DIR}/|${HX_LEGACY_DEC_DIR}/" "$FX_G/${HX_GOTCHAS_FILE}" \
    && { echo "  ✅ Fix E: ${HX_GOTCHAS_FILE} 无 Handoff_*/ 残留"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: ${HX_GOTCHAS_FILE} 仍含 Handoff_*/ 残留"; FAIL=$((FAIL+1)); }
# 无 .partial 残留（cleanup 已扩展覆盖 GOTCHAS.partial）
[ ! -e "$FX_G/${HX_GOTCHAS_FILE}.partial" ] \
    && { echo "  ✅ Fix E: 无 ${HX_GOTCHAS_FILE}.partial 残留"; PASS=$((PASS+1)); } \
    || { echo "  ❌ Fix E: ${HX_GOTCHAS_FILE}.partial 残留"; FAIL=$((FAIL+1)); }
rm -rf "$FX_G"

# U3/U5/U6/X4 (v4.1.1 field reports): after the rename the four pieces still
# told readers to type the pre-v4 slash commands, the sweep changed files
# silently, and nothing recorded when or by which version the tree was
# upgraded. Old command names are built from a split stem so this suite holds
# none of them literally (legacy-names guard).
_h=hand; _h="${_h}off"
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
printf '\n运行 /%s-tidy 整理，再 /%s 写入；`/%s-recall`；/%s /%s 相邻；见 scripts/%s-lint.sh 与 skills/%s-init/x；/%s-lint 不动\n' \
    "$_h" "$_h" "$_h" "$_h" "$_h" "$_h" "$_h" "$_h" >> "$FX_U/$HX_LEGACY_MAIN_FILE"
printf -- '- 先 /%s-memory\n' "$_h" >> "$FX_U/$HX_LEGACY_LOGS_DIR/0001-2026-04-20T0000-foo.md"
echo "旧症状原文：当时 ${HX_LEGACY_MAIN_FILE} 打不开" >> "$FX_U/${HX_GOTCHAS_FILE}"
u_out=$("$SCRIPT" schema-upgrade --apply --root "$FX_U" 2>&1)
um=$(cat "$FX_U/$HX_MAIN_FILE")
assert_contains "U3: /…-tidy → /handoffx-tidy" "$um" "运行 /handoffx-tidy 整理"
assert_contains "U3: bare command → /handoffx" "$um" "再 /handoffx 写入"
assert_contains "U3: command in backticks rewritten too" "$um" '`/handoffx-recall`'
assert_contains "U3: adjacent bare commands both rewritten" "$um" "/handoffx /handoffx 相邻"
assert_contains "U3: a script path is untouched" "$um" "scripts/${_h}-lint.sh"
assert_contains "U3: a skill dir path is untouched" "$um" "skills/${_h}-init/x"
assert_contains "U3: an unknown /…-lint is untouched" "$um" "/${_h}-lint 不动"
assert_contains "U3: dev log commands rewritten" "$(cat "$FX_U/$HX_LOGS_DIR/0001-2026-04-20T0000-foo.md")" "先 /handoffx-memory"
assert_contains "U5: per-file rewrite count for the main" "$u_out" "行: ${HX_MAIN_FILE}"
assert_contains "U5: per-file rewrite count for a dev log" "$u_out" "改写 2 行: ${HX_LOGS_DIR}/0001-2026-04-20T0000-foo.md"
assert_contains "U5: gotchas rewrite counted" "$u_out" "改写 1 行: ${HX_GOTCHAS_FILE}"
uv=$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")
assert_exit "U6: exactly one upgrade marker" 1 "$(grep -c '^<!-- handoffx-upgraded: ' "$FX_U/$HX_MAIN_FILE")"
assert_exit "U6: marker sits right after the v2 schema marker" 0 \
    "$(awk 'p { exit !($0 ~ /^<!-- handoffx-upgraded: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] by handoffx\//) } /^<!-- HANDOFF v2 schema -->$/ { p = 1 } END { if (!p) exit 1 }' "$FX_U/$HX_MAIN_FILE" && echo 0 || echo 1)"
assert_contains "U6: marker names today and the skill version" "$um" "<!-- handoffx-upgraded: $(date +%Y-%m-%d) by handoffx/$uv -->"
assert_exit "U6: handoff-lint still passes on the marked main" 0 "$(bash "$ROOT_DIR/scripts/handoff-lint.sh" "$FX_U/$HX_MAIN_FILE" >/dev/null 2>&1; echo $?)"
rm -rf "$FX_U"
# U6 idempotence: a main that already carries a marker never gets a second one.
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
awk 'NR == 1 { print; print "<!-- handoffx-upgraded: 2000-01-01 by handoffx/v0 -->"; next } { print }' "$FX_U/$HX_LEGACY_MAIN_FILE" > "$FX_U/m" && mv "$FX_U/m" "$FX_U/$HX_LEGACY_MAIN_FILE"
"$SCRIPT" schema-upgrade --apply --root "$FX_U" >/dev/null 2>&1
assert_exit "U6: an existing marker is never duplicated" 1 "$(grep -c '^<!-- handoffx-upgraded: ' "$FX_U/$HX_MAIN_FILE")"
rm -rf "$FX_U"
# X8: the marker step writes through a fresh mktemp name, so a symlink planted
# at the old fixed temp name can neither redirect the write nor block it.
FX_U=$(mktemp -d); mkdir "$FX_U/p" "$FX_U/out"; p21_materialize "$FX_U/p" || FAIL=$((FAIL+1))
echo sentinel > "$FX_U/out/s"; ln -s "$FX_U/out/s" "$FX_U/p/${HX_MAIN_FILE}.partial.mark.tmp"
"$SCRIPT" schema-upgrade --apply --root "$FX_U/p" >/dev/null 2>&1
assert_exit "X8: planted temp-name symlink → sentinel untouched" 0 "$([ "$(cat "$FX_U/out/s")" = sentinel ] && echo 0 || echo 1)"
assert_exit "X8: marker still applied" 1 "$(grep -c '^<!-- handoffx-upgraded: ' "$FX_U/p/$HX_MAIN_FILE" 2>/dev/null)"
rm -rf "$FX_U"
# X4: a changed gotchas file is flagged as rewritten historical prose.
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
echo "旧症状原文：当时 ${HX_LEGACY_MAIN_FILE} 打不开" >> "$FX_U/${HX_GOTCHAS_FILE}"
u_out=$("$SCRIPT" schema-upgrade --apply --root "$FX_U" 2>&1)
assert_contains "X4: gotchas rewrite flagged as historical prose" "$u_out" "改写 1 行: ${HX_GOTCHAS_FILE}（历史原文中的旧文件名已按新布局改写）"
rm -rf "$FX_U"
# U5: a sweep that changes nothing in the gotchas file says nothing about it.
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
u_out=$("$SCRIPT" schema-upgrade --apply --root "$FX_U" 2>&1)
assert_not_contains "U5: untouched gotchas file is not reported" "$u_out" "行: ${HX_GOTCHAS_FILE}"
rm -rf "$FX_U"
# Z4a (report 4 #7): a bare legacy dir name (no trailing /) was left while the
# main name beside it was rewritten — one sentence, half old, half new. All
# three legacy names are now rewritten on word boundaries.
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
printf -- '- %s / %s 全文 grep；%s 与 %s,%s\n- 不动：My%s 与 %s_old\n' \
    "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" \
    "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR" >> "$FX_U/$HX_LEGACY_LOGS_DIR/0001-2026-04-20T0000-foo.md"
u_out=$("$SCRIPT" schema-upgrade --apply --root "$FX_U" 2>&1)
zl=$(cat "$FX_U/$HX_LOGS_DIR/0001-2026-04-20T0000-foo.md")
assert_contains "Z4a: main + bare logs dir on one line → both rewritten" "$zl" "- $HX_MAIN_FILE / $HX_LOGS_DIR 全文 grep"
assert_contains "Z4a: bare decisions dir and adjacent bare logs dirs rewritten" "$zl" "；$HX_DEC_DIR 与 $HX_LOGS_DIR,$HX_LOGS_DIR"
assert_contains "Z4a: a name inside a longer identifier is untouched" "$zl" "- 不动：My$HX_LEGACY_LOGS_DIR 与 ${HX_LEGACY_DEC_DIR}_old"
# 2 lines: the fixture's own 关联 line plus the planted one.
assert_contains "Z4a: the rewrite is reported" "$u_out" "改写 2 行: ${HX_LOGS_DIR}/0001-2026-04-20T0000-foo.md"
rm -rf "$FX_U"
# Z4b (report 4 #6): the template boilerplate that names old commands — the
# four sentences exactly as the v3 templates wrote them, plus the hyphenated
# spelling of the bare command.
FX_U=$(mktemp -d); p21_materialize "$FX_U" || FAIL=$((FAIL+1))
printf '\n> 本节由 /%s 命令覆盖式重写\n> 新坑由 /%s 追加\n接手 → /%s-recall\n另见 /hand-off 与 /hand-off-recall\n' "$_h" "$_h" "$_h" >> "$FX_U/$HX_LEGACY_MAIN_FILE"
{ printf '> Read by /%s-recall\n' "$_h"; cat "$FX_U/$HX_GOTCHAS_FILE"; } > "$FX_U/g" && mv "$FX_U/g" "$FX_U/$HX_GOTCHAS_FILE"
"$SCRIPT" schema-upgrade --apply --root "$FX_U" >/dev/null 2>&1
um=$(cat "$FX_U/$HX_MAIN_FILE")
assert_contains "Z4b: 本节由 … 命令覆盖式重写" "$um" "本节由 /handoffx 命令覆盖式重写"
assert_contains "Z4b: 新坑由 … 追加" "$um" "新坑由 /handoffx 追加"
assert_contains "Z4b: 接手 → …-recall" "$um" "接手 → /handoffx-recall"
assert_contains "Z4b: hyphenated bare command rewritten" "$um" "另见 /handoffx 与 /handoffx-recall"
assert_contains "Z4b: gotchas header Read by …-recall" "$(sed -n 1p "$FX_U/$HX_GOTCHAS_FILE")" "Read by /handoffx-recall"
rm -rf "$FX_U"

# Fix A (Source 2 S2-A Critical + S2-B High): MIXED schema state — old four-piece
# 与 new handoffx 同存即 split-brain，必须 fail-loud 拒绝（不可静默 no-op）。
# 旧版只看 new-side 三件齐 → 误判 ALREADY-HANDOFFX → 数据孤儿。
FX_M=$(mktemp -d); p21_materialize "$FX_M" || FAIL=$((FAIL+1))
# 在 v2 fixture 顶上再撒一颗 new-side 残屑（模拟上次迁移半失败留下的目标）
mkdir -p "$FX_M/${HX_LOGS_DIR}"; touch "$FX_M/${HX_MAIN_FILE}"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX_M" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ MIXED state: refused with exit non-zero"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: should refuse but succeeded"; FAIL=$((FAIL+1)); }
echo "$out" | grep -qF -- "split-brain" \
    && { echo "  ✅ MIXED state: error message names split-brain"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: message missing 'split-brain' keyword"; FAIL=$((FAIL+1)); }
# 源 ${HX_LEGACY_MAIN_FILE} 必须未被触碰（MIXED 是 detect-only 拒绝，未进入 migrate_apply）
[ -f "$FX_M/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ MIXED state: source ${HX_LEGACY_MAIN_FILE} preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: source ${HX_LEGACY_MAIN_FILE} damaged"; FAIL=$((FAIL+1)); }
# new-side 残屑也未被触碰（detect 不动任何数据）
[ -f "$FX_M/${HX_MAIN_FILE}" ] \
    && { echo "  ✅ MIXED state: pre-existing ${HX_MAIN_FILE} preserved"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MIXED state: ${HX_MAIN_FILE} damaged"; FAIL=$((FAIL+1)); }
rm -rf "$FX_M"

# MEDIUM-G (2026-06-07 audit): detect_schema_state 计数用 [ -e ] 而非 [-f]/[-d]——
# 类型不符的同名 new 工件（${HX_MAIN_FILE} 建成目录）也须计入 has_new → 触 MIXED。
# 区分修复的 load-bearing 键 = 「split-brain」消息：旧 [-f] 漏计目录 → 落 OLD-V2 →
# preflight 报「target already exists」（亦非零但非 split-brain）；新 [-e] → MIXED。
FX_DT=$(mktemp -d); p21_materialize "$FX_DT" || FAIL=$((FAIL+1))
mkdir -p "$FX_DT/${HX_MAIN_FILE}"; touch "$FX_DT/${HX_MAIN_FILE}/blocker"
out=$("$SCRIPT" schema-upgrade --apply --root "$FX_DT" 2>&1); rc=$?
[ "$rc" -ne 0 ] \
    && { echo "  ✅ MEDIUM-G: 目录型 ${HX_MAIN_FILE} → 拒绝 exit 非零"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 目录型 new 工件应拒绝但成功了"; FAIL=$((FAIL+1)); }
echo "$out" | grep -qF -- "split-brain" \
    && { echo "  ✅ MEDIUM-G: 判为 MIXED split-brain（非 OLD-V2 误迁；detect -e 计数生效）"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 未判 MIXED（detect 漏计目录型工件 → -e 修复失效）"; FAIL=$((FAIL+1)); }
[ -f "$FX_DT/${HX_LEGACY_MAIN_FILE}" ] \
    && { echo "  ✅ MEDIUM-G: 源 ${HX_LEGACY_MAIN_FILE} 未被触碰"; PASS=$((PASS+1)); } \
    || { echo "  ❌ MEDIUM-G: 源 ${HX_LEGACY_MAIN_FILE} 被破坏"; FAIL=$((FAIL+1)); }
rm -rf "$FX_DT"

# A2 (fix wave 1): the gotchas staging path is written by apply and removed
# unconditionally by rollback, so a pre-existing one (file, dir, symlink) must be
# refused by preflight before any write — else apply overwrites the file and
# rollback recursively deletes the directory.
tree_sig() { ( cd "$1" && find . -print | LC_ALL=C sort && find . -type f -print | LC_ALL=C sort | xargs shasum ) 2>&1; }
for kind in file dir symlink; do
    FX_GP=$(mktemp -d); p21_materialize "$FX_GP" || FAIL=$((FAIL+1))
    gp="$FX_GP/${HX_GOTCHAS_FILE}.partial"
    case "$kind" in
        file)    echo "someone's notes" > "$gp" ;;
        dir)     mkdir "$gp"; echo sentinel > "$gp/keep" ;;
        symlink) ln -s "$FX_GP/nowhere" "$gp" ;;
    esac
    sig=$(tree_sig "$FX_GP"); lnk=$(ls -lA "$FX_GP")
    out=$("$SCRIPT" schema-upgrade --apply --root "$FX_GP" 2>&1); rc=$?
    assert_exit "A2[$kind]: stale ${HX_GOTCHAS_FILE}.partial → preflight refusal exit 1" 1 "$rc"
    assert_contains "A2[$kind]: names the stale gotchas partial" "$out" "stale partial $gp"
    assert_exit "A2[$kind]: tree unchanged (no write before refusal)" 0 "$([ "$(tree_sig "$FX_GP")" = "$sig" ] && [ "$(ls -lA "$FX_GP")" = "$lnk" ] && echo 0 || echo 1)"
    rm -rf "$FX_GP"
done

# A3 (fix wave 1): v3 = all four pieces. A missing gotchas file is a predictable
# precondition → preflight refusal (exit 1, named), not a mid-run cp failure (2).
FX_NG=$(mktemp -d); p21_materialize "$FX_NG" || FAIL=$((FAIL+1)); rm -f "$FX_NG/${HX_GOTCHAS_FILE}"
sig=$(tree_sig "$FX_NG")
out=$("$SCRIPT" schema-upgrade --apply --root "$FX_NG" 2>&1); rc=$?
assert_exit "A3: missing ${HX_GOTCHAS_FILE} → preflight refusal exit 1" 1 "$rc"
assert_contains "A3: names the missing gotchas file" "$out" "preflight: $HX_GOTCHAS_FILE missing"
assert_exit "A3: tree unchanged" 0 "$([ "$(tree_sig "$FX_NG")" = "$sig" ] && echo 0 || echo 1)"
rm -rf "$FX_NG"

# A4 (fix wave 1): a dangling symlink fails `-e` but the final mv would replace
# it — detection and preflight share one predicate (-e || -L).
FX_DL=$(mktemp -d); p21_materialize "$FX_DL" || FAIL=$((FAIL+1))
ln -s "$FX_DL/nowhere" "$FX_DL/$HX_MAIN_FILE"
st=$(detect_on "$FX_DL")
assert_exit "A4: dangling $HX_MAIN_FILE beside legacy layout → not OLD-V2 [got: $st]" 0 "$([ "$st" != "OLD-V2" ] && echo 0 || echo 1)"
rc=0; ( . "$SCRIPTS_DIR/lib/handoffx-tidy-migrate.sh" && preflight_check "$FX_DL" ) >/dev/null 2>&1 || rc=$?
assert_exit "A4: preflight_check refuses a dangling $HX_MAIN_FILE target" 1 "$rc"
[ -L "$FX_DL/$HX_MAIN_FILE" ] && [ -f "$FX_DL/$HX_LEGACY_MAIN_FILE" ] \
    && { echo "  ✅ A4: dangling target and legacy main untouched"; PASS=$((PASS+1)); } \
    || { echo "  ❌ A4: dangling target or legacy main changed"; FAIL=$((FAIL+1)); }
rm -rf "$FX_DL"

# P2.2 tidy 合并（plan §4）：默认 = 结构整理；schema-upgrade 仅显式子命令。
# Why: 合并后若 schema-upgrade 混入默认流程，/handoffx-tidy 会静默迁移四件套（P2.4 前禁止）。
# 默认段 = frontmatter 之后、`## schema-upgrade` 之前的正文（frontmatter description 合法提及子命令）。
shim_default=$(awk '/^## schema-upgrade/ { exit } fm >= 2 { print } /^---$/ { fm++ }' "$SHIM")
shim_upgrade=$(awk '/^## schema-upgrade/ { on = 1 } on { print }' "$SHIM")
assert_contains "合并 shim 默认段 = 结构整理" "$shim_default" "执行**整理**流程"
assert_contains "合并 shim 默认段跑 tidy-handoff.sh \$HX_MAIN_FILE" "$shim_default" "tidy-handoff.sh $HX_MAIN_FILE"
assert_contains "合并 shim 有显式 schema-upgrade 段" "$shim_upgrade" "## schema-upgrade（显式子命令，不自动触发）"
assert_contains "schema-upgrade 段声明仅显式运行" "$shim_upgrade" "仅在用户显式要求时运行；默认整理流程不会调用它"
echo "$shim_default" | grep -q 'schema-upgrade' \
    && { echo "  ❌ 默认整理段提到 schema-upgrade（不得自动触发）"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ 默认整理段不触发 schema-upgrade"; PASS=$((PASS+1)); }
echo "$shim_upgrade" | grep -qE '自动(运行|执行|迁移|调用)|automatic' \
    && { echo "  ❌ schema-upgrade 被描述为自动"; FAIL=$((FAIL+1)); } \
    || { echo "  ✅ schema-upgrade 未被描述为自动"; PASS=$((PASS+1)); }

# D2 (fix wave 1): the dogfood falls back to the synthetic corpus ONLY when the
# source holds no piece of either layout. A partial or mixed source used to
# take the fallback with a bare ℹ️ line and run an all-green migration on the
# small corpus — hiding the damaged real corpus this dogfood exists to catch.
# Run the suite itself against a scratch source (override set → no recursion).
if [ -z "${HANDOFFX_TEST_DOGFOOD_ROOT:-}" ]; then
    DS=$(mktemp -d); mkdir -p "$DS/$HX_LEGACY_LOGS_DIR"
    rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DS" bash "$0" 2>&1) || rc=$?
    assert_contains "D2: source with only $HX_LEGACY_LOGS_DIR/ → ❌ naming the partial layout" "$o" "❌ dogfood: source holds a partial or mixed layout"
    assert_contains "D2: the diagnostic names what was found" "$o" "legacy [ $HX_LEGACY_LOGS_DIR ]"
    assert_not_contains "D2: partial source never falls back to the synthetic corpus" "$o" "synthetic corpus"
    assert_exit "D2: partial source → suite exit 1" 1 "$rc"
    rm -rf "$DS"
    # fix wave 2 (Codex N2): the gotchas file belongs to both layouts — a
    # source holding only it is partial (no fallback), and a layout missing it
    # is not complete.
    DG=$(mktemp -d); mkdir -p "$DG/only" "$DG/nogot"; : > "$DG/only/$HX_GOTCHAS_FILE"
    p21_materialize "$DG/nogot" || FAIL=$((FAIL+1)); rm -f "$DG/nogot/$HX_GOTCHAS_FILE"
    for src in only nogot; do
        rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DG/$src" bash "$0" 2>&1) || rc=$?
        assert_contains "N2[$src]: → ❌ partial or mixed layout" "$o" "❌ dogfood: source holds a partial or mixed layout"
        assert_not_contains "N2[$src]: never falls back to the synthetic corpus" "$o" "synthetic corpus"
        assert_exit "N2[$src]: suite exit 1" 1 "$rc"
    done
    rm -rf "$DG"
fi

summary
