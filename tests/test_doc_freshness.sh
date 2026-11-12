#!/bin/bash
# test_doc_freshness.sh — 验证文档中引用的版本号和测试用例数与实际一致
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

DOC_DIR="${DOC_DIR:-$ROOT_DIR}"

# ── Helper: 项目当前/目标版本号（root VERSION 文件）──
# 不读 Release/latest symlink ——避免 K4 鸡蛋问题（Gotcha #14）：
# release pipeline 先 bump VERSION + 文档引用 v-next，最后才翻转 Release/latest。
# 如果从 Release/latest 取真相，doc 引用 v-next 必然被判 stale，
# 强迫 release 期间 revert 文档（K4 workaround），结果 v-next 的 tarball 内
# 锁死 v-prev 的文档 snapshot。VERSION 文件是项目所在版本的真相源，
# Release/latest 是产物部署状态，二者语义不同，时间线也不同。
get_project_version() {
    local version_file="$ROOT_DIR/VERSION"
    if [ -f "$version_file" ]; then
        local v
        v=$(tr -d '[:space:]' < "$version_file")
        [ -n "$v" ] && echo "handoffx-$v" || echo "NONE"
    else
        echo "NONE"
    fi
}

PROJECT_VERSION=$(get_project_version)

echo ""
echo "  📊 Project version (root VERSION): $PROJECT_VERSION"
echo ""

# 共享 canonical 文档集（机械派生+裁定，见 design §3.0；新增 canonical doc 须用
# 同谓词重派生，勿手加）。三 guard（Test10 / 新断言点 / Test15）共用，根除分散清单各漏。
CANONICAL_DOCS="README.md README_CN.md $HX_MAIN_FILE CONTRIBUTING.md TEST-SCENARIOS.md"

# _doc_main_or_skip <check> — 读主文件的检查先过这道闸：0 = 主文件在、可读，照常检查；
# 1 = 本检查不跑（已打 ➖ 或 ❌）。Why（D1, fix wave 1）：活仓迁移前、以及每个源码包里都
# 没有 $HX_MAIN_FILE；旧写法 `cat … || echo ""` / `[ -f ] || continue` / awk 2>/dev/null
# 在缺席时把检查静默打成 ✅，读者以为主文件被核过。缺席 = ➖（未迁移或源码包，合法态）；
# 存在却不是可读普通文件 = ❌（坏了，不是"没迁移"）。
_doc_main_or_skip() {
    local m="$DOC_DIR/$HX_MAIN_FILE"
    if ! hx_present "$m"; then
        echo "  ➖ $1: 主文件不存在（未迁移或源码包）SKIPPED"
        return 1
    fi
    if [ ! -f "$m" ] || [ ! -r "$m" ]; then
        echo "  ❌ $1: $HX_MAIN_FILE 存在但不是可读的普通文件（${m}）"
        FAIL=$((FAIL+1))
        return 1
    fi
    return 0
}

# 归一：① 删 $HX_MAIN_FILE 历史块（结构 marker 非魔数）；② 窄 URL 解码仅 %20 %2F %2B。
_normalize_doc_for_scan() {
    awk '
      /^### 最近完成/ {skip=1; next}
      /^## 📜 Development Log/ {skip=1; next}
      /^## / { if (skip) skip=0 }
      !skip
    ' "$1" | sed 's/%20/ /g; s/%2F/\//g; s/%2B/+/g'
}

# 单文件静态 assert 调用点（排除函数定义签名行）。Test 18 + Test 20 共用同谓词，
# 单点定义消两份漂移（design 0024 §1）。非文件/不可读 sentinel 见函数内注释
# （legit-0 套件读不到时逐行 0==0 假 + Σ 两侧共谓词同向偏移自洽 = 假绿，本 guard 存在意义即防此）。
_count_static_asserts_one() {
    local f="$1" a df
    # FINDING1 + NEW-1（Gotcha #24/#25 递归防御）：非普通文件（目录/FIFO/设备/磁盘损坏）
    # 或不可读（chmod 000 / ACL / 跨用户克隆属主错位）必发非数字 sentinel，绝不让 grep
    # 把"读不到/非文件"静默坍缩成"真 0 断言点"。[ -f ] 与 Test 18 既有 [ -f ]||continue 对齐。
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo "ERR_NOTFILE_OR_UNREADABLE"
        return 1
    fi
    a=$(grep -cE '^[[:space:]]*assert_' "$f" 2>/dev/null) || a=0
    df=$(grep -cE '^[[:space:]]*assert_[A-Za-z0-9_]*[[:space:]]*\(\)' "$f" 2>/dev/null) || df=0
    echo $(( ${a:-0} - ${df:-0} ))
}

# 目录求和（入参=含 test_*.sh 目录）= Σ 单文件谓词（DRY）。
# FINDING1：单文件返回非数字 sentinel（不可读）→ 整体发 sentinel + return 1，
# 绝不 $((s + ERR)) ——bash 算术里未定义名=0 会把不可读静默当 0（fail-open）。
_count_static_asserts() {
    local d="$1" f s=0 one
    for f in "$d"/test_*.sh; do
        [ -f "$f" ] || continue
        one=$(_count_static_asserts_one "$f")
        case "$one" in
            ''|*[!0-9]*) echo "$one"; return 1 ;;
        esac
        s=$((s + one))
    done
    echo "$s"
}

# ── Test 0: helper 单元佐证（辅助；生产 gate 见后续 fixture-DOC_DIR 任务）──
_t0=$(mktemp -d); trap 'rm -rf "$_t0"' EXIT; mkdir -p "$_t0/tests"
printf '%s\n' '## 🚀 Q' '当前 469 断言点' '### 最近完成' '历史 744 断言点' \
  '## 🐛 G' 'g' 'badge tests-29%20suites%20%2F%20469%2B%20assertion%20sites-x' > "$_t0/H.md"
_o=$(_normalize_doc_for_scan "$_t0/H.md")
assert_not_contains "Test0: 剥 ### 最近完成" "$_o" "744 断言点"
assert_contains "Test0: 留当前声称" "$_o" "469 断言点"
assert_contains "Test0: 窄解码" "$_o" "tests-29 suites / 469+ assertion sites-x"
printf '%s\n' '#!/bin/bash' 'assert_exit a 0 0' 'assert_x() { :; }' 'assert_x f' > "$_t0/tests/test_f.sh"
assert_exit "Test0: 静态计数减定义=2" 0 "$([ "$(_count_static_asserts "$_t0/tests")" = 2 ] && echo 0 || echo 1)"
assert_exit "Test0: _one 单文件计数=2" 0 "$([ "$(_count_static_asserts_one "$_t0/tests/test_f.sh")" = 2 ] && echo 0 || echo 1)"
rm -rf "$_t0"; trap - EXIT

# ── Test 1: INSTALL.md 不包含旧测试用例数 "99" ──
INSTALL_CONTENTS=$(cat "$DOC_DIR/INSTALL.md" 2>/dev/null || echo "")
if echo "$INSTALL_CONTENTS" | grep -qE '99 (用例|test|assertion)'; then
    echo "  ❌ INSTALL.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ INSTALL.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 2: README.md 不包含旧测试用例数 "99" ──
README_CONTENTS=$(cat "$DOC_DIR/README.md" 2>/dev/null || echo "")
if echo "$README_CONTENTS" | grep -qE '99 (用例|test|assertion)'; then
    echo "  ❌ README.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 3: TEST-SCENARIOS.md 不包含旧测试用例数 "99" ──
# TEST-SCENARIOS.md 是 DEV_ONLY（release-sanitize-public.sh 从公开镜像删除），
# 而本 freshness 套件随公开 tarball 发布。文件缺席时显式 SKIP，
# 不能 `cat || echo ""` 静默判 PASS——那是 Gotcha #18「窄域/缺席判绿」假绿。
if [[ ! -f "$DOC_DIR/TEST-SCENARIOS.md" ]]; then
    echo "  ➖ TEST-SCENARIOS.md 缺席（dev-only，公开镜像已删）→ skip"
elif grep -qE '99 (用例|test|assertion)' "$DOC_DIR/TEST-SCENARIOS.md"; then
    echo "  ❌ TEST-SCENARIOS.md 包含旧测试数 '99'"
    FAIL=$((FAIL+1))
else
    echo "  ✅ TEST-SCENARIOS.md 不包含旧测试数 '99'"
    PASS=$((PASS+1))
fi

# ── Test 4: README.md Release/latest 引用与 root VERSION 一致 ──
# README 中 `latest → handoffx-vX.Y.Z` 行声明的是"本版本发行后 Release/latest 将指向何处"，
# 因此真相源是 root VERSION，不是 Release/latest 的当前 symlink（见 Gotcha #14）。
README_LATEST_REF=$(echo "$README_CONTENTS" | grep -oE 'latest\s*→\s*(handoffx-)?v[0-9]+(\.[0-9]+)*' | head -1 | sed -E 's/.*→[[:space:]]*//')
if [ -n "$README_LATEST_REF" ] && [ "$README_LATEST_REF" != "$PROJECT_VERSION" ]; then
    echo "  ❌ README.md Release/latest 引用: $README_LATEST_REF, root VERSION: $PROJECT_VERSION"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md Release/latest 引用与 root VERSION 一致 ($PROJECT_VERSION)"
    PASS=$((PASS+1))
fi

# ── Test 5: $HX_MAIN_FILE Current State 版本号与 root VERSION 一致 ──
if _doc_main_or_skip Test5; then
HANDOFF_CONTENTS=$(cat "$DOC_DIR/$HX_MAIN_FILE")
HANDOFF_VERSION=$(echo "$HANDOFF_CONTENTS" | grep -oE '当前版本.*(handoffx-)?v[0-9]+(\.[0-9]+)*' | grep -oE '(handoffx-)?v[0-9]+(\.[0-9]+)*' | head -1)
if [ -n "$HANDOFF_VERSION" ] && [ "$HANDOFF_VERSION" != "$PROJECT_VERSION" ]; then
    echo "  ❌ $HX_MAIN_FILE Current State 版本: $HANDOFF_VERSION, root VERSION: $PROJECT_VERSION"
    FAIL=$((FAIL+1))
else
    echo "  ✅ $HX_MAIN_FILE Current State 版本号与 root VERSION 一致 ($PROJECT_VERSION)"
    PASS=$((PASS+1))
fi
fi

# ── Test 6: 安装文档不得用 commands/*.md 通配复制 slash shims ──
# /handoffx 由 SKILL.md name 注册；通配复制会重新安装 handoffx.md，导致 Claude Code palette 重复。
if grep -RInE 'cp .*commands/\*\.md|cp .*commands/handoffx\.md|cp .*commands/.*[[:space:]]handoff\.md' "$DOC_DIR/README.md" "$DOC_DIR/INSTALL.md" >/dev/null 2>&1; then
    echo "  ❌ README/INSTALL 含 commands/*.md 或 handoffx.md 通配安装说明"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README/INSTALL 未使用会重复注册 /handoffx 的通配安装说明"
    PASS=$((PASS+1))
fi

# ── Test 7: recall N<=0 语义统一为拒绝，不回默认 ──
if grep -RInE '非正整数.*回默认|0 / 负数.*回退|N=0 / 负数.*回退' \
    "$DOC_DIR/skills/handoffx/SKILL.md" \
    "$DOC_DIR/skills/handoffx/command-shims/handoffx-recall.md" \
    "$DOC_DIR/skills/handoffx/references/handoffx-recall.md" \
    "$DOC_DIR/TEST-SCENARIOS.md" >/dev/null 2>&1; then
    echo "  ❌ recall N<=0 文档仍含回默认/回退语义"
    FAIL=$((FAIL+1))
else
    echo "  ✅ recall N<=0 文档统一为拒绝语义"
    PASS=$((PASS+1))
fi

# ── Test 8: 不再用旧的“三条命令、五个脚本”描述当前产品面 ──
# 主文件段单独过闸：缺席时只跳过主文件那一段（➖），其余文档照查。
_t8_main=0; _doc_main_or_skip Test8 && _t8_main=1
if {
    grep -RInE '三条命令、五个脚本|三条命令对应|三条互补的命令|三条 slash 命令|5 个脚本|五个脚本|四个命令|4 commands|7 个脚本' \
        "$DOC_DIR/README.md" \
        "$DOC_DIR/INSTALL.md" \
        "$DOC_DIR/CONTRIBUTING.md" \
        "$DOC_DIR/skills/handoffx/SKILL.md"
    [ "$_t8_main" = 1 ] && sed -n '1,230p' "$DOC_DIR/$HX_MAIN_FILE" | grep -nE '三条命令、五个脚本|三条命令对应|三条互补的命令|三条 slash 命令|5 个脚本|五个脚本|四个命令|4 commands|7 个脚本'
} >/dev/null 2>&1; then
    echo "  ❌ 文档仍含旧命令/脚本数量描述"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 文档避免硬编码命令/脚本数量"
    PASS=$((PASS+1))
fi

# ── Test 9: 手动 .skill 升级说明必须包含 init shim（双语 + brace 形式容忍）──
# v2.2.3 双语拆分后：README.md=EN / README_CN.md=zh。说明是产物无关的：shim 以
# `<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md` 形式拷贝（基名前缀随
# 产物而异）。意图不变（升级说明不得丢 init shim）；接受 brace 形式或字面
# `-init.md`，任一 README 命中即可。
README_BOTH=$(cat "$DOC_DIR/README.md" "$DOC_DIR/README_CN.md" 2>/dev/null || echo "")
if ! echo "$README_BOTH" | grep -qE 'command-shims/[^ ]*-(init\.md|\{[a-z,]*init[a-z,]*\}\.md)'; then
    echo "  ❌ README 手动 .skill 升级说明缺 init shim（README.md/README_CN.md 均未命中）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README 手动 .skill 升级说明含 init shim（brace 形式或字面）"
    PASS=$((PASS+1))
fi

# ── Test 10: 当前文档不得停留在旧断言统计 ──
# 以 _normalize_doc_for_scan 过 CANONICAL_DOCS，历史块剥离替代魔数 sed -n '1,420p'；
# 同时覆盖旧清单漏掉的 README_CN.md（Gotcha #N：列表写死=盲区）。
_t10_hit=0
for _d in $CANONICAL_DOCS; do
    if [ "$_d" = "$HX_MAIN_FILE" ]; then _doc_main_or_skip Test10 || continue; fi
    [ -f "$DOC_DIR/$_d" ] || continue
    if _normalize_doc_for_scan "$DOC_DIR/$_d" \
        | grep -qE '(^|[[:space:]])(228|270|279) (断言|assertions|passed)'; then
        _t10_hit=1
    fi
done
if [ "$_t10_hit" -eq 1 ]; then
    echo "  ❌ 当前文档仍含旧断言统计"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 当前文档未停留在旧断言统计"
    PASS=$((PASS+1))
fi

# ── Test 11: Codex 文档不得推荐 ~/.codex/skills 作为 Handoff 安装/镜像路径 ──
if grep -RInE '~/.codex/skills|\\.codex/skills|sync-codex-skills.*镜像|合并到 `~/.codex/skills`' \
    "$DOC_DIR/README.md" \
    "$DOC_DIR/INSTALL.md" \
    "$DOC_DIR/skills/handoffx/SKILL.md" \
    "$DOC_DIR/skills/handoffx/references" >/dev/null 2>&1; then
    echo "  ❌ 文档仍推荐 Codex ~/.codex/skills 镜像路径"
    FAIL=$((FAIL+1))
else
    echo "  ✅ 文档未推荐 Codex ~/.codex/skills 镜像路径"
    PASS=$((PASS+1))
fi

# ── Test 12: /handoffx 与 /handoffx-tidy 后置校验必须使用 readiness 模式 ──
# v2: arg may be $HX_MAIN_FILE (single-file legacy mode) or <project-root> (multi-file).
if grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoffx/references/handoffx-write.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoffx/references/handoffx-tidy.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoffx/references/handoffx-init.md" \
   && grep -q 'validate-handoff.sh --readiness' "$DOC_DIR/skills/handoffx/SKILL.md"; then
    echo "  ✅ handoff 后置校验使用 readiness 模式"
    PASS=$((PASS+1))
else
    echo "  ❌ handoff 后置校验未统一使用 validate-handoff.sh --readiness"
    FAIL=$((FAIL+1))
fi

# ── Test 13: README.md 凭证前缀数量说明不得停留在旧值 "8 种" ──
if grep -q "8 种密钥前缀" "$DOC_DIR/README.md"; then
    echo "  ❌ README.md 凭证前缀数量说明已过时（'8 种'应为当前实际数量）"
    FAIL=$((FAIL+1))
else
    echo "  ✅ README.md 凭证前缀数量未停留在旧值 '8 种'"
    PASS=$((PASS+1))
fi

# ── Test 14: README 凭证前缀数量必须与扫描器实际匹配（动态计数，双语）──
# 真不变量 = README 声称数 == scan-credentials.sh PATTERNS 实际条数。
# 不再硬编码 "11 种密钥前缀" 字面（双语拆分后 EN 用 "N secret-prefix"、
# zh 用 "N 类 secret 前缀"）。动态读扫描器实际条数，断言该数字出现在任一
# README 的 secret/凭证 语境里。更新 pattern 数量后两 README 必须同步。
SCAN_N=$(awk '/^PATTERNS=\(/{f=1;next} f&&/^\)/{f=0} f&&/^[[:space:]]*'\''/{n++} END{print n+0}' \
    "$DOC_DIR/scripts/scan-credentials.sh")
if [ -z "$SCAN_N" ] || [ "$SCAN_N" -lt 1 ]; then
    echo "  ❌ 无法从 scan-credentials.sh 读出 PATTERNS 条数"
    FAIL=$((FAIL+1))
elif echo "$README_BOTH" | grep -qE "${SCAN_N}[[:space:]]*(secret-prefix|类 secret|种密钥前缀|secret 前缀)"; then
    echo "  ✅ README 凭证前缀数量与扫描器一致（动态 ${SCAN_N}，双语命中）"
    PASS=$((PASS+1))
else
    echo "  ❌ README 凭证前缀数量与扫描器实际 (${SCAN_N}) 不一致（更新 pattern 后需同步双语 README）"
    FAIL=$((FAIL+1))
fi

# ── Test 15: 测试套件数量声明跨文档一致（structural drift guard, Round 3 review）──
# Round 3 audit 发现 v2.1.5 之前各 doc 自声称套件数与实际 26 不一致。此测试机械
# 检测 "<N> 套件" pattern，强制 user-facing canonical 文档与 ls tests/test_*.sh
# 数量一致。
# v2.2.1 (post Decision 0018): scan list 移除 "Mac Project Transfer.md"——
# 此文件作为电脑转移残留已删（Decision 0018 D 落地，private-too 清理）
ACTUAL_SUITE_COUNT=$(ls "$DOC_DIR"/tests/test_*.sh 2>/dev/null | wc -l | tr -d ' ')
suite_drift=0
for _d in $CANONICAL_DOCS; do
    doc="$DOC_DIR/$_d"
    if [ "$_d" = "$HX_MAIN_FILE" ]; then _doc_main_or_skip Test15 || continue; fi
    [ -f "$doc" ] || continue
    # 提取所有 "<N> 套件|suites" 出现的正整数 N（排除 "0 套件断言变化" 这类 delta 描述；
    # `^[1-9][0-9]*` 强制首字非 0 即可——0 不是有效的 count 声称）。
    # _normalize_doc_for_scan 剥历史块并 URL 解码，捕捉 shields.io badge 中 %20suites。
    claimed_counts=$(_normalize_doc_for_scan "$doc" | grep -oE '[0-9]+ *(套件|suites)' | grep -oE '^[1-9][0-9]*' | sort -u)
    [ -z "$claimed_counts" ] && continue
    for n in $claimed_counts; do
        if [ "$n" != "$ACTUAL_SUITE_COUNT" ]; then
            echo "  ❌ $(basename "$doc"): 声称 '$n 套件'，实际 $ACTUAL_SUITE_COUNT 套件"
            suite_drift=1
        fi
    done
done
if [ "$suite_drift" -eq 0 ]; then
    echo "  ✅ 所有 canonical 文档 '<N> 套件' 声明与实际一致 ($ACTUAL_SUITE_COUNT)"
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi

# ── Test 16: <N>/<N> ✅ 平台兼容性声称 drift guard（v2.1.5，Round 7 I1+I2+I3）──
# $HX_MAIN_FILE current-state slot 用 "X/Y ✅" 表示 "X 通过 of Y 套件"。X==Y 时是
# 平台兼容声明，必须等于当前套件数；不限制 X<Y（partial pass，可能合法）。
# **仅扫 canonical living docs**——$HX_LOGS_DIR/ 是 immutable session 记录，
# CHANGELOG 历史 release 段 author-time 数据可能与现在不同。
# v2.2.1 (Decision 0018 D): "Mac Project Transfer.md" 已删，从 scan list 移除
if _doc_main_or_skip Test16; then
xy_drift=0
for doc in "$DOC_DIR/$HX_MAIN_FILE"; do
    # 抓 "X/Y ✅" 模式，提取 X 和 Y
    while IFS= read -r match; do
        x="${match%/*}"
        y="${match#*/}"
        # 仅检 X==Y 的全过声称
        if [ "$x" = "$y" ] && [ "$x" != "$ACTUAL_SUITE_COUNT" ]; then
            echo "  ❌ $(basename "$doc"): 声称 '$match ✅' (X==Y 平台全过)，但实际 $ACTUAL_SUITE_COUNT 套件"
            xy_drift=1
        fi
    done < <(grep -oE '[1-9][0-9]*/[1-9][0-9]* ✅' "$doc" | sed 's/ ✅//' | sort -u)
done
if [ "$xy_drift" -eq 0 ]; then
    echo "  ✅ $HX_MAIN_FILE '<N>/<N> ✅' 平台兼容声称与实际一致"
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi
fi

# ── Test 17: SOP 公开发布资产契约 guard（Codex round-6，doc/code drift 机械化）──
# 反复教训：脚本修了 public-checksums 自洽，但 SOP 手动 Phase 7 仍贴旧清单
# （上传指向全私有产物的 ${RELEASE_DIR}/checksums.txt + sbom.cyclonedx.json）
# → 跟脚本路径的人没事，照文档手动发的人重新坑消费者。机械断言：SOP 公开
# 资产清单不得引用 ${RELEASE_DIR}/checksums.txt 或 sbom.cyclonedx.json。
SOP_DOC="$DOC_DIR/docs/GITHUB_RELEASE_SOP.md"
if [ -f "$SOP_DOC" ]; then
    # 只匹配「带引号的 array-element」形式（真实资产行），不误伤 ❌ 警告注释
    bad_sop=$(grep -nE '^[[:space:]]*"\$\{RELEASE_DIR\}/(checksums\.txt|sbom\.cyclonedx\.json)"' "$SOP_DOC" || true)
    if [ -n "$bad_sop" ]; then
        echo "  ❌ SOP Phase 7 仍把私有 checksums/SBOM 当公开资产（doc/code drift 重演）:"
        echo "$bad_sop" | head -3 | sed 's/^/      /'
        FAIL=$((FAIL+1))
    else
        echo "  ✅ SOP 公开资产契约与脚本一致（无 \${RELEASE_DIR}/checksums|sbom 引用）"
        PASS=$((PASS+1))
    fi
fi

# ── Test 18: 断言点总数动态 drift guard（静态 assert 调用点计数，design §3.2）──
_REAL_STATIC=$(_count_static_asserts "$DOC_DIR/tests")
ap_drift=0
for _d in $CANONICAL_DOCS; do
    if [ "$_d" = "$HX_MAIN_FILE" ]; then _doc_main_or_skip Test18 || continue; fi
    [ -f "$DOC_DIR/$_d" ] || continue
    while IFS= read -r _n; do
        [ -z "$_n" ] && continue
        if [ "$_n" != "$_REAL_STATIC" ]; then
            echo "  ❌ $_d: 声称 '$_n 断言点'，实际 $_REAL_STATIC"
            ap_drift=1
        fi
    done <<EOF
$(_normalize_doc_for_scan "$DOC_DIR/$_d" | grep -oE '[0-9]+\+? *个? *(断言点|assertion[ -]sites?)' | grep -oE '^[0-9]+')
EOF
done
if [ "$ap_drift" -eq 0 ]; then
    echo "  ✅ 所有 CANONICAL_DOCS '断言点' 与静态计数一致 ($_REAL_STATIC)"
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
fi

# ── Test 19: ### 最近完成 块不得含 current-canonical 计数声称（CRITICAL-1 防御）──
# _normalize_doc_for_scan 会剥离该块；若有人误把当前计数声称写进历史区，
# strip 会悄悄隐藏它，导致 Test 18 漏检（Gotcha #20/757 母题的新变体）。
# 合法的 ### 最近完成 冻结 bullet 用旧词「断言」；「断言点/assertion sites」
# 只出现在当前状态声称，任何在该块出现的 = 误置当前声称，strip 会隐藏它。
if _doc_main_or_skip Test19; then
_rc_blk=$(awk '/^### 最近完成/{f=1;next} /^## /{f=0} f' "$DOC_DIR/$HX_MAIN_FILE")
if printf '%s' "$_rc_blk" | grep -qE '断言点|assertion[ -]sites?'; then
    echo "  ❌ $HX_MAIN_FILE ### 最近完成 块含 '断言点/assertion sites'——当前计数声称勿写历史区(会被 _normalize 剥离隐藏，CRITICAL-1)"
    FAIL=$((FAIL+1))
else
    echo "  ✅ ### 最近完成 块无 current 计数声称(strip 不会隐藏 drift)"
    PASS=$((PASS+1))
fi
fi

# ── Test B②: Current State references highest Dev Log ordinal (WARN-only, ADR-0002) ──
if _doc_main_or_skip B②; then
B2_MAX=$(ls "$DOC_DIR/$HX_LOGS_DIR/"[0-9]*.md 2>/dev/null | sed 's|.*/||' | grep -oE '^[0-9]{4}' | sort | tail -1)
B2_CS=$(awk '/^## 🎯 Current State/{f=1} f&&/^## /&&!/Current State/{f=0} f' "$DOC_DIR/$HX_MAIN_FILE")
if [ -n "$B2_MAX" ] && printf '%s' "$B2_CS" | grep -qE "(Dev Log|$HX_LOGS_DIR/)0*${B2_MAX#"${B2_MAX%%[1-9]*}"}|0*$B2_MAX"; then
    echo "  ✅ B②: Current State references highest Dev Log ordinal ($B2_MAX)"
    PASS=$((PASS+1))
else
    # WARN-only — NEVER FAIL (ADR-0002 K4-immune). Advisory + counts as PASS.
    echo "  ⚠️  B② WARN: Current State does not reference highest Dev Log ordinal ($B2_MAX) — advisory only, not a gate (ADR-0002)"
    PASS=$((PASS+1))
fi
fi

# ── Test 20: per-suite 静态断言点逐套件 drift guard（design 0024 §1，Test 18 per-suite 精炼）──
# 真相源 = 逐文件静态 assert 调用点（_count_static_asserts_one，与 Test 18 同谓词）。
# 三层：① 表每行 N==静态 ② 完整性（每套件恰一行/无孤儿）③ Σ==_REAL_STATIC。
# TEST-SCENARIOS.md 是 DEV_ONLY（Test 3 范式）：缺席显式 ➖skip，绝不 cat||echo 假绿（Gotcha #18）。
# _REAL_STATIC 由上方 Test 18 计算并在作用域内（DRY 复用，勿重算）。
_TS="$DOC_DIR/TEST-SCENARIOS.md"
if [[ ! -f "$_TS" ]]; then
    echo "  ➖ Test20: TEST-SCENARIOS.md 缺席（dev-only，公开镜像已删）→ skip"
else
    _ps_drift=0
    _actual_suites=$(ls "$DOC_DIR"/tests/test_*.sh 2>/dev/null | sed 's|.*/||' | sort)
    # 表行机械解析：^| `test_X.sh` | N → "test_X.sh N"（[|] 避 ERE alternation；单引号内 ` 字面）
    _table_rows=$(grep -oE '^[|][[:space:]]*`test_[A-Za-z0-9_]+\.sh`[[:space:]]*[|][[:space:]]*[0-9]+' "$_TS" \
        | sed -E 's/^[|][[:space:]]*`([^`]+)`[[:space:]]*[|][[:space:]]*([0-9]+).*/\1 \2/' | sort)
    _table_suites=$(echo "$_table_rows" | awk '{print $1}' | sort)
    # ② 完整性：actual ⊕ table 双向差必空
    _miss=$(comm -23 <(echo "$_actual_suites") <(echo "$_table_suites"))
    _orphan=$(comm -13 <(echo "$_actual_suites") <(echo "$_table_suites"))
    # 故意不引号 $_miss/$_orphan：借词分割 + tr 把多行套件名折成单行展示（勿"修"成引号）
    if [ -n "$_miss" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表缺套件行: $(echo $_miss | tr '\n' ' ')"
        _ps_drift=1
    fi
    if [ -n "$_orphan" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表孤儿行(套件不存在): $(echo $_orphan | tr '\n' ' ')"
        _ps_drift=1
    fi
    # ① 逐行 EXACT + ③ Σ
    _ps_sum=0
    while read -r _sfx _claim; do
        [ -z "$_sfx" ] && continue
        _real_one=$(_count_static_asserts_one "$DOC_DIR/tests/$_sfx")
        # FINDING1：不可读/非数字 → 显式拒绝，绝不静默坍缩成 0==0 假匹配（Gotcha #24）
        case "$_real_one" in
            ''|*[!0-9]*)
                echo "  ❌ Test20: $_sfx 不可读或非数字计数($_real_one) — 拒绝静默坍缩"
                _ps_drift=1
                continue ;;
        esac
        _ps_sum=$((_ps_sum + _claim))
        if [ "$_claim" != "$_real_one" ]; then
            echo "  ❌ Test20: $_sfx 表声称 '$_claim 断言点'，实际静态 $_real_one"
            _ps_drift=1
        fi
    done <<EOF
$_table_rows
EOF
    if [ "$_ps_sum" != "$_REAL_STATIC" ]; then
        echo "  ❌ Test20: TEST-SCENARIOS 表 Σ=$_ps_sum ≠ 静态总数 $_REAL_STATIC"
        _ps_drift=1
    fi
    if [ "$_ps_drift" -eq 0 ]; then
        echo "  ✅ Test20: per-suite 静态断言点逐套件/完整性/Σ 全一致 ($_REAL_STATIC)"
        PASS=$((PASS+1))
    else
        FAIL=$((FAIL+1))
    fi
fi

# ── Test 21: CHANGELOG 当前版本段必须以 `---` 收尾 ──
# Why：gitx 用 awk '/^## <ver> /,/^---$/' 切 RELEASE_NOTES / GitHub release body；
# 段尾缺 `---` 时范围一路吞到下一个版本段，公开发布说明就带上旧版本内容。
# 规则逐字照搬 gitx（版本取 root VERSION），不自写解析——自写的切法证明不了 gitx 切得对。
_t21_ver=$(tr -d '[:space:]' < "$ROOT_DIR/VERSION" 2>/dev/null)
_t21_safe=$(printf '%s' "$_t21_ver" | sed 's/\./\\./g')
_t21_block=$(awk "/^## $_t21_safe /,/^---\$/" "$DOC_DIR/CHANGELOG.md" 2>/dev/null)
_t21_heads=$(printf '%s\n' "$_t21_block" | grep -c '^## ')
assert_exit "Test21: CHANGELOG ${_t21_ver} 段恰含 1 个 '## ' 标题（got ${_t21_heads}）" 0 "$([ "$_t21_heads" = "1" ] && echo 0 || echo 1)"
assert_exit "Test21: CHANGELOG ${_t21_ver} 段以 '---' 收尾" 0 "$([ "$(printf '%s\n' "$_t21_block" | tail -n 1)" = "---" ] && echo 0 || echo 1)"

summary
