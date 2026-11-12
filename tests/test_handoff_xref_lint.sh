#!/bin/bash
# test_handoff_xref_lint.sh — P1 B① grammar lib + xref-lint TDD suite.
source "$(dirname "$0")/common.sh"

GRAMMAR="$SCRIPTS_DIR/lib/handoff-xref-grammar.sh"
LINT="$SCRIPTS_DIR/handoff-xref-lint.sh"
WORK="$TMP_DIR/xref-lint-$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

assert_file_exists "grammar lib exists" "$GRAMMAR"
assert_exit "grammar lib sources clean" 0 "$(bash -c '. "'"$GRAMMAR"'"; echo $?')"
assert_contains "grammar defines LOGS_DIR" "$(bash -c '. "'"$GRAMMAR"'"; echo "$RL_XREF_LOGS_DIR"')" "$HX_LOGS_DIR"

# --- Task 2: cross-ref resolver ---
mkdir -p "$WORK/$HX_LOGS_DIR" "$WORK/$HX_DEC_DIR"
echo "x" > "$WORK/$HX_LOGS_DIR/0042-2026-01-01T0000-x.md"
echo "x" > "$WORK/$HX_DEC_DIR/0007-2026-01-01-y.md"
printf '### Gotcha #3 — z\n' > "$WORK/$HX_GOTCHAS_FILE"
good="$WORK/g.md"; printf '见 Dev Log 0042 与 Decision 0007 与 Gotcha #3\n' > "$good"
bad="$WORK/b.md";  printf '见 Dev Log 9999 与 Decision 8888 与 Gotcha #77\n' > "$bad"
unr() { bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "$1" "$2"' _ "$WORK" "$1"; }
assert_exit "resolved refs -> no output" 0 "$([ -z "$(unr "$good")" ] && echo 0 || echo 1)"
assert_contains "Dev Log 9999 unresolved" "$(unr "$bad")" "Dev Log 9999"
assert_contains "Decision 8888 unresolved" "$(unr "$bad")" "Decision 8888"
assert_contains "Gotcha #77 unresolved" "$(unr "$bad")" "Gotcha #77"

# --- Task 3: residual placeholders ---
clean="$WORK/c.md"; printf 'owner set\n<!-- HANDOFF v2 schema -->\n<skill-path>/x\n' > "$clean"
dirty="$WORK/d.md"; printf 'Owner: <项目负责人>\nnum <NNNN>\nok <skill-path>\n' > "$dirty"
ph() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
assert_exit "no sentinels + legit <..> -> empty" 0 "$([ -z "$(ph "$clean")" ] && echo 0 || echo 1)"
assert_contains "detects <项目负责人>" "$(ph "$dirty")" "<项目负责人>"
assert_contains "detects <NNNN>" "$(ph "$dirty")" "<NNNN>"
assert_exit "does NOT flag <skill-path>" 0 "$(ph "$dirty" | grep -q 'skill-path' && echo 1 || echo 0)"

# --- Task 4: xref-lint CLI ---
mkdir -p "$WORK/assets"
tmpl="$WORK/assets/${HX_MAIN_FILE%.md}.template.md"; printf 'Owner: <项目负责人>\n' > "$tmpl"
ok="$WORK/ok.md"; printf 'see Dev Log 0042\n' > "$ok"
ng="$WORK/ng.md"; printf 'see Dev Log 7777 and Owner <项目负责人>\n' > "$ng"
assert_exit "all-clean files -> exit 0" 0 "$(bash "$LINT" "$ok" >/dev/null 2>&1; echo $?)"
assert_exit "template file skipped -> exit 0" 0 "$(bash "$LINT" "$tmpl" >/dev/null 2>&1; echo $?)"
assert_exit "unresolved+placeholder -> exit 1" 1 "$(bash "$LINT" "$ng" >/dev/null 2>&1; echo $?)"
assert_contains "reports the unresolved ref" "$(bash "$LINT" "$ng" 2>&1)" "Dev Log 7777"
assert_contains "reports the placeholder" "$(bash "$LINT" "$ng" 2>&1)" "<项目负责人>"
assert_exit "no args -> usage exit 2" 2 "$(bash "$LINT" >/dev/null 2>&1; echo $?)"

# --- F1: per-file root resolution (multi-dir write-target set) ---
# Subdir file ($HX_LOGS_DIR/0099-x.md) references a valid sibling ordinal 0042.
# Old code roots at the first file's dirname ($HX_LOGS_DIR/), so it looks for
# $HX_LOGS_DIR/$HX_LOGS_DIR/0042-* → not found → wrongly exits 1.
# Fixed code walks up from each file's dir to find the repo root containing
# $HX_LOGS_DIR/, then resolves from there → exits 0.
F1_WORK="$TMP_DIR/f1-root-$$"; rm -rf "$F1_WORK"
mkdir -p "$F1_WORK/$HX_LOGS_DIR" "$F1_WORK/$HX_DEC_DIR"
printf 'see Dev Log 0042\n' > "$F1_WORK/$HX_MAIN_FILE"
printf 'x\n' > "$F1_WORK/$HX_LOGS_DIR/0042-2026-01-01-x.md"
# Subdir file referencing valid sibling ordinal 0042 (cross-ref should resolve)
printf 'see Dev Log 0042\n' > "$F1_WORK/$HX_LOGS_DIR/0099-x.md"
# Subdir file FIRST so old code would root at $HX_LOGS_DIR/ and fail to resolve
f1_ec=$(bash "$LINT" "$F1_WORK/$HX_LOGS_DIR/0099-x.md" "$F1_WORK/$HX_MAIN_FILE" >/dev/null 2>&1; echo $?)
assert_exit "F1: subdir file + root file, valid refs → exit 0" 0 "$f1_ec"
# Single-file-at-root still works
f1_root_ec=$(bash "$LINT" "$F1_WORK/$HX_MAIN_FILE" >/dev/null 2>&1; echo $?)
assert_exit "F1: single root file still exit 0" 0 "$f1_root_ec"
rm -rf "$F1_WORK"

# --- Task 8: B③ Decision INDEX ---
mkdir -p "$WORK/$HX_DEC_DIR"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-01-02\nnumber: 0001\ntitle: First choice\n---\n' > "$WORK/$HX_DEC_DIR/0001-2026-01-02-first.md"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-03-04\nnumber: 0002\ntitle: Second choice\n---\n' > "$WORK/$HX_DEC_DIR/0002-2026-03-04-second.md"
bash -c '. "'"$SCRIPTS_DIR"'/lib/handoff-v2.sh"; regenerate_decision_index "'"$WORK"'"'
assert_file_exists "INDEX.md generated" "$WORK/$HX_DEC_DIR/INDEX.md"
assert_contains "INDEX lists 0001 title" "$(cat "$WORK/$HX_DEC_DIR/INDEX.md")" "First choice"
assert_contains "INDEX lists 0002 date" "$(cat "$WORK/$HX_DEC_DIR/INDEX.md")" "2026-03-04"
bash -c '. "'"$SCRIPTS_DIR"'/lib/handoff-v2.sh"; regenerate_decision_index "'"$WORK"'"'
assert_exit "idempotent (2nd run same content)" 0 "$([ "$(grep -c '^| 0' "$WORK/$HX_DEC_DIR/INDEX.md")" = 2 ] && echo 0 || echo 1)"

# --- F2: 5-digit ordinal must NOT be silently truncated to 4 digits ---
# Grammar is exactly-4-digit (<NNNN>). A 5-digit "Dev Log 12345" is OUT of
# grammar — must be ignored (like external ADR refs), not reported as
# "Dev Log 1234" (the old {4} grep silently truncated to first 4 digits).
F2_WORK="$TMP_DIR/f2-trunc-$$"; rm -rf "$F2_WORK"
mkdir -p "$F2_WORK/$HX_LOGS_DIR" "$F2_WORK/$HX_DEC_DIR"
# 5-digit ordinals: out-of-grammar, no targets exist for 1234 or 8888 either
printf 'see Dev Log 12345 and Decision 88888\n' > "$F2_WORK/oog.md"
f2_out=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$F2_WORK"'" "'"$F2_WORK/oog.md"'"')
assert_not_contains "F2: 5-digit Dev Log not reported as Dev Log 1234" "$f2_out" "Dev Log 1234"
assert_not_contains "F2: 5-digit Decision not reported as Decision 8888" "$f2_out" "Decision 8888"
# 4-digit still resolves correctly (positive check)
printf 'x\n' > "$F2_WORK/$HX_LOGS_DIR/0042-x.md"
printf 'see Dev Log 0042\n' > "$F2_WORK/ok4.md"
f2_ok=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$F2_WORK"'" "'"$F2_WORK/ok4.md"'"')
assert_not_contains "F2: valid 4-digit Dev Log 0042 not flagged" "$f2_ok" "Dev Log 0042"
# 3-digit (out-of-grammar) must not be reported
printf 'see Dev Log 042\n' > "$F2_WORK/short.md"
f2_short=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$F2_WORK"'" "'"$F2_WORK/short.md"'"')
assert_not_contains "F2: 3-digit Dev Log 042 not reported" "$f2_short" "Dev Log 042"
rm -rf "$F2_WORK"

# --- F4: pipe in Decision title must not corrupt INDEX table ---
mkdir -p "$WORK/Hd4/$HX_DEC_DIR"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-09-09\nnumber: 0042\ntitle: Bad | piped | title\n---\n' > "$WORK/Hd4/$HX_DEC_DIR/0042-x.md"
bash -c '. "'"$SCRIPTS_DIR"'/lib/handoff-v2.sh"; regenerate_decision_index "'"$WORK"'/Hd4"'
F4LINE=$(grep '0042' "$WORK/Hd4/$HX_DEC_DIR/INDEX.md")
assert_contains "F4: pipe in title escaped in INDEX" "$F4LINE" 'Bad \| piped \| title'
assert_contains "F4: structural row prefix intact" "$F4LINE" '| 0042 | 2026-09-09 |'

# --- P1.1 ① : Decision/Dev Log date-style label is out-of-grammar ---
# `Decision 2026-04-20` (legacy v2-pre date-style label in Milestones prose)
# must NOT be parsed as `Decision 2026` and reported as a dangling ordinal.
# Symmetric for `Dev Log YYYY-MM-DD`. 4-bare-digit refs still resolve.
S1_WORK="$TMP_DIR/p11-s1-$$"; rm -rf "$S1_WORK"
mkdir -p "$S1_WORK/$HX_LOGS_DIR" "$S1_WORK/$HX_DEC_DIR"
printf 'x\n' > "$S1_WORK/$HX_DEC_DIR/0007-2026-01-01-y.md"
printf 'x\n' > "$S1_WORK/$HX_LOGS_DIR/0042-2026-01-01-x.md"
printf 'see Decision 2026-04-20 and Dev Log 2026-04-18 and Decision 0007 and Dev Log 0042\n' > "$S1_WORK/m.md"
s1=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$S1_WORK"'" "'"$S1_WORK/m.md"'"')
assert_not_contains "①: Decision 2026-04-20 not parsed as Decision 2026" "$s1" "Decision 2026"
assert_not_contains "①: Dev Log 2026-04-18 not parsed as Dev Log 2026" "$s1" "Dev Log 2026"
assert_exit "①: valid 4-digit Decision 0007 / Dev Log 0042 still resolve (clean)" 0 "$([ -z "$s1" ] && echo 0 || echo 1)"
printf 'see Decision 8888\n' > "$S1_WORK/d.md"
s1b=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$S1_WORK"'" "'"$S1_WORK/d.md"'"')
assert_contains "①: real dangling Decision 8888 still flagged" "$s1b" "Decision 8888"
rm -rf "$S1_WORK"

# --- P1.1 ② : token wholly inside a backtick span is content, not a ref ---
# Spec CONTEXT.md:81 (cross-ref "not any token that looks like a reference")
# + :84 (residual "not any angle-bracket text"). Backtick span = literal /
# convention / content display → out-of-grammar for BOTH functions. Genuine
# assertions / unfilled fields are BARE (canonical `Dev Log NNNN`; template
# `Owner: <项目负责人>` bare).
S2_WORK="$TMP_DIR/p11-s2-$$"; rm -rf "$S2_WORK"; mkdir -p "$S2_WORK/$HX_LOGS_DIR" "$S2_WORK/$HX_DEC_DIR"
ph2() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
unr2() { bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "$1" "$2"' _ "$1" "$2"; }
bt="$S2_WORK/bt.md"
printf '> 按 `<NNNN>-<timestamp>-<slug>.md` 命名\nsee `<项目负责人>` token in prose\n' > "$bt"
assert_exit "②a: all-backticked sentinels → empty (not residual)" 0 "$([ -z "$(ph2 "$bt")" ] && echo 0 || echo 1)"
bare="$S2_WORK/bare.md"; printf 'num <NNNN>\nOwner: <slug>\n' > "$bare"
assert_contains "②b: bare <NNNN> still flagged" "$(ph2 "$bare")" "<NNNN>"
assert_contains "②b: bare <slug> still flagged" "$(ph2 "$bare")" "<slug>"
mix="$S2_WORK/mix.md"; printf 'doc `<slug>` but also bare <slug> here\n' > "$mix"
assert_contains "②c: mixed line bare occurrence still flagged" "$(ph2 "$mix")" "<slug>"
cq="$S2_WORK/cq.md"
printf 'bug: `Decision 2026-04-20` 误当 `Decision 2026` / 见 `Dev Log 9999`\n' > "$cq"
s2d=$(unr2 "$S2_WORK" "$cq")
assert_not_contains "②d: backticked content quote Decision 2026 not asserted" "$s2d" "Decision 2026"
assert_not_contains "②d: backticked Dev Log 9999 content quote not asserted" "$s2d" "Dev Log 9999"
cq2="$S2_WORK/cq2.md"; printf 'note: see `Decision 7654` somewhere\n' > "$cq2"
s2d2=$(unr2 "$S2_WORK" "$cq2")
assert_not_contains "②d-iso: backticked no-dash 4-digit Decision 7654 not asserted (isolates strip)" "$s2d2" "Decision 7654"
br="$S2_WORK/br.md"; printf 'see Decision 7777 and Dev Log 6666 (bare, dangling)\n' > "$br"
s2e=$(unr2 "$S2_WORK" "$br")
assert_contains "②e: bare dangling Decision 7777 still flagged" "$s2e" "Decision 7777"
assert_contains "②e: bare dangling Dev Log 6666 still flagged" "$s2e" "Dev Log 6666"
rm -rf "$S2_WORK"

# --- P1.1 ③ : deliberate dogfood placeholder allowlist, narrowly scoped ---
# Boss-decided (Decision 0021 A): the CANONICAL four-piece-root $HX_MAIN_FILE
# Stakeholder `<项目负责人>` is an intentional privacy placeholder. Exemption
# is anchored to the four-piece root (dir has $HX_LOGS_DIR/ or $HX_DEC_DIR/
# sibling) — NOT any file merely named $HX_MAIN_FILE. Token-axis AND path-axis
# over-broad regressions enforce non-blanket (Gotcha #12 / 0052母题).
S3_WORK="$TMP_DIR/p11-s3-$$"; rm -rf "$S3_WORK"; mkdir -p "$S3_WORK/$HX_LOGS_DIR" "$S3_WORK/sub"
ph3() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
# canonical root $HX_MAIN_FILE (has $HX_LOGS_DIR/ sibling) → allowlisted
hf="$S3_WORK/$HX_MAIN_FILE"; printf '| Owner | <项目负责人> | x |\n' > "$hf"
assert_exit "③: bare <项目负责人> in four-piece-root $HX_MAIN_FILE → allowlisted (clean)" 0 "$([ -z "$(ph3 "$hf")" ] && echo 0 || echo 1)"
# token-axis over-broad guard: other token in root $HX_MAIN_FILE still flagged
hf2="$S3_WORK/$HX_MAIN_FILE"; printf 'num <NNNN>\n| Owner | <项目负责人> | x |\n' > "$hf2"
assert_contains "③: non-allowlisted bare <NNNN> in root $HX_MAIN_FILE still flagged" "$(ph3 "$hf2")" "<NNNN>"
# path-axis over-broad guard: $HX_MAIN_FILE WITHOUT four-piece sibling → STILL flagged
nothf="$S3_WORK/sub/$HX_MAIN_FILE"; printf 'Owner: <项目负责人>\n' > "$nothf"
assert_contains "③ path-axis guard: $HX_MAIN_FILE w/o four-piece root STILL flagged" "$(ph3 "$nothf")" "<项目负责人>"
# basename over-broad guard: non-$HX_MAIN_FILE in a real root → STILL flagged
nb="$S3_WORK/0099-x.md"; printf 'Owner: <项目负责人>\n' > "$nb"
assert_contains "③ basename guard: non-$HX_MAIN_FILE in root STILL flagged" "$(ph3 "$nb")" "<项目负责人>"
rm -rf "$S3_WORK"

# --- P1.1 dogfood: B① clean on the REAL repo canonical docs (Gotcha #20) ---
# Synthetic fixtures passed P1 R1/R2 but real repo docs over-matched. This
# locks the real-doc outcome so a future grammar regression is caught here.
# Guard the glob resolution itself: if either newest-file lookup is empty the
# dogfood would silently check only $HX_MAIN_FILE (false-pass) — assert non-empty
# so an empty glob FAILS loudly instead of narrowing coverage.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Test-only overrides: HANDOFFX_TEST_DOGFOOD_ROOT points the dogfood at another
# source (exercises each branch below); HANDOFFX_TEST_XREF_MIGRATOR replaces the
# fallback's migrator command (proves its exit status is checked).
DF_SRC="${HANDOFFX_TEST_DOGFOOD_ROOT:-$REPO_ROOT}"
DF_ROOT="$DF_SRC"
DF_LABEL="real $HX_MAIN_FILE"
DF_OK=1
# Pick the corpus by what the source holds (D2, fix wave 1). Only NO piece of
# either layout — an extracted source package, whose own four-piece is
# export-ignored — falls back to the synthetic v2 fixture migrated to v4 by the
# shipped migrator (smaller scale, same lint call, so the tarball run still
# exercises B① on a migrated main file). A partial or mixed source is ❌: the
# fallback would hide exactly the damaged corpus this dogfood exists to catch.
# A complete layout of either kind keeps the real corpus.
df_leg=$(_hx_present "$DF_SRC" "$HX_LEGACY_MAIN_FILE" "$HX_LEGACY_LOGS_DIR" "$HX_LEGACY_DEC_DIR")
df_new=$(_hx_present "$DF_SRC" "$HX_MAIN_FILE" "$HX_LOGS_DIR" "$HX_DEC_DIR")
# The gotchas file belongs to both layouts (fix wave 2, Codex N2): a complete
# layout needs it, and its presence alone rules the fallback out.
df_got=$(_hx_present "$DF_SRC" "$HX_GOTCHAS_FILE")
if [ -z "$df_leg" ] && [ -z "$df_new" ] && [ -z "$df_got" ]; then
    echo "  ℹ️  dogfood: source holds neither layout → synthetic corpus migrated to v4"
    DF_LABEL="the migrated synthetic corpus"
    DF_ROOT="$TMP_DIR/xref-dogfood-$$"; rm -rf "$DF_ROOT"; mkdir -p "$DF_ROOT"
    p21_materialize "$DF_ROOT" || { FAIL=$((FAIL+1)); DF_OK=0; }
    if [ "$DF_OK" = 1 ]; then
        rc=0; mig_out=$(${HANDOFFX_TEST_XREF_MIGRATOR:-bash "$ROOT_DIR/scripts/tidy-handoff.sh"} schema-upgrade --apply --root "$DF_ROOT" 2>&1) || rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "  ❌ dogfood: migrating the synthetic corpus failed (rc $rc): $(printf '%s' "$mig_out" | tail -3)"
            FAIL=$((FAIL+1)); DF_OK=0
        fi
    fi
elif [ -z "$df_got" ] \
     || { ! { [ "$df_leg" = " $HX_LEGACY_MAIN_FILE $HX_LEGACY_LOGS_DIR $HX_LEGACY_DEC_DIR" ] && [ -z "$df_new" ]; } \
          && ! { [ "$df_new" = " $HX_MAIN_FILE $HX_LOGS_DIR $HX_DEC_DIR" ] && [ -z "$df_leg" ]; }; }; then
    echo "  ❌ dogfood: source holds a partial or mixed layout (legacy [$df_leg ] new [$df_new ] gotchas [$df_got ]) in $DF_SRC — refusing the synthetic fallback"
    FAIL=$((FAIL+1)); DF_OK=0
fi
if [ "$DF_OK" = 1 ]; then
RL_NEWEST_LOG="$(ls -1 "$DF_ROOT"/$HX_LOGS_DIR/[0-9]*.md 2>/dev/null | sort -r | head -1)"
RL_NEWEST_DEC="$(ls -1 "$DF_ROOT"/$HX_DEC_DIR/[0-9]*.md 2>/dev/null | sort -r | head -1)"
assert_exit "dogfood: newest Dev Log resolved (glob non-empty)" 0 "$([ -n "$RL_NEWEST_LOG" ] && [ -f "$RL_NEWEST_LOG" ] && echo 0 || echo 1)"
assert_exit "dogfood: newest Decision resolved (glob non-empty)" 0 "$([ -n "$RL_NEWEST_DEC" ] && [ -f "$RL_NEWEST_DEC" ] && echo 0 || echo 1)"
dogfood_ec=$(bash "$LINT" "$DF_ROOT/$HX_MAIN_FILE" "$RL_NEWEST_LOG" "$RL_NEWEST_DEC" >/dev/null 2>&1; echo $?)
assert_exit "dogfood: B① clean on $DF_LABEL + newest Dev Log + newest Decision" 0 "$dogfood_ec"
fi
[ "$DF_ROOT" = "$DF_SRC" ] || rm -rf "$DF_ROOT"

# --- P1.2 fail-closed: gate 无法检查时绝不报 clean(Decision 0022 / Gotcha #24)---
P12_W="$TMP_DIR/p12-$$"; rm -rf "$P12_W"; mkdir -p "$P12_W/$HX_LOGS_DIR" "$P12_W/assets"
ur="$P12_W/UNREAD.md"; printf 'see Decision 9999 real dangling\n' > "$ur"; chmod 000 "$ur"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ P1.2a unreadable-file controls SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
    chmod 644 "$ur"
else
p12a_ec=$(bash "$LINT" "$ur" >/dev/null 2>&1; echo $?)
p12a_out=$(bash "$LINT" "$ur" 2>&1)
chmod 644 "$ur"
assert_exit "P1.2a: 不可读文件 → 非零退出(非 clean)" 0 "$([ "$p12a_ec" != "0" ] && echo 0 || echo 1)"
assert_not_contains "P1.2a: 不可读绝不打印 write-target set clean" "$p12a_out" "write-target set clean"
fi
p12b_ec=$(bash "$LINT" "$P12_W/NOPE_A.md" "$P12_W/NOPE_B.md" >/dev/null 2>&1; echo $?)
p12b_out=$(bash "$LINT" "$P12_W/NOPE_A.md" "$P12_W/NOPE_B.md" 2>&1)
assert_exit "P1.2b: 全 absent 路径 → 非零(零处理不算 clean)" 0 "$([ "$p12b_ec" != "0" ] && echo 0 || echo 1)"
assert_not_contains "P1.2b: 零处理绝不打印 clean" "$p12b_out" "write-target set clean"
tmpl="$P12_W/assets/${HX_MAIN_FILE%.md}.template.md"; printf 'Owner: <项目负责人>\n' > "$tmpl"
assert_exit "P1.2c: 仅 template arg → 仍合法 exit 0" 0 "$(bash "$LINT" "$tmpl" >/dev/null 2>&1; echo $?)"
mkdir -p "$P12_W/$HX_DEC_DIR"; printf 'x\n' > "$P12_W/$HX_LOGS_DIR/0042-2026-01-01-x.md"
ok="$P12_W/ok.md"; printf 'see Dev Log 0042\n' > "$ok"
assert_exit "P1.2d: 正常可读 clean 文件 → exit 0(无回归)" 0 "$(bash "$LINT" "$ok" >/dev/null 2>&1; echo $?)"
ng="$P12_W/ng.md"; printf 'see Dev Log 7777\n' > "$ng"
assert_exit "P1.2e: 真实 dangling → 仍 exit 1(无回归)" 1 "$(bash "$LINT" "$ng" >/dev/null 2>&1; echo $?)"
rm -rf "$P12_W"

# --- P1.2 混合输入:可读 clean + 不可读 同一 write-target set → fail-closed ---
# load-bearing(独立审 Important:原 postflight-wrapped 断言因 validate/lint
# 噪声非 load-bearing,假绿)。此为「混合」场景(区别 P1.2a 单不可读):
# 一个可读且 clean 的目标不得把另一个不可读目标的 fail-closed 掩盖成 clean。
# 直接对 gate 取退出码隔离断言(postflight 传播由 run_check 恒等保证,属 P1
# 既有 wiring 非 P1.2 scope)。
P12M="$TMP_DIR/p12m-$$"; rm -rf "$P12M"; mkdir -p "$P12M/$HX_LOGS_DIR" "$P12M/$HX_DEC_DIR"
printf 'x\n' > "$P12M/$HX_LOGS_DIR/0001-2026-01-01-x.md"
okm="$P12M/clean.md"; printf 'see Dev Log 0001\n' > "$okm"
urm="$P12M/unread.md"; printf 'see Decision 9999\n' > "$urm"; chmod 000 "$urm"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ P1.2 混合 unreadable control SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
    chmod 644 "$urm"
else
p12m_ec=$(bash "$LINT" "$okm" "$urm" >/dev/null 2>&1; echo $?)
chmod 644 "$urm"
assert_exit "P1.2 混合:可读 clean + 不可读 → 非零(clean 不掩盖 fail-closed)" 0 "$([ "$p12m_ec" != "0" ] && echo 0 || echo 1)"
fi
rm -rf "$P12M"

# --- P1.2 模板跳过 fail-open 修复(Codex stop-time 第3源抓出)---
# template skip 必须按【存在且可读】而非纯路径 pattern:缺失/不可读的
# template-shaped 写入目标 = 不可检 → fail-closed,绝不计 clean。
P12T="$TMP_DIR/p12t-$$"; rm -rf "$P12T"; mkdir -p "$P12T/assets"
# (a) 不存在的 template-shaped 路径 → 必须非零(此前 fail-open 报 clean exit0)
p12t_a=$(bash "$LINT" "$P12T/assets/MISSING.template.md" >/dev/null 2>&1; echo $?)
p12t_ao=$(bash "$LINT" "$P12T/assets/MISSING.template.md" 2>&1)
assert_exit "P1.2t-a: 缺失 template-shaped 路径 → 非零(非 clean)" 0 "$([ "$p12t_a" != "0" ] && echo 0 || echo 1)"
assert_not_contains "P1.2t-a: 缺失模板绝不打印 clean" "$p12t_ao" "write-target set clean"
# (b) 不可读 template-shaped → 必须非零
urt="$P12T/assets/UR.template.md"; printf 'x\n' > "$urt"; chmod 000 "$urt"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ P1.2t-b unreadable template control SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
    chmod 644 "$urt"
else
p12t_b=$(bash "$LINT" "$urt" >/dev/null 2>&1; echo $?)
chmod 644 "$urt"
assert_exit "P1.2t-b: 不可读 template-shaped → 非零" 0 "$([ "$p12t_b" != "0" ] && echo 0 || echo 1)"
fi
# (c) 缺失模板 + 真实 finding 混合 → 非零(缺失模板不被静默)
printf 'see Dev Log 9999\n' > "$P12T/real.md"
p12t_c=$(bash "$LINT" "$P12T/assets/GONE.template.md" "$P12T/real.md" >/dev/null 2>&1; echo $?)
assert_exit "P1.2t-c: 缺失模板+finding 混合 → 非零" 0 "$([ "$p12t_c" != "0" ] && echo 0 || echo 1)"
# (d) 回归:真实存在且可读的 template → 仍合法 exit 0(不得误伤)
printf 'Owner: <项目负责人>\n<NNNN>\n' > "$P12T/assets/OK.template.md"
assert_exit "P1.2t-d: 存在且可读 template → 仍合法 exit 0(无误伤)" 0 "$(bash "$LINT" "$P12T/assets/OK.template.md" >/dev/null 2>&1; echo $?)"
rm -rf "$P12T"

# D2/D3 (fix wave 1): the dogfood picks its corpus by what the source holds.
# Only a source with NO piece of either layout falls back to the synthetic
# corpus; a partial or mixed one is ❌ naming what was found (falling back there
# would hide exactly the damaged corpus this dogfood exists to catch). The
# fallback is labelled as such and the migrator's exit status is checked.
# Run the suite itself against scratch sources (override set → no recursion).
if [ -z "${HANDOFFX_TEST_DOGFOOD_ROOT:-}" ]; then
    DS=$(mktemp -d); mkdir -p "$DS/empty" "$DS/partial/$HX_LEGACY_LOGS_DIR"
    rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DS/partial" bash "$0" 2>&1) || rc=$?
    assert_contains "D2: source with only $HX_LEGACY_LOGS_DIR/ → ❌ naming the partial layout" "$o" "❌ dogfood: source holds a partial or mixed layout"
    assert_contains "D2: the diagnostic names what was found" "$o" "legacy [ $HX_LEGACY_LOGS_DIR ]"
    assert_not_contains "D2: partial source never falls back to the synthetic corpus" "$o" "synthetic corpus"
    assert_exit "D2: partial source → suite exit 1" 1 "$rc"
    # fix wave 2 (Codex N2): the gotchas file belongs to both layouts — a
    # source holding only it is partial (no fallback), and a layout missing it
    # is not complete.
    DG=$(mktemp -d); mkdir -p "$DG/only" "$DG/nogot"; : > "$DG/only/$HX_GOTCHAS_FILE"
    p21_materialize "$DG/nogot" || FAIL=$((FAIL+1)); rm -f "$DG/nogot/$HX_GOTCHAS_FILE"
    for src in only nogot; do
        rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DG/$src" bash "$0" 2>&1) || rc=$?
        assert_contains "N2[$src]: → ❌ partial or mixed layout" "$o" "❌ dogfood: source holds a partial or mixed layout"
        assert_not_contains "N2[$src]: never falls back to the synthetic corpus" "$o" "synthetic corpus"
        assert_exit "N2[$src]: suite exit 1" 1 "$rc"
    done
    rm -rf "$DG"
    rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DS/empty" bash "$0" 2>&1) || rc=$?
    assert_contains "D3: empty source → fallback labelled as the synthetic corpus" "$o" "✅ dogfood: B① clean on the migrated synthetic corpus"
    assert_not_contains "D3: fallback never claims the real main file" "$o" "B① clean on real"
    rc=0; o=$(HANDOFFX_TEST_DOGFOOD_ROOT="$DS/empty" HANDOFFX_TEST_XREF_MIGRATOR=false bash "$0" 2>&1) || rc=$?
    assert_contains "D3: a failing migrator in the fallback → ❌ naming it" "$o" "❌ dogfood: migrating the synthetic corpus failed"
    assert_exit "D3: failing migrator → suite exit 1" 1 "$rc"
    rm -rf "$DS"
fi

summary
