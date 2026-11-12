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
assert_contains "dry-run lists README.md with its first hit line" "$lo" "README.md: 1 处 — L4:"
assert_not_contains "dry-run does not list the legacy main itself" "$lo" "$HX_LEGACY_MAIN_FILE:"
run_up --apply --root "$T"; lo=$(leftover_section "$out")
assert_exit "apply with leftovers → still exit 0 (informational)" 0 "$rc"
assert_contains "leftover header names files and hits" "$out" "⚠️ 其它文件仍引用旧名（需人工处理）：2 个文件，2 处"
assert_contains "README.md listed with its line number" "$lo" "README.md: 1 处 — L4:"
assert_contains "ci.sh listed with its line number" "$lo" "ci.sh: 1 处 — L2:"
assert_not_contains "new main not listed" "$lo" "$HX_MAIN_FILE:"
assert_not_contains "backup not listed" "$lo" ".pre-v2-backup"
assert_not_contains "binary file ignored" "$lo" "blob.dat"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
i=0; while [ "$i" -lt 60 ]; do echo "line $i $HX_LEGACY_DEC_DIR"; i=$((i+1)); done > "$T/bulk.txt"
run_up --dry-run --root "$T"; lo=$(leftover_section "$out")
assert_contains "60 hits in one file → aggregated to one line with its count" "$lo" "bulk.txt: 60 处 — L1:"
assert_exit "60 hits in one file → listed once" 1 "$(printf '%s\n' "$lo" | grep -c 'bulk.txt')"
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

echo "── 7c. many long leftover hits never turn into exit 141 (H1)"
# Why long lines: the old `printf … | head -n 50` only died of SIGPIPE once the
# listing outgrew the pipe buffer — 300 hits of ~1 KB each make that certain,
# so the regression is caught on every OS instead of by luck.
mk_bulk() {
    local d="$1" f i pad
    pad=$(printf '%0900d' 0)
    f=0; while [ "$f" -lt 60 ]; do
        i=0; while [ "$i" -lt 5 ]; do echo "row $i see $HX_LEGACY_LOGS_DIR/x $pad"; i=$((i+1)); done > "$d/doc$f.md"
        f=$((f+1))
    done
}
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); mk_bulk "$T"
run_up --dry-run --root "$T"
assert_exit "300 long hits: dry-run → exit 0 (not 141)" 0 "$rc"
assert_contains "300 long hits: dry-run still prints the checklist" "$out" "后续人工步骤"
assert_contains "300 long hits: cap line names files and hits" "$out" "showing 50 of 60 files (300 hits)"
assert_exit "300 long hits: exactly 50 file lines listed" 50 "$(leftover_section "$out" | grep -c '^   doc[0-9]*\.md: 5 处')"
run_up --apply --root "$T"
assert_exit "300 long hits: apply → exit 0 (not 141)" 0 "$rc"
assert_contains "300 long hits: apply still prints the checklist" "$out" "后续人工步骤"
rm -rf "$T"

echo "── 7b. copy-paste apply line survives a root with a space"
T=$(mktemp -d); mkdir "$T/my proj"; mk_v3 "$T/my proj" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T/my proj"
line=$(printf '%s\n' "$out" | sed -n 's/^   1\. 确认上面的清单后执行: //p')
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
blk_of() { awk '/^\*\*旧布局检测 → 询问 → 标准升级\*\*/ { n = 6 } n > 0 { print; n-- }' "$1"; }
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
    # fix1 I2: a migrator refusal is its own code — the AI must not read it as "migrated"
    assert_contains "$f: apply exit 3 is explained" "$b" "exit 3 = 迁移器拒绝、未迁移，按输出处理后重跑"
    # W4b (v4.1.1, report 5 §5.2): a user who already said "upgrade" was asked again in every reference
    assert_contains "$f: authorization given once is not asked again" "$(printf '%s\n' "$b" | grep '^5\. ')" "用户在本轮对话里已明确要求升级 → 直接跑 --dry-run 再 --apply，不再重复询问"
done

echo "── 11. non-git v3 apply takes a verified backup first (H3)"
# Why: the ask promised "v3 renames in place, git is the way back" — a
# Syncthing-only project had no way back at all. Outside a git work tree the
# four legacy pieces are packed and verified before anything is renamed.
bk_of() { find "$1" -maxdepth 1 -name '.handoffx-pre-upgrade-*.tar.gz' -print; }
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T"
assert_contains "non-git dry-run names the backup it would take" "$out" "非 git 项目：--apply 会先打包"
assert_exit "non-git dry-run writes no backup" 0 "$([ -z "$(bk_of "$T")" ] && echo 0 || echo 1)"
run_up --apply --root "$T"; bk=$(bk_of "$T")
assert_exit "non-git apply → exit 0" 0 "$rc"
assert_exit "non-git apply → exactly one backup tarball" 1 "$(printf '%s\n' "$bk" | grep -c .)"
lst=$( [ -n "$bk" ] && tar tzf "$bk" 2>/dev/null | sed 's#/$##' )
for p in "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR" "$HX_GOTCHAS_FILE"; do
    assert_exit "backup lists $p" 0 "$(printf '%s\n' "$lst" | grep -qxF -- "$p" && echo 0 || echo 1)"
done
assert_exit "backup holds the legacy dev log entries" 0 "$(printf '%s\n' "$lst" | grep -q "^$HX_LEGACY_LOGS_DIR/0001-" && echo 0 || echo 1)"
assert_not_contains "backup carries no AppleDouble entries" "$lst" "._"
assert_contains "non-git apply prints the backup path" "$out" "$(basename "$bk")"
assert_contains "checklist says the backup may be deleted once checked" "$out" "确认无误后可删除"
assert_file_exists "non-git apply still migrated" "$T/$HX_MAIN_FILE"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --apply --no-backup --root "$T"
assert_exit "--no-backup → exit 0" 0 "$rc"
assert_exit "--no-backup → no tarball" 0 "$([ -z "$(bk_of "$T")" ] && echo 0 || echo 1)"
assert_contains "--no-backup is said out loud" "$out" "--no-backup"
assert_file_exists "--no-backup still migrated" "$T/$HX_MAIN_FILE"
rm -rf "$T"
if command -v git >/dev/null 2>&1; then
    T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); git -C "$T" init -q
    run_up --dry-run --root "$T"
    assert_contains "git dry-run says git is the way back" "$out" "git 工作树：不打包"
    run_up --apply --root "$T"
    assert_exit "git work tree apply → exit 0" 0 "$rc"
    assert_exit "git work tree → no tarball" 0 "$([ -z "$(bk_of "$T")" ] && echo 0 || echo 1)"
    rm -rf "$T"
else
    echo "  ➖ git-work-tree backup case SKIPPED (git not on PATH)"
fi
# A fake tar that "succeeds" but writes garbage: the listing check must catch
# it, remove its own bad archive and migrate nothing.
# The writers' flock file is pre-created in the refusal cases below: on a
# flock system the run creates it and, by design (fix3 N2), never unlinks it.
T=$(mktemp -d); mkdir "$T/bin" "$T/p"; mk_v3 "$T/p" || FAIL=$((FAIL+1)); : > "$T/p/$HX_LEGACY_LOGS_DIR/.lock"
printf '#!/bin/sh\ncase "$1" in c*) echo garbage > "$2" ;; esac\nexit 0\n' > "$T/bin/tar"; chmod +x "$T/bin/tar"
sig=$(tree_sig "$T/p")
rc=0; out=$(PATH="$T/bin:$PATH" bash "$UP" --apply --root "$T/p" 2>&1) || rc=$?
assert_exit "unverifiable backup → exit 2" 2 "$rc"
assert_contains "unverifiable backup → names the failure" "$out" "❌ 升级前备份校验失败"
assert_exit "unverifiable backup → zero net writes, nothing migrated" 0 "$([ "$(tree_sig "$T/p")" = "$sig" ] && echo 0 || echo 1)"
rm -rf "$T"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unwritable-root backup refusal SKIPPED (root writes into mode-555 dirs)"
else
    T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); : > "$T/$HX_LEGACY_LOGS_DIR/.lock"; sig=$(tree_sig "$T"); chmod 555 "$T"
    run_up --apply --root "$T"
    chmod 755 "$T"
    assert_exit "unwritable root → exit 2" 2 "$rc"
    assert_contains "unwritable root → names the backup failure" "$out" "❌ 无法创建升级前备份"
    assert_exit "unwritable root → zero writes, nothing migrated" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
    rm -rf "$T"
fi

echo "── 12. leftover scan: prune, truncate, aggregate, full list (U1/U2)"
# Why: the field run listed 306 hits from 44 files capped at 50 lines with no
# total — backups, sync conflicts and session logs drowned the handful of real
# docs, one 5000-char JSONL line filled a screen, and the AI reported "about
# 50". Noise is pruned, lines are cut, files are aggregated and counted, and
# the complete list lands in a file.
RES=.handoffx-upgrade-residuals.txt
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
mkdir -p "$T/sessions" "$T/logs" "$T/vendor" "$T/docs"
for p in sessions/x.jsonl logs/run.md vendor/old.md a.jsonl "notes.sync-conflict-20261101.md" notes.md.bak_1 notes.bak.md "$RES"; do
    printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/$p"
done
printf 'a %s/\nb %s/\nc %s/\n' "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" > "$T/docs/three.md"
printf 'one %s/\n' "$HX_LEGACY_DEC_DIR" > "$T/docs/one.md"
long="$HX_LEGACY_DEC_DIR/ $(printf '%05000d' 0)"; printf '%s\n' "$long" > "$T/docs/long.md"
cjk=$(i=0; while [ "$i" -lt 80 ]; do printf '旧'; i=$((i+1)); done)
printf '%s/ %s\n' "$HX_LEGACY_LOGS_DIR" "$cjk" > "$T/docs/cjk.md"
sig=$(tree_sig "$T")
rc=0; out=$(HANDOFFX_SCAN_PRUNE="vendor" bash "$UP" --dry-run --root "$T" 2>&1) || rc=$?; lo=$(leftover_section "$out")
assert_exit "U1 dry-run → exit 0" 0 "$rc"
assert_contains "U2 progress line names the text-file count and pruned dirs" "$out" "🔎 残留扫描：4 个文本文件（跳过目录:"
assert_contains "U2 progress line names the env-appended prune dir" "$out" "vendor"
for p in sessions/x.jsonl logs/run.md vendor/old.md a.jsonl sync-conflict bak_1 notes.bak.md "$RES"; do
    assert_not_contains "U1 pruned: $p" "$lo" "$p"
done
assert_contains "U1 header counts files and hits" "$out" "其它文件仍引用旧名（需人工处理）：4 个文件，6 处"
assert_exit "U1 aggregated: the 3-hit file is listed first" 0 "$(printf '%s\n' "$lo" | grep '处 — L' | sed -n 1p | grep -qF 'docs/three.md: 3 处 — L1:' && echo 0 || echo 1)"
ln=$(printf '%s\n' "$lo" | grep -F 'docs/long.md:' | sed 's/.* — L1: //')
assert_exit "U1 a 5000-char line is cut to ≤ 120 chars" 0 "$([ -n "$ln" ] && [ "$(printf '%s' "$ln" | wc -c)" -le 120 ] && echo 0 || echo 1)"
cl=$(printf '%s\n' "$lo" | grep -F 'docs/cjk.md:' | sed 's/.* — L1: //')
assert_exit "U1 a cut CJK line stays valid UTF-8" 0 "$([ -n "$cl" ] && printf '%s' "$cl" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && echo 0 || echo 1)"
full=$(printf '%s\n' "$out" | sed -n 's/^📄 完整清单: //p')
assert_exit "U1 dry-run full list lives outside the project (dry-run writes nothing)" 0 "$([ -f "$full" ] && [ "${full#"$T"/}" = "$full" ] && echo 0 || echo 1)"
assert_exit "U1 dry-run leaves the tree byte-identical" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
[ -n "$full" ] && rm -f "$full"
rc=0; out=$(HANDOFFX_SCAN_PRUNE="vendor" bash "$UP" --apply --root "$T" 2>&1) || rc=$?
assert_exit "U1 apply → exit 0" 0 "$rc"
assert_contains "U1 apply names the residual file" "$out" "📄 完整清单: $T/$RES"
assert_exit "U1 residual file holds every hit, untruncated" 0 "$([ "$(grep -c . "$T/$RES")" = 6 ] && grep -qxF "docs/long.md:1:$long" "$T/$RES" && echo 0 || echo 1)"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/README.md"
run_up --dry-run --quick --root "$T"
assert_exit "U2 --quick → exit 0" 0 "$rc"
assert_not_contains "U2 --quick skips the scan" "$out" "🔎 残留扫描"
assert_not_contains "U2 --quick lists no leftovers" "$out" "其它文件仍引用旧名"
assert_contains "U2 --quick checklist says the scan was skipped" "$out" "已跳过残留扫描"
rm -rf "$T"

echo "── 13. decision INDEX exists right after apply (U4)"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
ndec=$(find "$T/$HX_LEGACY_DEC_DIR" -name '[0-9][0-9][0-9][0-9]-*.md' | grep -c .)
run_up --apply --root "$T"
assert_file_exists "U4 v3 apply → $HX_DEC_DIR/INDEX.md" "$T/$HX_DEC_DIR/INDEX.md"
assert_exit "U4 INDEX has one row per decision" "$ndec" "$(grep -cE '^\| [0-9]{4} ' "$T/$HX_DEC_DIR/INDEX.md" 2>/dev/null)"
rm -rf "$T"
T=$(mktemp -d); mk_v1 "$T"
run_up --apply --root "$T"
assert_file_exists "U4 v1 apply → $HX_DEC_DIR/INDEX.md" "$T/$HX_DEC_DIR/INDEX.md"
rm -rf "$T"

echo "── 14. lint pre-check, gotchas-sweep note, residual-file symlink (X3/X4/X7)"
# X3: lint findings in the legacy corpus used to surface only after --apply,
# as a red postflight on an already-renamed tree; the dry-run names them first.
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T"
assert_contains "X3 clean v3 corpus → pre-check passes" "$out" "✅ 迁移前 lint 预检通过"
bad=$(ls "$T/$HX_LEGACY_LOGS_DIR" | sed -n 1p)
sed '1,/^---$/d' "$T/$HX_LEGACY_LOGS_DIR/$bad" > "$T/x" && mv "$T/x" "$T/$HX_LEGACY_LOGS_DIR/$bad"
sig=$(tree_sig "$T")
run_up --dry-run --root "$T"
assert_exit "X3 findings are informational (dry-run exit 0)" 0 "$rc"
assert_contains "X3 pre-check counts the findings" "$out" "⚠️ 迁移前 lint 预检："
assert_contains "X3 pre-check names the broken Dev Log" "$out" "$bad: missing frontmatter"
assert_exit "X3 pre-check writes nothing" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
rm -rf "$T"
T=$(mktemp -d); mk_v1 "$T"
run_up --dry-run --root "$T"
assert_contains "X3 v1 file is pre-checked too" "$out" "迁移前 lint 预检"
rm -rf "$T"
# X4: the sweep rewrites historical prose in the gotchas file by design; the
# checklist says so once so nobody mistakes it for corruption.
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --apply --root "$T"
assert_exit "X4 checklist mentions the gotchas sweep exactly once" 1 "$(printf '%s\n' "$out" | grep -c "${HX_GOTCHAS_FILE} 历史原文中的旧文件名")"
rm -rf "$T"
# X7: a planted symlink at the residual-file name must never redirect the write.
T=$(mktemp -d); mkdir "$T/p" "$T/out"; mk_v3 "$T/p" || FAIL=$((FAIL+1))
printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/p/README.md"
echo sentinel > "$T/out/s"; ln -s "$T/out/s" "$T/p/$RES"
run_up --apply --root "$T/p"
assert_exit "X7 symlinked residual file → sentinel untouched" 0 "$([ "$(cat "$T/out/s")" = sentinel ] && echo 0 || echo 1)"
assert_contains "X7 symlinked residual file → refusal named" "$out" "❌ 不写完整清单"
assert_exit "X7 the symlink itself is left in place" 0 "$([ -L "$T/p/$RES" ] && echo 0 || echo 1)"
rm -rf "$T"

echo "── 15. sync-aware apply, migration lock, checklist order (Z2)"
# Why: report 4 upgraded a Syncthing-synced tree while sync ran — a rename
# racing the sync is how mixed trees are born. A sync marker on the way up to
# / is named on every run; --apply refuses (zero writes) until the human says
# the sync is paused.
T=$(mktemp -d); mkdir -p "$T/.stfolder" "$T/p"; mk_v3 "$T/p" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T/p"
assert_exit "Z2 synced dry-run → exit 0" 0 "$rc"
assert_contains "Z2 dry-run names the Syncthing marker and where it is" "$out" "⚠️ 检测到同步目录标记: .stfolder at $T"
sig=$(tree_sig "$T/p")
run_up --apply --root "$T/p"
assert_exit "Z2 synced apply without --sync-paused → exit 2" 2 "$rc"
assert_contains "Z2 refusal names the flag that lifts it" "$out" "--sync-paused"
assert_exit "Z2 refusal writes nothing" 0 "$([ "$(tree_sig "$T/p")" = "$sig" ] && echo 0 || echo 1)"
run_up --apply --sync-paused --root "$T/p"
assert_exit "Z2 --sync-paused → exit 0" 0 "$rc"
assert_file_exists "Z2 --sync-paused → migrated" "$T/p/$HX_MAIN_FILE"
rm -rf "$T"
for mk in .dropbox .dropbox.cache; do
    T=$(mktemp -d); mkdir -p "$T/$mk" "$T/a/p"; mk_v3 "$T/a/p" || FAIL=$((FAIL+1))
    run_up --apply --root "$T/a/p"
    assert_exit "Z2 $mk two levels up → apply refused (exit 2)" 2 "$rc"
    assert_contains "Z2 $mk marker named" "$out" "检测到同步目录标记: $mk at $T"
    rm -rf "$T"
done
T=$(mktemp -d); mkdir -p "$T/Library/Mobile Documents/p"; mk_v3 "$T/Library/Mobile Documents/p" || FAIL=$((FAIL+1))
run_up --apply --root "$T/Library/Mobile Documents/p"
assert_exit "Z2 iCloud path → apply refused (exit 2)" 2 "$rc"
assert_contains "Z2 iCloud marker named" "$out" "检测到同步目录标记: /Library/Mobile Documents/"
rm -rf "$T"
# Lock: a held lock (another write or upgrade) makes the apply give up within
# ~5 s, naming the directory; a normal run leaves no lock behind.
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); mkdir "$T/$HX_LEGACY_LOGS_DIR/.lock.d"
sig=$(tree_sig "$T"); t0=$(date +%s)
run_up --apply --root "$T"; el=$(( $(date +%s) - t0 ))
assert_exit "Z2 held lock → apply refused (exit 2)" 2 "$rc"
assert_contains "Z2 held lock → the lock dir is named" "$out" "$T/$HX_LEGACY_LOGS_DIR/.lock.d"
assert_exit "Z2 held lock → gives up within ~5 s" 0 "$([ "$el" -le 9 ] && echo 0 || echo 1)"
assert_exit "Z2 held lock → zero net writes (no backup left, nothing migrated)" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
rmdir "$T/$HX_LEGACY_LOGS_DIR/.lock.d"
run_up --apply --root "$T"
assert_exit "Z2 lock free → apply exit 0" 0 "$rc"
assert_exit "Z2 normal run leaves no lock behind" 0 "$(hx_present "$T/$HX_LOGS_DIR/.lock.d" || hx_present "$T/$HX_LEGACY_LOGS_DIR/.lock.d" && echo 1 || echo 0)"
# Checklist: pause sync and install v4 everywhere come BEFORE the apply line;
# outside git the commit line becomes "the backup may go".
assert_contains "Z2 non-git apply → backup-deletion line instead of git commit" "$out" "非 git 项目：确认后可删除 .handoffx-pre-upgrade-*.tar.gz（或移到别处保存）"
assert_not_contains "Z2 non-git apply → no git add line" "$out" "git add -A"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
run_up --dry-run --root "$T"
n0a=$(printf '%s\n' "$out" | grep -n '^   0a\. 暂停本项目目录的同步（Syncthing / Dropbox / iCloud）$' | cut -d: -f1)
n0b=$(printf '%s\n' "$out" | grep -n '^   0b\. 每台机器、每个 CLI 先装 v4$' | cut -d: -f1)
n1=$(printf '%s\n' "$out" | grep -n '^   1\. 确认上面的清单后执行: ' | cut -d: -f1)
assert_exit "Z2 checklist order 0a → 0b → 1 (apply)" 0 "$([ -n "$n0a" ] && [ -n "$n0b" ] && [ -n "$n1" ] && [ "$n0a" -lt "$n0b" ] && [ "$n0b" -lt "$n1" ] && echo 0 || echo 1)"
ref=$(printf '%s\n' "$out" | sed -n 's/^📝 后续人工步骤（顺序详见 \(.*\)）:$/\1/p')
assert_exit "Z2 checklist cites a migration-order.md that exists" 0 "$([ -f "$ref" ] && [ "$(basename "$ref")" = migration-order.md ] && echo 0 || echo 1)"
rc=0; out=$(bash "$ROOT_DIR/skills/handoffx/scripts/handoffx-upgrade.sh" --dry-run --root "$T" 2>&1) || rc=$?
ref=$(printf '%s\n' "$out" | sed -n 's/^📝 后续人工步骤（顺序详见 \(.*\)）:$/\1/p')
assert_exit "Z2 installed-skill layout resolves its own references/migration-order.md" 0 "$([ "$ref" = "$ROOT_DIR/skills/handoffx/scripts/../references/migration-order.md" ] && [ -f "$ref" ] && echo 0 || echo 1)"
rm -rf "$T"
if command -v git >/dev/null 2>&1; then
    T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); git -C "$T" init -q
    run_up --apply --root "$T"
    assert_contains "Z2 git work tree → commit line kept" "$out" "git add -A"
    assert_not_contains "Z2 git work tree → no backup-deletion line" "$out" "非 git 项目：确认后可删除"
    rm -rf "$T"
else
    echo "  ➖ Z2 git-branch checklist SKIPPED (git not on PATH)"
fi
# The shipped order (references/) and the guide's §5.6 are one text.
body() { awk '/^1\. /{ on = 1 } /^---$/{ on = 0 } on' "$1" | grep -v '^$'; }
MO="$ROOT_DIR/skills/handoffx/references/migration-order.md"
assert_exit "Z2 references/migration-order.md = MIGRATION_GUIDE §5.6 body" 0 \
    "$([ -f "$MO" ] && [ -n "$(body "$MO")" ] && [ "$(body "$MO")" = "$(awk '/^### 5\.6 /{ on = 1 } on' "$ROOT_DIR/MIGRATION_GUIDE_v2.md" | awk '/^1\. /{ on = 1 } /^---$/{ exit } on' | grep -v '^$')" ] && echo 0 || echo 1)"
assert_contains "Z2 migration order advises .stignore for the lock dir" "$(cat "$MO" 2>/dev/null)" "$HX_LOGS_DIR/.lock.d"

echo "── 16. residual scan: old commands, old skill path, rule files first, permission entries (Z4)"
# Why: report 4's real leftovers were rule files — a permission entry pinned to
# the old skill path, a CLAUDE.md that only names an old command — and they
# sat below the 50-line cap behind doc hits. Old command names and the old
# skill path are now scan patterns, rule files sort first, and permission
# entries get their own block with a suggested replacement (never edited).
_h=hand; _h="${_h}off"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1))
mkdir -p "$T/.claude" "$T/docs" "$T/config-backups"
SET="$T/.claude/settings.local.json"
printf '{\n  "permissions": {\n    "allow": [\n      "Bash(bash ~/.claude/skills/%s/scripts/handoff-postflight.sh %s)"\n    ]\n  }\n}\n' "$_h" "$HX_LEGACY_MAIN_FILE" > "$SET"
printf '先跑 /%s-recall 再说\n' "$_h" > "$T/CLAUDE.md"
printf 'a %s/\nb %s/\nc %s/\nd %s/\n' "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" > "$T/docs/four.md"
for p in "config-backups/settings-$_h-1.json" notes.bak .claude-md-bak-20260101; do printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/$p"; done
set_before=$(cksum < "$SET")
run_up --dry-run --root "$T"; lo=$(leftover_section "$out")
assert_exit "Z4c the settings file is listed first (rule files before docs)" 0 "$(printf '%s\n' "$lo" | grep '处 — L' | sed -n 1p | grep -qF '.claude/settings.local.json: 1 处' && echo 0 || echo 1)"
assert_contains "Z4c a command-only CLAUDE.md line is found" "$lo" "CLAUDE.md: 1 处 — L1:"
assert_exit "Z4c rule files come before the 4-hit doc" 0 "$(printf '%s\n' "$lo" | grep '处 — L' | awk '/CLAUDE.md:/ { c = NR } /docs\/four.md:/ { d = NR } END { exit !(c && d && c < d) }' && echo 0 || echo 1)"
for p in config-backups notes.bak .claude-md-bak-; do assert_not_contains "Z4c excluded: $p" "$lo" "$p"; done
assert_contains "Z4d permission block header" "$out" "🔐 权限条目指向旧 skill 路径（请自行决定是否更新，不自动修改）:"
assert_contains "Z4d the old entry is quoted" "$out" ".claude/settings.local.json:4:"
assert_contains "Z4d a prefix rule is suggested" "$out" "Bash(bash ~/.claude/skills/handoffx/scripts/handoff-postflight.sh:*)"
assert_contains "Z4d the prefix rule is said to be broader" "$out" "--files="
run_up --apply --root "$T"
assert_exit "Z4 apply → exit 0" 0 "$rc"
assert_contains "Z4d block printed on apply too" "$out" "🔐 权限条目指向旧 skill 路径"
assert_exit "Z4d the settings file is byte-identical after apply" 0 "$([ "$(cksum < "$SET")" = "$set_before" ] && echo 0 || echo 1)"
rm -rf "$T"

echo "── 17. relative root, migrator refusal, temp-dir failures (fix1 I1/I2, C7)"
# I1: the backup path was joined from a relative root and then used again
# inside `cd "$ROOT"`, so it resolved to root/root/… and every non-git apply
# with a relative --root refused, blaming permissions.
T=$(mktemp -d); mkdir -p "$T/work/proj"; mk_v3 "$T/work/proj" || FAIL=$((FAIL+1))
rc=0; out=$(cd "$T" && bash "$UP" --apply --root work/proj 2>&1) || rc=$?
assert_exit "I1 relative --root from another cwd → apply exit 0" 0 "$rc"
assert_exit "I1 relative --root → one verified backup in the project root" 1 "$(bk_of "$T/work/proj" | grep -c .)"
assert_file_exists "I1 relative --root → migrated" "$T/work/proj/$HX_MAIN_FILE"
assert_contains "I1 relative --root → checklist printed" "$out" "后续人工步骤"
rm -rf "$T"
# I2: the migrator exits 1 on every pre-commit refusal; forwarded as is, that
# read as "migrated, post-check failed — do not retry".
T=$(mktemp -d); mk_v1 "$T"; printf '# Known Gotchas\nreal entry\n' > "$T/$HX_GOTCHAS_FILE"; sig=$(tree_sig "$T")
run_up --apply --root "$T"
assert_exit "I2 v1 + existing $HX_GOTCHAS_FILE → migrator refusal → exit 3" 3 "$rc"
assert_contains "I2 refusal names exit 3" "$out" "迁移器拒绝"
assert_exit "I2 refusal leaves the tree byte-identical" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
rm -rf "$T"
# C7: a temp dir that cannot be made must not escape through set -e as exit 1.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unwritable TMPDIR cases SKIPPED (root writes into mode-555 dirs)"
else
    T=$(mktemp -d); mkdir "$T/ro" "$T/p"; mk_v3 "$T/p" || FAIL=$((FAIL+1)); : > "$T/p/$HX_LEGACY_LOGS_DIR/.lock"; chmod 555 "$T/ro"; sig=$(tree_sig "$T/p")
    rc=0; out=$(TMPDIR="$T/ro" bash "$UP" --dry-run --root "$T/p" 2>&1) || rc=$?
    assert_exit "C7 unwritable TMPDIR → dry-run still exit 0" 0 "$rc"
    assert_contains "C7 unwritable TMPDIR → lint pre-check says it did not run" "$out" "迁移前 lint 预检未执行"
    assert_contains "C7 unwritable TMPDIR → checklist still printed" "$out" "后续人工步骤"
    rc=0; out=$(TMPDIR="$T/ro" bash "$UP" --apply --root "$T/p" 2>&1) || rc=$?
    assert_exit "C7 unwritable TMPDIR → non-git apply refuses with exit 2 (not 1)" 2 "$rc"
    assert_contains "C7 unwritable TMPDIR → backup failure named" "$out" "❌ 无法创建升级前备份"
    assert_exit "C7 unwritable TMPDIR → apply wrote nothing" 0 "$([ "$(tree_sig "$T/p")" = "$sig" ] && echo 0 || echo 1)"
    rc=0; out=$(TMPDIR="$T/ro" bash "$UP" --apply --no-backup --root "$T/p" 2>&1) || rc=$?
    # The migration itself runs; post-checks that need a temp dir may fail on
    # some systems (that is the honest exit 1). What must not happen is a
    # set -e escape: the checklist and the "未执行" line both print.
    assert_contains "C7 unwritable TMPDIR → --no-backup apply still reaches the checklist" "$out" "后续人工步骤"
    assert_file_exists "C7 unwritable TMPDIR → --no-backup apply migrated" "$T/p/$HX_MAIN_FILE"
    assert_contains "C7 unwritable TMPDIR → residual scan says it did not run" "$out" "残留扫描未执行"
    chmod 755 "$T/ro"; rm -rf "$T"
fi
# fix2: the writers' flock file is lock state, like .lock.d — a restore must
# not bring it back, and on Linux this run may have created it empty.
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); : > "$T/$HX_LEGACY_LOGS_DIR/.lock"
run_up --apply --root "$T"; bk=$(bk_of "$T")
assert_exit "fix2 apply with a flock file present → exit 0" 0 "$rc"
lst=$( [ -n "$bk" ] && tar tzf "$bk" 2>/dev/null | sed 's#/$##' )
assert_exit "fix2 backup lists the legacy logs dir" 0 "$(printf '%s\n' "$lst" | grep -qxF -- "$HX_LEGACY_LOGS_DIR" && echo 0 || echo 1)"
assert_exit "fix2 backup carries no $HX_LEGACY_LOGS_DIR/.lock entry" 1 "$(printf '%s\n' "$lst" | grep -qxF -- "$HX_LEGACY_LOGS_DIR/.lock" && echo 0 || echo 1)"
rm -rf "$T"
# fix3 N2: after publication a v4 writer may hold an fd on the new dir's
# copied .lock; unlinking it on exit lets the next writer lock a fresh inode.
# The run removes only the mkdir lock dirs, never a flock file. A stand-in
# flock that always grants makes the flock path run on macOS too.
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); mkdir "$T.bin"
printf '#!/bin/sh\nexit 0\n' > "$T.bin/flock"; chmod +x "$T.bin/flock"
rc=0; out=$(PATH="$T.bin:$PATH" bash "$UP" --apply --no-backup --root "$T" 2>&1) || rc=$?
assert_exit "fix3-N2 apply via the flock path → exit 0" 0 "$rc"
assert_exit "fix3-N2 the new dir's flock file is never unlinked" 0 "$([ -f "$T/$HX_LOGS_DIR/.lock" ] && echo 0 || echo 1)"
assert_exit "fix3-N2 no .lock.d left in the new dir" 1 "$(hx_present "$T/$HX_LOGS_DIR/.lock.d" && echo 0 || echo 1)"
assert_exit "fix3-N2 no .lock.d left in the legacy dir" 1 "$(hx_present "$T/$HX_LEGACY_LOGS_DIR/.lock.d" && echo 0 || echo 1)"
rm -rf "$T"
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); printf 'not ours\n' > "$T/$HX_LEGACY_LOGS_DIR/.lock"
rc=0; out=$(PATH="$T.bin:$PATH" bash "$UP" --apply --no-backup --root "$T" 2>&1) || rc=$?
assert_exit "fix3-N2 apply with a pre-existing flock file → exit 0" 0 "$rc"
assert_contains "fix3-N2 a .lock the run did not create survives (copied into the new dir)" "$(cat "$T/$HX_LOGS_DIR/.lock" 2>/dev/null)" "not ours"
assert_exit "fix3-N2 no .lock.d left after a pre-existing flock file" 1 "$(hx_present "$T/$HX_LOGS_DIR/.lock.d" || hx_present "$T/$HX_LEGACY_LOGS_DIR/.lock.d" && echo 0 || echo 1)"
rm -rf "$T" "$T.bin"
MO="$ROOT_DIR/skills/handoffx/references/migration-order.md"
assert_contains "fix5-R2 migration order states the exact lock guarantee" "$(cat "$MO" 2>/dev/null)" "升级期间持有旧目录上的取号锁：阻止 v3 写入者**取号**，不保证整次写入互斥（取号锁在返回编号时即释放）；mkdir 分支下 \`.lock.d\` 会随目录复制进新目录、直到升级退出才删除，所以新目录在后置检查阶段对 mkdir 取号也是关的，对 flock 取号不关；迁移前必须先停止正在运行的 handoff 写入会话（§5.6 第 1–2 步）"
assert_not_contains "fix5-R2 migration order no longer claims write exclusion" "$(cat "$MO" 2>/dev/null)" "排斥 v3 写入者"
# fix3 N5: --scan-only exists only to run the scan; one that could not run
# is a refusal (exit 2), not a quiet 0. dry-run/apply keep it informational
# (C7 above). An unwritable TMPDIR makes the scan's mktemp fail.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ fix3-N5 unwritable TMPDIR --scan-only SKIPPED (root writes into mode-555 dirs)"
else
    T=$(mktemp -d); mkdir "$T/ro" "$T/p"; : > "$T/p/$HX_MAIN_FILE"; chmod 555 "$T/ro"
    rc=0; out=$(TMPDIR="$T/ro" bash "$UP" --scan-only --root "$T/p" 2>&1) || rc=$?
    assert_exit "fix3-N5 --scan-only with no usable temp dir → exit 2" 2 "$rc"
    assert_contains "fix3-N5 --scan-only refusal is a ❌ line" "$out" "❌ 残留扫描未执行"
    chmod 755 "$T/ro"; rm -rf "$T"
fi
# fix5 R3: a stage of the scan that fails after mktemp succeeded (here: the
# enumerating find exits 1 though it printed everything) was swallowed by
# `|| true` with an empty stderr file → "无旧名引用", exit 0. The shim fails
# only the scan's own `find … -print0`, so nothing else in the run changes.
T=$(mktemp -d); mkdir "$T/bin" "$T/p" "$T/v4"; mk_v3 "$T/p" || FAIL=$((FAIL+1)); : > "$T/v4/$HX_MAIN_FILE"
RF=$(command -v find)
printf '#!/bin/sh\n"%s" "$@"; r=$?\nfor a in "$@"; do [ "$a" = -print0 ] && exit 1; done\nexit $r\n' "$RF" > "$T/bin/find"; chmod +x "$T/bin/find"
rc=0; out=$(PATH="$T/bin:$PATH" bash "$UP" --dry-run --root "$T/p" 2>&1) || rc=$?
assert_exit "fix5-R3 failing find → dry-run still exit 0" 0 "$rc"
assert_contains "fix5-R3 failing find → dry-run says the scan is incomplete" "$out" "⚠️ 残留扫描不完整"
assert_not_contains "fix5-R3 failing find → no clean verdict" "$out" "✅ 项目其它文件无旧名引用"
assert_contains "fix5-R3 failing find → checklist still printed" "$out" "后续人工步骤"
rc=0; out=$(PATH="$T/bin:$PATH" bash "$UP" --scan-only --root "$T/v4" 2>&1) || rc=$?
assert_exit "fix5-R3 failing find → --scan-only exit 2" 2 "$rc"
assert_contains "fix5-R3 failing find → --scan-only ❌ line" "$out" "❌ 残留扫描不完整"
rc=0; out=$(bash "$UP" --scan-only --root "$T/v4" 2>&1) || rc=$?
assert_exit "fix5-R3 control: real find → --scan-only exit 0" 0 "$rc"
rm -rf "$T"

echo "── 18. symlinked root, flock writers, --scan-only (Codex C4/C5/C10)"
# C5: the ancestor walk used the logical path only; a root reached through a
# symlink skipped a marker that sits above the physical directory.
T=$(mktemp -d); mkdir -p "$T/real/.stfolder" "$T/real/p" "$T/view"; mk_v3 "$T/real/p" || FAIL=$((FAIL+1))
ln -s "$T/real/p" "$T/view/p"; sig=$(tree_sig "$T/real/p")
run_up --apply --root "$T/view/p"
assert_exit "C5 symlinked root, marker only above the physical dir → apply refused (exit 2)" 2 "$rc"
assert_contains "C5 the physical marker is named" "$out" ".stfolder at $(cd "$T/real" && pwd -P)"
assert_exit "C5 refusal writes nothing" 0 "$([ "$(tree_sig "$T/real/p")" = "$sig" ] && echo 0 || echo 1)"
rm -rf "$T"
# C4: on a flock system the writers lock <logs>/.lock with flock, which never
# sees the mkdir lock; the upgrade must hold that one too. Without flock here
# (macOS) a stand-in that reports "held" proves the refusal path; the real
# hold runs on Linux (container).
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); : > "$T/$HX_LEGACY_LOGS_DIR/.lock"; sig=$(tree_sig "$T")
if command -v flock >/dev/null 2>&1; then
    exec 8>"$T/$HX_LEGACY_LOGS_DIR/.lock"; flock 8
    rc=0; out=$(bash "$UP" --apply --no-backup --root "$T" 8>&- 2>&1) || rc=$?
    exec 8>&-
else
    mkdir "$T.bin"; printf '#!/bin/sh\nexit 1\n' > "$T.bin/flock"; chmod +x "$T.bin/flock"
    rc=0; out=$(PATH="$T.bin:$PATH" bash "$UP" --apply --no-backup --root "$T" 2>&1) || rc=$?
    rm -rf "$T.bin"
fi
assert_exit "C4 a held flock on the writers' lock file → apply refused (exit 2)" 2 "$rc"
assert_contains "C4 the flock lock file is named" "$out" "$T/$HX_LEGACY_LOGS_DIR/.lock"
assert_exit "C4 flock refusal writes nothing" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
run_up --apply --no-backup --root "$T"
assert_exit "C4 flock free → apply exit 0" 0 "$rc"
rm -rf "$T"
# C10: after --apply --quick the advertised follow-up must be able to run on
# the now-v4 tree; a dry-run there stops at "already handoffx".
T=$(mktemp -d); mk_v3 "$T" || FAIL=$((FAIL+1)); printf 'see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$T/README.md"
run_up --apply --quick --root "$T"
assert_contains "C10 --quick checklist names --scan-only" "$out" "--scan-only"
sig=$(tree_sig "$T")
run_up --scan-only --root "$T"
assert_exit "C10 --scan-only on a v4 tree → exit 0" 0 "$rc"
assert_contains "C10 --scan-only lists the leftover" "$(leftover_section "$out")" "README.md: 1 处 — L1:"
assert_exit "C10 --scan-only writes nothing into the project" 0 "$([ "$(tree_sig "$T")" = "$sig" ] && echo 0 || echo 1)"
full=$(printf '%s\n' "$out" | sed -n 's/^📄 完整清单: //p'); [ -n "$full" ] && rm -f "$full"
rm -rf "$T"

echo "── 9. contract"
# Code lines only: comments and echo/printf text may name git (the checklist
# tells the human to commit) without the script ever running it.
assert_file_exists "upgrade script exists (contract below is not vacuous)" "$UP"
code=$(grep -vE '^[[:space:]]*(#|echo|printf)' "$UP" 2>/dev/null)
# H3: the one git call allowed is the read-only "is this a work tree?" probe
# that decides whether a backup is needed; anything else (add/commit/…) is out.
gitl=$(printf '%s\n' "$code" | grep -E '(^|[;&|(`[:space:]])git[[:space:]]')
assert_exit "script's only git call is the read-only work-tree probe" 0 \
    "$([ -n "$gitl" ] && ! printf '%s\n' "$gitl" | grep -vqF 'git -C "$ROOT" rev-parse --is-inside-work-tree' && echo 0 || echo 1)"
assert_exit "script never reads the terminal" 1 "$(printf '%s\n' "$code" | grep -qE '(^|[;&|(`[:space:]])(read|select)[[:space:]]' && echo 0 || echo 1)"

summary
