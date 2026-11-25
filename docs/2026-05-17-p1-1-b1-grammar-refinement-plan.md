# P1.1 — B① Grammar Over-Match Refinement + Deliberate-Placeholder Allowlist Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine B①'s cross-reference + residual-placeholder grammar so it stops cry-wolf-ing on this repo's own canonical docs, making the just-shipped P1 `postflight --files=` recommendation actually usable in the dogfood repo.

**Architecture:** Three surgical changes inside the single centralized grammar lib `scripts/lib/handoff-xref-grammar.sh` (+ its byte-equal `skills/handoff/scripts/` copy — coupling b, the lone P2 rename locus): ① `Decision/Dev Log NNNN` grammar treats a digit-run followed by `-digits` (date-style `YYYY-MM-DD`) as out-of-grammar legacy label (not asserted, like external ADR refs); ② `rl_residual_placeholders` excludes sentinel occurrences that are wholly inside a backtick code span on their line (literal/convention/content references — not unfilled instance fields, CONTEXT.md:84); ③ a single explicit `(HANDOFF.md, <项目负责人>)` allowlist pair as defense-in-depth for the deliberate dogfood privacy placeholder (Decision 0021 ③, Boss-decided), scoped to that exact (basename, token) — never basename-global.

**Tech Stack:** Bash 3.2 / mawk-safe (grep -E groups + sed BRE only; no awk `{N}`, Gotcha #15) + markdown. No git in any predicate (§1). TDD via `tests/common.sh`; `tests/run_all.sh` auto-discovers `test_*.sh`.

**Spec truth sources (authoritative — Boss-accepted; do NOT re-brainstorm):**
- `Handoff_Decisions/0021-2026-05-17-p1-1-b1-grammar-refinement-plus-placeholder-allowlist.md` (3-item scope + Boss-decided allowlist policy A + 反悔代价 over-broad guard clause)
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/CONTEXT.md` lines 80–84 ("Cross-reference assertion" = bounded enumerable grammar, "not any token that looks like a reference"; "Residual placeholder" = template sentinel **unfilled in a write-target instance**, "not any angle-bracket text")
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/docs/adr/0004-spec-b1-scope-set-write-target.md`
- Prior P1 plan `docs/2026-05-17-p1-doc-integrity-plan.md` (Post-implementation note: assertion-total drift backlog; ADR-0004 in-repo grammar note)

**Scope lock:** P1.1 only — the three Decision 0021 items inside `handoff-xref-grammar.sh`. **Out of scope:** P0 review-loop (shipped), P1 B②/B③ (shipped), P2 handoffx mega-program, perf track, the absent `ADR-NNNN`→`docs/adr/` grammar (this repo has no in-repo `docs/adr/`; external absolute ADR paths are out-of-grammar by design — noted, NOT added; Karpathy#3).

**Dual-source (CRITICAL — same as P1, opposite of P0):** B① tooling is part of the END-USER `/handoff` flow, NOT maintainer-only. `scripts/lib/handoff-xref-grammar.sh` MUST stay byte-identical to `skills/handoff/scripts/lib/handoff-xref-grammar.sh`. `tests/test_scripts_sync.sh` enforces this — do NOT add to its `DEV_ONLY`. Every grammar-lib edit is applied to BOTH copies in the same task. Test files (`tests/test_*.sh`) are NOT dual-sourced.

**Coupling (b) reminder (NOT implemented here):** `handoff-xref-grammar.sh` is the ONE place the four-piece path constants live so P2's P-A manifest enumerates a single locus. P1.1 edits its grammar functions only — it does NOT touch `RL_XREF_LOGS_DIR/RL_XREF_DEC_DIR/RL_XREF_GOTCHAS_FILE` and does NOT re-hardcode paths anywhere else.

**Dogfood mandate (Gotcha #20 / #22, P1.1-specific):** Synthetic fixtures passed P1 R1/R2 but real repo docs炸. Every GREEN here is verified BOTH by unit fixtures AND by running B① against the **real** `HANDOFF.md` + a real `Handoff_Logs/*` + a real `Handoff_Decisions/*` (Task 7). Final verification uses the self-hosted review-loop (coupling a) + independent opus reviewer + Codex stop-time gate — multiple heterogeneous sources, never single (Gotcha #22).

---

## File Structure

| File | Responsibility | Class |
|------|----------------|-------|
| `scripts/lib/handoff-xref-grammar.sh` + `skills/handoff/scripts/lib/handoff-xref-grammar.sh` | Apply scope ①②③ to `rl_xref_unresolved` + `rl_residual_placeholders`; add documented `RL_PLACEHOLDER_ALLOWLIST` constant. Sole P2 rename locus — paths untouched. | Modify (dual) |
| `tests/test_handoff_xref_lint.sh` | Add RED→GREEN suites for ①②③ + over-broad allowlist regression + real-repo-doc dogfood regression. | Modify |

No other files change. `handoff-xref-lint.sh` / `handoff-postflight.sh` / `handoff-v2.sh` are unaffected (grammar is centralized; consumers source it).

---

## Task 1: RED — scope ① Decision/Dev Log vs date-style disambiguation

**Files:**
- Test: `tests/test_handoff_xref_lint.sh` (append before final `summary`)

- [ ] **Step 1: Write the failing test**

Append immediately before the final `summary` line in `tests/test_handoff_xref_lint.sh`:

```bash
# --- P1.1 ① : Decision/Dev Log date-style label is out-of-grammar ---
# `Decision 2026-04-20` (legacy v2-pre date-style label in Milestones prose)
# must NOT be parsed as `Decision 2026` and reported as a dangling ordinal.
# Symmetric for `Dev Log YYYY-MM-DD`. 4-bare-digit refs still resolve.
S1_WORK="$TMP_DIR/p11-s1-$$"; rm -rf "$S1_WORK"
mkdir -p "$S1_WORK/Handoff_Logs" "$S1_WORK/Handoff_Decisions"
printf 'x\n' > "$S1_WORK/Handoff_Decisions/0007-2026-01-01-y.md"
printf 'x\n' > "$S1_WORK/Handoff_Logs/0042-2026-01-01-x.md"
printf 'see Decision 2026-04-20 and Dev Log 2026-04-18 and Decision 0007 and Dev Log 0042\n' > "$S1_WORK/m.md"
s1=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$S1_WORK"'" "'"$S1_WORK/m.md"'"')
assert_not_contains "①: Decision 2026-04-20 not parsed as Decision 2026" "$s1" "Decision 2026"
assert_not_contains "①: Dev Log 2026-04-18 not parsed as Dev Log 2026" "$s1" "Dev Log 2026"
assert_exit "①: valid 4-digit Decision 0007 / Dev Log 0042 still resolve (clean)" 0 "$([ -z "$s1" ] && echo 0 || echo 1)"
# A genuinely-dangling 4-digit ref is still caught (no false negative)
printf 'see Decision 8888\n' > "$S1_WORK/d.md"
s1b=$(bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "'"$S1_WORK"'" "'"$S1_WORK/d.md"'"')
assert_contains "①: real dangling Decision 8888 still flagged" "$s1b" "Decision 8888"
rm -rf "$S1_WORK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E '①|passed|failed'`
Expected: FAIL — `①: Decision 2026-04-20 not parsed as Decision 2026` fails (current grep `[0-9]+` matches `2026`, length 4, reported as `Decision 2026 -> no target`).

- [ ] **Step 3: (no impl in this task — RED only)**

Commit the RED test alone so the failing state is recorded.

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.1): RED — Decision/Dev Log date-style must be out-of-grammar (scope ①)"
```

---

## Task 2: GREEN — implement scope ① in grammar lib (dual-source)

**Files:**
- Modify: `scripts/lib/handoff-xref-grammar.sh` (`rl_xref_unresolved`, lines 25–49)
- Modify: `skills/handoff/scripts/lib/handoff-xref-grammar.sh` (identical edit)

- [ ] **Step 1: Edit `scripts/lib/handoff-xref-grammar.sh`**

Replace the `Dev Log` and `Decision` blocks inside `rl_xref_unresolved` (currently `grep -oE 'Dev Log [0-9]+'` … and `grep -oE 'Decision [0-9]+'` …) with the date-style-aware grammar. New `rl_xref_unresolved` body for those two blocks:

```bash
    # Dev Log NNNN — exactly-4-digit. Capture an optional `-digits` tail so a
    # legacy date-style label (`Dev Log 2026-04-18`, pre-v2 Milestones prose)
    # is recognized and dropped as OUT-OF-GRAMMAR (like external ADR refs),
    # not mis-parsed as `Dev Log 2026`. Gotcha #2: no | as field delimiter.
    grep -oE 'Dev Log [0-9]+(-[0-9]+)*' "$f" 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac   # date-style legacy → out of grammar
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_LOGS_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Dev Log $n -> no target"
    done
    # Decision NNNN — same exactly-4-digit + date-style-out-of-grammar rule.
    grep -oE 'Decision [0-9]+(-[0-9]+)*' "$f" 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac   # date-style legacy → out of grammar
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_DEC_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Decision $n -> no target"
    done
```

Note: `grep -oE` is POSIX leftmost-longest, so `Decision 2026-04-20` matches the full `Decision 2026-04-20` (then `${ref##* }` → `2026-04-20`, `case *-*` skips). `Decision 0007` → `0007`, length 4, resolves. `Decision 12345` → no `-`, length 5, skipped (F2 preserved). grep -E groups `(-[0-9]+)*` are supported on BSD/GNU/mawk-host grep (Gotcha #15: grep -E intervals/groups are universal; only awk `{N}` is not — no awk here).

- [ ] **Step 2: Apply the byte-identical edit to the skill copy**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo "DUAL-SOURCE OK"
```

Expected: no diff output, then `DUAL-SOURCE OK`.

- [ ] **Step 3: Run the Task 1 + F2 tests to verify GREEN**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | tail -3`
Expected: `… passed, 0 failed` (Task 1 ① assertions pass; F2 5-digit/3-digit assertions still pass).

- [ ] **Step 4: Run full regression + shellcheck**

Run: `bash tests/run_all.sh 2>&1 | tail -3 && shellcheck -S error scripts/lib/handoff-xref-grammar.sh && echo SHELLCHECK_OK`
Expected: `All suites passed ✅` then `SHELLCHECK_OK`.

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "fix(p1.1): Decision/Dev Log date-style label out-of-grammar (scope ①, dual-source)"
```

---

## Task 3: RED — scope ② backtick-span exclusion (BOTH cross-ref + residual)

**Refinement note (dogfood-driven, plan-vs-actual delta — 0017 Outcome convention):** Real-repo dogfood after scope ① showed `rl_xref_unresolved` ALSO over-matches a backtick-wrapped *content quote* (`HANDOFF.md` Current State prose `` `Decision 2026` `` explaining the bug itself — no date tail, so scope ① alone does not catch it). CONTEXT.md:81 ("Cross-reference assertion … Not 'any token that looks like a reference'") and :84 ("Residual placeholder … not any angle-bracket text") share one principle: a token displayed literally inside a backtick span is content, not an assertion/field. Decision 0021 ② explicitly deferred the precise criterion to this spec phase and names *"正文里作为内容引用的 token"*. Resolution: a single shared `_rl_strip_code_spans` helper, applied to BOTH grammar functions — consistent out-of-grammar treatment (like date-style / 5-digit / external-ADR: not asserted, not flagged). Canonical assertion form remains bare `Dev Log NNNN` / `Decision NNNN`.

**Files:**
- Test: `tests/test_handoff_xref_lint.sh` (append before final `summary`)

- [ ] **Step 1: Write the failing test**

Append before the final `summary` line:

```bash
# --- P1.1 ② : token wholly inside a backtick span is content, not a ref ---
# Spec CONTEXT.md:81 (cross-ref "not any token that looks like a reference")
# + :84 (residual "not any angle-bracket text"). Backtick span = literal /
# convention / content display → out-of-grammar for BOTH functions. Genuine
# assertions / unfilled fields are BARE (canonical `Dev Log NNNN`; template
# `Owner: <项目负责人>` bare).
S2_WORK="$TMP_DIR/p11-s2-$$"; rm -rf "$S2_WORK"; mkdir -p "$S2_WORK/Handoff_Logs" "$S2_WORK/Handoff_Decisions"
ph2() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
unr2() { bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "$1" "$2"' _ "$1" "$2"; }
# (a) residual: all-backticked sentinels (convention prose + content ref) → NOT residual
bt="$S2_WORK/bt.md"
printf '> 按 `<NNNN>-<timestamp>-<slug>.md` 命名\nsee `<项目负责人>` token in prose\n' > "$bt"
assert_exit "②a: all-backticked sentinels → empty (not residual)" 0 "$([ -z "$(ph2 "$bt")" ] && echo 0 || echo 1)"
# (b) residual: bare sentinel (real unfilled instance field) → STILL flagged
bare="$S2_WORK/bare.md"; printf 'num <NNNN>\nOwner: <slug>\n' > "$bare"
assert_contains "②b: bare <NNNN> still flagged" "$(ph2 "$bare")" "<NNNN>"
assert_contains "②b: bare <slug> still flagged" "$(ph2 "$bare")" "<slug>"
# (c) residual: mixed line — same token bare AND backticked → bare wins (flagged)
mix="$S2_WORK/mix.md"; printf 'doc `<slug>` but also bare <slug> here\n' > "$mix"
assert_contains "②c: mixed line bare occurrence still flagged" "$(ph2 "$mix")" "<slug>"
# (d) cross-ref: backtick-wrapped content quote `Decision 2026` (no date tail,
#     scope ① cannot catch) must NOT be asserted as a dangling ordinal
cq="$S2_WORK/cq.md"
printf 'bug: `Decision 2026-04-20` 误当 `Decision 2026` / 见 `Dev Log 9999`\n' > "$cq"
s2d=$(unr2 "$S2_WORK" "$cq")
assert_not_contains "②d: backticked content quote Decision 2026 not asserted" "$s2d" "Decision 2026"
assert_not_contains "②d: backticked Dev Log 9999 content quote not asserted" "$s2d" "Dev Log 9999"
# (e) cross-ref: BARE dangling ref still caught (no false negative)
br="$S2_WORK/br.md"; printf 'see Decision 7777 and Dev Log 6666 (bare, dangling)\n' > "$br"
s2e=$(unr2 "$S2_WORK" "$br")
assert_contains "②e: bare dangling Decision 7777 still flagged" "$s2e" "Decision 7777"
assert_contains "②e: bare dangling Dev Log 6666 still flagged" "$s2e" "Dev Log 6666"
rm -rf "$S2_WORK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E '②|passed|failed'`
Expected: FAIL — `②a` (residual `grep -qF` flags regardless of backticks) AND `②d` (cross-ref greps raw file, asserts backticked `Decision 2026`) both fail.

- [ ] **Step 3: (RED only — no impl)**

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.1): RED — backtick span is content for BOTH cross-ref + residual (scope ②)"
```

---

## Task 4: GREEN — shared `_rl_strip_code_spans` applied to both fns (dual-source)

**Files:**
- Modify: `scripts/lib/handoff-xref-grammar.sh` (add helper; route both functions through it)
- Modify: `skills/handoff/scripts/lib/handoff-xref-grammar.sh` (identical edit)

- [ ] **Step 1: Add the shared helper**

Immediately AFTER the `RL_PLACEHOLDER_SENTINELS='...'` line, add:

```bash
# Shared: emit <file> content with paired backtick code spans removed. A token
# wholly inside `...` is literal/convention/content display, NOT a cross-ref
# assertion (CONTEXT.md:81) nor an unfilled field (CONTEXT.md:84) — excluded
# from BOTH grammar fns, consistently out-of-grammar (cf. date-style / 5-digit
# / external ADR: the canonical assertion form is BARE `Dev Log NNNN`). sed
# BRE per-line; ` not special; mawk uninvolved; bash 3.2 safe (Gotcha #15).
_rl_strip_code_spans() {
    sed 's/`[^`]*`//g' "$1" 2>/dev/null
}
```

- [ ] **Step 2: Route `rl_xref_unresolved` through the helper**

In `rl_xref_unresolved`, replace each of the THREE `grep -oE '<pat>' "$f"` with `_rl_strip_code_spans "$f" | grep -oE '<pat>'`. The full updated function:

```bash
rl_xref_unresolved() {
    local root="$1" f="$2" line ref n
    [ -f "$f" ] || return 0
    # Dev Log NNNN — exactly-4-digit. Optional `-digits` tail ⇒ legacy
    # date-style label (out-of-grammar, like external ADR). Backtick spans
    # stripped first (content quote, not assertion). Gotcha #2: no | delim.
    _rl_strip_code_spans "$f" | grep -oE 'Dev Log [0-9]+(-[0-9]+)*' | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_LOGS_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Dev Log $n -> no target"
    done
    # Decision NNNN — same rule.
    _rl_strip_code_spans "$f" | grep -oE 'Decision [0-9]+(-[0-9]+)*' | sort -u | while read -r ref; do
        n=${ref##* }
        case "$n" in *-*) continue ;; esac
        [ ${#n} -eq 4 ] || continue
        ls "$root/$RL_XREF_DEC_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: Decision $n -> no target"
    done
    # Gotcha #N — same backtick-stripped, bounded grammar.
    _rl_strip_code_spans "$f" | grep -oE 'Gotcha #[0-9]+' | sort -u | while read -r ref; do
        n=${ref##*#}
        grep -qE "^### Gotcha #${n} " "$root/$RL_XREF_GOTCHAS_FILE" 2>/dev/null \
            || echo "$f: $ref -> no target"
    done
    return 0
}
```

- [ ] **Step 3: Route `rl_residual_placeholders` through the helper**

Replace the entire `rl_residual_placeholders` function with:

```bash
# B①: echo one line per EXACT residual sentinel occurring BARE (outside any
# backtick span) in <file>. Backticked = literal/content (CONTEXT.md:84).
# Genuine unfilled fields are bare (template/instances `Owner: <项目负责人>`).
rl_residual_placeholders() {
    local f="$1" tok
    [ -f "$f" ] || return 0
    for tok in $RL_PLACEHOLDER_SENTINELS; do
        _rl_strip_code_spans "$f" | grep -qF -- "$tok" || continue
        echo "$f: $tok"
    done
    return 0
}
```

- [ ] **Step 4: Apply byte-identical edit to skill copy**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo "DUAL-SOURCE OK"
```

Expected: no diff, then `DUAL-SOURCE OK`.

- [ ] **Step 5: Run Task 3 + existing P1 assertions**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | tail -3`
Expected: `… passed, 0 failed`. Pre-existing P1 assertions (bare `<项目负责人>`/`<NNNN>` flagged; `<skill-path>` not flagged; F1/F2/F4) still pass — those fixtures are bare.

- [ ] **Step 6: Full regression + shellcheck**

Run: `bash tests/run_all.sh 2>&1 | tail -3 && shellcheck -S error scripts/lib/handoff-xref-grammar.sh && echo SHELLCHECK_OK`
Expected: `All suites passed ✅` then `SHELLCHECK_OK`.

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "fix(p1.1): shared _rl_strip_code_spans — backtick = content for both grammar fns (scope ②, dual-source)"
```

---

## Task 5: RED — scope ③ narrow `<项目负责人>` allowlist + over-broad regression

**Files:**
- Test: `tests/test_handoff_xref_lint.sh` (append before final `summary`)

- [ ] **Step 1: Write the failing test**

Append before the final `summary` line. This test asserts BOTH the allowlist AND that it is NOT over-broad (Decision 0021 反悔代价 / Gotcha #12 / 0052母题):

```bash
# --- P1.1 ③ : deliberate dogfood placeholder allowlist, narrowly scoped ---
# Boss-decided (Decision 0021 A): HANDOFF.md Stakeholder `<项目负责人>` is an
# intentional privacy placeholder (CLAUDE.md no-real-names), allowlisted as
# defense-in-depth so it stays exempt even if its backticks are reformatted
# to bare. Scoped to EXACT (basename HANDOFF.md, token <项目负责人>) — the
# over-broad regression below proves it does NOT blanket-exempt the token.
S3_WORK="$TMP_DIR/p11-s3-$$"; rm -rf "$S3_WORK"; mkdir -p "$S3_WORK"
ph3() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
# BARE <项目负责人> in a file named HANDOFF.md → allowlisted (not flagged)
hf="$S3_WORK/HANDOFF.md"; printf '| Owner | <项目负责人> | x |\n' > "$hf"
assert_exit "③: bare <项目负责人> in HANDOFF.md → allowlisted (clean)" 0 "$([ -z "$(ph3 "$hf")" ] && echo 0 || echo 1)"
# OVER-BROAD REGRESSION: bare <项目负责人> in a NON-HANDOFF.md instance
# (e.g. a Dev Log written with the field genuinely unfilled) MUST still flag.
nothf="$S3_WORK/0099-x.md"; printf 'Owner: <项目负责人>\n' > "$nothf"
assert_contains "③ over-broad guard: bare <项目负责人> in non-HANDOFF.md STILL flagged" "$(ph3 "$nothf")" "<项目负责人>"
# Allowlist is token-specific too: bare <NNNN> in HANDOFF.md still flags
hf2="$S3_WORK/HANDOFF.md"; printf 'num <NNNN>\n| Owner | <项目负责人> | x |\n' > "$hf2"
assert_contains "③: non-allowlisted bare <NNNN> in HANDOFF.md still flagged" "$(ph3 "$hf2")" "<NNNN>"
rm -rf "$S3_WORK"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E '③|passed|failed'`
Expected: FAIL — `③: bare <项目负责人> in HANDOFF.md → allowlisted (clean)` fails (no allowlist yet; bare token still flagged). The over-broad guard + `<NNNN>` assertions will already pass (they assert flagging) — that is intentional: they must STAY green after Step 3.

- [ ] **Step 3: (RED only — no impl)**

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.1): RED — narrow <项目负责人> allowlist + over-broad guard (scope ③)"
```

---

## Task 6: GREEN — implement scope ③ narrow allowlist (dual-source)

**Files:**
- Modify: `scripts/lib/handoff-xref-grammar.sh` (add `RL_PLACEHOLDER_ALLOWLIST` constant + allowlist branch in `rl_residual_placeholders`)
- Modify: `skills/handoff/scripts/lib/handoff-xref-grammar.sh` (identical edit)

- [ ] **Step 1: Add the documented allowlist constant**

Immediately AFTER the `RL_PLACEHOLDER_SENTINELS='...'` line (and BEFORE the `_rl_strip_code_spans` helper added in Task 4 — group it with the other `RL_` data constants), add:

```bash
# Deliberate-placeholder allowlist (Decision 0021 ③, Boss-decided A). EXACT
# (file-basename|token) pairs that are intentional dogfood placeholders, not
# unfilled fields: HANDOFF.md Stakeholder Owner keeps `<项目负责人>` to avoid
# leaking a real name (CLAUDE.md no-real-names; Gotcha #18/#20 privacy-at-source).
# Narrowly scoped per-pair — NEVER basename-global / token-global (Gotcha #12 /
# Dev Log 0052 over-broad母题; over-broad regression test enforces this).
RL_PLACEHOLDER_ALLOWLIST='HANDOFF.md|<项目负责人>'
```

- [ ] **Step 2: Add the allowlist branch in `rl_residual_placeholders`**

Replace the `rl_residual_placeholders` function (the helper-routed form from Task 4 Step 3) with the allowlist-aware version. `base` is the file basename; the exact `(basename|token)` pair is skipped:

```bash
rl_residual_placeholders() {
    local f="$1" tok base
    [ -f "$f" ] || return 0
    base=${f##*/}
    for tok in $RL_PLACEHOLDER_SENTINELS; do
        _rl_strip_code_spans "$f" | grep -qF -- "$tok" || continue
        # Decision 0021 ③: exact (basename|token) deliberate-placeholder skip.
        case " $RL_PLACEHOLDER_ALLOWLIST " in
            *" $base|$tok "*) continue ;;
        esac
        echo "$f: $tok"
    done
    return 0
}
```

(The B① doc-comment block directly above the function from Task 4 Step 3 stays — keep it.)

- [ ] **Step 3: Apply byte-identical edit to skill copy**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo "DUAL-SOURCE OK"
```

Expected: no diff, then `DUAL-SOURCE OK`.

- [ ] **Step 4: Run Task 5 + over-broad guard GREEN**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | tail -3`
Expected: `… passed, 0 failed`. Critically: `③ over-broad guard: bare <项目负责人> in non-HANDOFF.md STILL flagged` and `③: non-allowlisted bare <NNNN> in HANDOFF.md still flagged` MUST be green (proves the allowlist is the exact pair, not blanket).

- [ ] **Step 5: Full regression + shellcheck**

Run: `bash tests/run_all.sh 2>&1 | tail -3 && shellcheck -S error scripts/lib/handoff-xref-grammar.sh && echo SHELLCHECK_OK`
Expected: `All suites passed ✅` then `SHELLCHECK_OK`.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "fix(p1.1): narrow (HANDOFF.md|<项目负责人>) deliberate-placeholder allowlist (scope ③, dual-source)"
```

---

## Task 7: Dogfood — B① clean on REAL repo docs + regression assertion

**Files:**
- Test: `tests/test_handoff_xref_lint.sh` (append before final `summary`)

This is the Gotcha #20 mandate: synthetic fixtures passed P1 R1/R2 but the real repo炸. Verify against the actual repo docs and lock it with a regression assertion.

- [ ] **Step 1: Manually reproduce the now-fixed real-repo run**

Run:
```bash
bash scripts/handoff-xref-lint.sh HANDOFF.md \
  "$(ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -1)" \
  "$(ls -1 Handoff_Decisions/[0-9]*.md | sort -r | head -1)" ; echo "EXIT=$?"
```
Expected: `✅ xref-lint: write-target set clean` then `EXIT=0`. (Before P1.1 this emitted `Decision 2026 -> no target` + `<项目负责人>`/`<NNNN>`/`<slug>`/`<timestamp>` and `EXIT=1`.)

- [ ] **Step 2: Write the real-repo regression assertion**

Append before the final `summary` line. Uses the actual repo root (the test runs from the repo), real `HANDOFF.md` + newest real Dev Log + newest real Decision:

```bash
# --- P1.1 dogfood: B① clean on the REAL repo canonical docs (Gotcha #20) ---
# Synthetic fixtures passed P1 R1/R2 but real repo docs over-matched. This
# locks the real-doc outcome so a future grammar regression is caught here.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RL_NEWEST_LOG="$(ls -1 "$REPO_ROOT"/Handoff_Logs/[0-9]*.md 2>/dev/null | sort -r | head -1)"
RL_NEWEST_DEC="$(ls -1 "$REPO_ROOT"/Handoff_Decisions/[0-9]*.md 2>/dev/null | sort -r | head -1)"
dogfood_ec=$(bash "$LINT" "$REPO_ROOT/HANDOFF.md" "$RL_NEWEST_LOG" "$RL_NEWEST_DEC" >/dev/null 2>&1; echo $?)
assert_exit "dogfood: B① clean on real HANDOFF.md + newest Dev Log + newest Decision" 0 "$dogfood_ec"
```

- [ ] **Step 3: Run test to verify GREEN**

Run: `bash tests/test_handoff_xref_lint.sh 2>&1 | grep -E 'dogfood|passed|failed'`
Expected: `dogfood: B① clean on real …` passes; `… passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add tests/test_handoff_xref_lint.sh
git commit -m "test(p1.1): dogfood regression — B① clean on real repo canonical docs (Gotcha #20)"
```

---

## Task 8: Assertion-total + per-suite count resync (deterministic recompute)

**Files:**
- Modify: `HANDOFF.md` (lines 15, 37, 274, 306), `README.md` (lines 101, 197), `docs/TEST-SCENARIOS.md` (xref-lint per-suite count), `tests/test_doc_freshness.sh` if it hard-codes a total

Recurring backlog (P0 N1 / P1 Task9): the assertion total is NOT structurally guarded; every count-sync drifts. **Recompute deterministically — never guess a magic number** (P1 lesson: per-task delta is the contract, running total is recomputed from actual run).

- [ ] **Step 1: Deterministically recompute the real totals**

Run:
```bash
XREF_N=$(bash tests/test_handoff_xref_lint.sh 2>&1 | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+')
TOTAL_SUITES=$(ls -1 tests/test_*.sh | wc -l | tr -d ' ')
TOTAL_ASSERT=$(bash tests/run_all.sh 2>&1 | grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s}')
echo "xref-lint=$XREF_N  suites=$TOTAL_SUITES  assertions=$TOTAL_ASSERT"
```
Record the three numbers. (Pre-P1.1 baseline: xref-lint 29, suites 28, assertions 724. P1.1 adds ①+②+③+dogfood assertions; the recomputed numbers are authoritative — do NOT assume a delta.)

- [ ] **Step 2: Grep every count locus and update to the recomputed values**

Run to enumerate every stale literal:
```bash
grep -rn '724\|28 套件\|28 suites\|724 assertions\|724+ assertions\|xref-lint 29/0' HANDOFF.md README.md docs/TEST-SCENARIOS.md
```
Update each hit to the recomputed `$TOTAL_SUITES` / `$TOTAL_ASSERT` / `$XREF_N` (HANDOFF.md:15, :37 `xref-lint NN/0` + the `+ NN 个其他` arithmetic, :274 `（NN suites）`, :306 `合计`; README.md:101, :197; TEST-SCENARIOS xref-lint per-suite line). Suite count stays 28 unless `ls tests/test_*.sh | wc -l` changed (it does not — P1.1 adds no new test file).

- [ ] **Step 3: Verify doc-freshness is green (it guards counts)**

Run: `bash tests/test_doc_freshness.sh 2>&1 | tail -3 && bash tests/run_all.sh 2>&1 | tail -3`
Expected: both green; `All suites passed ✅`.

- [ ] **Step 4: Commit**

```bash
git add HANDOFF.md README.md docs/TEST-SCENARIOS.md
git commit -m "docs(p1.1): resync assertion total + xref-lint per-suite count (deterministic recompute)"
```

---

## Task 9: Multi-source independent review + Dev Log + Decision 0021 outcome backfill

Gotcha #22: a grammar/gate change must be verified by **multiple heterogeneous independent sources**, never single. Authoring/review separation (§4) — the controller does NOT self-approve.

- [ ] **Step 1: Self-hosted review-loop (coupling a — uses the shipped P0 tool)**

Run the shipped `scripts/review-loop.sh` to drive an independent opus reviewer over the P1.1 diff (the three grammar edits + tests). Each round must cite `content_hash` + `file:line`; strict 3-consecutive-PASS on the SAME content_hash to converge (or honest CAPPED — never fake convergence). Record rounds in the gitignored `.review-loop/` scratch; the durable trace is the Dev Log outcome line.

- [ ] **Step 2: Codex stop-time gate (second heterogeneous source)**

Invoke `/codex:adversarial-review` (or the stop-time gate) on the P1.1 change. Codex's blind spots differ from opus's (Gotcha #22: opus missed P0 Spec-B; Codex caught it). Every Codex finding → TDD RED→GREEN→controller adversarial repro, do NOT trust "looks fixed".

- [ ] **Step 3: Controller adversarial repro of every finding**

For each finding from Step 1/2, reproduce the failure mechanically before and after the fix (the session母题: claim ≠ fact). Re-run `bash tests/run_all.sh` + the real-repo dogfood command (Task 7 Step 1) after every fix.

- [ ] **Step 4: Write the Dev Log (event stream — What)**

`acquire_next_number Handoff_Logs/`, write `Handoff_Logs/<NNNN>-<TZ-timestamp>-p1-1-b1-grammar-refinement-shipped.md` (schema-2 frontmatter). Record: scope ①②③ implemented; backtick-exclusion is the spec-aligned core (CONTEXT.md:84); allowlist narrow + over-broad guard (anti-0052); real-repo dogfood green; multi-source review outcome; any review findings + their TDD closure; plan-vs-actual delta if any (0017 Outcome-backfill convention — do NOT rewrite the executed plan).

- [ ] **Step 5: Backfill Decision 0021 Outcome**

Append an `**Outcome（回填）**` paragraph to `Handoff_Decisions/0021-*.md`: which of ①②③ shipped as specified vs adjusted, the chosen ② mechanism (backtick-span exclusion — note this is spec-alignment to CONTEXT.md:84, the candidate "explicit allowlist line/section" was NOT needed for ② because all real over-matches are backtick-wrapped), and confirmation the ③ allowlist is the exact (HANDOFF.md|<项目负责人>) pair with an enforced over-broad regression. (0013/0017 Outcome-backfill precedent.)

- [ ] **Step 6: Overwrite HANDOFF.md Current State + regenerate pointers/index**

Overwrite `## 🎯 Current State` (date via `date "+%Y-%m-%d %H:%M"`, invariant push phrasing — no commit counts/SHAs, Gotcha #10). Run `regenerate_pointers HANDOFF.md` + `regenerate_decision_index` (from `lib/handoff-v2.sh`). Run `bash scripts/handoff-postflight.sh HANDOFF.md` (positional = HANDOFF.md file, NEVER a dir — Gotcha #23) → expect `✅ all checks passed`.

- [ ] **Step 7: Final full regression + dual-source proof + commit**

```bash
bash tests/run_all.sh 2>&1 | tail -3
diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo DUAL-OK
git add -A && git commit -m "docs(handoff): Dev Log <NNNN> — P1.1 B① grammar refinement shipped + multi-source review + Decision 0021 outcome"
```

Push to private Git host is a SEPARATE step requiring explicit Boss authorization (§4 — push authorization does not carry forward). Do NOT push in this task.

---

## Self-Review

**1. Spec coverage (Decision 0021 three items + grill CONTEXT.md):**
- ① Decision/Dev Log vs date → Task 1–2 ✓ (symmetric Dev Log + Decision; F2 5/3-digit preserved; real dangling still caught).
- ② residual-placeholder scope tightening → Task 3–4 ✓ (backtick-span exclusion = spec-alignment to CONTEXT.md:84 "not any angle-bracket text"/"filled instances"; bare still flagged; mixed-line bare wins).
- ③ `<项目负责人>` allowlist → Task 5–6 ✓ (Boss-decided A; exact (basename|token) pair; over-broad regression enforces non-blanket per Decision 0021 反悔代价 / Gotcha #12 / 0052母题).
- Dogfood real-repo (Gotcha #20, P1.1-specific mandate) → Task 7 ✓.
- Dual-source byte-equal (NOT DEV_ONLY) → every grammar task Step "skill copy" + Task 9 Step 7 diff ✓.
- Coupling (b) path constants untouched → stated in header + only grammar fns edited ✓.
- Multi-source independent review (Gotcha #22) + §4 separation → Task 9 ✓.
- Assertion-total drift (recurring backlog) → Task 8 deterministic recompute ✓.

**2. Placeholder scan:** No TBD/TODO; every code step shows full function bodies / exact commands / expected output. ✓

**3. Type/name consistency:** `rl_xref_unresolved`, `rl_residual_placeholders`, `RL_PLACEHOLDER_SENTINELS`, `RL_PLACEHOLDER_ALLOWLIST`, `RL_XREF_LOGS_DIR/DEC_DIR`, `$GRAMMAR`/`$LINT`/`$TMP_DIR` (existing test harness vars) used identically across tasks. ✓

**4. Out-of-scope discipline:** absent `ADR-NNNN`→`docs/adr/` grammar noted but NOT added (Karpathy#3); paths constants untouched (coupling b); no consumer scripts edited. ✓

---

## Execution Handoff

**Plan complete and saved to `docs/2026-05-17-p1-1-b1-grammar-refinement-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task + controller mechanical verification between tasks + multi-source independent review (Task 9). This matches the proven P0/P1 discipline (Gotcha #20/#22) and the Decision 0021 mandate.

**2. Inline Execution** — execute tasks in this session via executing-plans, batch with checkpoints.

**Which approach?**

---
