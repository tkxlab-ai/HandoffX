#!/bin/bash
# handoff-xref-grammar.sh — THE single source of the doc-integrity cross-reference
# grammar + target-path constants + placeholder sentinels (Spec B①, ADR-0004).
# Sourced, never executed. Pure data + pure resolver fns; no I/O policy, no git (§1).
#
# Four-piece path constants are now centralized in scripts/lib/handoff-schema.sh
# (P2.0 coupling-b: ONE rename locus, Decision 0020 / Gotcha #25). This lib
# sources it and re-exports as RL_XREF_* for back-compat with existing callers.
# Do NOT re-hardcode four-piece paths anywhere — source handoff-schema.sh instead.

[ -n "${_RL_XREF_GRAMMAR_SOURCED:-}" ] && return 0
_RL_XREF_GRAMMAR_SOURCED=1

# Four-piece target dirs/files — derived from the single schema source
# (P2.0 coupling-b: ONE rename locus, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "${BASH_SOURCE[0]}")/handoff-schema.sh"
RL_XREF_LOGS_DIR="$HX_LOGS_DIR"
RL_XREF_DEC_DIR="$HX_DEC_DIR"
RL_XREF_GOTCHAS_FILE="$HX_GOTCHAS_FILE"

# Residual-placeholder sentinels — exact tokens only, never generic <...>.
RL_PLACEHOLDER_SENTINELS='<项目负责人> <NNNN> <slug> <date> <timestamp> <标题> <title>'

# Deliberate-placeholder allowlist (Decision 0021 ③, Boss-decided A). EXACT
# (file-basename|token) pairs that are intentional dogfood placeholders, not
# unfilled fields: $HX_MAIN_FILE Stakeholder Owner keeps `<项目负责人>` to avoid
# leaking a real name (CLAUDE.md no-real-names; Gotcha #18/#20 privacy-at-source).
# Narrowly scoped per-pair — NEVER basename-global / token-global (Gotcha #12 /
# Dev Log 0052 over-broad母题; over-broad regression test enforces this).
RL_PLACEHOLDER_ALLOWLIST="$HX_MAIN_FILE|<项目负责人>"

# Shared: emit <file> content with paired backtick code spans removed. A token
# wholly inside `...` is literal/convention/content display, NOT a cross-ref
# assertion (CONTEXT.md:81) nor an unfilled field (CONTEXT.md:84) — excluded
# from BOTH grammar fns, consistently out-of-grammar (cf. date-style / 5-digit
# / external ADR: the canonical assertion form is BARE `Dev Log NNNN`). sed
# BRE per-line; ` not special; mawk uninvolved; bash 3.2 safe (Gotcha #15).
#
# 不变式 (Decision 0022 ④ / Gotcha #24): 本 lib 内所有 `2>/dev/null` 仅可掩蔽
# 「over-flag 方向」失败 (误报安全 —— 多报一个待人工排除); **绝不可** 让
# 「under-flag 方向」失败 (漏报) 被静默。文件可达性/可读性的 fail-closed 兜底
# 由 gate 层 handoff-xref-lint.sh 负责 (不可读/零处理 → 非零退出, 不报 clean);
# grammar 纯解析器维持 absent=skip。改本 lib 任一 `2>/dev/null` 前, 先确认其
# 失败方向是 over-flag。
_rl_strip_code_spans() {
    sed 's/`[^`]*`//g' "$1" 2>/dev/null
}

# B①: echo one line per UNRESOLVED in-repo cross-ref in <file>. git-orthogonal:
# targets resolved by globbing RL_XREF_* dirs, never git. Bounded grammar only.
# Backtick spans stripped first — a token wholly inside `...` is content display,
# not a cross-ref assertion (CONTEXT.md:81).
rl_xref_unresolved() {
    local root="$1" f="$2" line ref n
    [ -f "$f" ] || return 0
    # Dev Log NNNN — exactly-4-digit. Capture an optional `-digits` tail so a
    # legacy date-style label (`Dev Log 2026-04-18`, pre-v2 Milestones prose)
    # is recognized and dropped as OUT-OF-GRAMMAR (like external ADR refs),
    # not mis-parsed as `Dev Log 2026`. Gotcha #2: no | as field delimiter.
    _rl_strip_code_spans "$f" | grep -oE 'Dev Log [0-9]+(-[0-9]+)*' 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac   # date-style legacy → out of grammar
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_LOGS_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Dev Log $n -> no target"
    done
    # Decision NNNN — same exactly-4-digit + date-style-out-of-grammar rule.
    _rl_strip_code_spans "$f" | grep -oE 'Decision [0-9]+(-[0-9]+)*' 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac   # date-style legacy → out of grammar
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_DEC_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Decision $n -> no target"
    done
    # Gotcha #N
    _rl_strip_code_spans "$f" | grep -oE 'Gotcha #[0-9]+' 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##*#}
        grep -qE "^### Gotcha #${n} " "$root/$RL_XREF_GOTCHAS_FILE" 2>/dev/null \
            || echo "$f: $ref -> no target"
    done
    return 0
}

# B①: echo one line per EXACT residual sentinel occurring BARE (outside any
# backtick span) in <file>. Backtick stripping is single-line/inline only —
# fenced ``` blocks are NOT stripped (safe over-flag direction). Genuine
# unfilled fields are bare (template/instances `Owner: <项目负责人>`).
rl_residual_placeholders() {
    local f="$1" tok base dir al
    [ -f "$f" ] || return 0
    base=${f##*/}
    dir=$(dirname "$f")
    for tok in $RL_PLACEHOLDER_SENTINELS; do
        _rl_strip_code_spans "$f" | grep -qF -- "$tok" || continue
        # Decision 0021 ③: deliberate-placeholder skip, anchored to the
        # CANONICAL four-piece-root $HX_MAIN_FILE only — its own dir has a
        # $HX_LOGS_DIR/ or $HX_DEC_DIR/ sibling. A file merely named
        # $HX_MAIN_FILE (test fixture / vendored copy / sub/$HX_MAIN_FILE) must
        # NOT inherit the exemption (Gotcha #12 / 0052 over-broad母题, path
        # axis). Literal compare — no case-glob on $tok (M-3).
        if [ "$base" = "$HX_MAIN_FILE" ] && \
           { [ -d "$dir/$RL_XREF_LOGS_DIR" ] || [ -d "$dir/$RL_XREF_DEC_DIR" ]; }; then
            for al in $RL_PLACEHOLDER_ALLOWLIST; do
                [ "$al" = "$HX_MAIN_FILE|$tok" ] && continue 2
            done
        fi
        echo "$f: $tok"
    done
    return 0
}
