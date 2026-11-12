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
out=$(RENAME_FROM=v9.0.0 run_lib release_prefix v3.0.0)
assert_exit "RENAME_FROM=v9.0.0: v3.0.0 = handoff" 0 "$([ "$out" = "handoff" ] && echo 0 || echo 1)"
out=$(RENAME_FROM=v2.9.0 run_lib release_prefix v2.10.0)
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

# --- lib: verify_release_integrity ---
out=$(run_lib verify_release_integrity "$WORK/nope" v3.0.0 2>&1); rc=$?
assert_exit "verify_release_integrity missing dir -> exit 1" 1 "$rc"
assert_contains "verify_release_integrity missing dir diagnostic" "$out" "missing dir"

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
out=$(run_lib verify_release_integrity "$D3" v3.0.0 2>&1); rc=$?
assert_exit "verify_release_integrity sandbox v3.0.0 -> 0" 0 "$rc"

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

summary
