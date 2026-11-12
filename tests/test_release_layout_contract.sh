#!/bin/bash
# test_release_layout_contract.sh — P2.2b release-layout contract: the single
# dev-only lib (scripts/release-layout.sh) decides handoff- vs handoffx- per
# version, so release.sh / publishers / this test can never drift apart.
# No gitx, no run_all, no Release/ — everything lives in a mktemp sandbox.
source "$(dirname "$0")/common.sh"

LIB="$SCRIPTS_DIR/release-layout.sh"
# outside the repo on purpose: release.sh --sandbox refuses any in-repo outdir (tests/.tmp too)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/release-layout.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# LIB is deliberately not exported: the subprocess gets it as $1, and a failed
# `.` propagates its status instead of running the function against nothing.
run_lib() { /bin/bash -c '. "$1" || exit $?; shift; "$@"' _ "$LIB" "$@"; }

# --- 前置工具：缺失即 ❌（绝不 ➖ 跳过——缺工具时契约无从证明）---
for t in zip unzip tar; do
    if command -v "$t" >/dev/null 2>&1; then
        assert_exit "tool present: $t" 0 0
    else
        assert_exit "tool present: $t" 0 1
    fi
done
if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    assert_exit "tool present: sha256sum|shasum" 0 0
else
    assert_exit "tool present: sha256sum|shasum" 0 1
fi

# --- lib: release_prefix ---
for v in v2.2.2 v2.10.0; do
    out=$(run_lib release_prefix "$v"); rc=$?
    assert_exit "release_prefix $v exit 0" 0 "$rc"
    assert_exit "release_prefix $v = handoff" 0 "$([ "$out" = "handoff" ] && echo 0 || echo 1)"
done
for v in v3.0.0 v10.0.0; do
    out=$(run_lib release_prefix "$v"); rc=$?
    assert_exit "release_prefix $v exit 0" 0 "$rc"
    assert_exit "release_prefix $v = handoffx" 0 "$([ "$out" = "handoffx" ] && echo 0 || echo 1)"
done
for v in 3.0.0 v3 v3.0.0-rc1 v03.0.0 v3.00.0; do
    out=$(run_lib release_prefix "$v"); rc=$?
    assert_exit "release_prefix $v invalid -> exit 2" 2 "$rc"
    assert_exit "release_prefix $v invalid -> empty stdout" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
done
out=$(RENAME_FROM=v9.0.0 run_lib release_prefix v3.0.0); rc=$?
assert_exit "RENAME_FROM=v9.0.0: v3.0.0 exit 0" 0 "$rc"
assert_exit "RENAME_FROM=v9.0.0: v3.0.0 = handoff" 0 "$([ "$out" = "handoff" ] && echo 0 || echo 1)"
out=$(RENAME_FROM=v2.9.0 run_lib release_prefix v2.10.0); rc=$?
assert_exit "RENAME_FROM=v2.9.0: v2.10.0 exit 0" 0 "$rc"
assert_exit "RENAME_FROM=v2.9.0: v2.10.0 = handoffx (numeric, not string compare)" 0 "$([ "$out" = "handoffx" ] && echo 0 || echo 1)"
out=$(RENAME_FROM=bogus run_lib release_prefix v3.0.0); rc=$?
assert_exit "RENAME_FROM=bogus -> exit 2" 2 "$rc"
assert_exit "RENAME_FROM=bogus -> empty stdout" 0 "$([ -z "$out" ] && echo 0 || echo 1)"

# --- errexit 调用方（root release.sh 是 set -e）：合法旧版本不得静默中止 ---
out=$(/bin/bash -c 'set -e; . "$1" || exit $?; release_prefix v2.2.2; echo after' _ "$LIB" 2>&1); rc=$?
assert_exit "set -e: release_prefix v2.2.2 continues (exit 0)" 0 "$rc"
assert_exit "set -e: release_prefix v2.2.2 prints handoff then after" 0 "$([ "$out" = "$(printf 'handoff\nafter')" ] && echo 0 || echo 1)"
out=$(/bin/bash -c 'set -e; . "$1" || exit $?; release_prefix v3; echo after' _ "$LIB" 2>&1); rc=$?
assert_exit "set -e: release_prefix v3 invalid still exits 2" 2 "$rc"
assert_not_contains "set -e: invalid version stops before after" "$out" "after"

# --- lib: release_dir_for / release_asset ---
out=$(run_lib release_dir_for v3.0.0)
assert_exit "release_dir_for v3.0.0 = Release/handoffx-v3.0.0" 0 "$([ "$out" = "Release/handoffx-v3.0.0" ] && echo 0 || echo 1)"
out=$(run_lib release_asset v2.2.2 skill)
assert_exit "release_asset v2.2.2 skill = handoff-v2.2.2.skill" 0 "$([ "$out" = "handoff-v2.2.2.skill" ] && echo 0 || echo 1)"
out=$(run_lib release_asset v3.0.0 full)
assert_exit "release_asset v3.0.0 full = handoffx-v3.0.0-full.tar.gz" 0 "$([ "$out" = "handoffx-v3.0.0-full.tar.gz" ] && echo 0 || echo 1)"
assert_exit "release_asset v3.0.0 bogus -> exit 2" 2 "$(run_lib release_asset v3.0.0 bogus >/dev/null 2>&1; echo $?)"
# 非法版本：调用方据 rc=2 中止，stdout 必须空（不能拼出 "Release/-v3" 之类的半截名）
out=$(run_lib release_dir_for v3); rc=$?
assert_exit "release_dir_for v3 invalid -> exit 2" 2 "$rc"
assert_exit "release_dir_for v3 invalid -> empty stdout" 0 "$([ -z "$out" ] && echo 0 || echo 1)"
out=$(run_lib release_asset v3 skill); rc=$?
assert_exit "release_asset v3 skill invalid -> exit 2" 2 "$rc"
assert_exit "release_asset v3 skill invalid -> empty stdout" 0 "$([ -z "$out" ] && echo 0 || echo 1)"

# --- lib: verify_release_integrity ---
out=$(run_lib verify_release_integrity "$WORK/nope" v3.0.0 2>&1); rc=$?
assert_exit "verify_release_integrity missing dir -> exit 1" 1 "$rc"
assert_contains "verify_release_integrity missing dir diagnostic" "$out" "missing dir"
# 存在但读不进的目录：每个资产都会报 "missing or empty"，把权限问题误导成产物缺失
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ verify_release_integrity unreadable dir SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    ud="$WORK/unreadable"; mkdir "$ud"; chmod 000 "$ud"
    out=$(run_lib verify_release_integrity "$ud" v3.0.0 2>&1); rc=$?
    chmod 755 "$ud"
    assert_exit "verify_release_integrity chmod 000 dir -> exit 1" 1 "$rc"
    assert_contains "verify_release_integrity chmod 000 dir diagnostic" "$out" "unreadable dir"
fi

# --- 端到端：根 release.sh --sandbox 造同形产物，lib 的 verify 认它 ---
RELEASE="$ROOT_DIR/release.sh"
# if/else 与 lib 同形：sha256sum 失败不得落到 shasum
sha_check() { if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1"; else shasum -a 256 -c "$1"; fi; }
sha_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

SB="$WORK/sb"
D3="$SB/handoffx-v3.0.0"
out=$(/bin/bash "$RELEASE" --sandbox v3.0.0 "$SB" 2>&1); rc=$?
assert_exit "--sandbox v3.0.0 exit 0" 0 "$rc"
assert_contains "--sandbox v3.0.0 last line" "$(printf '%s\n' "$out" | tail -n 1)" "✅ sandbox layout → "
assert_exit "--sandbox v3.0.0 dir handoffx-v3.0.0 exists" 0 "$([ -d "$D3" ] && echo 0 || echo 1)"
for f in handoffx-v3.0.0.skill handoffx-v3.0.0-source.tar.gz RELEASE_NOTES.md sbom.cyclonedx.json checksums.txt; do
    assert_exit "sandbox v3.0.0 non-empty: $f" 0 "$([ -s "$D3/$f" ] && echo 0 || echo 1)"
done
first=$(unzip -l "$D3/handoffx-v3.0.0.skill" 2>/dev/null | awk 'NR==4 {print $NF}')
assert_exit "sandbox .skill first entry under handoffx/ (got: $first)" 0 "$(case "$first" in (handoffx/*) echo 0 ;; (*) echo 1 ;; esac)"
first=$(tar tzf "$D3/handoffx-v3.0.0-source.tar.gz" 2>/dev/null | head -n 1)
assert_exit "sandbox tarball root handoffx-v3.0.0/ (got: $first)" 0 "$(case "$first" in (handoffx-v3.0.0/*) echo 0 ;; (*) echo 1 ;; esac)"
n=$(wc -l < "$D3/checksums.txt" 2>/dev/null | tr -d ' ')
assert_exit "sandbox checksums.txt has 3 lines (got: $n)" 0 "$([ "$n" = "3" ] && echo 0 || echo 1)"
cks=$(cat "$D3/checksums.txt" 2>/dev/null)
for f in handoffx-v3.0.0.skill handoffx-v3.0.0-source.tar.gz sbom.cyclonedx.json; do
    assert_contains "sandbox checksums.txt lists $f" "$cks" "  $f"
done
assert_exit "sandbox checksums verify (sha256sum|shasum -c)" 0 "$(cd "$D3" 2>/dev/null && sha_check checksums.txt >/dev/null 2>&1; echo $?)"
notes=$(cat "$D3/RELEASE_NOTES.md" 2>/dev/null)
assert_contains "sandbox RELEASE_NOTES title" "$notes" "# HandoffX v3.0.0 — Release Notes"
assert_contains "sandbox RELEASE_NOTES names the .skill" "$notes" "handoffx-v3.0.0.skill"
# 沙箱不平摊文档、不放 install.sh：说明里提到它就是在指一个不存在的文件
assert_not_contains "sandbox RELEASE_NOTES does not mention install.sh" "$notes" "install.sh"
out=$(run_lib verify_release_integrity "$D3" v3.0.0 2>&1); rc=$?
assert_exit "verify_release_integrity sandbox v3.0.0 -> 0" 0 "$rc"
out=$(run_lib verify_release_integrity "$D3" v3 2>&1); rc=$?
assert_exit "verify_release_integrity invalid version -> exit 1" 1 "$rc"
assert_contains "verify_release_integrity invalid version diagnostic" "$out" "invalid version"

out=$(/bin/bash "$RELEASE" --sandbox v2.9.9 "$SB" 2>&1); rc=$?
assert_exit "--sandbox v2.9.9 exit 0" 0 "$rc"
assert_file_exists "--sandbox v2.9.9 keeps old prefix" "$SB/handoff-v2.9.9/handoff-v2.9.9.skill"
# 旧纪元 fixture 须忠实：已发布的 handoff-v2.2.2.skill 根是 handoff/，沙箱同形
first=$(unzip -l "$SB/handoff-v2.9.9/handoff-v2.9.9.skill" 2>/dev/null | awk 'NR==4 {print $NF}')
assert_exit "sandbox v2.9.9 .skill first entry under handoff/ (got: $first)" 0 "$(case "$first" in (handoff/*) echo 0 ;; (*) echo 1 ;; esac)"
out=$(run_lib verify_release_integrity "$SB/handoff-v2.9.9" v2.9.9 2>&1); rc=$?
assert_exit "verify_release_integrity sandbox v2.9.9 -> 0" 0 "$rc"

# 目标已存在：拒绝且不动原产物
cp "$D3/checksums.txt" "$WORK/checksums.before" 2>/dev/null
out=$(/bin/bash "$RELEASE" --sandbox v3.0.0 "$SB" 2>&1); rc=$?
assert_exit "--sandbox target exists -> exit 1" 1 "$rc"
assert_contains "--sandbox target exists diagnostic" "$out" "already exists"
assert_exit "--sandbox target exists leaves checksums.txt untouched" 0 "$(cmp -s "$WORK/checksums.before" "$D3/checksums.txt"; echo $?)"

/bin/bash "$RELEASE" --sandbox v3.0 "$WORK/sb2" >/dev/null 2>&1; rc=$?
assert_exit "--sandbox v3.0 (two-segment) -> exit 1" 1 "$rc"
assert_exit "--sandbox v3.0 creates nothing" 0 "$([ ! -e "$WORK/sb2" ] && echo 0 || echo 1)"
/bin/bash "$RELEASE" --sandbox >/dev/null 2>&1; rc=$?
assert_exit "--sandbox no args -> exit 1" 1 "$rc"
/bin/bash "$RELEASE" --sandbox v3.0.0 >/dev/null 2>&1; rc=$?
assert_exit "--sandbox without outdir -> exit 1" 1 "$rc"

# C4：outdir 落在仓内一律拒绝，且什么都不写。承重的仓内用例用 tests/.tmp 下的私有路径——
# 生产者永远不会预建它，所以"不存在"在任何环境下都成立
INREPO="$ROOT_DIR/tests/.tmp/inrepo-$$"
/bin/bash "$RELEASE" --sandbox v3.0.0 "$INREPO" >/dev/null 2>&1; rc=$?
assert_exit "--sandbox v3.0.0 <repo>/tests/.tmp/… -> exit 1" 1 "$rc"
assert_exit "--sandbox in-repo tmp path creates nothing" 0 "$([ ! -e "$INREPO" ] && echo 0 || echo 1)"
# A1：仓根 basename 大小写翻转。大小写不敏感的 APFS 上它就是仓本身，字符串前缀比较认不出；
# 大小写敏感的 FS 上它是仓外一个不存在的兄弟路径——跑生产者会在仓旁合法地建目录，
# 所以只断言"它不是仓"，两支断言数相同
CI_ROOT="$(dirname "$ROOT_DIR")/$(basename "$ROOT_DIR" | tr '[:lower:][:upper:]' '[:upper:][:lower:]')"
CI_OUT="$CI_ROOT/tests/.tmp/inrepo-ci-$$"
if [ "$CI_ROOT" -ef "$ROOT_DIR" ]; then
    /bin/bash "$RELEASE" --sandbox v3.0.0 "$CI_OUT" >/dev/null 2>&1; rc=$?
    assert_exit "--sandbox case-mangled repo path -> exit 1" 1 "$rc"
    assert_exit "--sandbox case-mangled repo path creates nothing" 0 "$([ ! -e "$CI_OUT" ] && echo 0 || echo 1)"
    rm -rf "$CI_OUT"   # 回归红时生产者已写进仓内 tests/.tmp，不留垃圾
else
    assert_exit "case-sensitive FS: case-mangled repo path is not the repo" 0 "$([ ! -e "$CI_ROOT" ] && echo 0 || echo 1)"
    assert_exit "case-sensitive FS: nothing created at the case-mangled path" 0 "$([ ! -e "$CI_OUT" ] && echo 0 || echo 1)"
fi
# Release/ 用例只断言"被拒的调用没改动任何东西"，不断言目录不存在：gitx 在跑本测试之前
# 就已经预建了空的 Release/handoffx-v3.0.0/（Gotcha #14 形态：发版前门禁不得断言生产者阶段的状态）
rel_snap() {
    ls -1 "$ROOT_DIR/Release" 2>/dev/null | sort
    if [ -d "$ROOT_DIR/Release/handoffx-v3.0.0" ]; then echo "--"; ls -1A "$ROOT_DIR/Release/handoffx-v3.0.0"; fi
}
snap_before=$(rel_snap)
out=$(cd "$ROOT_DIR" && /bin/bash "$RELEASE" --sandbox v3.0.0 Release 2>&1); rc=$?
assert_exit "--sandbox v3.0.0 Release (in-repo) -> exit 1" 1 "$rc"
assert_contains "--sandbox in-repo diagnostic" "$out" "outside the repository"
assert_exit "--sandbox Release refusal leaves Release/ unchanged (snapshot before == after)" 0 "$([ "$snap_before" = "$(rel_snap)" ] && echo 0 || echo 1)"
# C4：源码 tarball 不夹带本机工作区（publish worktree 含嵌套 .git、SDD 工作区、编辑器配置）
n=$(tar tzf "$D3/handoffx-v3.0.0-source.tar.gz" 2>/dev/null | grep -cE '\.github-publish-wt/|\.superpowers/|\.cursor/')
assert_exit "sandbox tarball has no .github-publish-wt/.superpowers/.cursor entries (got: $n)" 0 "$([ "$n" = "0" ] && echo 0 || echo 1)"
# 根级禁止项（两套命名都禁）：只禁"前缀/ 之后紧跟"的根位置——fixture 里嵌套的同名输入数据是合法的，
# 未锚定的排除会把它们一并吃掉（P2.4 之前 gitx 的 rsync 路径就是这样）。名字取自常量，改名不用改这里。
_re() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
FILES_RE="$(_re "$HX_GOTCHAS_FILE")|CLAUDE\\.md"
DIRS_RE=""
for _n in "$HX_MAIN_FILE" "$HX_LEGACY_MAIN_FILE"; do
    FILES_RE="$FILES_RE|$(_re "$_n")([.]bak.*|[.]pre-v2-backup)?|$(_re "${_n%.md}.archive.md")"
done
for _n in "$HX_LOGS_DIR" "$HX_LEGACY_LOGS_DIR" "$HX_DEC_DIR" "$HX_LEGACY_DEC_DIR"; do
    DIRS_RE="$DIRS_RE|$(_re "$_n")([.]archive)?/"
done
SB_LIST=$(tar tzf "$D3/handoffx-v3.0.0-source.tar.gz" 2>/dev/null | sed 's|^handoffx-v3\.0\.0/||')
n=$(printf '%s\n' "$SB_LIST" | grep -cE "^($FILES_RE)$|^(${DIRS_RE#|})")
assert_exit "sandbox tarball has no root-level four-piece/GOTCHAS/CLAUDE.md entries (got: $n)" 0 "$([ "$n" = "0" ] && echo 0 || echo 1)"
# 夹具正向：合成 v2 夹具是输入数据，必须留在包内，否则源码包里迁移/dogfood 套件无语料
# (stored under neutral names — gitx rejects the legacy names at any depth; see p21_materialize)
assert_exit "sandbox tarball keeps tests/fixtures/p2-1-synthetic-v2/legacy-main.md" 0 "$(printf '%s\n' "$SB_LIST" | grep -qxF "tests/fixtures/p2-1-synthetic-v2/legacy-main.md"; echo $?)"

# --- 负向：各在 cp -R 副本上破坏一处，verify 必须 1 且诊断点名 ---
neg="$WORK/neg1"; cp -R "$D3" "$neg"; rm -f "$neg/checksums.txt"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg1 checksums.txt removed -> 1" 1 "$rc"
assert_contains "neg1 diagnostic" "$out" "missing or empty"

neg="$WORK/neg2"; cp -R "$D3" "$neg"; printf ' ' >> "$neg/sbom.cyclonedx.json"
# 先证明只有 checksums 能抓到：zip 仍好、SBOM 仍是 CycloneDX、但 sha 已变
assert_exit "neg2 precondition: .skill still unzip -t ok" 0 "$(unzip -t "$neg/handoffx-v3.0.0.skill" >/dev/null 2>&1; echo $?)"
assert_exit "neg2 precondition: SBOM still has bomFormat" 0 "$(grep -q '"bomFormat"' "$neg/sbom.cyclonedx.json"; echo $?)"
assert_exit "neg2 precondition: SBOM sha changed" 0 "$([ "$(sha_of "$neg/sbom.cyclonedx.json")" != "$(sha_of "$D3/sbom.cyclonedx.json")" ] && echo 0 || echo 1)"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg2 SBOM appended byte -> 1" 1 "$rc"
assert_contains "neg2 diagnostic" "$out" "checksums.txt"

neg="$WORK/neg3"; cp -R "$D3" "$neg"
mv "$neg/handoffx-v3.0.0.skill" "$neg/handoff-v3.0.0.skill"
mv "$neg/handoffx-v3.0.0-source.tar.gz" "$neg/handoff-v3.0.0-source.tar.gz"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg3 old-prefix assets under v3.0.0 -> 1" 1 "$rc"
assert_contains "neg3 diagnostic" "$out" "missing or empty"

neg="$WORK/neg4"; cp -R "$D3" "$neg"; : > "$neg/handoffx-v3.0.0-source.tar.gz"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg4 0-byte source tarball -> 1" 1 "$rc"
assert_contains "neg4 diagnostic" "$out" "missing or empty"

# B1：checksums.txt 必须逐个覆盖三件必需资产——"文件里每行都对"不等于"该校验的都校验了"。
# 替身 .skill：另一个合法 zip，根仍是 handoffx/，只有覆盖检查能抓到它
ALT="$WORK/alt"; mkdir -p "$ALT/handoffx"; printf 'alt\n' > "$ALT/handoffx/x.txt"
(cd "$ALT" && zip -rq "$ALT/alt.skill" handoffx)
neg="$WORK/neg5"; cp -R "$D3" "$neg"; cp "$ALT/alt.skill" "$neg/handoffx-v3.0.0.skill"
(cd "$neg" && if command -v sha256sum >/dev/null 2>&1; then sha256sum sbom.cyclonedx.json; else shasum -a 256 sbom.cyclonedx.json; fi) > "$neg/checksums.txt.t"
mv "$neg/checksums.txt.t" "$neg/checksums.txt"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg5 checksums lists only sbom, .skill swapped -> 1" 1 "$rc"
assert_contains "neg5 diagnostic" "$out" "checksums.txt"

# neg5b：3 条有效行（够 OK 数）却漏掉被换的 .skill——只有覆盖检查能判红
neg="$WORK/neg5b"; cp -R "$D3" "$neg"; cp "$ALT/alt.skill" "$neg/handoffx-v3.0.0.skill"
(cd "$neg" && for f in handoffx-v3.0.0-source.tar.gz sbom.cyclonedx.json RELEASE_NOTES.md; do
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi
done) > "$neg/checksums.txt.t"
mv "$neg/checksums.txt.t" "$neg/checksums.txt"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg5b 3 valid lines but .skill uncovered -> 1" 1 "$rc"
assert_contains "neg5b diagnostic names the uncovered asset" "$out" "handoffx-v3.0.0.skill"

# neg6：只有注释行——macOS /sbin/sha256sum -c 对零有效行返回 0
neg="$WORK/neg6"; cp -R "$D3" "$neg"; printf '# no entries\n' > "$neg/checksums.txt"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg6 checksums.txt comment-only -> 1" 1 "$rc"
assert_contains "neg6 diagnostic" "$out" "checksums.txt"

# 重算 checksums（让 sha 门放行，只剩被测的那道门能判红）
regen_cks() { (cd "$1" && for f in "$2" "$3" sbom.cyclonedx.json; do
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f"; else shasum -a 256 "$f"; fi
done) > "$1/checksums.txt.t" && mv "$1/checksums.txt.t" "$1/checksums.txt"; }

# C2 neg7：截断的 SBOM 仍含 bomFormat 子串——子串 grep 认它，JSON 解析/结构检查不认
neg="$WORK/neg7"; cp -R "$D3" "$neg"
head -c 60 "$D3/sbom.cyclonedx.json" > "$neg/sbom.cyclonedx.json"
regen_cks "$neg" handoffx-v3.0.0.skill handoffx-v3.0.0-source.tar.gz
assert_exit "neg7 precondition: truncated SBOM still has bomFormat substring" 0 "$(grep -q '"bomFormat"' "$neg/sbom.cyclonedx.json"; echo $?)"
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg7 truncated SBOM -> 1" 1 "$rc"
assert_contains "neg7 diagnostic" "$out" "SBOM"

# C3 neg8：.skill 是合法 zip 但根目录不是 <prefix>/——装到 ~/.claude/skills/w/ 等于没装
mkdir -p "$WORK/w8/w"; printf 'x\n' > "$WORK/w8/w/SKILL.md"
neg="$WORK/neg8"; cp -R "$D3" "$neg"; rm -f "$neg/handoffx-v3.0.0.skill"
(cd "$WORK/w8" && zip -rq "$neg/handoffx-v3.0.0.skill" w)
regen_cks "$neg" handoffx-v3.0.0.skill handoffx-v3.0.0-source.tar.gz
out=$(run_lib verify_release_integrity "$neg" v3.0.0 2>&1); rc=$?
assert_exit "neg8 .skill root w/ -> 1" 1 "$rc"
assert_contains "neg8 diagnostic" "$out" "root"

# --- scrub-tarball.sh：gitx-release 的源码包钩子 ---
# gitx 只在钩子 -x 且项目是 git 工作树时走它，否则静默回落到 rsync（排除表写死旧四件套名 →
# 新名进包）。契约基于 git archive HEAD：跑之前候选必须已 commit。解压的源码包里没有 .git，
# 本段无从证明 → 明示 ➖ 跳过（分发契约），其余段照跑，summary 照打。
SCRUB="$SCRIPTS_DIR/scrub-tarball.sh"
# C1（fix wave 1）：只有结构性缺席（无 .git 且 git 判"不是仓库"/顶层在别处）才 ➖；git 在真实
# 检出里失败（PATH 无 git、dubious ownership、坏 GIT_DIR）→ ❌，绝不当作"不是工作树"跳过。
# 与旧名守卫共用 tests/common.sh hx_git_worktree_state，两处判据不再分叉。
_wt=$(hx_git_worktree_state "$ROOT_DIR")
if [ "$_wt" = error ]; then
    echo "  ❌ scrub-tarball 契约段：无法判定 $ROOT_DIR 是否 git 检出（git 失败，见上）——拒绝跳过"
    FAIL=$((FAIL + 1))
elif [ "$_wt" = none ]; then
    echo "  ➖ SKIPPED（不是 git 工作树）: scrub-tarball 契约段需要 git archive HEAD"
else
    # (a) 模式位：工作区 -x 与 git 索引 100755 都要——只有索引模式会随 clone/包走
    assert_exit "scrub: scripts/scrub-tarball.sh is executable" 0 "$([ -x "$SCRUB" ] && echo 0 || echo 1)"
    mode=$(git -C "$ROOT_DIR" ls-files -s scripts/scrub-tarball.sh | awk '{print $1}')
    assert_exit "scrub: git mode 100755 (got: ${mode:-untracked})" 0 "$([ "$mode" = "100755" ] && echo 0 || echo 1)"

    # (b) 产物：前缀、集合相等、正反向必含/必不含、确定性
    SO="$WORK/scrub"; mkdir -p "$SO"
    rc=0; bash "$SCRUB" "$SO/x.tar.gz" handoffx-v9.9.9 HEAD >/dev/null 2>&1 || rc=$?
    assert_exit "scrub: HEAD → exit 0" 0 "$rc"
    ENTRIES=$(tar tzf "$SO/x.tar.gz" 2>/dev/null)
    n=$(printf '%s\n' "$ENTRIES" | grep -cv '^handoffx-v9\.9\.9/')
    assert_exit "scrub: every entry under handoffx-v9.9.9/ (outside: $n)" 0 "$([ -n "$ENTRIES" ] && [ "$n" = "0" ] && echo 0 || echo 1)"
    ACTUAL=$(printf '%s\n' "$ENTRIES" | grep -v '/$' | sed 's|^handoffx-v9\.9\.9/||' | LC_ALL=C sort)
    # 期望集从 git ls-tree 与 .gitattributes 推出，不手列：根锚定字面量 "/x"（文件）或 "/x/"（目录），
    # 外加唯一一种通配——根锚定文件模式末尾的单个 "*"（"/x.bak*" = 根级、名字以 x.bak 开头的文件；
    # B2：tidy 备份带时间戳后缀，只列两个具体名会漏掉真实产生的那些）。其余通配即 ❌——推导只认
    # 这两种形态，别的通配会让期望集悄悄偏离 git 的真实语义。
    # ga_ignores <attributes-file> / scrub_expected <repo> <ignores> — 同一推导既用于本仓也用于下方哨兵克隆
    ga_ignores() { awk '$1 !~ /^#/ && NF >= 2 { for (i = 2; i <= NF; i++) if ($i == "export-ignore") print $1 }' "$1"; }
    # 模式经 ENVIRON 传：BSD awk 的 -v 值不许含换行（"newline in string"），期望集会被静默吃空
    scrub_expected() {
        git -C "$1" -c core.quotePath=false ls-tree -r --name-only HEAD \
        | PATS="$2" awk 'BEGIN { n = split(ENVIRON["PATS"], p, "\n") }
            { for (i = 1; i <= n; i++) { q = substr(p[i], 2)
                  if (substr(q, length(q)) == "/") { if (index($0, q) == 1) next }
                  else if (substr(q, length(q)) == "*") { b = substr(q, 1, length(q) - 1)
                      if (index($0, b) == 1 && index(substr($0, length(b) + 1), "/") == 0) next }
                  else if ($0 == q) next }
              print }' | LC_ALL=C sort
    }
    GA="$ROOT_DIR/.gitattributes"
    IGN=$(ga_ignores "$GA")
    bad=$(printf '%s\n' "$IGN" | grep -vE '^/[^*?[]*[*]?$' || true)
    assert_exit "scrub: .gitattributes export-ignore entries are root-anchored literals or trailing-* file patterns (bad: ${bad:-none})" 0 "$([ -n "$IGN" ] && [ -z "$bad" ] && echo 0 || echo 1)"
    EXPECTED=$(scrub_expected "$ROOT_DIR" "$IGN")
    d=$(diff <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$ACTUAL") | grep -c '^[<>]')
    assert_exit "scrub: file set == git ls-tree HEAD minus export-ignore ($d differing lines)" 0 "$([ -n "$EXPECTED" ] && [ "$d" = "0" ] && echo 0 || echo 1)"
    for f in .sanitize-ignore tools/review-loop.sh tests/fixtures/p2-1-synthetic-v2/legacy-gotchas.md tests/fixtures/p2-1-synthetic-v2/legacy-main.md; do
        assert_exit "scrub: keeps $f" 0 "$(printf '%s\n' "$ACTUAL" | grep -qxF -- "$f"; echo $?)"
    done
    n=$(printf '%s\n' "$ACTUAL" | grep -cE "^($FILES_RE)$|^(${DIRS_RE#|})")
    assert_exit "scrub: no root-level four-piece/GOTCHAS/CLAUDE.md entries (got: $n)" 0 "$([ "$n" = "0" ] && echo 0 || echo 1)"
    # B1 (fix wave 1): gitx's deep audit rejects the legacy main / gotchas /
    # legacy dirs NESTED anywhere below the prefix (fixture data included) —
    # the root-level check above is blind to that, and the real cut would fail.
    NESTED_RE=$(hx_gitx_nested_re handoffx-v9.9.9)
    nested=$(printf '%s\n' "$ENTRIES" | grep -E -- "$NESTED_RE")
    assert_exit "scrub: zero entries match gitx's nested legacy-name audit regex (got: $(printf '%s' "$nested" | grep -c .))" 0 "$([ -z "$nested" ] && echo 0 || echo 1)"
    [ -z "$nested" ] || printf '%s\n' "$nested" | head -8 | sed 's/^/      /'
    rc=0; bash "$SCRUB" "$SO/y.tar.gz" handoffx-v9.9.9 HEAD >/dev/null 2>&1 || rc=$?
    assert_exit "scrub: second run exit 0" 0 "$rc"
    assert_exit "scrub: two runs byte-identical (cmp)" 0 "$(cmp -s "$SO/x.tar.gz" "$SO/y.tar.gz"; echo $?)"

    # (b2) B2 (fix wave 1): the archive / backup / notes variants that the root
    # release path and the artifact gate forbid must be export-ignored as well —
    # otherwise a committed one ships. Proven on a scratch clone where they ARE
    # committed (force-added past .gitignore) with this tree's .gitattributes, so
    # git's own attribute matching decides, and the derivation above must agree.
    SC="$WORK/sentinel"
    # --no-hardlinks: an explicit --local fails across filesystems (git 2.34,
    # "Invalid cross-device link") — the Linux container's mktemp is on another
    # device than the bind-mounted tree.
    git clone -q --no-hardlinks "$ROOT_DIR" "$SC" >/dev/null 2>&1
    cp "$ROOT_DIR/.gitattributes" "$SC/.gitattributes"
    sentinels="${HX_MAIN_FILE%.md}.archive.md ${HX_LOGS_DIR}.archive/x.md ${HX_LEGACY_MAIN_FILE%.md}.archive.md ${HX_LEGACY_LOGS_DIR}.archive/x.md"
    sentinels="$sentinels ${HX_MAIN_FILE}.bak.tidy-20261101-0000 ${HX_LEGACY_MAIN_FILE}.bak ${HX_MAIN_FILE}.pre-v2-backup ${HX_LEGACY_MAIN_FILE}.pre-v2-backup"
    sentinels="$sentinels ${HX_LEGACY_MAIN_FILE%.md}.archive.md.pre-v2-backup NEXT_SESSION_NOTES.md"
    for f in $sentinels; do mkdir -p "$SC/$(dirname "$f")"; echo sentinel > "$SC/$f"; done
    # shellcheck disable=SC2086
    rc=0; { git -C "$SC" add -f .gitattributes $sentinels && git -C "$SC" -c user.name=t -c user.email=nobody commit -qm sentinels; } >/dev/null 2>&1 || rc=$?
    assert_exit "scrub sentinels: committed in a scratch clone" 0 "$rc"
    rc=0; bash "$SC/scripts/scrub-tarball.sh" "$SO/s.tar.gz" handoffx-v9.9.9 HEAD >/dev/null 2>&1 || rc=$?
    assert_exit "scrub sentinels: scrub → exit 0" 0 "$rc"
    S_ACTUAL=$(tar tzf "$SO/s.tar.gz" 2>/dev/null | grep -v '/$' | sed 's|^handoffx-v9\.9\.9/||' | LC_ALL=C sort)
    leaked=""
    for f in $sentinels; do printf '%s\n' "$S_ACTUAL" | grep -qxF -- "$f" && leaked="$leaked $f"; done
    assert_exit "scrub sentinels: none of the committed archive/backup/notes variants ships (leaked:${leaked:- none})" 0 "$([ -n "$S_ACTUAL" ] && [ -z "$leaked" ] && echo 0 || echo 1)"
    d=$(diff <(scrub_expected "$SC" "$(ga_ignores "$SC/.gitattributes")") <(printf '%s\n' "$S_ACTUAL") | grep -c '^[<>]')
    assert_exit "scrub sentinels: derived expected set agrees with git ($d differing lines)" 0 "$([ "$d" = "0" ] && echo 0 || echo 1)"

    # (c) 失败路径：非零且不留残留；参数个数错 → 2
    rc=0; bash "$SCRUB" "$SO/bad.tar.gz" handoffx-v9.9.9 no-such-ref-p24 >/dev/null 2>&1 || rc=$?
    assert_exit "scrub: invalid ref → non-zero (got: $rc)" 0 "$([ "$rc" != "0" ] && echo 0 || echo 1)"
    assert_exit "scrub: invalid ref leaves neither out nor out.tmp" 0 "$([ ! -e "$SO/bad.tar.gz" ] && [ ! -e "$SO/bad.tar.gz.tmp" ] && echo 0 || echo 1)"
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        echo "  ➖ scrub unwritable out dir SKIPPED (root bypasses chmod 555; Gotcha #15 / B7-a 同范式)"
    else
        ro="$SO/ro"; mkdir "$ro"; chmod 555 "$ro"
        rc=0; bash "$SCRUB" "$ro/x.tar.gz" handoffx-v9.9.9 HEAD >/dev/null 2>&1 || rc=$?
        chmod 755 "$ro"
        assert_exit "scrub: unwritable out dir → non-zero (got: $rc)" 0 "$([ "$rc" != "0" ] && echo 0 || echo 1)"
    fi
    rc=0; bash "$SCRUB" "$SO/z.tar.gz" handoffx-v9.9.9 >/dev/null 2>&1 || rc=$?
    assert_exit "scrub: two args → exit 2" 2 "$rc"
    rc=0; bash "$SCRUB" "$SO/z.tar.gz" handoffx-v9.9.9 HEAD extra >/dev/null 2>&1 || rc=$?
    assert_exit "scrub: four args → exit 2" 2 "$rc"
    # Empty operands: an empty <prefix> archives at the tarball root, an empty
    # <ref>/<out> only fails later with a vaguer git/gzip error — refuse up front.
    for args in "out||handoffx-v9.9.9|HEAD" "prefix|$SO/e.tar.gz||HEAD" "ref|$SO/e.tar.gz|handoffx-v9.9.9|"; do
        IFS='|' read -r which a1 a2 a3 <<EOF
$args
EOF
        rc=0; bash "$SCRUB" "$a1" "$a2" "$a3" >/dev/null 2>&1 || rc=$?
        assert_exit "scrub: empty <$which> → exit 2" 2 "$rc"
    done
    assert_exit "scrub: empty operands left no e.tar.gz / .tmp" 0 "$([ ! -e "$SO/e.tar.gz" ] && [ ! -e "$SO/e.tar.gz.tmp" ] && echo 0 || echo 1)"
fi

# Unpacked source tree that sits inside some other checkout: git would happily
# archive the OUTER repository. Runs without .git of its own on purpose — that
# is exactly the extracted-package situation this refusal exists for.
OUTER="$WORK/outer"; mkdir -p "$OUTER/pkg/scripts"
git init -q "$OUTER" >/dev/null 2>&1
printf 'outer\n' > "$OUTER/o.txt"
git -C "$OUTER" add o.txt >/dev/null 2>&1
git -C "$OUTER" -c user.name=t -c user.email=nobody commit -qm o >/dev/null 2>&1
cp "$SCRUB" "$OUTER/pkg/scripts/scrub-tarball.sh"
rc=0; err=$(bash "$OUTER/pkg/scripts/scrub-tarball.sh" "$WORK/outer.tar.gz" handoffx-v9.9.9 HEAD 2>&1 >/dev/null) || rc=$?
assert_exit "scrub: tree nested inside another repo → exit 2" 2 "$rc"
assert_contains "scrub: nested refusal names the outer top-level" "$err" "not the top of its own git work tree"
assert_exit "scrub: nested refusal wrote no tarball" 0 "$([ ! -e "$WORK/outer.tar.gz" ] && [ ! -e "$WORK/outer.tar.gz.tmp" ] && echo 0 || echo 1)"

summary
