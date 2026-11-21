#!/bin/bash
# test_handoff_postflight.sh — v2.1.0 UX #3: aggregator script runs all 5
# post-handoff checks (scan / validate / lint / rotation / archive) with
# unified summary.
source "$(dirname "$0")/common.sh"

POSTFLIGHT="$SCRIPTS_DIR/handoff-postflight.sh"
SKILL_TEMPLATES="$ROOT_DIR/skills/handoffx/assets"

# T1: script exists and is executable
assert_file_exists "postflight.sh exists" "$POSTFLIGHT"
[ -x "$POSTFLIGHT" ] && { echo "  ✅ postflight.sh is executable"; PASS=$((PASS+1)); } || { echo "  ❌ postflight.sh not executable"; FAIL=$((FAIL+1)); }

# T2: -h / --help shows the 5 checks (self-documenting)
out_help=$(bash "$POSTFLIGHT" -h 2>&1)
assert_contains "T2: help mentions scan-credentials" "$out_help" "scan-credentials"
assert_contains "T2: help mentions validate-handoff" "$out_help" "validate-handoff"
assert_contains "T2: help mentions handoff-lint" "$out_help" "handoff-lint"
assert_contains "T2: help mentions rotation-reminder" "$out_help" "rotation-reminder"
assert_contains "T2: help mentions archive-devlog" "$out_help" "archive-devlog"

# T3: missing file → exit 2 + clear error
SANDBOX_MISS=$(mktemp -d)
out_miss=$(bash "$POSTFLIGHT" "$SANDBOX_MISS/nonexistent.md" 2>&1)
ec_miss=$?
assert_exit "T3: missing file → exit 2" 2 "$ec_miss"
assert_contains "T3: missing file error message" "$out_miss" "not found"
rm -rf "$SANDBOX_MISS"

# T4: valid v2 layout → exit 0 + "all 5 checks passed" summary
SANDBOX_OK=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_OK/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_OK/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_OK/${HX_LOGS_DIR}" "$SANDBOX_OK/${HX_DEC_DIR}"
out_ok=$(bash "$POSTFLIGHT" "$SANDBOX_OK/${HX_MAIN_FILE}" 2>&1)
ec_ok=$?
assert_exit "T4: valid v2 → exit 0" 0 "$ec_ok"
assert_contains "T4: summary says all passed" "$out_ok" "all checks passed"
rm -rf "$SANDBOX_OK"

# T5: --quiet mode suppresses per-check details, prints only summary
SANDBOX_Q=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_Q/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_Q/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_Q/${HX_LOGS_DIR}" "$SANDBOX_Q/${HX_DEC_DIR}"
out_q=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_Q/${HX_MAIN_FILE}" 2>&1)
ec_q=$?
assert_exit "T5: --quiet on valid → exit 0" 0 "$ec_q"
assert_contains "T5: --quiet still prints summary" "$out_q" "all checks passed"
# --quiet should NOT print per-step "→ 1. scan-credentials" headers
if echo "$out_q" | grep -q "→ 1\."; then
    echo "  ❌ T5: --quiet leaked per-step output"; FAIL=$((FAIL+1))
else
    echo "  ✅ T5: --quiet suppresses per-step output"; PASS=$((PASS+1))
fi
rm -rf "$SANDBOX_Q"

# T6: file path flexibility — flag and positional in any order
SANDBOX_POS=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$SANDBOX_POS/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$SANDBOX_POS/${HX_GOTCHAS_FILE}"
mkdir -p "$SANDBOX_POS/${HX_LOGS_DIR}" "$SANDBOX_POS/${HX_DEC_DIR}"
# file then flag
out_p1=$(bash "$POSTFLIGHT" "$SANDBOX_POS/${HX_MAIN_FILE}" --quiet 2>&1)
ec_p1=$?
assert_exit "T6a: file then --quiet → exit 0" 0 "$ec_p1"
# flag then file
out_p2=$(bash "$POSTFLIGHT" --quiet "$SANDBOX_POS/${HX_MAIN_FILE}" 2>&1)
ec_p2=$?
assert_exit "T6b: --quiet then file → exit 0" 0 "$ec_p2"
rm -rf "$SANDBOX_POS"

# T7: unknown flag → exit 2
out_uf=$(bash "$POSTFLIGHT" --bogus 2>&1)
ec_uf=$?
assert_exit "T7: unknown flag → exit 2" 2 "$ec_uf"
assert_contains "T7: unknown flag error" "$out_uf" "unknown flag"

# T8: failing check → exit 1 + summary names which failed
# Use a v1-marker-less file with missing required structure to trip validate
SANDBOX_BAD=$(mktemp -d)
cat > "$SANDBOX_BAD/${HX_MAIN_FILE}" <<'EOF'
# Demo
no sections, no anchor, definitely incomplete
EOF
out_bad=$(bash "$POSTFLIGHT" "$SANDBOX_BAD/${HX_MAIN_FILE}" 2>&1)
ec_bad=$?
assert_exit "T8: bad file → exit 1" 1 "$ec_bad"
assert_contains "T8: summary lists failure count" "$out_bad" "check(s) failed"
rm -rf "$SANDBOX_BAD"

# --- Task 5: postflight --files runs B① xref-lint ---
PF_W="$TMP_DIR/pf-files-$$"; rm -rf "$PF_W"; mkdir -p "$PF_W/${HX_LOGS_DIR}"
printf '<!-- HANDOFF v2 schema -->\n# H\n## 🎯 Current State\n' > "$PF_W/${HX_MAIN_FILE}"
ngf="$PF_W/ng.md"; printf 'dangling Dev Log 7777\n' > "$ngf"
out_files=$(bash "$POSTFLIGHT" --files="$ngf" "$PF_W/${HX_MAIN_FILE}" 2>&1)
ec_files=$?
assert_exit "T9: postflight --files= with dangling ref → exit 1" 1 "$ec_files"
assert_contains "T9: xref-lint runs and reports" "$out_files" "xref-lint"
out_help_files=$(bash "$POSTFLIGHT" --help 2>&1)
assert_contains "T9: --help still works" "$out_help_files" "Usage"
rm -rf "$PF_W"

# --- F3: --files= glob expansion must NOT occur ---
# Without set -f, --files='*.md' expands to all .md files in CWD, causing
# xref-lint to run on files not in the explicit write-target set (ADR-0004
# violation). Fixed behaviour: '*.md' is treated as a literal path; since no
# file literally named '*.md' exists, xref-lint skips it (missing file) →
# no spurious exit 1 from globbed a.md's dangling ref.
# Assertion: xref-lint output must NOT mention a.md's dangling ref (Dev Log 7777).
# We use a valid v2 sandbox so the other checks pass; only the xref-lint (check 5) output is inspected.
F3_DIR=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$F3_DIR/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$F3_DIR/${HX_GOTCHAS_FILE}"
mkdir -p "$F3_DIR/${HX_LOGS_DIR}" "$F3_DIR/${HX_DEC_DIR}"
printf 'dangling Dev Log 7777\n' > "$F3_DIR/a.md"
printf 'clean content\n'          > "$F3_DIR/b.md"
# Run from F3_DIR so that '*.md' would glob-expand if set -f is absent.
# With the fix: literal '*.md' path doesn't exist → xref-lint skips it → no "Dev Log 7777" output.
# Without the fix: '*.md' globs to a.md+b.md+${HX_MAIN_FILE} → a.md has dangling ref → output contains it.
f3_out=$(cd "$F3_DIR" && bash "$POSTFLIGHT" --files='*.md' "$HX_MAIN_FILE" 2>&1)
assert_not_contains "F3: glob NOT expanded — Dev Log 7777 not reported" "$f3_out" "Dev Log 7777"
rm -rf "$F3_DIR"

# --- F5: empty --files= is a distinct usage error (exit 2), not silent skip ---
F5W="$TMP_DIR/pf-f5-$$"; rm -rf "$F5W"; mkdir -p "$F5W"
printf '<!-- HANDOFF v2 schema -->\n# H\n## 🎯 Current State\n' > "$F5W/${HX_MAIN_FILE}"
assert_exit "F5: empty --files= -> exit 2 usage error" 2 "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --files= "$F5W/${HX_MAIN_FILE}" >/dev/null 2>&1; echo $?)"
assert_contains "F5: --help still works (no-flag path intact)" "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --help 2>&1)" "Usage"
rm -rf "$F5W"

# --- P2.4 §4b-4 legacy-layout guard: postflight must stop with exit 2 and the
# upgrade command instead of running five checks against a missing main file.
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
ec=0; out=$(cd "$LG" && bash "$POSTFLIGHT" 2>&1) || ec=$?
assert_exit "legacy v3 tree → postflight exit 2" 2 "$ec"
assert_contains "legacy v3 tree → names schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
rm -rf "$LG"
LG=$(mktemp -d); cp "$ROOT_DIR/tests/fixtures/handoff-v1-sample.md" "$LG/$HX_LEGACY_MAIN_FILE"
ec=0; out=$(bash "$POSTFLIGHT" "$LG/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "legacy v1 file → postflight exit 2" 2 "$ec"
assert_contains "legacy v1 file → names migrate-to-v2 --apply" "$out" "migrate-to-v2.sh --apply"
rm -rf "$LG"
LG=$(mktemp -d); p21_materialize "$LG" || FAIL=$((FAIL+1))
cp "$LG/$HX_LEGACY_MAIN_FILE" "$LG/$HX_MAIN_FILE"
ec=0; out=$(bash "$POSTFLIGHT" "$LG/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "mixed legacy+new → postflight exit 2" 2 "$ec"
assert_contains "mixed legacy+new → names the mixed state" "$out" "mixed layout"
assert_contains "mixed legacy+new → names a legacy piece" "$out" "$HX_LEGACY_LOGS_DIR"
rm -rf "$LG"

# --- X1 (v4.1.1): relative --files= entries resolve against the project root
# (the main file's dir), not the cwd. Why: SKILL.md's own example passes
# relative paths, and from any other cwd xref-lint reported every target as
# missing. Absolute entries are kept as they are.
X1=$(mktemp -d)
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$X1/${HX_MAIN_FILE}"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$X1/${HX_GOTCHAS_FILE}"
mkdir -p "$X1/${HX_LOGS_DIR}" "$X1/${HX_DEC_DIR}"
printf 'clean note\n' > "$X1/${HX_LOGS_DIR}/0001-2026-11-02T1000-x.md"
x1_out=$(cd / && bash "$POSTFLIGHT" --files="${HX_MAIN_FILE},${HX_LOGS_DIR}/0001-2026-11-02T1000-x.md" "$X1/${HX_MAIN_FILE}" 2>&1)
assert_not_contains "X1: relative --files= from another cwd → targets found" "$x1_out" "写入目标不存在"
x1_out=$(cd / && bash "$POSTFLIGHT" --files="$X1/${HX_LOGS_DIR}/0001-2026-11-02T1000-x.md" "$X1/${HX_MAIN_FILE}" 2>&1)
assert_not_contains "X1: absolute --files= entry kept as is" "$x1_out" "写入目标不存在"
x1_ec=0; x1_out=$(cd / && bash "$POSTFLIGHT" --files="${HX_LOGS_DIR}/nope.md" "$X1/${HX_MAIN_FILE}" 2>&1) || x1_ec=$?
assert_contains "X1: a genuinely missing relative target is still ❌, named under the root" "$x1_out" "写入目标不存在,无法检查: $(cd "$X1" && pwd)/${HX_LOGS_DIR}/nope.md"
assert_exit "X1: missing target → postflight exit 1" 1 "$x1_ec"
rm -rf "$X1"

# R01/R04/R09/U04：全部新 fixture 放临时目录，不使用仓库交接数据。
AUD=$(mktemp -d)
trap 'rm -rf "$AUD"' EXIT
mkdir "$AUD/project"
P="$AUD/project"
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$P/$HX_MAIN_FILE"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$P/$HX_GOTCHAS_FILE"
mkdir "$P/$HX_LOGS_DIR" "$P/$HX_DEC_DIR"
brief_bound() {
    local text="$2" code=0 count lines
    # 固定摘要是合法 UTF-8：只数 ASCII/多字节首字节，非 wc -c 的字节数。
    count=$(printf '%s' "$text" | LC_ALL=C tr -cd '\000-\177\300-\377' | wc -c | tr -d ' ')
    lines=$(printf '%s\n' "$text" | wc -l | tr -d ' ')
    [ "$count" -gt 0 ] && [ "$count" -le 200 ] && [ "$lines" -eq 1 ] || code=1
    assert_exit "$1：单行且 ≤200 Unicode 字符" 0 "$code"
}
ex=0; out=$(bash "$POSTFLIGHT" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "brief 成功" 0 "$ex"
brief_bound "brief 成功" "$out"
assert_not_contains "brief 成功不回放 worker" "$out" '→ 1.'
mkdir "$AUD/explicit"
for name in "$HX_LEGACY_MAIN_FILE" '自定义 交接.md'; do
    cp "$FIXTURES_DIR/handoff-v1-sample.md" "$AUD/explicit/$name"
    cat "$FIXTURES_DIR/openai_key.md" >> "$AUD/explicit/$name"
    ex=0; out=$(bash "$POSTFLIGHT" "$AUD/explicit/$name" 2>&1) || ex=$?
    assert_exit "R01 postflight 显式 $name 阻断" 1 "$ex"
    assert_contains "R01 显式命中报告" "$out" "detected in $AUD/explicit/$name"
    assert_contains "R04 凭证阻断不归档" "$out" 'archive-devlog: skipped'
    ex=0; out=$(bash "$POSTFLIGHT" --brief "$AUD/explicit/$name" 2>&1) || ex=$?
    brief_bound "R01 brief 显式命中" "$out"
    assert_contains "R01 brief 关键原因" "$out" '凭证扫描'
    assert_not_contains "R01 brief 不泄露路径" "$out" "$P"
    rm "$AUD/explicit/$name"
done
# 老坏条目不能第一次失败后被归档，从而第二次无修复全绿。
printf '坏的旧记录，缺 frontmatter\n' > "$P/$HX_LOGS_DIR/0001-2020-01-01T0000-bad.md"
cp -R "$P" "$AUD/before"
for repeat in 1 2; do
    ex=0; out=$(bash "$POSTFLIGHT" "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
    assert_exit "R04 第 $repeat 次坏条目仍阻断" 1 "$ex"
    assert_contains "R04 第 $repeat 次 skipped 不能标 ✅" "$out" 'archive-devlog: skipped'
    unchanged=0; diff -r "$AUD/before" "$P" >/dev/null || unchanged=$?
    assert_exit "R04 第 $repeat 次字节和路径不变" 0 "$unchanged"
done
rm "$P/$HX_LOGS_DIR/0001-2020-01-01T0000-bad.md"
# 并集扫描仍涵盖 siblings / archive，不能只扫显式 clean 主文件。
mkdir -p "$P/$HX_LOGS_DIR.archive/2020"
cp "$FIXTURES_DIR/openai_key.md" "$P/$HX_LOGS_DIR.archive/2020/leaked.md"
ex=0; out=$(bash "$POSTFLIGHT" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "R01 postflight 保留归档安全扫描" 1 "$ex"
assert_contains "R01 brief 归档凭证原因" "$out" '凭证扫描'
brief_bound "R01 brief 归档凭证" "$out"
rm "$P/$HX_LOGS_DIR.archive/2020/leaked.md"

# 使用真实检查器 + 包装器计数，证明 validate 仅结构，独立 lint 一次。
# context guard requires the real source layout scripts/lib, not an arbitrary
# bin/lib stub directory. Copy every lib (including handoff-context.sh), keep
# this fixture source_unbound, and do not forge an installed manifest or bypass
# the product guard merely to reach the workers under test.
mkdir -p "$AUD/scripts/lib"
cp "$SCRIPTS_DIR/"*.sh "$AUD/scripts/"
cp "$SCRIPTS_DIR/lib/"*.sh "$AUD/scripts/lib/"
ex=0; out=$(bash "$AUD/scripts/handoff-runtime.sh" context 2>&1) || ex=$?
assert_exit "U04 copied source context accepted" 0 "$ex"
assert_contains "U04 copied fixture is source_unbound" "$out" 'scope=source_unbound'
mv "$AUD/scripts/handoff-lint.sh" "$AUD/scripts/real-lint.sh"
cat > "$AUD/scripts/handoff-lint.sh" <<EOF
#!/bin/bash
printf 'lint\\n' >> "$AUD/lint-count"
exec bash "$AUD/scripts/real-lint.sh" "\$@"
EOF
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "U04 计数 fixture 真实检查通过" 0 "$ex"
assert_exit "U04 lint 仅运行一次" 1 "$(wc -l < "$AUD/lint-count" | tr -d ' ')"

# 隔离编排测试：注入明确失败/缺 worker/巨量诊断，但其它真实检查照常执行。
cat > "$AUD/scripts/archive-devlog.sh" <<EOF
#!/bin/bash
printf 'archive\\n' >> "$AUD/archive-count"
exit 0
EOF
# 真实 rotation 近期到期不阻断，旧独立 exit 契约在 rotation suite 覆盖。
SOON=$(date -v+3d +%Y-%m-%d 2>/dev/null || date -d '+3 days' +%Y-%m-%d)
sed "s@| <service> |.*@| 中文服务 | vault://safe | $SOON |@" "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" > "$P/$HX_MAIN_FILE"
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "R09 临近到期不阻断" 0 "$ex"
assert_contains "R09 brief 明确非阻断 warning" "$out" '非阻断'
brief_bound "R09 brief warning" "$out"
assert_file_exists "R09 warning 仍允许归档" "$AUD/archive-count"
for expiry in 2020-01-01 not-a-date; do
    rm -f "$AUD/archive-count"
    sed "s@| <service> |.*@| 中文服务 | vault://safe | $expiry |@" "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" > "$P/$HX_MAIN_FILE"
    ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
    assert_exit "R09 $expiry 阻断 postflight" 1 "$ex"
    brief_bound "R09 brief $expiry" "$out"
    assert_contains "R09 brief 轮换原因" "$out" '凭证轮换'
    assert_contains "R09 brief 不归档" "$out" '未执行归档'
    no_archive=0; [ ! -e "$AUD/archive-count" ] || no_archive=1
    assert_exit "R04 $expiry 未调用 archive" 0 "$no_archive"
done
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$P/$HX_MAIN_FILE"
mv "$AUD/scripts/scan-credentials.sh" "$AUD/scripts/real-scan.sh"
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "R04 scanner 无法执行必须阻断" 1 "$ex"
assert_contains "R04 brief 无法检查" "$out" '无法检查'
brief_bound "R04 brief 无法执行" "$out"
assert_contains "R04 无法执行不归档" "$out" '未执行归档'
# 杀死单个后台 worker，无 rc 文件也不允许归档。
printf '#!/bin/bash\nkill -KILL "$PPID"\n' > "$AUD/scripts/scan-credentials.sh"
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "R04 worker 缺 rc 不假绿" 1 "$ex"
assert_contains "R04 worker 缺 rc 不归档" "$out" '未执行归档'
brief_bound "R04 brief worker 缺 rc" "$out"
printf '#!/bin/bash\ni=0; while [ "$i" -lt 500 ]; do echo "敏感超长诊断 $i" >&2; i=$((i+1)); done\nexit 1\n' > "$AUD/scripts/scan-credentials.sh"
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief --quiet "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
brief_bound "brief 巨量 stderr 且优先于 quiet" "$out"
assert_not_contains "brief 不直接拼 stderr" "$out" '敏感超长诊断'
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --quiet "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "quiet 保留失败契约" 1 "$ex"
assert_contains "quiet 仍是原英文摘要" "$out" 'check(s) failed'
assert_exit "quiet 失败也只一行" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
mv "$AUD/scripts/real-scan.sh" "$AUD/scripts/scan-credentials.sh"
printf '#!/bin/bash\necho 归档中途失败 >&2\nexit 2\n' > "$AUD/scripts/archive-devlog.sh"
ex=0; out=$(bash "$AUD/scripts/handoff-postflight.sh" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "R04 archive 失败不假成功" 1 "$ex"
assert_contains "brief archive 失败诚实说明" "$out" '可能已部分执行'
assert_not_contains "brief archive 已执行不谎报 skipped" "$out" '未执行归档'
brief_bound "brief archive 失败" "$out"
LONG=$(printf '%300s' '' | sed 's/ /长/g')
for arg in "--unknown=$LONG" "$P/$LONG" '--files='; do
    ex=0; out=$(bash "$POSTFLIGHT" "$arg" --brief 2>&1) || ex=$?
    assert_exit "brief 前置输入错误 exit 2" 2 "$ex"
    brief_bound "brief 前置错误" "$out"
    assert_contains "brief 提供具体详查命令" "$out" 'bash scripts/handoff-postflight.sh'
    assert_not_contains "brief 不拼超长输入" "$out" "$LONG"
done
mkdir "$AUD/failbin"
printf '#!/bin/sh\nexit 1\n' > "$AUD/failbin/mktemp"; chmod +x "$AUD/failbin/mktemp"
ex=0; out=$(PATH="$AUD/failbin:$PATH" bash "$POSTFLIGHT" --brief "$P/$HX_MAIN_FILE" 2>&1) || ex=$?
assert_exit "brief 临时目录失败 exit 2" 2 "$ex"
brief_bound "brief 临时目录失败" "$out"

# Auto-managed v2 anchors must not depend on the caller remembering --files.
AUTO=$(mktemp -d); mkdir -p "$AUTO/scripts"; cp -R "$SCRIPTS_DIR/." "$AUTO/scripts/"
cat > "$AUTO/scripts/archive-devlog.sh" <<'STUB'
#!/bin/bash
# Unbound source callers keep the legacy FILE API; explicit roots must be
# forwarded unchanged and agree with the target, never silently discarded.
if [ "$#" -eq 3 ] && [ "$1" = --expect-root ]; then
    [ -n "$2" ] && [ "$2" = "$(dirname "$3")" ] || exit 2
    target="$3"
elif [ "$#" -eq 1 ] && [ -n "$1" ] && [[ "$1" != -* ]]; then
    target="$1"
else
    exit 2
fi
[ -f "$target" ] || exit 2
printf 'archive-called\n' > "$(dirname "$target")/archive-called"
STUB
for mode in omitted explicit; do
    for target in "$HX_MAIN_FILE" "$HX_GOTCHAS_FILE" "$HX_DEC_DIR/INDEX.md"; do
        P="$AUTO/project $mode"; rm -rf "$P"; mkdir -p "$P/$HX_LOGS_DIR" "$P/$HX_DEC_DIR"
        cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$P/$HX_MAIN_FILE"
        cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$P/$HX_GOTCHAS_FILE"
        printf 'clean index\n' > "$P/$HX_DEC_DIR/INDEX.md"
        printf 'clean explicit note\n' > "$P/note.md"
        opts=(); [ "$mode" = explicit ] && opts=(--files=note.md)
        ec=0; out=$(cd / && bash "$AUTO/scripts/handoff-postflight.sh" "${opts[@]}" "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
        assert_exit "auto $mode/$target clean baseline" 0 "$ec"
        assert_file_exists "auto $mode/$target clean reaches archive" "$P/archive-called"
        rm -f "$P/archive-called"
        ec=0; out=$(cd "$P" && bash "$AUTO/scripts/handoff-postflight.sh" --expect-root "$P" "${opts[@]}" "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
        assert_exit "auto $mode/$target explicit root clean baseline" 0 "$ec"
        assert_file_exists "auto $mode/$target explicit root reaches archive" "$P/archive-called"
        rm -f "$P/archive-called"
        printf '\n<标题>\n' >> "$P/$target"
        ec=0; out=$(cd / && bash "$AUTO/scripts/handoff-postflight.sh" "${opts[@]}" "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
        assert_exit "auto $mode omitted $target blocks" 1 "$ec"
        assert_contains "auto $mode diagnostic identifies $target" "$out" "$target"
        assert_contains "auto $mode identifies the actual placeholder" "$out" '<标题>'
        assert_exit "auto $mode/$target failure never archives" 1 "$([ -e "$P/archive-called" ] && echo 0 || echo 1)"
        ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --brief "${opts[@]}" "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
        assert_exit "auto $mode/$target brief preserves failure" 1 "$ec"
        assert_contains "auto $mode/$target brief names xref failure" "$out" '交叉引用'
    done
done
# Inspect the actual argv, not an assertion on source wording. Missing INDEX is
# allowed before the first regen; explicit scope must not grow to all history.
P="$AUTO/args, space"; mkdir -p "$P/$HX_LOGS_DIR" "$P/$HX_DEC_DIR"
cp "$SKILL_TEMPLATES/${HX_MAIN_FILE%.md}.template.md" "$P/$HX_MAIN_FILE"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$P/$HX_GOTCHAS_FILE"
printf 'note\n' > "$P/note.md"
printf -- '---\nschema: 2\ntype: dev-log\ndate: 2026-11-15T00:00\nnumber: 0001\ntitle: history\n---\n\n### 2026-11-15 — history\n\n**触发**: fixture\n\n**改动**: <标题>\n\n**验证**: fixture\n\n**关联**: 无\n' > "$P/$HX_LOGS_DIR/0001-2026-11-15T0000-history.md"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-11-15\nnumber: 0001\ntitle: history\n---\n\n### 2026-11-15 — history\n<标题>\n' > "$P/$HX_DEC_DIR/0001-2026-11-15-history.md"
cat > "$AUTO/scripts/handoff-xref-lint.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$PF_CAPTURE"
STUB
CAP="$AUTO/captured"; ec=0
out=$(PF_CAPTURE="$CAP" bash "$AUTO/scripts/handoff-postflight.sh" --files="$HX_MAIN_FILE,$HX_GOTCHAS_FILE,note.md,note.md" "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "auto absent INDEX and comma/space root remain supported" 0 "$ec"
assert_exit "auto union deduplicates stable anchors and explicit notes" 3 "$(wc -l < "$CAP" | tr -d ' ')"
assert_contains "auto argv contains mandatory GOTCHAS" "$(cat "$CAP")" "$P/$HX_GOTCHAS_FILE"
# Even if an external tr fails, explicit targets must not vanish silently.
mkdir -p "$AUTO/bin"
printf '#!/bin/bash\nexit 77\n' > "$AUTO/bin/tr"; chmod +x "$AUTO/bin/tr"
PF_CAPTURE="$CAP" PATH="$AUTO/bin:$PATH" bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/$HX_MAIN_FILE" >/dev/null 2>&1
assert_contains "CSV split retains explicit targets without an external producer" "$(cat "$CAP")" "$P/note.md"
assert_not_contains "auto does not invent absent INDEX" "$(cat "$CAP")" 'INDEX.md'
printf 'clean index\n' > "$P/$HX_DEC_DIR/INDEX.md"
PF_CAPTURE="$CAP" bash "$AUTO/scripts/handoff-postflight.sh" "$P/$HX_MAIN_FILE" >/dev/null 2>&1
assert_contains "auto INDEX included without --files" "$(cat "$CAP")" "$P/$HX_DEC_DIR/INDEX.md"
assert_exit "auto no-files scope is exactly the three stable anchors" 3 "$(wc -l < "$CAP" | tr -d ' ')"
# Same omission with a real unprocessable INDEX must fail closed, never skip.
cp "$SCRIPTS_DIR/handoff-xref-lint.sh" "$AUTO/scripts/handoff-xref-lint.sh"
rm -f "$P/$HX_DEC_DIR/INDEX.md" "$P/archive-called"; mkdir "$P/$HX_DEC_DIR/INDEX.md"
ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "auto INDEX directory is a failure, not absent" 1 "$ec"
assert_contains "auto invalid INDEX names path" "$out" 'INDEX.md'
assert_exit "auto invalid INDEX blocks archive" 1 "$([ -e "$P/archive-called" ] && echo 0 || echo 1)"
rmdir "$P/$HX_DEC_DIR/INDEX.md"
for link_target in "$P/note.md" "$P/does-not-exist"; do
    ln -s "$link_target" "$P/$HX_DEC_DIR/INDEX.md"
    ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
    assert_exit "auto live/dangling INDEX symlink rejected" 1 "$ec"
    assert_contains "auto symlink error identifies INDEX" "$out" 'INDEX.md'
    assert_exit "auto rejected symlink preserved" 0 "$([ -L "$P/$HX_DEC_DIR/INDEX.md" ] && echo 0 || echo 1)"
    rm -f "$P/$HX_DEC_DIR/INDEX.md"
done
# Explicitly malformed CSV is not rescued by auto anchors.
ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=,, "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "auto anchors cannot turn an empty CSV target set green" 2 "$ec"
# Ad-hoc files preserve the old explicit-only scope; siblings are unrelated.
cp "$P/$HX_MAIN_FILE" "$P/custom.md"; printf '\n<标题>\n' >> "$P/$HX_GOTCHAS_FILE"
ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/custom.md" 2>&1) || ec=$?
assert_not_contains "ad-hoc main does not acquire canonical sibling xrefs" "$out" '<标题>'
# Unreadable/missing managed files must be observable in check 5 itself, not
# merely masked by another checker already failing.
rm -f "$P/$HX_GOTCHAS_FILE"
ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
assert_exit "auto missing mandatory GOTCHAS fails" 1 "$ec"
assert_contains "auto missing GOTCHAS is an xref target, not skipped" "$out" "写入目标不存在,无法检查: $P/$HX_GOTCHAS_FILE"
cp "$SKILL_TEMPLATES/GOTCHAS.template.md" "$P/$HX_GOTCHAS_FILE"
printf 'clean index\n' > "$P/$HX_DEC_DIR/INDEX.md"
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    chmod 000 "$P/$HX_DEC_DIR/INDEX.md"
    ec=0; out=$(bash "$AUTO/scripts/handoff-postflight.sh" --files=note.md "$P/$HX_MAIN_FILE" 2>&1) || ec=$?
    chmod 644 "$P/$HX_DEC_DIR/INDEX.md"
    assert_exit "auto unreadable INDEX fails" 1 "$ec"
    assert_contains "auto unreadable INDEX is not omitted" "$out" "写入目标不可读/非常规文件,无法检查: $P/$HX_DEC_DIR/INDEX.md"
else
    echo "  ➖ auto INDEX permissions require non-root"
fi
# A main-file Gotcha reference must never make xref read a non-regular
# GOTCHAS. The watchdog supplies one FIFO line only to unblock a broken gate;
# the marker proves that waiting for a writer was required (a regression).
rm -f "$P/$HX_GOTCHAS_FILE" "$P/archive-called"
mkfifo "$P/$HX_GOTCHAS_FILE"
printf '\nGotcha #1\n' >> "$P/$HX_MAIN_FILE"
(sleep 5; : > "$AUTO/fifo-waited"; printf '### Gotcha #1 — watchdog\n' > "$P/$HX_GOTCHAS_FILE") &
watchdog=$!
ec=0; bash "$AUTO/scripts/handoff-postflight.sh" "$P/$HX_MAIN_FILE" > "$AUTO/fifo.out" 2>&1 || ec=$?
kill "$watchdog" 2>/dev/null || true; wait "$watchdog" 2>/dev/null || true
assert_exit "auto GOTCHAS FIFO is refused" 1 "$ec"
assert_exit "auto GOTCHAS FIFO does not wait for a writer" 1 "$([ -e "$AUTO/fifo-waited" ] && echo 0 || echo 1)"
assert_contains "auto FIFO refusal reports the problematic target" "$(cat "$AUTO/fifo.out")" "$HX_GOTCHAS_FILE"
assert_exit "auto FIFO refusal never archives" 1 "$([ -e "$P/archive-called" ] && echo 0 || echo 1)"
rm -rf "$AUTO"

summary
