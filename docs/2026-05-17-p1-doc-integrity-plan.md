# P1 doc-integrity (B①②③) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add git-orthogonal documentation-integrity guards to the `/handoff` flow — B① reference-integrity + residual-placeholder lint over the explicit write-target set, B② ordinal Current-State staleness WARN, B③ a generated standalone Decision INDEX — so dangling cross-refs / unfilled placeholders / stale Current State are caught mechanically before P2's four-piece rename makes them catastrophic.

**Architecture:** A single sourced grammar library (`scripts/lib/handoff-xref-grammar.sh`) centralizes the bounded cross-reference grammar + target-path constants — the ONE place P2 must rename (coupling b). `scripts/handoff-xref-lint.sh <file...>` (B①) consumes that grammar and lints exactly the files passed (write-target set, ADR-0004 — never git, never mtime). `handoff-postflight.sh` gains an additive `--files` arg that, when present, runs B① on that set (no `--files` ⇒ B① no-op: limited-domain per Decision 0019 ①). B② is a WARN-only ordinal sub-check inside the existing `test_doc_freshness.sh` (ADR-0002, K4-immune). B③ is a `regenerate_decision_index` helper in the already-shared `lib/handoff-v2.sh`, emitting `Handoff_Decisions/INDEX.md` (recall never auto-reads it ⇒ zero hot-path token cost, Decision 0019 ③).

**Tech Stack:** Bash 3.2 / mawk-safe + markdown. No git in any predicate (§1). TDD via `tests/common.sh`; `tests/run_all.sh` auto-discovers `test_*.sh`. Cross-platform sha256 already in `lib/handoff-v2.sh`.

**Spec truth sources (authoritative — Boss-accepted; do NOT re-brainstorm):**
- `Handoff_Decisions/0019-*.md` §"doc-integrity 轴" (① adopt 限域 / ② adapt 剥 git / ③ adapt 独立 INDEX) + `Handoff_Decisions/0020-*.md` lines 34-40
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/docs/adr/0002-current-state-staleness-ordinal-warn.md` (B②)
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/docs/adr/0004-spec-b1-scope-set-write-target.md` (B①)
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/CONTEXT.md` (Scope set / write-target set, Cross-reference assertion, Residual placeholder, Current-State staleness, K4 chicken-egg)

**Scope lock:** P1 only — B① reference-integrity + residual-placeholder lint (PRIORITY), B② ordinal Current-State staleness WARN, B③ standalone Decision INDEX. **Out of scope:** P0 review-loop (shipped), P2 handoffx mega-program, perf track, D markdown-as-IPC.

**Dual-source (CRITICAL — opposite of P0):** B①/B② tooling is part of the END-USER `/handoff` flow (postflight + test_doc_freshness), NOT maintainer-only. Every new runtime script/lib MUST be byte-identical in BOTH `scripts/` AND `skills/handoff/scripts/` (like `handoff-postflight.sh` / `handoff-lint.sh` / `lib/handoff-v2.sh`). `tests/test_scripts_sync.sh` enforces this — do NOT add these to its `DEV_ONLY` allowlist. Test files (`tests/test_*.sh`) are NOT dual-sourced.

**Coupling (b) — most critical, P2 design constraint (NOT implemented here):** B①'s cross-reference grammar + target-path constants (`Dev Log NNNN`→`Handoff_Logs/`, `Decision NNNN`→`Handoff_Decisions/`, `Gotcha #N`→`GOTCHAS.md`) are themselves a future P2 rename locus (P2 renames the four-piece). They MUST live in exactly ONE file — `scripts/lib/handoff-xref-grammar.sh` (+ its dual-source copy) — so P2's P-A manifest can enumerate a single locus. If the grammar scatters, P2 rename silently breaks B① the instant four-piece is renamed (grill ADR-0004 consequence + 0020 open#2 (b)). **This plan's Task 1 establishes that single point; every later task sources it, never re-hardcodes the grammar.** The plan's closing note re-states this for the P2 planner.

**Coupling (d) — serialization note:** Task 5 adds `--files` to `handoff-postflight.sh`; the parallel perf-track also edits that script (limited-domain `scan-credentials`). Whoever touches `handoff-postflight.sh` second must rebase, not concurrently edit — coordinate serially (0020 open#2 (d)).

**ADR-0004 in-repo grammar note:** ADR-0004 lists `ADR-NNNN`→`docs/adr/` but THIS repo has no `docs/adr/` (ADR refs point to absolute `grillme` paths = external, not in-repo-resolvable). B① asserts only in-repo-resolvable refs: `Dev Log NNNN`, `Decision NNNN`, `Gotcha #N` (+ literal `Handoff_Logs/NNNN`, `Handoff_Decisions/NNNN`). External absolute paths are out of grammar by design (not asserted, not failed).

---

## File Structure

| File | Responsibility | Class |
|------|----------------|-------|
| `scripts/lib/handoff-xref-grammar.sh` + `skills/handoff/scripts/lib/handoff-xref-grammar.sh` | THE single centralized cross-ref grammar + target-path table + resolver + placeholder sentinel set. Sourced, never executed. The lone P2 rename locus (coupling b). | Create (dual) |
| `scripts/handoff-xref-lint.sh` + `skills/handoff/scripts/handoff-xref-lint.sh` | B① CLI: given an explicit file list, flag unresolved cross-refs + residual placeholders. Sources the grammar lib. | Create (dual) |
| `scripts/lib/handoff-v2.sh` + bundle copy | Add `regenerate_decision_index` (B③), mirroring `regenerate_pointers`. | Modify (dual) |
| `scripts/handoff-postflight.sh` + bundle copy | Add additive `--files a,b,c`; when present, run B① xref-lint on exactly those. No `--files` ⇒ unchanged behavior. | Modify (dual) |
| `tests/test_handoff_xref_lint.sh` | TDD for grammar lib + xref-lint CLI. | Create |
| `tests/test_doc_freshness.sh` | Add B② ordinal Current-State staleness WARN sub-check (advisory, never FAIL). | Modify |
| `tests/test_handoff_postflight.sh` | Assert `--files` wiring (B① invoked on the set; absent ⇒ no-op). | Modify |
| `Handoff_Decisions/INDEX.md` | Generated B③ artifact (regenerated, not hand-edited). recall never auto-reads it. | Generated |
| `skills/handoff/references/handoff-write.md` + `SKILL.md` | Doc: write flow passes its write-target set to `postflight --files`. | Modify |

**Cross-ref grammar (centralized; the P2 locus):** in-repo bounded enumeration only:
- `Dev Log <NNNN>` or `Handoff_Logs/<NNNN>` → a file matching `Handoff_Logs/<NNNN>-*.md`
- `Decision <NNNN>` or `Handoff_Decisions/<NNNN>` → a file matching `Handoff_Decisions/<NNNN>-*.md`
- `Gotcha #<N>` → a line `^### Gotcha #<N> ` present in `GOTCHAS.md`

**Residual-placeholder sentinels (centralized):** exact tokens only — `<项目负责人>`, `<NNNN>`, `<slug>`, `<date>`, `<timestamp>`, `<标题>`, `<title>`. NEVER match generic `<...>` (HANDOFF.md legitimately has `<!-- HANDOFF v2 schema -->`, `<skill-path>`, `<project-root>`, `<target>`). Scan skips any path matching `assets/*.template.md`.

---

## Task 1: Centralized grammar lib scaffold (the single P2 rename locus)

**Files:**
- Create: `scripts/lib/handoff-xref-grammar.sh`
- Create: `skills/handoff/scripts/lib/handoff-xref-grammar.sh` (byte-identical)
- Create: `tests/test_handoff_xref_lint.sh` (harness skeleton)

- [ ] **Step 1: Create `scripts/lib/handoff-xref-grammar.sh`**

```bash
#!/bin/bash
# handoff-xref-grammar.sh — THE single source of the doc-integrity cross-reference
# grammar + target-path constants + placeholder sentinels (Spec B①, ADR-0004).
# Sourced, never executed. Pure data + pure resolver fns; no I/O policy, no git (§1).
#
# ⚠ P2 RENAME LOCUS (coupling b, 0020 open#2): the four-piece path constants below
# (Handoff_Logs / Handoff_Decisions / GOTCHAS.md) are exactly what the future
# handoffx mega-program renames. This file is the ONE place they are defined so
# P2's P-A allowlist can enumerate a single locus. Do NOT re-hardcode these paths
# anywhere else — every consumer sources this lib.

[ -n "${_RL_XREF_GRAMMAR_SOURCED:-}" ] && return 0
_RL_XREF_GRAMMAR_SOURCED=1

# Four-piece target dirs/files (relative to repo root). P2 rename locus.
RL_XREF_LOGS_DIR="Handoff_Logs"
RL_XREF_DEC_DIR="Handoff_Decisions"
RL_XREF_GOTCHAS_FILE="GOTCHAS.md"

# Residual-placeholder sentinels — exact tokens only, never generic <...>.
RL_PLACEHOLDER_SENTINELS='<项目负责人> <NNNN> <slug> <date> <timestamp> <标题> <title>'
```

- [ ] **Step 2: Mirror to the bundle (dual-source)**

Run: `cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh`

- [ ] **Step 3: Create `tests/test_handoff_xref_lint.sh` skeleton**

```bash
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
assert_contains "grammar defines LOGS_DIR" "$(bash -c '. "'"$GRAMMAR"'"; echo "$RL_XREF_LOGS_DIR"')" "Handoff_Logs"

summary
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_handoff_xref_lint.sh`
Expected: `─── 3 passed, 0 failed`

- [ ] **Step 5: Verify dual-source byte-equality**

Run: `diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo IDENTICAL`
Expected: `IDENTICAL`

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "feat(doc-integrity): P1 scaffold — centralized xref grammar lib (single P2 rename locus, coupling b)"
```

---

## Task 2: B① cross-reference resolver (grammar lib)

**Files:**
- Modify: `scripts/lib/handoff-xref-grammar.sh` (+ bundle copy) — add `rl_xref_unresolved`
- Test: `tests/test_handoff_xref_lint.sh`

`rl_xref_unresolved <repo_root> <file>` echoes one line per UNRESOLVED in-repo cross-ref found in `<file>` (format: `<file>: <ref> -> no target`). Exit 0 always (it reports, the CLI decides failure). git-orthogonal: resolves by globbing the target dirs, never git.

- [ ] **Step 1: Write the failing test** (append before `summary`):

```bash
# --- Task 2: cross-ref resolver ---
mkdir -p "$WORK/Handoff_Logs" "$WORK/Handoff_Decisions"
echo "x" > "$WORK/Handoff_Logs/0042-2026-01-01T0000-x.md"
echo "x" > "$WORK/Handoff_Decisions/0007-2026-01-01-y.md"
printf '### Gotcha #3 — z\n' > "$WORK/GOTCHAS.md"
good="$WORK/g.md"; printf '见 Dev Log 0042 与 Decision 0007 与 Gotcha #3\n' > "$good"
bad="$WORK/b.md";  printf '见 Dev Log 9999 与 Decision 8888 与 Gotcha #77\n' > "$bad"
unr() { bash -c '. "'"$GRAMMAR"'"; rl_xref_unresolved "$1" "$2"' _ "$WORK" "$1"; }
assert_exit "resolved refs -> no output" 0 "$([ -z "$(unr "$good")" ] && echo 0 || echo 1)"
assert_contains "Dev Log 9999 unresolved" "$(unr "$bad")" "Dev Log 9999"
assert_contains "Decision 8888 unresolved" "$(unr "$bad")" "Decision 8888"
assert_contains "Gotcha #77 unresolved" "$(unr "$bad")" "Gotcha #77"
```

- [ ] **Step 2: Run — expect FAIL** (`rl_xref_unresolved: command not found`).

Run: `bash tests/test_handoff_xref_lint.sh`

- [ ] **Step 3: Implement — append to BOTH copies of `handoff-xref-grammar.sh`:**

```bash
# B①: echo one line per UNRESOLVED in-repo cross-ref in <file>. git-orthogonal:
# targets resolved by globbing RL_XREF_* dirs, never git. Bounded grammar only.
rl_xref_unresolved() {
    local root="$1" f="$2" line ref n
    [ -f "$f" ] || return 0
    # Dev Log NNNN
    grep -oE 'Dev Log [0-9]{4}' "$f" 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        ls "$root/$RL_XREF_LOGS_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: $ref -> no target"
    done
    # Decision NNNN
    grep -oE 'Decision [0-9]{4}' "$f" 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##* }
        ls "$root/$RL_XREF_DEC_DIR/${n}-"*.md >/dev/null 2>&1 || echo "$f: $ref -> no target"
    done
    # Gotcha #N
    grep -oE 'Gotcha #[0-9]+' "$f" 2>/dev/null | sort -u | while read -r ref; do
        n=${ref##*#}
        grep -qE "^### Gotcha #${n} " "$root/$RL_XREF_GOTCHAS_FILE" 2>/dev/null \
            || echo "$f: $ref -> no target"
    done
    return 0
}
```

- [ ] **Step 4: Mirror to bundle + run — expect PASS**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
bash tests/test_handoff_xref_lint.sh
```
Expected: `─── 7 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "feat(doc-integrity): B① cross-ref resolver — bounded grammar, git-orthogonal"
```

---

## Task 3: B① residual-placeholder detector (grammar lib)

**Files:**
- Modify: `scripts/lib/handoff-xref-grammar.sh` (+ bundle) — add `rl_residual_placeholders`
- Test: `tests/test_handoff_xref_lint.sh`

`rl_residual_placeholders <file>` echoes one line per residual sentinel found (`<file>: <token>`). Matches ONLY the exact `RL_PLACEHOLDER_SENTINELS`, never generic `<...>`. Caller is responsible for skipping `assets/*.template.md` (Task 4) — this fn is pure.

- [ ] **Step 1: Write the failing test** (append before `summary`):

```bash
# --- Task 3: residual placeholders ---
clean="$WORK/c.md"; printf 'owner set\n<!-- HANDOFF v2 schema -->\n<skill-path>/x\n' > "$clean"
dirty="$WORK/d.md"; printf 'Owner: <项目负责人>\nnum <NNNN>\nok <skill-path>\n' > "$dirty"
ph() { bash -c '. "'"$GRAMMAR"'"; rl_residual_placeholders "$1"' _ "$1"; }
assert_exit "no sentinels + legit <..> -> empty" 0 "$([ -z "$(ph "$clean")" ] && echo 0 || echo 1)"
assert_contains "detects <项目负责人>" "$(ph "$dirty")" "<项目负责人>"
assert_contains "detects <NNNN>" "$(ph "$dirty")" "<NNNN>"
assert_exit "does NOT flag <skill-path>" 0 "$(ph "$dirty" | grep -q 'skill-path' && echo 1 || echo 0)"
```

- [ ] **Step 2: Run — expect FAIL** (`rl_residual_placeholders: command not found`).

- [ ] **Step 3: Implement — append to BOTH copies:**

```bash
# B①: echo one line per EXACT residual sentinel in <file>. Never generic <...>.
rl_residual_placeholders() {
    local f="$1" tok
    [ -f "$f" ] || return 0
    for tok in $RL_PLACEHOLDER_SENTINELS; do
        if grep -qF -- "$tok" "$f" 2>/dev/null; then
            echo "$f: $tok"
        fi
    done
    return 0
}
```

- [ ] **Step 4: Mirror + run — expect PASS**

```bash
cp scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh
bash tests/test_handoff_xref_lint.sh
```
Expected: `─── 11 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh tests/test_handoff_xref_lint.sh
git commit -m "feat(doc-integrity): B① residual-placeholder detector — exact sentinels only"
```

---

## Task 4: B① `handoff-xref-lint.sh` CLI (write-target set)

**Files:**
- Create: `scripts/handoff-xref-lint.sh` + `skills/handoff/scripts/handoff-xref-lint.sh`
- Test: `tests/test_handoff_xref_lint.sh`

CLI: `handoff-xref-lint.sh <file...>` — operates on EXACTLY the files passed (the write-target set; never git, never mtime — ADR-0004). For each file: skip if it matches `assets/*.template.md`; collect unresolved refs + residual placeholders. Exit 0 if all clean, 1 if any finding (prints them). Repo root = `dirname` of the first non-template file (refs resolve relative to repo root; all write-target files share the repo root).

- [ ] **Step 1: Write the failing test** (append before `summary`):

```bash
# --- Task 4: xref-lint CLI ---
mkdir -p "$WORK/assets"
tmpl="$WORK/assets/HANDOFF.template.md"; printf 'Owner: <项目负责人>\n' > "$tmpl"
ok="$WORK/ok.md"; printf 'see Dev Log 0042\n' > "$ok"
ng="$WORK/ng.md"; printf 'see Dev Log 7777 and Owner <项目负责人>\n' > "$ng"
assert_exit "all-clean files -> exit 0" 0 "$(bash "$LINT" "$ok" >/dev/null 2>&1; echo $?)"
assert_exit "template file skipped -> exit 0" 0 "$(bash "$LINT" "$tmpl" >/dev/null 2>&1; echo $?)"
assert_exit "unresolved+placeholder -> exit 1" 1 "$(bash "$LINT" "$ng" >/dev/null 2>&1; echo $?)"
assert_contains "reports the unresolved ref" "$(bash "$LINT" "$ng" 2>&1)" "Dev Log 7777"
assert_contains "reports the placeholder" "$(bash "$LINT" "$ng" 2>&1)" "<项目负责人>"
assert_exit "no args -> usage exit 2" 2 "$(bash "$LINT" >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: Run — expect FAIL** (no such file `handoff-xref-lint.sh`).

- [ ] **Step 3: Implement `scripts/handoff-xref-lint.sh`:**

```bash
#!/bin/bash
# handoff-xref-lint.sh — B① reference-integrity + residual-placeholder lint.
# Operates on the EXPLICIT write-target set passed as args (ADR-0004):
# never git, never mtime. assets/*.template.md is skipped (placeholders are
# legitimate there). Exit 0 clean / 1 finding(s) / 2 usage.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/handoff-xref-grammar.sh
. "$SCRIPT_DIR/lib/handoff-xref-grammar.sh"

[ $# -ge 1 ] || { echo "usage: handoff-xref-lint.sh <file...>" >&2; exit 2; }

findings=0
root=""
for f in "$@"; do
    case "$f" in
        *assets/*.template.md) continue ;;
    esac
    [ -f "$f" ] || continue
    [ -z "$root" ] && root="$(cd "$(dirname "$f")" && pwd)"
    out="$(rl_xref_unresolved "$root" "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
    out="$(rl_residual_placeholders "$f")"
    [ -n "$out" ] && { echo "$out"; findings=1; }
done

if [ "$findings" = "0" ]; then
    echo "✅ xref-lint: write-target set clean"
    exit 0
fi
echo "❌ xref-lint: unresolved cross-refs or residual placeholders above" >&2
exit 1
```

- [ ] **Step 4: Mirror + chmod + run — expect PASS**

```bash
cp scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh
chmod +x scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh
bash tests/test_handoff_xref_lint.sh
```
Expected: `─── 17 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh tests/test_handoff_xref_lint.sh
git commit -m "feat(doc-integrity): B① handoff-xref-lint CLI — write-target set, skips templates"
```

---

## Task 5: `handoff-postflight.sh --files` (B① wiring, additive)

**Files:**
- Modify: `scripts/handoff-postflight.sh` + `skills/handoff/scripts/handoff-postflight.sh`
- Test: `tests/test_handoff_postflight.sh`

Add an additive `--files a,b,c` option. When present, after the existing 5 checks, run `handoff-xref-lint.sh` on exactly those comma-split files (limited-domain: Decision 0019 ① "仅扫本次改动文件"). When ABSENT, behaviour is byte-for-byte unchanged (B① no-op — postflight standalone never tree-scans). A xref-lint failure makes postflight exit 1 (joins the worst-of aggregate).

- [ ] **Step 1: Write the failing test** (append before `summary` in `tests/test_handoff_postflight.sh`; reuse its existing fixture HANDOFF.md setup — inspect the file first for its scratch pattern):

```bash
# --- Task 5: postflight --files runs B① xref-lint ---
PF_WORK="$TMP_DIR/pf-files-$$"; rm -rf "$PF_WORK"; mkdir -p "$PF_WORK/Handoff_Logs"
cp "$TEMPLATES_DIR/HANDOFF.template.md" "$PF_WORK/HANDOFF.md" 2>/dev/null || printf '<!-- HANDOFF v2 schema -->\n# H\n## 🎯 Current State\n' > "$PF_WORK/HANDOFF.md"
ngf="$PF_WORK/ng.md"; printf 'dangling Dev Log 7777\n' > "$ngf"
assert_exit "postflight --files with dangling ref -> exit 1" 1 "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --files "$ngf" "$PF_WORK/HANDOFF.md" >/dev/null 2>&1; echo $?)"
okf="$PF_WORK/ok.md"; printf 'no refs here\n' > "$okf"
# (no --files ⇒ B① not run; behaviour unchanged — smoke that flag parse is additive)
assert_contains "postflight --help still documents usage" "$(bash "$SCRIPTS_DIR/handoff-postflight.sh" --help 2>&1)" "Usage"
```

- [ ] **Step 2: Run — expect FAIL** (`--files` is an unknown flag → current postflight exits 2).

- [ ] **Step 3: Implement** — in BOTH `handoff-postflight.sh` copies: add `--files) FILES_CSV="$2"; shift ;;` style parsing to the existing arg loop (mirror its current `case "$arg"`; note its loop is `for arg in "$@"` — convert the `--files` value capture safely: accept `--files=a,b` OR `--files a,b`; keep bash 3.2). After the 5 `run_check` calls and BEFORE the summary, add:

```bash
if [ -n "${FILES_CSV:-}" ]; then
    # B① limited-domain: lint exactly the write-target set (ADR-0004). Comma-split.
    _IFS_SAVE=$IFS; IFS=','; set -- $FILES_CSV; IFS=$_IFS_SAVE
    run_check 6 "xref-lint(B①)" bash "$SCRIPT_DIR/handoff-xref-lint.sh" "$@"
fi
```

Adjust the summary text/threshold from a hardcoded "5" to the actual `fail_count`/total (the script already tracks `fail_count`/`fail_list`; ensure the final line reports "all checks passed" generically, not literally "all 5", when `--files` added a 6th). Keep no-`--files` output identical to today.

- [ ] **Step 4: Mirror + run both suites — expect PASS**

```bash
cp scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh
bash tests/test_handoff_postflight.sh && bash tests/test_handoff_xref_lint.sh
```
Expected: both green; `test_handoff_postflight.sh` shows the 2 new assertions pass and all prior ones still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/handoff-postflight.sh skills/handoff/scripts/handoff-postflight.sh tests/test_handoff_postflight.sh
git commit -m "feat(doc-integrity): postflight --files runs B① xref-lint on write-target set (additive)"
```

---

## Task 6: Write-flow doc — pass the write-target set to postflight

**Files:**
- Modify: `skills/handoff/references/handoff-write.md`
- Modify: `skills/handoff/SKILL.md` (the postflight step in 执行流程)

B① only runs when the `/handoff` write flow passes the files it just wrote. This is a DOC contract change (the AI executing `/handoff` reads these). No code.

- [ ] **Step 1: Read both files' postflight step**

Run: `grep -n 'handoff-postflight' skills/handoff/references/handoff-write.md skills/handoff/SKILL.md`

- [ ] **Step 2: Edit `references/handoff-write.md`** — at the postflight step, add: after writing the Dev Log + Current State, invoke postflight with the write-target set:

```
bash <skill-path>/scripts/handoff-postflight.sh --files HANDOFF.md,Handoff_Logs/<刚写的NNNN文件> <project-root>
```
Add one Why line: `# --files = 本次写入集（write-target set，ADR-0004）：仅扫本次改动文件，非 git diff 非全树（Decision 0019 ① 限域）`

- [ ] **Step 3: Edit `SKILL.md`** — the 后置五连检查 step 9: append a sentence that when run as part of `/handoff` write, pass `--files HANDOFF.md,<新Dev Log路径>` so B① lints the write-target set; standalone tidy/manual postflight omits `--files` (B① no-op by design).

- [ ] **Step 4: Verify dual-source/bundle consistency**

Run: `bash tests/test_bundle_sync.sh 2>&1 | tail -2`
Expected: still green (references/ bundle parity intact).

- [ ] **Step 5: Commit**

```bash
git add skills/handoff/references/handoff-write.md skills/handoff/SKILL.md
git commit -m "docs(doc-integrity): /handoff write flow passes write-target set to postflight --files"
```

---

## Task 7: B② ordinal Current-State staleness (WARN-only, in test_doc_freshness.sh)

**Files:**
- Modify: `tests/test_doc_freshness.sh` (add the B② sub-check)
- Test: same file (it is the test; add a self-asserting fixture block)

ADR-0002: verify `HANDOFF.md`'s Current State references the HIGHEST Dev Log ordinal in `Handoff_Logs/`. Ordinal compare — never wall-clock/mtime/git. **WARN-only: must NEVER increment `FAIL`** (K4-immune; hard-blocking freshness is exactly Gotcha #14). Print `⚠️` advisory + count as PASS so `run_all` stays green even when Current State legitimately lags during release.

- [ ] **Step 1: Write the failing test** — append a focused block before `test_doc_freshness.sh`'s final `summary` (it uses the same `PASS/FAIL`/`summary` from common.sh):

```bash
# ── Test B②: Current State references highest Dev Log ordinal (WARN-only, ADR-0002) ──
B2_MAX=$(ls "$DOC_DIR/Handoff_Logs/"[0-9]*.md 2>/dev/null | sed 's|.*/||' | grep -oE '^[0-9]{4}' | sort | tail -1)
B2_CS=$(awk '/^## 🎯 Current State/{f=1} f&&/^## /&&!/Current State/{f=0} f' "$DOC_DIR/HANDOFF.md" 2>/dev/null)
if [ -n "$B2_MAX" ] && printf '%s' "$B2_CS" | grep -qE "(Dev Log|Handoff_Logs/)0*${B2_MAX#"${B2_MAX%%[1-9]*}"}|0*$B2_MAX"; then
    echo "  ✅ B②: Current State references highest Dev Log ordinal ($B2_MAX)"
    PASS=$((PASS+1))
else
    # WARN-only — NEVER FAIL (ADR-0002 K4-immune). Advisory + counts as PASS.
    echo "  ⚠️  B② WARN: Current State does not reference highest Dev Log ordinal ($B2_MAX) — advisory only, not a gate (ADR-0002)"
    PASS=$((PASS+1))
fi
```

> Note: matching `0*$B2_MAX` tolerates `Dev Log 0050` vs `Handoff_Logs/0050`; the WARN branch still `PASS`es so the suite never blocks release (K4). Do NOT convert to `FAIL` — ADR-0002 explicitly forbids it.

- [ ] **Step 2: Run — expect PASS now** (HANDOFF.md Current State already references the latest Dev Log from the P0 cutover; this is a guard that stays green and only WARNs on real drift).

Run: `bash tests/test_doc_freshness.sh`
Expected: all green incl. the new `✅ B②` line.

- [ ] **Step 3: Negative-fixture sanity (manual, not committed)** — temporarily point a scratch HANDOFF.md Current State at an old ordinal, run the block logic, confirm it prints `⚠️ B② WARN` and still `PASS`es (does not FAIL). Revert. (This proves WARN-only; no test artifact committed — the assertion above is the permanent guard.)

- [ ] **Step 4: Commit**

```bash
git add tests/test_doc_freshness.sh
git commit -m "feat(doc-integrity): B② ordinal Current-State staleness WARN (ADR-0002, K4-immune, never FAIL)"
```

---

## Task 8: B③ generated Decision INDEX

**Files:**
- Modify: `scripts/lib/handoff-v2.sh` + `skills/handoff/scripts/lib/handoff-v2.sh` — add `regenerate_decision_index`
- Modify: `skills/handoff/references/handoff-write.md` + `SKILL.md` — call it alongside `regenerate_pointers`
- Test: `tests/test_handoff_xref_lint.sh` (add B③ assertions; it already has scratch infra)

`regenerate_decision_index <repo_root>` writes `Handoff_Decisions/INDEX.md` — a table from each `Handoff_Decisions/[0-9]*.md` frontmatter (`number` / `date` / `title`). Idempotent, atomic (`.new`+`mv`), mirrors `regenerate_pointers`. recall NEVER auto-reads `Handoff_Decisions/` ⇒ zero hot-path token cost (Decision 0019 ③).

- [ ] **Step 1: Write the failing test** (append before `summary` in `tests/test_handoff_xref_lint.sh`):

```bash
# --- Task 8: B③ Decision INDEX ---
mkdir -p "$WORK/Handoff_Decisions"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-01-02\nnumber: 0001\ntitle: First choice\n---\n' > "$WORK/Handoff_Decisions/0001-2026-01-02-first.md"
printf -- '---\nschema: 2\ntype: decision\ndate: 2026-03-04\nnumber: 0002\ntitle: Second choice\n---\n' > "$WORK/Handoff_Decisions/0002-2026-03-04-second.md"
bash -c '. "'"$SCRIPTS_DIR"'/lib/handoff-v2.sh"; regenerate_decision_index "'"$WORK"'"'
assert_file_exists "INDEX.md generated" "$WORK/Handoff_Decisions/INDEX.md"
assert_contains "INDEX lists 0001 title" "$(cat "$WORK/Handoff_Decisions/INDEX.md")" "First choice"
assert_contains "INDEX lists 0002 date" "$(cat "$WORK/Handoff_Decisions/INDEX.md")" "2026-03-04"
bash -c '. "'"$SCRIPTS_DIR"'/lib/handoff-v2.sh"; regenerate_decision_index "'"$WORK"'"'
assert_exit "idempotent (2nd run same content)" 0 "$([ "$(grep -c '^| 0' "$WORK/Handoff_Decisions/INDEX.md")" = 2 ] && echo 0 || echo 1)"
```

- [ ] **Step 2: Run — expect FAIL** (`regenerate_decision_index: command not found`).

- [ ] **Step 3: Implement — append to BOTH `handoff-v2.sh` copies:**

```bash
# B③ (Decision 0019 ③): regenerate Handoff_Decisions/INDEX.md from per-file
# frontmatter. recall never auto-reads Handoff_Decisions/ ⇒ zero hot-path cost.
# Idempotent + atomic (.new + mv). No-op if dir absent.
regenerate_decision_index() {
    local root="$1" dir="$1/Handoff_Decisions" tmp f num date title
    [ -d "$dir" ] || return 0
    tmp=$(mktemp) || return 1
    {
        echo "# Decision Index"
        echo
        echo "> 自动生成（regenerate_decision_index）。recall 默认不读，按需查。"
        echo
        echo "| # | 日期 | 标题 |"
        echo "|---|------|------|"
        for f in "$dir"/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] || continue
            num=$(sed -n 's/^number: *//p' "$f" | head -1)
            date=$(sed -n 's/^date: *//p' "$f" | head -1)
            title=$(sed -n 's/^title: *//p' "$f" | head -1)
            echo "| $num | $date | $title |"
        done
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$dir/INDEX.md"
}
```

- [ ] **Step 4: Mirror + run — expect PASS**

```bash
cp scripts/lib/handoff-v2.sh skills/handoff/scripts/lib/handoff-v2.sh
bash tests/test_handoff_xref_lint.sh
```
Expected: `─── 22 passed, 0 failed`

- [ ] **Step 5: Wire into the write flow + generate the real INDEX**

Edit `references/handoff-write.md` + `SKILL.md` step 8: call `regenerate_decision_index <project-root>` immediately after `regenerate_pointers HANDOFF.md`. Then generate the real artifact:
```bash
bash -c '. scripts/lib/handoff-v2.sh; regenerate_decision_index "$PWD"'
```

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/handoff-v2.sh skills/handoff/scripts/lib/handoff-v2.sh skills/handoff/references/handoff-write.md skills/handoff/SKILL.md Handoff_Decisions/INDEX.md tests/test_handoff_xref_lint.sh
git commit -m "feat(doc-integrity): B③ generated Handoff_Decisions/INDEX.md (zero recall hot-path, Decision 0019 ③)"
```

---

## Task 9: Integration — dual-source sync, suite/assertion-count drift, run_all green

**Files:** `tests/test_scripts_sync.sh` (verify, NOT modify), canonical docs (count sync).

Two new dual-sourced runtime files (`handoff-xref-lint.sh`, `lib/handoff-xref-grammar.sh`) + a new test suite (`test_handoff_xref_lint.sh`) → `test_scripts_sync.sh` requires byte-equality (these are NOT DEV_ONLY — opposite of P0) and the v2.1.5 recursive-drift coupling re-triggers (suite count 27→28; assertion total grows).

- [ ] **Step 1: Confirm dual-source byte-equality (NOT DEV_ONLY)**

```bash
diff scripts/handoff-xref-lint.sh skills/handoff/scripts/handoff-xref-lint.sh && diff scripts/lib/handoff-xref-grammar.sh skills/handoff/scripts/lib/handoff-xref-grammar.sh && echo DUAL-OK
bash tests/test_scripts_sync.sh 2>&1 | tail -2
```
Expected: `DUAL-OK`; `test_scripts_sync.sh` green WITHOUT adding these to DEV_ONLY (they belong in the bundle).

- [ ] **Step 2: shellcheck the new scripts**

Run: `shellcheck -S error scripts/handoff-xref-lint.sh scripts/lib/handoff-xref-grammar.sh`
Expected: clean.

- [ ] **Step 3: Recompute + sync counts (Gotcha #20 — never hand-guess)**

```bash
NSUITE=$(ls tests/test_*.sh | wc -l | tr -d ' ')                                  # 27 → 28
NASSERT=$(bash tests/run_all.sh 2>/dev/null | grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s}')
echo "suites=$NSUITE assertions=$NASSERT"
```
Update `<N> 套件` / `<N>/<N> ✅` / assertion totals in `HANDOFF.md` (15/37/301 region), `README.md`, `README_CN.md`, `CONTRIBUTING.md`, `TEST-SCENARIOS.md` (add a `test_handoff_xref_lint.sh` row) to the recomputed values — pure number sync, no prose rewrites. Suite count IS guarded (Test 15/16) so this is mandatory to keep run_all green.

- [ ] **Step 4: Full green gate**

```bash
bash tests/run_all.sh        # expect: All suites passed ✅
shellcheck -S error scripts/handoff-xref-lint.sh scripts/lib/handoff-xref-grammar.sh scripts/handoff-postflight.sh scripts/lib/handoff-v2.sh
```

- [ ] **Step 5: Commit**

```bash
git add HANDOFF.md README.md README_CN.md CONTRIBUTING.md TEST-SCENARIOS.md
git commit -m "test(doc-integrity): integrate P1 suite + sync canonical suite/assertion counts (v2.1.5 drift coupling)"
```

---

## Task 10: Independent review (self-hosted on shipped P0 review-loop) + cutover

**Files:** no code — independent review of P1 + a Dev Log line.

P0 review-loop is now SHIPPED and self-hosting (0020 open#2 coupling (a) payoff). Run P1's independent review THROUGH `scripts/review-loop.sh` — this is the first real self-hosted use (dogfood the now-shipped harness on real downstream P1 work). Keep multi-source per Gotcha #22.

- [ ] **Step 1: Start a real review loop over the P1 surface**

```bash
bash scripts/review-loop.sh start --topic p1-doc-integrity \
  scripts/lib/handoff-xref-grammar.sh scripts/handoff-xref-lint.sh \
  scripts/lib/handoff-v2.sh scripts/handoff-postflight.sh tests/test_handoff_xref_lint.sh
```

- [ ] **Step 2: Independent reviewers → record each round**

Dispatch an independent opus code-reviewer subagent AND let the Codex stop-time gate review (multi-source, Gotcha #22). For each verdict run `review-loop.sh record --reviewer <id> --verdict <V> [--ground …] --findings <file> <the P1 files>`. Address every Critical/Important via TDD (RED→fix→GREEN→commit). Iterate until the loop's own discipline is satisfied (independent PASS, zero open Critical/Important — plan does NOT close with open ones).

- [ ] **Step 3: Finalize + fold the durable line into a Dev Log**

```bash
bash scripts/review-loop.sh finalize --devlog Handoff_Logs/<new>   # exit 0 only if CONVERGED/OVERRIDDEN
```
Via `/handoff`: a Dev Log entry — P1 doc-integrity shipped; first self-hosted review-loop use (coupling (a) payoff proven); B①'s grammar lib is the single P2 rename locus (coupling b — restate for the P2 planner that `scripts/lib/handoff-xref-grammar.sh` + bundle copy + its target-path constants MUST be in P2's P-A allowlist or P2 silently breaks B①).

- [ ] **Step 4: Push gate**

Do NOT push without explicit Boss authorization (§4 — does not carry forward). Report ready-to-push state.

---

## Self-Review

**1. Spec coverage:**
- B① write-target set (ADR-0004): Task 4 CLI operates on explicit args only; Task 5 postflight `--files`; Task 6 write-flow passes the set; never git/mtime — stated + enforced (no git in any code). ✅
- B① cross-ref grammar bounded enumeration (ADR-0004 / CONTEXT.md): Task 2, centralized Task 1. ✅
- B① residual-placeholder, exact sentinels, skip templates (CONTEXT.md): Task 3 + Task 4 skip. ✅
- B② ordinal, WARN-only, K4-immune, inside test_doc_freshness.sh (ADR-0002): Task 7, never FAIL, explicit note. ✅
- B③ standalone INDEX, zero recall hot-path (Decision 0019 ③): Task 8, recall never auto-reads Handoff_Decisions/. ✅
- Coupling (b) single P2 rename locus: Task 1 establishes it; header + Task 10 Step 3 restate for P2 planner. ✅
- Coupling (d) postflight serialization: header note + Task 5. ✅
- Dual-source (not DEV_ONLY): header + Task 1/2/3/4/8 mirror steps + Task 9 verify. ✅
- Out-of-scope (P0/P2/perf/D): none introduced. ✅

**2. Placeholder scan:** No TBD/TODO; every code step has complete bash; every test step has runnable assertions + expected counts. ✅ (Note: assertion running totals 3→7→11→17→22 assume in-order; per-task delta is the contract — same caveat as the P0 plan; if doc-freshness count differs, recompute, never move test goalposts.)

**3. Type/name consistency:** `rl_xref_unresolved`, `rl_residual_placeholders` (grammar lib); `RL_XREF_LOGS_DIR/RL_XREF_DEC_DIR/RL_XREF_GOTCHAS_FILE`, `RL_PLACEHOLDER_SENTINELS` (constants); `regenerate_decision_index` (mirrors `regenerate_pointers`); `handoff-xref-lint.sh` `--files` — all defined once (Tasks 1-4,8), consumed with identical names (Tasks 4,5,8). Source guard `_RL_XREF_GRAMMAR_SOURCED`. ✅

---

## Execution Handoff

Plan complete and saved to `docs/2026-05-17-p1-doc-integrity-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, controller verification + (Task 10) independent review now self-hosted on the shipped P0 review-loop. Structurally enforces §4 and proves coupling (a) payoff.
2. **Inline Execution** — executing-plans, batch with checkpoints.

Which approach?
