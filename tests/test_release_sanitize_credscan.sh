#!/bin/bash
# test_release_sanitize_credscan.sh — 公开脱敏门禁必须拦住私钥
#
# 回归 CRITICAL-A（2026-06-07 三异构源 audit）：release-sanitize-public.sh
# Step 3 全树凭证扫描所有 grep 调用缺 `--`，凭证 pattern 第 11 条
# `-----BEGIN…PRIVATE KEY-----` 以 `-` 开头被 grep 当选项 → 报错 → `2>/dev/null`
# 吞 → 计 0 命中（Gotcha #1 母题在 publish 流水线的未修复实例 + #18/#24 fail-open）。
# 真私钥曾能 exit 0「0 leaks remain」推到公开镜像。同根 grep 缺 `--` 还散落在
# release-publish-github{,-backfill}.sh 的 fulltree_credscan/scan_skill_asset/
# scan_public_file——本测试守 sanitize 这道全树门禁，是该类的 load-bearing 哨兵。
#
# load-bearing 判据（Gotcha #25）：断言键在 gate 判决——exit≠0 + 「sanitize
# failed」verdict 行，不键在循环里的诊断 echo。把任一 grep 的 `--` 撤掉本测试必 RED。
#
# 私钥标记运行时拼接（源码里只有 `${D}BEGIN…${D}`，无连续 `-----BEGIN…-----`），
# 使本测试文件自身不被任何凭证扫描器命中——否则进公开镜像 source tarball 会
# 自我触发（Gotcha #18「门禁扫到自己的测试样本」母题）。
source "$(dirname "$0")/common.sh"

SANITIZE="$ROOT_DIR/scripts/release-sanitize-public.sh"
if [ ! -f "$SANITIZE" ]; then
    # 公开镜像把 maintainer-only release-* 脚本删了（DEV_ONLY）——缺席静默跳过，
    # 私仓 / dev 仍跑该断言（与 test_release_artifact_content.sh skip 范式一致）。
    echo "  ➖ release-sanitize-public.sh 不在，跳过（公开镜像已删 maintainer-only 脚本）"
    summary
    exit 0
fi

# 运行时拼接私钥标记——源码只见 `${D}BEGIN…${D}`，扫描器扫本文件不命中
D="-----"
KEY_MARKER="${D}BEGIN OPENSSH PRIVATE KEY${D}"
KEY_FOOTER="${D}END OPENSSH PRIVATE KEY${D}"

WT="$(mktemp -d)"
trap 'rm -rf "$WT"' EXIT

# 植入存活路径：README.md 不在 DEV_ONLY 删除清单，脱敏后仍在树里 → Step 3 必须扫到。
# base64 体故意无其他凭证 pattern，确保 RED 阶段只由私钥这一条触发（隔离信号）。
printf '# Public Readme\n\n%s\nb3blbnNzaGZ4ZTawMGZ4ZTawMA\n%s\n' \
    "$KEY_MARKER" "$KEY_FOOTER" > "$WT/README.md"

set +e
OUT=$(bash "$SANITIZE" "$WT" 2>&1)
RC=$?
set -e

# (1) gate 判决：含私钥时脱敏必须 fail-closed exit≠0（不是 0「0 leaks remain」）
assert_exit "私钥在存活路径 → 脱敏 fail-closed exit≠0" 1 "$RC"
# (2) verdict 键在 gate 判决文案，非诊断 echo（Gotcha #25 load-bearing）
assert_contains "脱敏 verdict 指明泄漏（sanitize failed）" "$OUT" "sanitize failed"

# (3) 不可读子目录 → Step 3 的 `grep -r … 2>/dev/null | wc -l` 曾把「读不到」
# 坍缩成「0 命中」→ exit 0「0 leaks remain」（Gotcha #24，twin of CRITICAL-B /
# scan-credentials）。门禁声称的是「全树扫过」，扫不全就必须拒绝报 clean——
# 与里面有没有私钥无关。键在 verdict 文案 + exit≠0（非循环诊断 echo）。
# root-skip：EUID=0 绕过 chmod 000，场景不可构造（Gotcha #15 / B7-a 同范式）。
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ 不可读子目录控制 SKIPPED（root bypasses chmod 000）"
else
    WT2="$(mktemp -d)"
    printf '# Public Readme\n\nclean\n' > "$WT2/README.md"
    mkdir "$WT2/vendor"; printf 'clean\n' > "$WT2/vendor/notes.md"
    chmod 000 "$WT2/vendor"
    set +e
    OUT2=$(bash "$SANITIZE" "$WT2" 2>&1)
    RC2=$?
    set -e
    chmod 755 "$WT2/vendor"; rm -rf "$WT2"
    assert_exit "不可读子目录 → 脱敏 fail-closed exit≠0（不是「0 leaks」）" 1 "$RC2"
    # needle 必须是 verdict 整句：循环里的诊断行也含「cannot scan」，只键
    # 「cannot scan」会被诊断 echo 满足而对 verdict 缺席视而不见（#25 M4）。
    assert_contains "脱敏 verdict 指明扫不全（sanitize failed — cannot scan）" "$OUT2" "sanitize failed — cannot scan"
fi

# (4) 正控：干净树必须 exit 0 + 「0 leaks remain」。没有它，把「grep rc>1 才算
# 扫不全」误改成「rc>0」（即「无命中」也算扫不全）会让每次发布必 fail 而无测试察觉。
WT3="$(mktemp -d)"
printf '# Public Readme\n\nclean\n' > "$WT3/README.md"
mkdir "$WT3/docs"; printf 'clean\n' > "$WT3/docs/notes.md"
set +e
OUT3=$(bash "$SANITIZE" "$WT3" 2>&1)
RC3=$?
set -e
rm -rf "$WT3"
assert_exit "干净树 → 脱敏 exit 0" 0 "$RC3"
assert_contains "干净树 verdict 为 0 leaks remain" "$OUT3" "0 leaks remain"

# (4b) Step 2 的「N 个文件被改」曾只比最后一条表达式的 .bak：README 里的私有 org 名
# 被换成占位符后仍报「0 个文件被改」。org 名运行时拼接（本文件随公开 tarball 走）。
WT5="$(mktemp -d)"; L1="lax"
printf '# Readme

org: %s-team
' "$L1" > "$WT5/README.md"
set +e
OUT5=$(bash "$SANITIZE" "$WT5" 2>&1)
RC5=$?
set -e
assert_exit "脱敏替换后 exit 0（替换本身不算泄漏）" 0 "$RC5"
assert_contains "Step 2 计数报告 1 个文件被改（非 0）" "$OUT5" "1 个文件被改"
assert_not_contains "README 里的私有 org 名已被替换" "$(cat "$WT5/README.md")" "${L1}-team"
rm -rf "$WT5"

# (5) 结构性守卫：仓库自身的 tests/*.sh 随公开 source tarball 发布，sanitize 无
# allowlist——任何测试脚本写死一个像样的凭证/隐私字面量，下一次真实 publish 就会
# 被自己的样本拦下（Gotcha #18「门禁扫到自己的测试样本」；2026-10-29 新套件亲犯）。
# 只拷顶层 *.sh：fixtures/ 是 DEV_ONLY 必删，.tmp/ 是本地 scratch（上万文件，
# 拷进去既慢又带假命中）。sanitize 自己会删 test_sync_memory.sh（DEV_ONLY）。
WT4="$(mktemp -d)"
mkdir "$WT4/tests"; cp "$ROOT_DIR"/tests/*.sh "$WT4/tests/"
set +e
OUT4=$(bash "$SANITIZE" "$WT4" 2>&1)
RC4=$?
set -e
rm -rf "$WT4"
assert_exit "仓库自身 tests/*.sh 过脱敏门禁（没有测试把凭证/隐私字面量带进公开树）" 0 "$RC4"
if [ "$RC4" -ne 0 ]; then printf '%s\n' "$OUT4" | grep -E '❌' | head -5; fi

# m4 (fix wave 2): the migrator writes its backup under the LEGACY main name;
# after the T0 constant flip the DEV_ONLY entry silently became the new-name
# backup, which nothing produces. Both names must be stripped.
dev_only=$(awk '/^DEV_ONLY=\(/,/^\)/' "$SANITIZE")
for bk in '${HX_MAIN_FILE}.pre-v2-backup' '${HX_LEGACY_MAIN_FILE}.pre-v2-backup'; do
    assert_contains "m4: DEV_ONLY strips $bk" "$dev_only" "\"$bk\""
done

summary
