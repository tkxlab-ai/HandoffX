#!/bin/bash
# P2.0 four-piece schema 单一真相源 + load-bearing baseline-ratchet 护栏。
# 真相源 = scripts/lib/handoff-schema.sh 的 4 常量；护栏键 gate 判决（comm 空集）
# 非诊断 echo（Gotcha #25）。baseline 机械冻结，later task 收窄至空 ≡ strict-zero。
source "$(dirname "$0")/common.sh"
ROOT="$ROOT_DIR"
SCHEMA="$ROOT/scripts/lib/handoff-schema.sh"

assert_file_exists "schema 单一真相源文件存在" "$SCHEMA"
# 防御深度（与 BASELINE [-r] gate 对称）：assert_file_exists 用 [-f] 不抓不可读；
# schema 不可读会让 `. "$SCHEMA"` 静默 no-op，下游靠 4 个常量等值断言间接 fail-close
# （已实测 exit=1），但显式 [-r] gate 让 fail-close 单跳显式（Source 1+2 重审建议）。
[ -r "$SCHEMA" ] || { echo "  ❌ schema unreadable: $SCHEMA" >&2; exit 1; }
. "$SCHEMA"

assert_exit "HX_LOGS_DIR=Handoff_Logs" 0 "$([ "$HX_LOGS_DIR" = Handoff_Logs ] && echo 0 || echo 1)"
assert_exit "HX_DEC_DIR=Handoff_Decisions" 0 "$([ "$HX_DEC_DIR" = Handoff_Decisions ] && echo 0 || echo 1)"
assert_exit "HX_MAIN_FILE=HANDOFF.md" 0 "$([ "$HX_MAIN_FILE" = HANDOFF.md ] && echo 0 || echo 1)"
assert_exit "HX_GOTCHAS_FILE=GOTCHAS.md" 0 "$([ "$HX_GOTCHAS_FILE" = GOTCHAS.md ] && echo 0 || echo 1)"

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
# F2 fix: drop inner quotes on HANDOFF.md so the gate matches the plan manifest
# scope (bare unquoted runtime literals like `${1:-HANDOFF.md}` in catch-up
# scripts). Narrower-than-manifest regex was silently certifying scripts clean
# that still hold runtime four-piece literals (Gotcha #25 母题再发, Source 1 C1).
#
# Codex 3rd-source [high] fix (Gotcha #25 母题 recursion in archive-name class):
# HANDOFF\.md does NOT substring-match HANDOFF.archive.md (after `HANDOFF.`
# comes `a` not `m`), so the previous regex silently certified archive-class
# leaks clean — pure data-loss path under P2.2 rename. Add HANDOFF\.archive\.md
# as a separate alternation. GOTCHAS.md inclusion is defense-in-depth: LEAVE
# per ADR-0005 (no P2.2 rename) but centralizing references via
# $HX_GOTCHAS_FILE is consistent with the schema-source design + prevents drift
# if a future rename ever touches GOTCHAS.
gen_stray() { grep -rlE 'Handoff_Logs|Handoff_Decisions|HANDOFF\.md|HANDOFF\.archive\.md|GOTCHAS\.md' \
  "$ROOT/scripts" --include='*.sh' 2>/dev/null \
  | sed "s#^$ROOT/##" | grep -vx 'scripts/lib/handoff-schema.sh' | LC_ALL=C sort; }
drift=$(diff <(grep -v '^#' "$BASELINE" | LC_ALL=C sort) <(gen_stray))
assert_exit "current stray set EQUALS mechanically-frozen baseline (no drift; fail-closed on both directions)" 0 \
  "$([ -z "$drift" ] && echo 0 || echo 1)"

# schema-swap 佐证：不真改名即证改名机制（仅改 schema 值 → 消费端随之翻转）——P2.2 预演。
# 子壳须先 unset _HX_SCHEMA_SOURCED：上面 `. "$SCHEMA"` 已在本壳置哨，子壳继承
# 会令换名副本的幂等闸提前 return（哨即设计目标——防消费端重复 source 互踩），
# swap 佐证须真正加载换名副本故先清哨（Why > How，Tacit#4）。
tmp=$(mktemp -d); sed 's/Handoff_Logs/Handoffx_Logs/' "$SCHEMA" > "$tmp/s.sh"
swapped=$( unset _HX_SCHEMA_SOURCED; . "$tmp/s.sh"; echo "$HX_LOGS_DIR" ); rm -rf "$tmp"
assert_exit "schema-swap honored (rename mechanism proven)" 0 \
  "$([ "$swapped" = Handoffx_Logs ] && echo 0 || echo 1)"

# Task 2 (coupling-b): grammar lib must derive four-piece paths from schema source.
# 同址 swap-follow：复制 schema 改名副本 + grammar lib 副本到同一 tmp 目录，子壳
# 解 source-guard 后 source grammar lib（其内部 `dirname BASH_SOURCE` 取同目录的
# 改名 schema 副本）→ 若 lib 真从 schema 派生，`RL_XREF_LOGS_DIR` 应翻为 Handoffx_Logs。
# 改本断言前 lib 自定义 RL_XREF_LOGS_DIR=Handoff_Logs（swap 不影响 lib）→ RED。
tmp2=$(mktemp -d)
sed 's/Handoff_Logs/Handoffx_Logs/' "$SCHEMA" > "$tmp2/handoff-schema.sh"
cp "$ROOT/scripts/lib/handoff-xref-grammar.sh" "$tmp2/handoff-xref-grammar.sh"
gl_follow=$( unset _HX_SCHEMA_SOURCED _RL_XREF_GRAMMAR_SOURCED
             . "$tmp2/handoff-xref-grammar.sh"
             echo "$RL_XREF_LOGS_DIR" )
rm -rf "$tmp2"
assert_exit "grammar lib derives RL_XREF_LOGS_DIR from schema (swap-follow)" 0 \
  "$([ "$gl_follow" = Handoffx_Logs ] && echo 0 || echo 1)"

# Codex 3rd-source [high] fix: migrate-to-v2 v1-overflow archive path must
# derive from $HX_MAIN_FILE so a P2.2 rename catches the renamed *.archive.md
# (else silent data loss — the existing ratchet regex `HANDOFF\.md` does NOT
# substring-match `HANDOFF.archive.md`, so the load-bearing guard would pass
# the leak unseen). Mirror the swap-follow pattern: swap schema in subshell,
# source, then assert the derivation `${HX_MAIN_FILE%.md}.archive.md` flips
# alongside (same idiom as migrate-to-v2.sh:174 and archive-devlog.sh:93).
arc_follow=$( tmp3=$(mktemp -d)
  sed 's/HANDOFF\.md/HANDOFFX.md/' "$SCHEMA" > "$tmp3/handoff-schema.sh"
  ( unset _HX_SCHEMA_SOURCED
    . "$tmp3/handoff-schema.sh"
    echo "${HX_MAIN_FILE%.md}.archive.md" )
  rm -rf "$tmp3" )
assert_exit "archive path derives from HX_MAIN_FILE (Codex 3rd-source [high] fix)" 0 \
  "$([ "$arc_follow" = HANDOFFX.archive.md ] && echo 0 || echo 1)"

summary
