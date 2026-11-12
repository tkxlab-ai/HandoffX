#!/bin/bash
# test_release_publish_gates.sh — publish 流水线自写门禁函数的 load-bearing 哨兵
#
# release-publish-github.sh / -backfill.sh 不能端到端跑（需真实 release + gh），
# 所以它们的 fulltree_credscan / scan_skill_asset / scan_public_file 以前零覆盖：
# 把 `[[ total -eq 0 && unscanned -eq 0 ]]` 的后半删掉即静默回到 fail-open，
# 没有任何测试会红（2026-10-29 独立审查点名）。本套件把函数体从脚本里抽出来
# 在沙箱里直接调用——测的是真实源码，不是复制品。
#
# 同时机械化两脚本三函数的 parity（Gotcha #17：能机械化的 parity 必须机械化）：
# 以前只靠人手 diff，漏对齐就是 CRITICAL-A/#23 那类「修一处漏孪生」。
#
# 公开镜像删了 maintainer-only 的 release-* 脚本（DEV_ONLY）→ 缺席静默跳过，
# 与 test_release_sanitize_credscan.sh 的 skip 范式一致。
source "$(dirname "$0")/common.sh"

PUB="$ROOT_DIR/scripts/release-publish-github.sh"
BACKFILL="$ROOT_DIR/scripts/release-publish-github-backfill.sh"
if [ ! -f "$PUB" ] || [ ! -f "$BACKFILL" ]; then
    echo "  ➖ release-publish-github{,-backfill}.sh 不在，跳过（公开镜像已删 maintainer-only 脚本）"
    summary
    exit 0
fi

extract_fn() { sed -n "/^$2() {/,/^}/p" "$1"; }

# ── parity：三函数在两脚本间必须 byte-identical ─────────────────────────────
for fn in fulltree_credscan scan_skill_asset scan_public_file; do
    if diff -q <(extract_fn "$PUB" "$fn") <(extract_fn "$BACKFILL" "$fn") >/dev/null; then
        echo "  ✅ parity: $fn identical in publish + backfill"; PASS=$((PASS+1))
    else
        echo "  ❌ parity: $fn differs between publish + backfill"; FAIL=$((FAIL+1))
    fi
done

# ── 挂接：verify_release_integrity 来自 release-layout lib，不再各存一份 ─────
# body-parity 对这个函数是空转的（两份副本一致≠与 producer 一致）。改为证明：
# 脚本里那行 source 真能在子 shell 里装出 lib 的函数，并且它认 release.sh
# --sandbox 现场造的两种前缀产物、拒一个缺 checksums 的坏产物。键在退出码上。
HOOK_T="$(mktemp -d)"
# 在 trap 里：任一断言前的提前退出都不得把 sandbox 产物留在 $TMPDIR
trap 'rm -rf "$HOOK_T"' EXIT
"$ROOT_DIR/release.sh" --sandbox v3.0.0 "$HOOK_T" >/dev/null 2>&1
assert_exit "hookup fixture: --sandbox v3.0.0 builds" 0 "$?"
"$ROOT_DIR/release.sh" --sandbox v2.9.9 "$HOOK_T" >/dev/null 2>&1
assert_exit "hookup fixture: --sandbox v2.9.9 builds" 0 "$?"
cp -R "$HOOK_T/handoffx-v3.0.0" "$HOOK_T/bad-v3.0.0"
rm -f "$HOOK_T/bad-v3.0.0/checksums.txt"
# 旧前缀字面量只许出现在 layout lib 与契约测试里（P2.2b 全局约束），这里取产物实名；
# glob 落空时 basename 原样返回模式串，verify 必拒 → 该断言红，不会假绿
OLD_FX=$(basename "$HOOK_T"/*-v2.9.9)
for f in "$PUB" "$BACKFILL"; do
    b=$(basename "$f")
    # 行尾锚定：`. lib || true` 之类的尾巴会把 source 失败吞掉，不能算挂上
    hook=$(grep -E '^\. "\$ROOT/scripts/release-layout\.sh"$' "$f")
    if [ -n "$hook" ]; then
        echo "  ✅ hookup: $b sources release-layout.sh"; PASS=$((PASS+1))
    else
        echo "  ❌ hookup: $b has no '. \"\$ROOT/scripts/release-layout.sh\"' line"; FAIL=$((FAIL+1))
    fi
    # 能装出函数 ≠ 生产路径真的调用它：钉住调用行，且同行或续行带 `|| ` 中止
    awk '/^[[:space:]]*verify_release_integrity "/ {
             if ($0 ~ /\|\| /) ok = 1; else if ($0 ~ /\\$/) { pend = 1; next } }
         pend { if ($0 ~ /^[[:space:]]*\|\| /) ok = 1; pend = 0 }
         END { exit !ok }' "$f"
    assert_exit "hookup: $b calls verify_release_integrity with an abort (|| …)" 0 "$?"
    for c in "handoffx-v3.0.0 v3.0.0 0" "$OLD_FX v2.9.9 0" "bad-v3.0.0 v3.0.0 1"; do
        read -r fx ver want <<< "$c"
        ROOT="$ROOT_DIR" /bin/bash -c "$hook; declare -f verify_release_integrity | grep -q . && verify_release_integrity \"\$1\" \"\$2\"" \
            _ "$HOOK_T/$fx" "$ver" >/dev/null 2>&1
        assert_exit "hookup: $b verify_release_integrity $fx → $want" "$want" "$?"
    done
    n=$(grep -c '^verify_release_integrity() {' "$f")
    assert_exit "hookup: $b keeps no own verify_release_integrity copy" 0 "$n"
done
rm -rf "$HOOK_T"

# ── 抽出真实函数体 + 两个 pattern 数组，沙箱里调用 ─────────────────────────
FNS="$(mktemp)"
{
    sed -n '/^CREDENTIAL_PATTERNS=(/,/^)/p; /^PRIVACY_PATTERNS=(/,/^)/p' "$PUB"
    for fn in fulltree_credscan scan_skill_asset scan_public_file; do extract_fn "$PUB" "$fn"; done
} > "$FNS"
# 抽取自检：五样都真的在 runner 里（抽空了会让下面全部假绿；bash ≥4.4 对未定义
# 数组 "${arr[@]}" 不报 unbound，所以 PRIVACY_PATTERNS 缺席在 CI 上不会自爆）
grep -q '^fulltree_credscan() {' "$FNS" && grep -q '^scan_skill_asset() {' "$FNS" \
    && grep -q '^scan_public_file() {' "$FNS" \
    && grep -q '^CREDENTIAL_PATTERNS=(' "$FNS" && grep -q '^PRIVACY_PATTERNS=(' "$FNS"
assert_exit "runner 抽到三函数 + 两个 pattern 数组" 0 "$?"

# runner：$1=函数名 $2…=参数；在与脚本相同的 shell 选项下跑
run_fn() { bash -c 'set -uo pipefail; . "$1"; shift; "$@"' _ "$FNS" "$@"; }

# 样本凭证运行时拼接：tests/ 随公开 source tarball 发布，sanitize Step 3 会扫到
# 本文件——写死 AKIA+16 位字面量 = 门禁扫到自己的测试样本（Gotcha #18，
# 与 test_release_sanitize_credscan.sh 的 ${D}BEGIN 手法同理）。
K4="AKIA"; FAKE_AWS="${K4}IOSFODNN7EXAMPLE"
L1="lax"; FAKE_ORG="${L1}-team"

T="$(mktemp -d)"
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" "$FNS" "$HOOK_T"' EXIT
mkdir -p "$T/a/b"; printf 'clean\n' > "$T/a/b/x.md"; printf 'clean\n' > "$T/README.md"

run_fn fulltree_credscan "$T" >/dev/null 2>&1
assert_exit "fulltree_credscan: clean tree → 0" 0 "$?"

printf '%s\n' "$FAKE_AWS" > "$T/a/b/leak.md"
out=$(run_fn fulltree_credscan "$T" 2>&1); ec=$?
assert_exit "fulltree_credscan: planted key → 1" 1 "$ec"
assert_contains "fulltree_credscan: names the pattern hit" "$out" "credential pattern found"
rm -f "$T/a/b/leak.md"

run_fn scan_public_file "$T/README.md" >/dev/null 2>&1
assert_exit "scan_public_file: clean file → 0" 0 "$?"

# scan_skill_asset：解包后对内容硬扫（凭证经 fulltree_credscan，隐私串自有循环）
if command -v zip >/dev/null 2>&1; then
    ( cd "$T" && zip -qr "$T/clean.skill" README.md a )
    run_fn scan_skill_asset "$T/clean.skill" >/dev/null 2>&1
    assert_exit "scan_skill_asset: clean .skill → 0" 0 "$?"
    printf '%s\n' "$FAKE_ORG" > "$T/a/b/priv.md"
    ( cd "$T" && zip -qr "$T/priv.skill" README.md a )
    out=$(run_fn scan_skill_asset "$T/priv.skill" 2>&1); ec=$?
    assert_exit "scan_skill_asset: privacy string inside .skill → 1" 1 "$ec"
    assert_contains "scan_skill_asset: names the privacy hit" "$out" "privacy pattern in .skill"
    rm -f "$T/a/b/priv.md"; printf '%s\n' "$FAKE_AWS" > "$T/a/b/leak.md"
    ( cd "$T" && zip -qr "$T/cred.skill" README.md a )
    run_fn scan_skill_asset "$T/cred.skill" >/dev/null 2>&1
    assert_exit "scan_skill_asset: credential inside .skill → 1 (via fulltree_credscan)" 1 "$?"
    rm -f "$T/a/b/leak.md"
    # Not covered on purpose: the privacy loop's own grep-rc>1 branch. Reaching it
    # needs an unreadable entry inside the unzipped tree, but `zip` cannot read a
    # chmod-000 file to archive it in the first place — the branch is defensive.
else
    # not a skip: zip is a declared test dependency (README §Linux deps); a
    # silent ➖ here would hide six assertions (Gotcha #12)
    echo "  ❌ zip not installed — scan_skill_asset cases cannot run (install zip)"; FAIL=$((FAIL+1))
fi

if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unreadable-input controls SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$T/a/b"
    out=$(run_fn fulltree_credscan "$T" 2>&1); ec=$?
    chmod 755 "$T/a/b"
    assert_exit "fulltree_credscan: unreadable subdir → 1 (not silent clean)" 1 "$ec"
    assert_contains "fulltree_credscan: says it cannot scan the whole tree" "$out" "cannot scan the whole tree"

    chmod 000 "$T/README.md"
    run_fn scan_public_file "$T/README.md" >/dev/null 2>&1; ec=$?
    chmod 644 "$T/README.md"
    assert_exit "scan_public_file: unreadable file → 1" 1 "$ec"
fi

summary
