#!/bin/bash
# (B) load-bearing 负控:对 fixture canonical-doc 树跑真实 test_doc_freshness.sh。
# 关键:断 TestN 专属精确信号「声称 '9999 断言点'」,与环境套件 drift 噪声解耦
# (Gotcha #20:负控须为正确原因 RED/GREEN,非被 ambient drift 喂饱;Codex 第5 finding)。
source "$(dirname "$0")/common.sh"
RT="$(cd "$(dirname "$0")/.." && pwd)"
_mk_fx() {
  local F="$1"; mkdir -p "$F/tests"
  cp "$RT"/tests/common.sh "$F/tests/" 2>/dev/null
  cp "$RT"/tests/test_*.sh "$F/tests/" 2>/dev/null
  local d
  for d in README.md README_CN.md HANDOFF.md CONTRIBUTING.md TEST-SCENARIOS.md INSTALL.md VERSION; do
    cp "$RT/$d" "$F/" 2>/dev/null
  done
  cp -R "$RT/scripts" "$F/" 2>/dev/null; mkdir -p "$F/Release"
}
SIG="声称 '9999 断言点'"
FXB=""; FXI=""; FXT=""; FXR=""; FXH=""; FXC1=""; FXP0=""; FXP1=""; FXP2=""; FXP3=""; FXP4="" FXP5="" FXP6=""
trap 'rm -rf "$FXB" "$FXI" "$FXT" "$FXR" "$FXH" "$FXC1" "$FXP0" "$FXP1" "$FXP2" "$FXP3" "$FXP4" "$FXP5" "$FXP6" 2>/dev/null' EXIT INT TERM

# (a) baseline: 干净 fixture(无注入) → 输出绝不含 SIG（证 SIG 非环境噪声产物）
FXB=$(mktemp -d); _mk_fx "$FXB"
base_out=$(DOC_DIR="$FXB" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_not_contains "baseline: 干净 fixture 不产生 9999 断言点信号" "$base_out" "$SIG"
rm -rf "$FXB"

# (b) 注入合成「当前 9999 断言点」声称到 fixture HANDOFF.md 头部(当前区,非历史块)
FXI=$(mktemp -d); _mk_fx "$FXI"
# 在第 1 行后插入(HANDOFF.md 第1行是 <!-- HANDOFF v2 schema -->;插其后仍属当前区)
awk 'NR==1{print; print "<!-- bguard --> 当前 9999 断言点 synthetic"; next} {print}' \
  "$FXI/HANDOFF.md" > "$FXI/HANDOFF.md.t" && mv "$FXI/HANDOFF.md.t" "$FXI/HANDOFF.md"
inj_out=$(DOC_DIR="$FXI" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "load-bearing: 注入 9999 断言点 → TestN 精确报 SIG" "$inj_out" "$SIG"
assert_contains "load-bearing: SIG 行指明 HANDOFF.md" "$inj_out" "HANDOFF.md: 声称 '9999 断言点'"
# CRITICAL-2: gate-coupled — pass-verdict 行 absent 意味着 ap_drift 真的置 1 进了 FAIL 分支
# 若 ap_drift=1 被中和为 0，pass-verdict 会出现 → 此断言变 FAIL → bguard 正确 RED
assert_not_contains "load-bearing(gate): 注入后 pass-verdict 不得出现(gate 中和则失败)" \
  "$inj_out" "✅ 所有 CANONICAL_DOCS '断言点' 与静态计数一致"
rm -rf "$FXI"

# ── Test 15 折入 load-bearing:README_CN badge 套件 drift 须被真实脚本抓 ──
FXT=$(mktemp -d); _mk_fx "$FXT"
# README_CN.md 顶部 shields.io badge: tests-<N>%20suites%20%2F%20...  改成 88
awk '{ if ($0 ~ /tests-[0-9]+%20suites/) gsub(/tests-[0-9]+%20suites/,"tests-88%20suites"); print }' \
  "$FXT/README_CN.md" > "$FXT/README_CN.md.t" && mv "$FXT/README_CN.md.t" "$FXT/README_CN.md"
assert_contains "Test15 折入注入前置:README_CN badge 已被改成 88%20suites" \
  "$(cat "$FXT/README_CN.md")" "tests-88%20suites"
t15_out=$(DOC_DIR="$FXT" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test15 折入 load-bearing: README_CN badge 88 套件 → 精确报漂移指 README_CN.md" \
  "$t15_out" "README_CN.md: 声称 '88 套件'"
# CRITICAL-2: gate-coupled — pass-verdict absent 意味着 suite_drift 真的进了 FAIL 分支
# 若 suite_drift=1 被中和为 0，pass-verdict 出现 → 此断言 FAIL → bguard 正确 RED
assert_not_contains "Test15(gate): 注入后 pass-verdict 不得出现(suite_drift 中和则失败)" \
  "$t15_out" "所有 canonical 文档 '<N> 套件' 声明与实际一致"
rm -rf "$FXT"

# ── Test 10 硬化 load-bearing:README_CN 退役号被抓 + 历史块豁免不回归 ──
FXR=$(mktemp -d); _mk_fx "$FXR"
printf '\n当前 270 assertions demo\n' >> "$FXR/README_CN.md"   # 旧 Test10 清单漏 README_CN
t10_out=$(DOC_DIR="$FXR" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test10 硬化 load-bearing: README_CN 退役号 270 → 真实脚本拦" \
  "$t10_out" "当前文档仍含旧断言统计"
# 历史块豁免:把退役号放进 HANDOFF.md ### 最近完成 块内,不应被拦(归一剥离)
FXH=$(mktemp -d); _mk_fx "$FXH"
awk '1; /^### 最近完成/ && !done { print "历史 228 assertions in 最近完成 块"; done=1 }' \
  "$FXH/HANDOFF.md" > "$FXH/HANDOFF.md.t" && mv "$FXH/HANDOFF.md.t" "$FXH/HANDOFF.md"
t10h_out=$(DOC_DIR="$FXH" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_not_contains "Test10 硬化:HANDOFF ### 最近完成 块内退役号不误拦(归一剥离)" \
  "$t10h_out" "❌ 当前文档仍含旧断言统计"
rm -rf "$FXR" "$FXH"

# ── Test 19 CRITICAL-1 load-bearing:### 最近完成 含 断言点 → 真实脚本拦 ──
# 注入 '断言点' 到 fixture HANDOFF.md ### 最近完成 块内，验证 Test 19 正确 FAIL。
# if/else 结构：❌ echo 与 FAIL gate 同在 if 分支，assert_contains ❌ 即 gate-coupled
# （若 grep 条件失效整个 if 不走，❌ echo 不出现 → 此断言 FAIL → bguard 正确 RED）。
# baseline 反向：干净 fixture 不得产生该精确 ❌ 信号（证信号非环境噪声）。
FXC1=$(mktemp -d); _mk_fx "$FXC1"
c1_base_out=$(DOC_DIR="$FXC1" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_not_contains "Test19 CRITICAL-1 baseline: 干净 fixture 不产生误报" \
  "$c1_base_out" "HANDOFF.md ### 最近完成 块含 '断言点/assertion sites'"
awk '1; /^### 最近完成/ && !c1done { print "<!-- bguard-c1 --> 当前 9999 断言点 in 最近完成"; c1done=1 }' \
  "$FXC1/HANDOFF.md" > "$FXC1/HANDOFF.md.t" && mv "$FXC1/HANDOFF.md.t" "$FXC1/HANDOFF.md"
c1_out=$(DOC_DIR="$FXC1" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test19 CRITICAL-1 load-bearing: ### 最近完成 含断言点 → 精确报 ❌" \
  "$c1_out" "HANDOFF.md ### 最近完成 块含 '断言点/assertion sites'"
rm -rf "$FXC1"

# ════ Test 20 per-suite guard load-bearing 负控（design 0024 §4，Gotcha #25 gate-coupled）════
# 键在 gate 判决（pass-verdict 缺席 ⟺ _ps_drift 真置 1 进 FAIL），非诊断 ❌ echo。
T20_PASS="✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致"

# (c0) baseline：干净 fixture → pass-verdict 出现（反向锚：信号非环境噪声产物）
FXP0=$(mktemp -d); _mk_fx "$FXP0"
p0_out=$(DOC_DIR="$FXP0" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c0 baseline: 干净 fixture pass-verdict 出现" "$p0_out" "$T20_PASS"
rm -rf "$FXP0"

# (c1) 逐行漂移：首个表行数字→9999（机械定位首行，不手挑套件名）
FXP1=$(mktemp -d); _mk_fx "$FXP1"
awk 'BEGIN{d=0} !d && /^\| `test_[A-Za-z0-9_]+\.sh` \| [0-9]+ \|/ { sub(/\| [0-9]+ \|/,"| 9999 |"); d=1 } {print}' \
  "$FXP1/TEST-SCENARIOS.md" > "$FXP1/TS.t" && mv "$FXP1/TS.t" "$FXP1/TEST-SCENARIOS.md"
p1_out=$(DOC_DIR="$FXP1" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c1: 逐行漂移 → 精确报 9999 断言点" "$p1_out" "表声称 '9999 断言点'"
assert_not_contains "Test20 c1 gate-coupled: 漂移后 pass-verdict 不得出现" "$p1_out" "$T20_PASS"
rm -rf "$FXP1"

# (c2) 完整性：删一表行（套件仍在）→ 报缺套件行 + pass-verdict 缺席
FXP2=$(mktemp -d); _mk_fx "$FXP2"
awk '!/^\| `test_skill_metadata_budget\.sh` \|/' \
  "$FXP2/TEST-SCENARIOS.md" > "$FXP2/TS.t" && mv "$FXP2/TS.t" "$FXP2/TEST-SCENARIOS.md"
p2_out=$(DOC_DIR="$FXP2" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c2: 删表行 → 报缺套件行" "$p2_out" "表缺套件行"
assert_not_contains "Test20 c2 gate-coupled: 缺行后 pass-verdict 不得出现" "$p2_out" "$T20_PASS"
rm -rf "$FXP2"

# (c3) 孤儿行（套件不存在）→ 报孤儿 + pass-verdict 缺席
FXP3=$(mktemp -d); _mk_fx "$FXP3"
printf '| `test_ZZZ_nonexistent.sh` | 7 | 孤儿行 |\n' >> "$FXP3/TEST-SCENARIOS.md"
p3_out=$(DOC_DIR="$FXP3" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c3: 孤儿行 → 报孤儿" "$p3_out" "孤儿行(套件不存在)"
assert_not_contains "Test20 c3 gate-coupled: 孤儿后 pass-verdict 不得出现" "$p3_out" "$T20_PASS"
rm -rf "$FXP3"

# (c4) load-bearing 矩阵：gate-中性化但保留 ❌ 诊断 echo → 证负控键在 verdict 非 echo。
# C1 修复：c4 是**唯一**跑 fixture 脚本副本（非 $RT）的控——因为它验证的是「脚本 gate
# 逻辑分支」而非文档；DOC_DIR 只重定向文档读取，改不了 $RT 的脚本逻辑，故必须显式
# 执行被 patch 的副本 $FXP4/tests/test_doc_freshness.sh（_mk_fx 已拷 common.sh，副本内
# source/ROOT_DIR 自洽解析到 $FXP4，与 DOC_DIR=$FXP4 一致）。勿"修正"回 $RT（Tacit#4 Why）。
# I1 修复：用 sub() 只中性化条件表达式本身，保留原行缩进/`if`/`; then`/未来任何 && 后缀，
# 不写死整行（写死整行 = 缩进/复合条件漂移时静默改写 gate = Gotcha #25 递归）。
FXP4=$(mktemp -d); _mk_fx "$FXP4"
awk 'BEGIN{d=0} !d && /^\| `test_[A-Za-z0-9_]+\.sh` \| [0-9]+ \|/ { sub(/\| [0-9]+ \|/,"| 9999 |"); d=1 } {print}' \
  "$FXP4/TEST-SCENARIOS.md" > "$FXP4/TS.t" && mv "$FXP4/TS.t" "$FXP4/TEST-SCENARIOS.md"
awk '{ sub(/"\$_ps_drift" -eq 0/, "0 -eq 0"); print }' \
  "$FXP4/tests/test_doc_freshness.sh" > "$FXP4/td.t" && mv "$FXP4/td.t" "$FXP4/tests/test_doc_freshness.sh"
# FINDING2 防御：自检 sub() 中性化确已落地——未来 gate 改 [[ ]]/(( )) 形式 sub() 会
# 静默 no-op 使 c4 假 load-bearing（Gotcha #25 递归）。显式断言中性化行已存在。
assert_contains "Test20 c4 自检: sub() 中性化确已落地(防未来 gate 形式变静默 no-op)" "$(cat "$FXP4/tests/test_doc_freshness.sh")" "if [ 0 -eq 0 ]; then"
p4_out=$(DOC_DIR="$FXP4" bash "$FXP4/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c4 前置: gate-中性化后 ❌ 诊断 echo 仍在" "$p4_out" "表声称 '9999 断言点'"
assert_contains "Test20 c4 load-bearing: gate-中性化→pass-verdict 出现(键 gate 非 echo)" "$p4_out" "$T20_PASS"
rm -rf "$FXP4"

# (c5) FINDING1 回归防御：legit-0 套件不可读 → Test20 必硬 FAIL，绝不静默坍缩成 0==0 假绿。
# Gotcha #24 母题在本 guard 自身的递归防御；键 gate pass-verdict 缺席（非诊断 echo）。
# c5 跑 $RT（同 c0-c3）：不可读文件在 $FXP5/tests/ 即 DOC_DIR 树内，无需跑副本。
# Codex 第3源 [high] 修复（Tacit#3 镜像 B7-a test_migrate_to_v2.sh:172）：root（EUID=0
# 容器/CI）CAP_DAC_OVERRIDE 绕过 chmod 000 → 文件仍可读 → 此 chmod-based 不可读场景
# 在 root 下无法构造，必须 skip（Gotcha #15 / Decision 0016 母题）。本 skip 仅豁免
# c5 这条 root 下不可复现的负控；FINDING1 的生产 [ -r ] 闸在 test_doc_freshness.sh
# 内、每次 Test20 都跑、不依赖本测试；c6 目录冒充 root-immune（[ -f ] 对目录恒假）
# 仍覆盖该共享谓词的非常规文件路径——故 skip 不削弱守卫。
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ Test20 c5 SKIPPED (root bypasses chmod 000; chmod-based unreadable not reproducible under EUID=0 — Gotcha #15 / B7-a 同范式; c6 dir-masquerade root-immune covers non-regular-file path of same predicate)"
else
    FXP5=$(mktemp -d); _mk_fx "$FXP5"
    chmod 000 "$FXP5/tests/test_shellcheck.sh"
    p5_out=$(DOC_DIR="$FXP5" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
    chmod 644 "$FXP5/tests/test_shellcheck.sh" 2>/dev/null   # 立即恢复，防 rm -rf 留不可读残骸
    assert_contains "Test20 c5: 不可读 legit-0 套件 → 显式拒绝静默坍缩" "$p5_out" "拒绝静默坍缩"
    assert_not_contains "Test20 c5 gate-coupled: 不可读后 pass-verdict 不得出现" "$p5_out" "$T20_PASS"
    rm -rf "$FXP5"
fi

# (c6) NEW-1 回归防御：legit-0 套件被目录冒充（磁盘结构损坏）→ Test20 必硬 FAIL，
# 绝不让 grep 对目录输出 0 静默坍缩成 0==0 假匹配。共享谓词 [ -f ] 闸（与 Test18 对齐）。
# c6 跑 $RT（同 c0-c3/c5）：冒充目录在 $FXP6/tests/ 即 DOC_DIR 树内。
FXP6=$(mktemp -d); _mk_fx "$FXP6"
rm -f "$FXP6/tests/test_shellcheck.sh"; mkdir "$FXP6/tests/test_shellcheck.sh"
p6_out=$(DOC_DIR="$FXP6" bash "$RT/tests/test_doc_freshness.sh" 2>&1)
assert_contains "Test20 c6: legit-0 套件被目录冒充 → 显式拒绝静默坍缩" "$p6_out" "拒绝静默坍缩"
assert_not_contains "Test20 c6 gate-coupled: 目录冒充后 pass-verdict 不得出现" "$p6_out" "$T20_PASS"
rm -rf "$FXP6"

summary
