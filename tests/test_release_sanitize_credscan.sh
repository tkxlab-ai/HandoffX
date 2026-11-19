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

# (4c) SH 私有 Git 服务（2026-11-02 起的唯一私有 remote）必须和 LAX 一样被映射成占位符。
# 本文件随公开 tarball 走：样本不能写在这里，连拆字拼接也不行（v4.1.1/v4.2.1
# 就是拆字发出去的，人能拼回来）。改为从脱敏器自己的 REPLACEMENTS 里按
# `# hx-test:` 标记读——脱敏器是 maintainer-only、公开树里会被删，本套件那时整体跳过。
# 同一文件放一个把 org 名含作子串的合法词（评估场景名 recall-fresh-teammate）：
# org 名若裸替换会把它改坏——映射必须带 `/` 形态，残留检查必须带词边界。
_sh_sample() { sed -n "s@^[[:space:]]*'s|\(.*\)|/\{0,1\}<private-[a-z-]*>/\{0,1\}|g'[[:space:]]*# hx-test:$1\$@\1@p" "$SANITIZE" | sed 's/\\//g' | head -1; }
SH_H=$(_sh_sample sh-host); SH_P=$(_sh_sample sh-port); SH_O=$(_sh_sample sh-org); SH_O=${SH_O//\//}
assert_exit "SH 样本从脱敏器的 hx-test 标记读到（主机/端口/org 都非空）" 0 "$([ -n "$SH_H" ] && [ -n "$SH_P" ] && [ -n "$SH_O" ] && echo 0 || echo 1)"
WT6="$(mktemp -d)"
printf '# Readme\n\nremote: ssh://git@%s:%s/%s/HandoffX.git\nscenario: recall-fresh-teammate\n' \
    "$SH_H" "$SH_P" "$SH_O" > "$WT6/README.md"
set +e
OUT6=$(bash "$SANITIZE" "$WT6" 2>&1)
RC6=$?
set -e
R6=$(cat "$WT6/README.md")
assert_exit "SH 主机/端口/org 被映射后 exit 0" 0 "$RC6"
assert_not_contains "SH 主机名已替换为占位符" "$R6" "$SH_H"
assert_not_contains "SH 端口已替换为占位符" "$R6" ":${SH_P}/"
assert_not_contains "SH org 已替换为占位符" "$R6" "/${SH_O}/"
assert_contains "占位符形态与 LAX 一致（<private-git-host>）" "$R6" "<private-git-host>"
assert_contains "recall-fresh-teammate 未被 org 替换误伤" "$R6" "recall-fresh-teammate"
rm -rf "$WT6"

# (4d) 脱敏只改 .md；一个 .sh 里带着 SH 主机名 → 全树残留检查必须 fail-closed。
WT7="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WT7/README.md"
printf 'git remote add origin ssh://git@%s:%s/%s/HandoffX.git\n' "$SH_H" "$SH_P" "$SH_O" > "$WT7/ci.sh"
set +e
OUT7=$(bash "$SANITIZE" "$WT7" 2>&1)
RC7=$?
set -e
rm -rf "$WT7"
assert_exit "非 .md 文件里的 SH 主机名 → 脱敏 fail-closed exit≠0" 1 "$RC7"
assert_contains "verdict 指明泄漏（sanitize failed）" "$OUT7" "sanitize failed"

# (4e) 安全审查两条：主机/org 残留检查须不分大小写（DNS 本就不分；大写写法不能溜过），
# 端口按 LAX 先例裸替换（散文里「SSH 端口 <数字>」也要变占位符）。
SH_HU=$(printf '%s' "$SH_H" | tr 'a-z' 'A-Z'); SH_OU=$(printf '%s' "$SH_O" | tr 'a-z' 'A-Z')
WT8="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WT8/README.md"
printf 'host %s org %s\n' "$SH_HU" "$SH_OU" > "$WT8/ci.sh"
set +e
OUT8=$(bash "$SANITIZE" "$WT8" 2>&1)
RC8=$?
set -e
rm -rf "$WT8"
assert_exit "大写写法的 SH 主机/org 在 .sh 里 → 仍 fail-closed exit≠0" 1 "$RC8"
WT9="$(mktemp -d)"
printf '# Readme\n\nSSH 端口 %s 已开放\n' "$SH_P" > "$WT9/README.md"
set +e
OUT9=$(bash "$SANITIZE" "$WT9" 2>&1)
RC9=$?
set -e
R9=$(cat "$WT9/README.md")
rm -rf "$WT9"
assert_exit "散文里的 SH 端口被裸替换后 exit 0" 0 "$RC9"
assert_not_contains "散文里的 SH 端口已替换为占位符" "$R9" "$SH_P"
assert_contains "占位符为 <private-port>" "$R9" "<private-port>"

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

# (6) parity (W1, v4.1.1): the three maintainer gates promise to mirror
# scan-credentials' PATTERNS "逐条对齐" — only comments said so, and a rule
# added to the scanner alone would let the public mirror / release assets
# carry what the handoff gate blocks. Compare the evaluated arrays (quoting
# may differ, the regex strings may not).
_arr() { bash -c 'eval "$(sed -n "/^$2=(/,/^)/p" "$1")"; printf "%s\n" "${'"$2"'[@]}"' _ "$1" "$2"; }
CANON=$(_arr "$ROOT_DIR/scripts/scan-credentials.sh" PATTERNS)
assert_exit "parity: canonical PATTERNS extracted (14 rules)" 14 "$(printf '%s\n' "$CANON" | grep -c .)"
for g in release-sanitize-public.sh release-publish-github.sh release-publish-github-backfill.sh; do
    MIRROR=$(_arr "$ROOT_DIR/scripts/$g" CREDENTIAL_PATTERNS)
    if [ "$MIRROR" = "$CANON" ]; then
        echo "  ✅ parity: $g CREDENTIAL_PATTERNS == scan-credentials PATTERNS"; PASS=$((PASS+1))
    else
        echo "  ❌ parity: $g CREDENTIAL_PATTERNS differs from scan-credentials PATTERNS"; FAIL=$((FAIL+1))
        diff <(printf '%s\n' "$CANON") <(printf '%s\n' "$MIRROR") | sed -n '1,6p'
    fi
done

# fix3 N4: the header rule needs a second step (drop an all-placeholder
# value) that an array cannot carry — so the helper block itself must be
# byte-identical in all four gates, or one of them filters differently.
_blk() { sed -n '/^# ── credential placeholder filter (fix3 N4)/,/^# ── end credential placeholder filter/p' "$1"; }
CBLK=$(_blk "$ROOT_DIR/scripts/scan-credentials.sh")
assert_exit "parity: scan-credentials carries the placeholder filter block" 0 "$(printf '%s\n' "$CBLK" | grep -q '^cred_tree_hits() {' && echo 0 || echo 1)"
for g in release-sanitize-public.sh release-publish-github.sh release-publish-github-backfill.sh; do
    if [ "$(_blk "$ROOT_DIR/scripts/$g")" = "$CBLK" ]; then
        echo "  ✅ parity: $g placeholder filter block == scan-credentials'"; PASS=$((PASS+1))
    else
        echo "  ❌ parity: $g placeholder filter block differs from scan-credentials'"; FAIL=$((FAIL+1))
    fi
done
# and the sanitizer applies it: x+19 is a hit, an all-x value is not.
A19=aaaaaaaaaaaaaaaaaaa; X40=$(printf '%s' "$A19$A19" | tr a x)xx
for v in "x$A19:1" "_$A19:1" "$X40:0"; do
    WTN="$(mktemp -d)"
    printf '# Readme\n\nclean\n' > "$WTN/README.md"
    printf 'curl -H "Authorization: Bearer %s"\n' "${v%:*}" > "$WTN/ci.sh"
    set +e; bash "$SANITIZE" "$WTN" >/dev/null 2>&1; RCN=$?; set -e
    rm -rf "$WTN"
    assert_exit "fix3-N4 sanitizer: header value ${v:0:1}…(${#v} incl. tag) → exit ${v##*:}" "${v##*:}" "$RCN"
done

# fix5 R1: the second-pass filter re-read `grep -l` output line by line, so
# a file whose NAME holds a newline split into two other names; with clean
# files sitting at those two names the real hit was dropped → exit 0. Names
# now travel NUL-separated. Credential assembled at runtime.
WTR="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WTR/README.md"
printf 'clean\n' > "$WTR/x.sh"
printf 'curl -H "Authorization: Bearer x%s"\n' "$A19" > "$WTR/x.sh
README.md"
set +e; OUTR=$(bash "$SANITIZE" "$WTR" 2>&1); RCR=$?; set -e
rm -rf "$WTR"
assert_exit "fix5-R1 sanitizer: hit in a file whose name holds a newline → exit 1" 1 "$RCR"
assert_contains "fix5-R1 sanitizer: verdict names the failure" "$OUTR" "sanitize failed"

# (7) the forge-token rules reach the full-tree gate (a .sh is not redacted,
# so this is the only thing between a pasted header and the public mirror),
# and the scanner's own source — which now spells those rules — passes it
# (no self-match, no forge name in a non-.md file). Samples assembled at runtime.
H10="0123456789"; HEX40="${H10}abcdef${H10}abcdef01234567"
WT10="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WT10/README.md"
printf 'curl -H "Authorization: token %s" https://forge.example/api\n' "$HEX40" > "$WT10/ci.sh"
set +e; OUT10=$(bash "$SANITIZE" "$WT10" 2>&1); RC10=$?; set -e
rm -rf "$WT10"
assert_exit "Authorization: token <hex40> in a .sh → 脱敏 fail-closed exit≠0" 1 "$RC10"
assert_contains "verdict 指明泄漏（sanitize failed）" "$OUT10" "sanitize failed"
WT11="$(mktemp -d)"
mkdir "$WT11/scripts"; cp "$ROOT_DIR/scripts/scan-credentials.sh" "$WT11/scripts/"
set +e; OUT11=$(bash "$SANITIZE" "$WT11" 2>&1); RC11=$?; set -e
rm -rf "$WT11"
assert_exit "scan-credentials.sh 源码自身过脱敏门禁（规则不自命中、无私有字样）" 0 "$RC11"
if [ "$RC11" -ne 0 ]; then printf '%s\n' "$OUT11" | grep -E '❌' | head -5; fi

# (8) Codex C1: the forge-context rule keys on the forge's name in the line,
# and the .md redaction rewrites that name — `<forge> token=<hex40>` lost its
# context before the post-redaction scan and shipped. The credential rules now
# also run on the original tree, before any redaction. Pieces built at runtime.
FGN="Git"; FGN="${FGN}ea"
WT12="$(mktemp -d)"
printf '# Notes\n\n%s api token=%s\n' "$FGN" "$HEX40" > "$WT12/README.md"
set +e; OUT12=$(bash "$SANITIZE" "$WT12" 2>&1); RC12=$?; set -e
rm -rf "$WT12"
assert_exit "C1: context-only forge token in a .md → 脱敏 fail-closed exit≠0" 1 "$RC12"
assert_contains "C1: verdict 指明泄漏（sanitize failed）" "$OUT12" "sanitize failed"
# fix1 I3: the x-initial header token and the JSON-key form reach the gate too
WT13="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WT13/README.md"
printf '{ "%s_TOKEN": "%s" }\n' "$(printf '%s' "$FGN" | tr 'a-z' 'A-Z')" "$HEX40" > "$WT13/settings.json"
set +e; OUT13=$(bash "$SANITIZE" "$WT13" 2>&1); RC13=$?; set -e
rm -rf "$WT13"
assert_exit "I3: JSON \"<FORGE>_TOKEN\": \"<hex40>\" in a .json → 脱敏 fail-closed exit≠0" 1 "$RC13"
WT14="$(mktemp -d)"
printf '# Readme\n\nclean\n' > "$WT14/README.md"
printf 'curl -H "Authorization: Bearer x%s"\n' "${HEX40#?}" > "$WT14/ci.sh"
set +e; OUT14=$(bash "$SANITIZE" "$WT14" 2>&1); RC14=$?; set -e
rm -rf "$WT14"
assert_exit "I3: x-initial Bearer token in a .sh → 脱敏 fail-closed exit≠0" 1 "$RC14"

# m4 (fix wave 2): the migrator writes its backup under the LEGACY main name;
# after the T0 constant flip the DEV_ONLY entry silently became the new-name
# backup, which nothing produces. Both names must be stripped.
dev_only=$(awk '/^DEV_ONLY=\(/,/^\)/' "$SANITIZE")
for bk in '${HX_MAIN_FILE}.pre-v2-backup' '${HX_LEGACY_MAIN_FILE}.pre-v2-backup'; do
    assert_contains "m4: DEV_ONLY strips $bk" "$dev_only" "\"$bk\""
done

summary
