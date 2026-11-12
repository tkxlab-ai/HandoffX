#!/bin/bash
# test_handoffx_upgrade.sh — the guided-upgrade flow (scripts/handoffx-upgrade.sh).
# Why its own suite: the /handoffx* commands now ask the user and then run this
# one script on their project, so its refusals, its zero-write dry-run, the
# post-checks and the leftover scan are what the user actually relies on — each
# migrator's own suite proves the migration, not the flow around it.
# Every legacy name is planted through $HX_LEGACY_* (the legacy-names guard
# would otherwise need an allowlist row for this file).
source "$(dirname "$0")/common.sh"
UP="$SCRIPTS_DIR/handoffx-upgrade.sh"

# tree_sig <dir> — names + bytes of everything under <dir>; equal sigs = the
# run wrote nothing (a dry-run or a refusal must leave the tree byte-identical).
tree_sig() {
    ( cd "$1" && find . -print | LC_ALL=C sort \
        && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum ) | cksum
}
# leftover_section <output> — only the leftover listing, so a hit elsewhere in
# the output (migrator plan, check lines) cannot satisfy or break an assertion.
leftover_section() { printf '%s\n' "$1" | awk '/其它文件仍引用旧名/ { on = 1; next } /^📝/ { on = 0 } on'; }
# The synthetic corpora are minimal on purpose; give the legacy main the
# REQUIRED sections so "validate passed" is a statement about the flow.
mk_v3() {
    p21_materialize "$1" || return 1
    printf '\n## 📦 Project Overview\nx\n\n## 🏗 Architecture\nx\n\n## 📜 Development Log\nx\n' >> "$1/$HX_LEGACY_MAIN_FILE"
}
mk_v1() {
    awk '/^## 🎯 Current State/ { print "## 🏗 Architecture\nx\n" } { print }' \
        "$FIXTURES_DIR/handoff-v1-sample.md" > "$1/$HX_LEGACY_MAIN_FILE"
}
run_up() { rc=0; out=$(bash "$UP" "$@" 2>&1) || rc=$?; }

echo "── 1. usage"
run_up; assert_exit "no mode → exit 2" 2 "$rc"
run_up --dry-run --apply; assert_exit "both modes → exit 2" 2 "$rc"
run_up --dry-run --bogus; assert_exit "unknown flag → exit 2" 2 "$rc"
run_up --dry-run --root; assert_exit "--root without a dir → exit 2" 2 "$rc"

echo "── 2. nothing to upgrade"
T=$(mktemp -d); mkdir -p "$T/v4" "$T/empty"; : > "$T/v4/$HX_MAIN_FILE"
run_up --apply --root "$T/v4"
assert_exit "none + main present → exit 0" 0 "$rc"
assert_contains "none + main present → already handoffx" "$out" "已是 handoffx 布局"
run_up --dry-run --root "$T/empty"
assert_exit "empty dir → exit 0" 0 "$rc"
assert_contains "empty dir → points at /handoffx-init" "$out" "/handoffx-init"
rm -rf "$T"

echo "── 3. v3 dry-run"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); sig=$(tree_sig "$T")
run_up --dry-run --root "$T"
assert_exit "v3 dry-run → exit 0" 0 "$rc"
assert_contains "names the layout" "$out" "布局判定: v3"
assert_contains "names the main rename" "$out" "$HX_LEGACY_MAIN_FILE → $HX_MAIN_FILE"
assert_contains "names the logs rename" "$out" "$HX_LEGACY_LOGS_DIR/ → $HX_LOGS_DIR/"
assert_contains "names the decisions rename" "$out" "$HX_LEGACY_DEC_DIR/ → $HX_DEC_DIR/"
assert_contains "prints the checklist" "$out" "后续人工步骤"
assert_exit "dry-run leaves the tree byte-identical" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"

echo "── 4. v3 apply"
run_up --apply --root "$T"
assert_exit "v3 apply → exit 0" 0 "$rc"
for p in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE"; do assert_file_exists "new $p present" "$T/$p"; done
assert_exit "new dirs present" 0 "$([ -d "$T/$HX_LOGS_DIR" ] && [ -d "$T/$HX_DEC_DIR" ] && echo 0 || echo 1)"
assert_exit "legacy pieces gone" 0 "$(hx_present "$T/$HX_LEGACY_MAIN_FILE" || hx_present "$T/$HX_LEGACY_LOGS_DIR" || hx_present "$T/$HX_LEGACY_DEC_DIR" && echo 1 || echo 0)"
assert_contains "validate --readiness passed" "$out" "✅ validate --readiness 通过"
assert_contains "postflight passed" "$out" "✅ postflight: all checks passed"
run_up --apply --root "$T"
assert_exit "second apply → exit 0" 0 "$rc"
assert_contains "second apply → already handoffx (idempotent)" "$out" "已是 handoffx 布局"
rm -rf "$T"

echo "── 5. v1 dry-run / apply"
T=$(mktemp -d); mk_v1 "$T"
ARC="${HX_LEGACY_MAIN_FILE%.md}.archive.md"
printf '# Archive\n\n### 2025-01-02 10:00 — archived entry\n**触发**: a\n**改动**: b\n**验证**: c\n**关联**: 无\n' > "$T/$ARC"
sig=$(tree_sig "$T")
run_up --dry-run --root "$T"
assert_exit "v1 dry-run → exit 0" 0 "$rc"
assert_contains "v1 dry-run names the layout" "$out" "布局判定: v1"
assert_contains "v1 dry-run shows the migrate-to-v2 plan" "$out" "$HX_LEGACY_MAIN_FILE → $HX_MAIN_FILE"
assert_exit "v1 dry-run leaves the tree byte-identical" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
run_up --apply --root "$T"
assert_exit "v1 apply → exit 0" 0 "$rc"
assert_file_exists "v1 apply → new main" "$T/$HX_MAIN_FILE"
assert_file_exists "v1 apply → main backup retained" "$T/$HX_LEGACY_MAIN_FILE.pre-v2-backup"
assert_file_exists "v1 apply → archive backup retained" "$T/$ARC.pre-v2-backup"
assert_exit "v1 apply → legacy main and archive gone" 0 "$(hx_present "$T/$HX_LEGACY_MAIN_FILE" || hx_present "$T/$ARC" && echo 1 || echo 0)"
assert_exit "v1 apply → archive merged into the logs dir" 0 "$([ -n "$(find "$T/$HX_LOGS_DIR" -name '*archived-entry*')" ] && echo 0 || echo 1)"
assert_contains "v1 apply → validate passed" "$out" "✅ validate --readiness 通过"
run_up --apply --root "$T"
assert_contains "v1 second apply → already handoffx" "$out" "已是 handoffx 布局"
rm -rf "$T"

echo "── 6. refusals write nothing"
T=$(mktemp -d); mkdir "$T/mixed" "$T/unknown"
mk_v3 "$T/mixed" || FAIL=$((FAIL+1)); mkdir "$T/mixed/$HX_DEC_DIR"
mk_v3 "$T/unknown" || FAIL=$((FAIL+1)); rm -rf "${T:?}/unknown/$HX_LEGACY_DEC_DIR"
for k in mixed unknown; do
    sig=$(tree_sig "$T/$k")
    run_up --apply --root "$T/$k"
    assert_exit "$k → exit 2" 2 "$rc"
    assert_contains "$k → names the refusal" "$out" "❌"
    assert_exit "$k → zero writes" 0 "$([ "$(tree_sig "$T/$k")" = "$sig" ] && echo 0 || echo 1)"
done
rm -rf "$T"

echo "── 7. leftover scan"
T=$(mktemp -d); mk_v1 "$T"
# The legacy main mentions the old logs dir too: its backup and the new main
# carry that line after apply and must not be reported as leftovers.
awk -v l="见 $HX_LEGACY_LOGS_DIR/ 下的旧条目" '{ print } /^## 🎯 Current State/ { print l }' "$T/$HX_LEGACY_MAIN_FILE" > "$T/m" && mv "$T/m" "$T/$HX_LEGACY_MAIN_FILE"
printf '# Demo\n\nsee\nlogs live in %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/README.md"
printf '#!/bin/sh\nls %s\n' "$HX_LEGACY_LOGS_DIR" > "$T/ci.sh"
printf 'bin\000ary %s\n' "$HX_LEGACY_LOGS_DIR" > "$T/blob.dat"
run_up --dry-run --root "$T"; lo=$(leftover_section "$out")
assert_contains "dry-run lists README.md" "$lo" "README.md:4:"
assert_not_contains "dry-run does not list the legacy main itself" "$lo" "$HX_LEGACY_MAIN_FILE:"
run_up --apply --root "$T"; lo=$(leftover_section "$out")
assert_exit "apply with leftovers → still exit 0 (informational)" 0 "$rc"
assert_contains "leftover header printed" "$out" "⚠️ 其它文件仍引用旧名（需人工处理）:"
assert_contains "README.md listed with its line number" "$lo" "README.md:4:"
assert_contains "ci.sh listed with its line number" "$lo" "ci.sh:2:"
assert_not_contains "new main not listed" "$lo" "$HX_MAIN_FILE:"
assert_not_contains "backup not listed" "$lo" ".pre-v2-backup"
assert_not_contains "binary file ignored" "$lo" "blob.dat"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
i=0; while [ "$i" -lt 60 ]; do echo "line $i $HX_LEGACY_DEC_DIR"; i=$((i+1)); done > "$T/bulk.txt"
run_up --dry-run --root "$T"; lo=$(leftover_section "$out")
assert_contains ">50 hits → total count named" "$lo" "共 60 处"
assert_exit ">50 hits → capped at 50 lines" 50 "$(printf '%s\n' "$lo" | grep -c 'bulk.txt:')"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T"
assert_contains "clean project → no-leftover line" "$out" "✅ 项目其它文件无旧名引用"
rm -rf "$T"
# fix1 Minor 4: find skips an unreadable subdirectory with only a stderr line;
# the scan must say it is incomplete instead of reporting a clean project.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ leftover scan over an unreadable subdirectory SKIPPED (root reads mode-000 dirs)"
else
    T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); mkdir "$T/locked"
    printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/locked/notes.md"; chmod 000 "$T/locked"
    run_up --dry-run --root "$T"
    assert_contains "unreadable subdir → scan reported incomplete" "$out" "⚠️ 扫描不完整"
    assert_not_contains "unreadable subdir → no clean ✅" "$out" "✅ 项目其它文件无旧名引用"
    chmod 755 "$T/locked"; rm -rf "$T"
fi

echo "── 7b. copy-paste apply line survives a root with a space"
T=$(mktemp -d); mkdir "$T/my proj"; mk_v3 "$T/my proj" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T/my proj"
line=$(printf '%s\n' "$out" | sed -n 's/^   0\. 确认上面的清单后执行: //p')
assert_contains "printed apply line quotes the root" "$line" "--root $(printf '%q' "$T/my proj")"
rc=0; eval "$line" >/dev/null 2>&1 || rc=$?
assert_exit "the printed line, run verbatim, applies" 0 "$rc"
assert_file_exists "the printed line migrated the spaced root" "$T/my proj/$HX_MAIN_FILE"
rm -rf "$T"

echo "── 8. post-check failure"
# Natural shape first: a v3 main without the REQUIRED sections migrates fine
# and then fails validate — no hook, no root dependency.
T=$(mktemp -d); p21_materialize "$T" || FAIL=$((FAIL+1))
run_up --apply --root "$T"
assert_exit "thin main: post-check failure → exit 1" 1 "$rc"
assert_contains "thin main: validate failure is named" "$out" "❌ validate --readiness 未通过"
assert_contains "thin main: says the migration is done" "$out" "迁移已完成；后置检查未过，请看上面的输出"
assert_file_exists "thin main: migrated tree stays" "$T/$HX_MAIN_FILE"
rm -rf "$T"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ post-check failure via unreadable main SKIPPED (root reads mode-000 files)"
else
    T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
    # Test-only hook (same contract as HANDOFFX_MIGRATE_FAIL_AT): the migrated
    # main goes unreadable between the migration and the checks.
    rc=0; out=$(HANDOFFX_UPGRADE_FAIL_AT=unreadable-main bash "$UP" --apply --root "$T" 2>&1) || rc=$?
    assert_exit "post-check failure → exit 1" 1 "$rc"
    assert_contains "validate failure is named" "$out" "❌ validate --readiness 未通过"
    assert_contains "says the migration is done" "$out" "迁移已完成；后置检查未过，请看上面的输出"
    assert_exit "migrated tree stays (no rollback)" 0 "$([ -f "$T/$HX_MAIN_FILE" ] && [ -d "$T/$HX_LOGS_DIR" ] && ! hx_present "$T/$HX_LEGACY_MAIN_FILE" && echo 0 || echo 1)"
    chmod 644 "$T/$HX_MAIN_FILE" 2>/dev/null; rm -rf "$T"
fi

echo "── 10. skill instruction block (nine places, one text)"
# Why: the ask is only as good as its trigger — a block that fires on the
# legacy main alone lets a mixed tree or a stray legacy dir (the sync-came-back
# case of MIGRATION_GUIDE §5.6) bypass the script's refusal. One text in nine
# places, so a later edit to one copy shows up here.
SK="$ROOT_DIR/skills/handoffx"
blk_of() { awk '/^\*\*旧布局检测 → 询问 → 标准升级\*\*/ { n = 5 } n > 0 { print; n-- }' "$1"; }
first=""
for f in SKILL.md command-shims/handoffx.md command-shims/handoffx-init.md \
         command-shims/handoffx-recall.md command-shims/handoffx-tidy.md \
         references/handoffx-write.md references/handoffx-init.md \
         references/handoffx-tidy.md references/handoffx-recall.md; do
    b=$(blk_of "$SK/$f"); t1=$(printf '%s\n' "$b" | grep '^1\. ')
    [ -n "$first" ] || first="$b"
    assert_exit "block in $f identical to SKILL.md's" 0 "$([ -n "$b" ] && [ "$b" = "$first" ] && echo 0 || echo 1)"
    for p in "\`$HX_LEGACY_MAIN_FILE\`" "\`$HX_LEGACY_LOGS_DIR/\`" "\`$HX_LEGACY_DEC_DIR/\`"; do
        assert_contains "$f: trigger names $p" "$t1" "$p"
    done
    assert_contains "$f: trigger is any legacy piece" "$t1" "任一旧版件"
    assert_contains "$f: apply exit 1 is explained" "$b" "脚本 exit 1 = 迁移已完成但后置检查未过"
done

echo "── 9. contract"
# Code lines only: comments and echo/printf text may name git (the checklist
# tells the human to commit) without the script ever running it.
assert_file_exists "upgrade script exists (contract below is not vacuous)" "$UP"
code=$(grep -vE '^[[:space:]]*(#|echo|printf)' "$UP" 2>/dev/null)
assert_exit "script never calls git" 1 "$(printf '%s\n' "$code" | grep -qE '(^|[;&|(`[:space:]])git[[:space:]]' && echo 0 || echo 1)"
assert_exit "script never reads the terminal" 1 "$(printf '%s\n' "$code" | grep -qE '(^|[;&|(`[:space:]])(read|select)[[:space:]]' && echo 0 || echo 1)"

summary
