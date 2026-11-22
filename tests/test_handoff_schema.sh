#!/bin/bash
# P2.0 four-piece schema 单一真相源 + load-bearing baseline-ratchet 护栏。
# 真相源 = scripts/lib/handoff-schema.sh 的 4 新名常量 + 3 旧名（HX_LEGACY_*）常量；
# 护栏键 gate 判决（comm 空集）非诊断 echo（Gotcha #25）。
# baseline 机械冻结，later task 收窄至空 ≡ strict-zero。
source "$(dirname "$0")/common.sh"
ROOT="$ROOT_DIR"
SCHEMA="$ROOT/scripts/lib/handoff-schema.sh"

assert_file_exists "schema 单一真相源文件存在" "$SCHEMA"
# 防御深度（与 BASELINE [-r] gate 对称）：assert_file_exists 用 [-f] 不抓不可读；
# schema 不可读会让 `. "$SCHEMA"` 静默 no-op，下游靠常量等值断言间接 fail-close
# （已实测 exit=1），但显式 [-r] gate 让 fail-close 单跳显式（Source 1+2 重审建议）。
[ -r "$SCHEMA" ] || { echo "  ❌ schema unreadable: $SCHEMA" >&2; exit 1; }
. "$SCHEMA"

assert_exit "HX_LOGS_DIR=Handoffx_Logs" 0 "$([ "$HX_LOGS_DIR" = Handoffx_Logs ] && echo 0 || echo 1)"
assert_exit "HX_DEC_DIR=Handoffx_Decisions" 0 "$([ "$HX_DEC_DIR" = Handoffx_Decisions ] && echo 0 || echo 1)"
assert_exit "HX_MAIN_FILE=HANDOFFX.md" 0 "$([ "$HX_MAIN_FILE" = HANDOFFX.md ] && echo 0 || echo 1)"
assert_exit "HX_GOTCHAS_FILE=GOTCHAS.md" 0 "$([ "$HX_GOTCHAS_FILE" = GOTCHAS.md ] && echo 0 || echo 1)"
assert_exit "HX_LEGACY_LOGS_DIR=Handoff_Logs" 0 "$([ "$HX_LEGACY_LOGS_DIR" = Handoff_Logs ] && echo 0 || echo 1)"
assert_exit "HX_LEGACY_DEC_DIR=Handoff_Decisions" 0 "$([ "$HX_LEGACY_DEC_DIR" = Handoff_Decisions ] && echo 0 || echo 1)"
assert_exit "HX_LEGACY_MAIN_FILE=HANDOFF.md" 0 "$([ "$HX_LEGACY_MAIN_FILE" = HANDOFF.md ] && echo 0 || echo 1)"

# EQUALITY 不变式（双向 diff）——subset 形态有 Gotcha #24/#25 fail-open（gen_stray 空时
# comm -13 空→假 GREEN；grep 静默漏文件时 subset 仍成立漏检）。equality 同时抓：
# (a) NEW leak（current 多出 baseline 没有的文件）(b) baseline 漂移/未 ratchet（current
# 少了 baseline 有的）(c) 零处理 fail-open（current 空 + baseline 非空 → diff 非空 → RED）。
# Task2/3 每 ratchet 步同 commit 内机械重生成 baseline + 迁脚本，两侧同步收缩，equality
# 始终稳态成立（语义对齐 test_doc_freshness Test20 第2层双向 comm 范式既有先例）。
BASELINE="$ROOT/tests/fixtures/p2_fourpiece_stray_baseline.txt"
# F1 母题 fix: assert_file_exists in common.sh uses [-f] not [-r]; baseline
# unreadable (chmod 000 / ACL deny) would let `grep -v '^#' "$BASELINE"` emit
# empty stdout → diff vs empty gen_stray (terminal state) → vacuous GREEN.
# Gotcha #24 mother-theme just fixed in adf6ea1 for test_doc_freshness;
# here we add a local [-r] check before the equality test (Source 2 F1 fix).
[ -r "$BASELINE" ] || { echo "  ❌ baseline unreadable: $BASELINE" >&2; exit 1; }
assert_file_exists "机械冻结 baseline fixture 存在" "$BASELINE"
# 九项 = 旧名三件 + 新名三件 + 两种 archive 形态 + GOTCHAS。
# Why 九项：P2.4 起新旧两套名都是"只许住在 schema 库"的字面量——旧名漏守则迁移器
# 之外的脚本会悄悄按旧布局读写；新名漏守则下一次改名又要全仓猎杀。
# archive 形态须单列：HANDOFF\.md 不是 HANDOFF.archive.md 的子串（`.` 后是 a 不是 m），
# 只守主文件名会让归档类泄漏被假 GREEN 放过（Gotcha #25 母题）。GOTCHAS 纳入是纵深防御：
# 即便当前不改名，集中走 $HX_GOTCHAS_FILE 也防日后漂移。
gen_stray() { grep -rlE 'Handoffx_Logs|Handoffx_Decisions|HANDOFFX\.md|HANDOFFX\.archive\.md|Handoff_Logs|Handoff_Decisions|HANDOFF\.md|HANDOFF\.archive\.md|GOTCHAS\.md' \
  "$ROOT/scripts" --include='*.sh' 2>/dev/null \
  | sed "s#^$ROOT/##" | grep -vx 'scripts/lib/handoff-schema.sh' | LC_ALL=C sort; }
drift=$(diff <(grep -v '^#' "$BASELINE" | LC_ALL=C sort) <(gen_stray))
assert_exit "current stray set EQUALS mechanically-frozen baseline (no drift; fail-closed on both directions)" 0 \
  "$([ -z "$drift" ] && echo 0 || echo 1)"
# 迁移器注释曾含旧/新名字面量（:39,:82）：注释也算命中，须改为引用常量名。
assert_exit "tidy-migrate comments hold no four-piece literal (gen_stray misses it)" 0 \
  "$(gen_stray | grep -qx 'scripts/lib/handoffx-tidy-migrate.sh' && echo 1 || echo 0)"

# schema-swap 佐证：不真改名即证改名机制（仅改 schema 值 → 消费端随之翻转）。
# 改成**第三名**（Handoffz_* / HANDOFFZ）而非再改回已有名：第三名与现名、旧名都不同，
# 才能证明消费端跟的是常量而不是碰巧等于某个既有字面量；且只 sed 新名常量行，
# 绝不碰 HX_LEGACY_*（旧名常量是迁移器识别旧布局的依据，不随改名漂移）。
# 子壳须先 unset _HX_SCHEMA_SOURCED：上面 `. "$SCHEMA"` 已在本壳置哨，子壳继承
# 会令换名副本的幂等闸提前 return（哨即设计目标——防消费端重复 source 互踩），
# swap 佐证须真正加载换名副本故先清哨（Why > How，Tacit#4）。
tmp=$(mktemp -d); sed 's/^HX_LOGS_DIR="Handoffx_Logs"/HX_LOGS_DIR="Handoffz_Logs"/' "$SCHEMA" > "$tmp/s.sh"
swapped=$( unset _HX_SCHEMA_SOURCED; . "$tmp/s.sh"; echo "$HX_LOGS_DIR" ); rm -rf "$tmp"
assert_exit "schema-swap honored (rename mechanism proven)" 0 \
  "$([ "$swapped" = Handoffz_Logs ] && echo 0 || echo 1)"

# Task 2 (coupling-b): grammar lib must derive four-piece paths from schema source.
# 同址 swap-follow：复制 schema 改名副本 + grammar lib 副本到同一 tmp 目录，子壳
# 解 source-guard 后 source grammar lib（其内部 `dirname BASH_SOURCE` 取同目录的
# 改名 schema 副本）→ 若 lib 真从 schema 派生，`RL_XREF_LOGS_DIR` 应翻为第三名。
tmp2=$(mktemp -d)
sed 's/^HX_LOGS_DIR="Handoffx_Logs"/HX_LOGS_DIR="Handoffz_Logs"/' "$SCHEMA" > "$tmp2/handoff-schema.sh"
cp "$ROOT/scripts/lib/handoff-xref-grammar.sh" "$tmp2/handoff-xref-grammar.sh"
gl_follow=$( unset _HX_SCHEMA_SOURCED _RL_XREF_GRAMMAR_SOURCED
             . "$tmp2/handoff-xref-grammar.sh"
             echo "$RL_XREF_LOGS_DIR" )
rm -rf "$tmp2"
assert_exit "grammar lib derives RL_XREF_LOGS_DIR from schema (swap-follow)" 0 \
  "$([ "$gl_follow" = Handoffz_Logs ] && echo 0 || echo 1)"

# Codex 3rd-source [high] fix: migrate-to-v2 v1-overflow archive path must
# derive from $HX_MAIN_FILE so a rename catches the renamed *.archive.md
# (else silent data loss — the main-file regex does NOT substring-match the
# archive form, so the load-bearing guard would pass the leak unseen). Mirror
# the swap-follow pattern: swap schema in subshell, source, then assert the
# derivation `${HX_MAIN_FILE%.md}.archive.md` flips alongside (same idiom as
# migrate-to-v2.sh:174 and archive-devlog.sh:93).
arc_follow=$( tmp3=$(mktemp -d)
  sed 's/^HX_MAIN_FILE="HANDOFFX\.md"/HX_MAIN_FILE="HANDOFFZ.md"/' "$SCHEMA" > "$tmp3/handoff-schema.sh"
  ( unset _HX_SCHEMA_SOURCED
    . "$tmp3/handoff-schema.sh"
    echo "${HX_MAIN_FILE%.md}.archive.md" )
  rm -rf "$tmp3" )
assert_exit "archive path derives from HX_MAIN_FILE (Codex 3rd-source [high] fix)" 0 \
  "$([ "$arc_follow" = HANDOFFZ.archive.md ] && echo 0 || echo 1)"

# Legacy-layout classifier (one copy for tidy / validate / postflight / install).
# Why a table here: the gates only exercise v1 / v3 / mixed through their own
# fixtures; the stricter v3 (marker AND both dirs) and the unknown branch would
# otherwise change behaviour with no assertion watching them.
LK=$(mktemp -d)
kind_of() { hx_legacy_layout_kind "$LK/$1"; }
mkdir -p "$LK/none" "$LK/v1" "$LK/v3" "$LK/half" "$LK/bare" "$LK/mixed"
cp "$FIXTURES_DIR/handoff-v1-sample.md" "$LK/v1/$HX_LEGACY_MAIN_FILE"
p21_materialize "$LK/v3" || FAIL=$((FAIL+1))
cp "$LK/v3/$HX_LEGACY_MAIN_FILE" "$LK/half/"; mkdir "$LK/half/$HX_LEGACY_LOGS_DIR"
printf '# Project\n\n## Dev Log\n' > "$LK/bare/$HX_LEGACY_MAIN_FILE"
p21_materialize "$LK/mixed" || FAIL=$((FAIL+1)); mkdir "$LK/mixed/$HX_DEC_DIR"
for k in none v1 v3 mixed; do
  assert_exit "hx_legacy_layout_kind: $k fixture → $k" 0 "$([ "$(kind_of $k)" = "$k" ] && echo 0 || echo 1)"
done
assert_exit "hx_legacy_layout_kind: marker but one legacy dir → unknown" 0 "$([ "$(kind_of half)" = unknown ] && echo 0 || echo 1)"
# F1 (fix wave 1): v1 is decided by elimination — a legacy main without the v2
# marker, no legacy dir, no new piece. Requiring inline dated entries made an
# entry-less v1 file "unknown", which migrate-to-v2 refused while the refusal
# pointed back at migrate-to-v2: a loop with no way out.
assert_exit "hx_legacy_layout_kind: no marker, no dated entries, nothing else → v1 [got: $(kind_of bare)]" 0 "$([ "$(kind_of bare)" = v1 ] && echo 0 || echo 1)"
rc=0; out=$(hx_refuse_if_legacy_layout "$LK/bare" probe 2>&1) || rc=$?
assert_exit "hx_refuse_if_legacy_layout: entry-less v1 → 2" 2 "$rc"
assert_contains "entry-less v1 refusal names migrate-to-v2" "$out" "migrate-to-v2.sh --apply"
assert_not_contains "entry-less v1 refusal does not name schema-upgrade" "$out" "schema-upgrade"
rc=0; out=$(hx_refuse_if_legacy_layout "$LK/v1" probe 2>&1) || rc=$?
assert_contains "v1 refusal names migrate-to-v2" "$out" "migrate-to-v2.sh --apply"
# A marker-less main WITH a legacy dir is neither v1 (the v1 migrator would
# leave that dir behind beside the new layout) nor v3 → unknown, both commands.
mkdir -p "$LK/v1dirs/$HX_LEGACY_LOGS_DIR"; cp "$LK/bare/$HX_LEGACY_MAIN_FILE" "$LK/v1dirs/"
assert_exit "hx_legacy_layout_kind: no marker + a legacy dir → unknown [got: $(kind_of v1dirs)]" 0 "$([ "$(kind_of v1dirs)" = unknown ] && echo 0 || echo 1)"
rc=0; out=$(hx_refuse_if_legacy_layout "$LK/v1dirs" probe 2>&1) || rc=$?
assert_exit "hx_refuse_if_legacy_layout: unknown → 2" 2 "$rc"
assert_contains "unknown refusal names migrate-to-v2" "$out" "migrate-to-v2.sh --apply"
assert_contains "unknown refusal names schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
rc=0; hx_refuse_if_legacy_layout "$LK/none" probe >/dev/null 2>&1 || rc=$?
assert_exit "hx_refuse_if_legacy_layout: none → 0" 0 "$rc"
# Legacy dirs without a legacy main: install --template already refuses this
# tree, so the classifier must not call it "none" and let tidy/validate proceed.
mkdir -p "$LK/dirsonly/$HX_LEGACY_LOGS_DIR" "$LK/dirsonly/$HX_LEGACY_DEC_DIR"
assert_exit "hx_legacy_layout_kind: legacy dirs, no legacy main → unknown" 0 "$([ "$(kind_of dirsonly)" = unknown ] && echo 0 || echo 1)"
rc=0; out=$(hx_refuse_if_legacy_layout "$LK/dirsonly" probe 2>&1) || rc=$?
assert_exit "hx_refuse_if_legacy_layout: dirs-only → 2" 2 "$rc"
assert_contains "dirs-only refusal says the legacy main is missing" "$out" "without $HX_LEGACY_MAIN_FILE"
# The v2 marker already proves a four-piece main: the only sane upgrade is
# schema-upgrade, so the hint must not send the user to the v1 migrator.
rc=0; out=$(hx_refuse_if_legacy_layout "$LK/half" probe 2>&1) || rc=$?
assert_exit "hx_refuse_if_legacy_layout: marker but one legacy dir → 2" 2 "$rc"
assert_contains "marker-carrying unknown refusal names schema-upgrade" "$out" "/handoffx-tidy schema-upgrade"
assert_not_contains "marker-carrying unknown refusal does not name migrate-to-v2" "$out" "migrate-to-v2.sh"
# A4 (fix wave 1): a dangling symlink is a present piece (the migrators' final
# mv would replace it) — the classifier must see it like everyone else does.
mkdir -p "$LK/dangle-only" "$LK/dangle-mixed/$HX_LOGS_DIR" "$LK/dangle-mixed/$HX_DEC_DIR"
ln -s "$LK/nowhere" "$LK/dangle-only/$HX_LEGACY_LOGS_DIR"
: > "$LK/dangle-mixed/$HX_MAIN_FILE"; ln -s "$LK/nowhere" "$LK/dangle-mixed/$HX_LEGACY_MAIN_FILE"
assert_exit "A4: hx_present sees a dangling symlink" 0 "$(hx_present "$LK/dangle-only/$HX_LEGACY_LOGS_DIR" && echo 0 || echo 1)"
assert_exit "A4: hx_present rejects an absent path" 1 "$(hx_present "$LK/dangle-only/absent" && echo 0 || echo 1)"
assert_exit "A4: dangling legacy dir alone → unknown (not none)" 0 "$([ "$(kind_of dangle-only)" = unknown ] && echo 0 || echo 1)"
assert_exit "A4: dangling legacy main beside new layout → mixed" 0 "$([ "$(kind_of dangle-mixed)" = mixed ] && echo 0 || echo 1)"
rm -rf "$LK"

summary
