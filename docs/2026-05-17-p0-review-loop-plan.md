# P0 Review-Loop (A/B/C/E) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a git-orthogonal, mechanically-decidable cyclic code-review harness that records per-round verdicts, converges only on 3 consecutive PASS, distrusts self-reported verdicts, and hard-stops on credential/privacy veto — formalizing the ad-hoc discipline this repo already runs by hand.

**Architecture:** A sourced bash library (`scripts/lib/review-ledger.sh`) holds the four mechanical primitives — A content-hash + two-tier ledger, B convergence predicate, C orchestrator validation, E veto detection. A thin CLI orchestrator (`scripts/review-loop.sh`) wires them into `start / record / status / finalize / override` subcommands. The per-round ledger is ephemeral gitignored scratch (`.review-loop/`, the `graphify-out/` not-shipped precedent); the only durable trace is one distilled line the operator folds into a `Handoff_Logs/` Dev Log. This is a **maintainer-only dev tool** — NOT dual-sourced into `skills/handoff/scripts/`, NOT in the `.skill` bundle, NOT referenced by `SKILL.md`/`install.sh` (ADR-0003 hard gate ⑦; also keeps it out of the future Spec C rename blast radius).

**Tech Stack:** Bash 3.2 (macOS default) + mawk-safe (Ubuntu) + markdown. No git in any predicate (§1). Cross-platform sha256 (`sha256sum` ‖ `shasum -a 256`). TDD via `tests/common.sh` assertions; `tests/run_all.sh` auto-discovers `test_*.sh`.

**Spec truth sources (authoritative, do not paraphrase from memory):**
- `Handoff_Decisions/0019-*.md` §"review-loop 轴" + `Handoff_Decisions/0020-*.md` lines 34-40
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/docs/adr/0003-verdict-ledger-two-tier-placement.md` (A)
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/docs/adr/0006-spec-e-credential-privacy-veto-tiers.md` (E)
- `<dev-home>/tkbox/Cloud_Coding/Independent_Research/grillme/CONTEXT.md` (Converged / Verdict / Orchestrator validation / Credential-privacy veto definitions)

**Scope lock:** P0 only — A (two-tier ledger), B (6-state ladder + strict 3-consecutive-PASS), C (orchestrator distrust), E (credential/privacy veto tiers). **Out of scope:** P1 doc-integrity (B①②③), P2 handoffx mega-program, perf track, D markdown-as-IPC.

**0020 open#2 coupling (a) — P0 self-bootstrap (mandatory, Task 11):** A/B/C/E has no review-loop to review its own genesis. It is bootstrapped by the *existing* ad-hoc cross-agent review (Codex stop-time gate already live on this repo + superpowers code-reviewer). After P0 ships it self-hosts. The plan's own review uses the old mechanism by necessity; this is acknowledged, not a gap.

---

## File Structure

| File | Responsibility | Class |
|------|----------------|-------|
| `scripts/lib/review-ledger.sh` | Pure primitives: content-hash, append/read ledger, convergence (B), validation (C), veto detection (E). No I/O policy, no escalation. Sourced, never executed. | Create |
| `scripts/review-loop.sh` | CLI orchestrator: `start/record/status/finalize/override`. Owns scratch-dir lifecycle, escalation exit codes, durable outcome line. | Create |
| `tests/test_review_loop.sh` | TDD suite for both files above. Uses `common.sh`. | Create |
| `.gitignore` | Add `.review-loop/` ephemeral scratch (graphify-out/ precedent — never tracked, never shipped). | Modify |
| `HANDOFF.md` + canonical docs | Suite/assertion counts (`<N> 套件`) bumped — adding a suite trips `test_doc_freshness.sh` Test 15/16 (the recursive-drift coupling v2.1.5 found). | Modify (Task 10) |

**Ledger record format** (one space-separated line per round, all values space-free; `|` deliberately NOT used as delimiter — Gotcha #2):

```
round=<N> reviewer=<id> content_hash=<sha256> verdict=<V> ground=<g|-> ts=<ISO8601+TZ> findings=<count>
```

Verdict enum (6-state ladder, CONTEXT.md): `PASS WARN BLOCKED USER_DECISION ERROR N-A`. Findings detail (for C's `file:line` check) lives in a sibling `round-<N>.findings`, one `path:line message` per line.

**Scratch layout** (single active loop — concurrent loops are explicitly out of scope, spec defers multi-agent D):

```
.review-loop/current/
  ledger.tsv          # one line per round (format above)
  round-<N>.findings  # findings for round N (path:line message)
  state               # ACTIVE | CONVERGED | VETOED | CAPPED | OVERRIDDEN
  outcome.txt         # distilled durable line (written at finalize)
```

---

## Task 1: Scaffold + gitignore the ephemeral scratch dir

**Files:**
- Modify: `.gitignore` (append one entry near the `graphify-out/` block)
- Create: `scripts/lib/review-ledger.sh` (header + guard only)
- Create: `scripts/review-loop.sh` (shebang + usage stub only)
- Create: `tests/test_review_loop.sh` (harness skeleton)

- [ ] **Step 1: Add scratch dir to `.gitignore`**

Append after the `graphify-out/` / `.claude/` block (keep the existing comment style — Why over How):

```
# Review-loop ephemeral scratch（ADR-0003：per-round ledger 是 gitignored
# 草稿，收敛即弃；唯一耐久痕迹是 Handoff_Logs/ 一行结论。复用 graphify-out/
# 不发布先例——绝不入库、绝不进 .skill bundle、recall 不读。
.review-loop/
```

- [ ] **Step 2: Create the library file with a source guard**

`scripts/lib/review-ledger.sh`:

```bash
#!/bin/bash
# review-ledger.sh — P0 review-loop primitives (A/B/C/E). Sourced, not executed.
# A: content-hash + two-tier ledger (ADR-0003). B: 3-consecutive-PASS convergence
# (CONTEXT.md "Converged"). C: orchestrator validation (CONTEXT.md). E: credential/
# privacy veto detection (ADR-0006). NO git in any predicate (§1 git-orthogonal).
# Pure functions only — escalation policy + scratch I/O live in review-loop.sh.

# idempotent source guard
[ -n "${_RL_LEDGER_SOURCED:-}" ] && return 0
_RL_LEDGER_SOURCED=1
```

- [ ] **Step 3: Create the CLI stub**

`scripts/review-loop.sh`:

```bash
#!/bin/bash
# review-loop.sh — maintainer-only cyclic code-review harness (P0: A/B/C/E).
# Dev tool: NOT dual-sourced to skills/handoff/scripts/, NOT in .skill (ADR-0003 ⑦).
# usage: review-loop.sh {start|record|status|finalize|override|help} ...
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/review-ledger.sh
. "$SCRIPT_DIR/lib/review-ledger.sh"

usage() {
    cat <<'EOF'
review-loop.sh — cyclic code-review harness (P0)

  start    --topic <slug> <file...>         begin a loop over a content set
  record   --reviewer <id> --verdict <V> [--ground credential|privacy|-]
           [--findings <file>] <file...>    record one reviewer round
  status                                    show streak / state / rounds
  finalize [--devlog <path>] [--cap]        emit durable outcome line
  override --reason <text>                  Boss-only: lift a credential/privacy veto
  help                                      this text

Verdicts: PASS WARN BLOCKED USER_DECISION ERROR N-A
Exit: 0 ok / 1 error / 2 usage / 3 escalation-to-Boss (veto or cap)
EOF
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift
case "$cmd" in
    -h|--help|help) usage; exit 0 ;;
    *) echo "❌ not yet implemented: $cmd" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: Create the test harness skeleton**

`tests/test_review_loop.sh`:

```bash
#!/bin/bash
# test_review_loop.sh — P0 review-loop (A/B/C/E) TDD suite.
source "$(dirname "$0")/common.sh"

LIB="$SCRIPTS_DIR/lib/review-ledger.sh"
CLI="$SCRIPTS_DIR/review-loop.sh"
WORK="$TMP_DIR/review-loop-$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

assert_file_exists "review-ledger.sh exists" "$LIB"
assert_file_exists "review-loop.sh exists"  "$CLI"
assert_exit "cli help exits 0" 0 "$(bash "$CLI" help >/dev/null 2>&1; echo $?)"

summary
```

- [ ] **Step 5: Run the harness — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 3 passed, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add .gitignore scripts/lib/review-ledger.sh scripts/review-loop.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): P0 scaffold — gitignored scratch + lib/CLI stubs (ADR-0003)"
```

---

## Task 2: A — cross-platform content hash (git-orthogonal)

**Files:**
- Modify: `scripts/lib/review-ledger.sh` (add `_rl_sha256`, `rl_content_hash`)
- Test: `tests/test_review_loop.sh`

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 2: content hash ---
echo "alpha" > "$WORK/a.txt"; echo "beta" > "$WORK/b.txt"
H1=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/a.txt" "'"$WORK"'/b.txt"')
H2=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/b.txt" "'"$WORK"'/a.txt"')
assert_contains "hash is 64-hex" "$H1" "$(printf '%s' "$H1" | grep -oE '^[0-9a-f]{64}$')"
assert_exit "hash order-stable (sorted input)" 0 "$([ "$H1" = "$H2" ] && echo 0 || echo 1)"
echo "alpha-changed" > "$WORK/a.txt"
H3=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/a.txt" "'"$WORK"'/b.txt"')
assert_exit "hash changes with content" 0 "$([ "$H1" != "$H3" ] && echo 0 || echo 1)"
assert_exit "missing file -> exit 2" 2 "$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/nope.txt"' >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `rl_content_hash: command not found` / 4 new assertions fail.

- [ ] **Step 3: Implement** — append to `scripts/lib/review-ledger.sh`:

```bash
# A: sha256 of the SORTED concatenation of explicitly-passed file contents.
# Truth = the explicit file list (same discipline as ADR-0004 write-target set),
# NEVER a git rev — keeps §1 intact. Cross-platform: sha256sum ‖ shasum -a 256.
_rl_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
    else echo "review-ledger: no sha256 tool (need sha256sum or shasum)" >&2; return 2; fi
}

rl_content_hash() {
    [ $# -ge 1 ] || { echo "review-ledger: rl_content_hash needs >=1 file" >&2; return 2; }
    local f tmp
    for f in "$@"; do
        [ -f "$f" ] || { echo "review-ledger: content file missing: $f" >&2; return 2; }
    done
    tmp=$(mktemp)
    printf '%s\n' "$@" | LC_ALL=C sort > "$tmp"
    local rc
    while IFS= read -r f; do cat "$f"; done < "$tmp" | _rl_sha256
    rc=$?
    rm -f "$tmp"
    return $rc
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 7 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-ledger.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): A content-hash — sorted file-content sha256, git-orthogonal"
```

---

## Task 3: A — append + read the per-round ledger

**Files:**
- Modify: `scripts/lib/review-ledger.sh` (`rl_append_round`, `rl_round_count`)
- Test: `tests/test_review_loop.sh`

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 3: ledger append/read ---
LED="$WORK/ledger.tsv"; : > "$LED"
bash -c '. "'"$LIB"'"; rl_append_round "'"$LED"'" 1 codex abc PASS - 2026-05-17T18:00:00+08:00 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$LED"'" 2 spcr def WARN - 2026-05-17T18:05:00+08:00 3'
assert_contains "round 1 line" "$(cat "$LED")" "round=1 reviewer=codex content_hash=abc verdict=PASS ground=- ts=2026-05-17T18:00:00+08:00 findings=0"
assert_contains "round 2 verdict" "$(cat "$LED")" "verdict=WARN"
assert_exit "round count = 2" 0 "$([ "$(bash -c '. "'"$LIB"'"; rl_round_count "'"$LED"'"')" = 2 ] && echo 0 || echo 1)"
assert_exit "round count missing file = 0" 0 "$([ "$(bash -c '. "'"$LIB"'"; rl_round_count "'"$WORK"'/none"')" = 0 ] && echo 0 || echo 1)"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `rl_append_round: command not found`.

- [ ] **Step 3: Implement** — append to `scripts/lib/review-ledger.sh`:

```bash
# A durable-tier helpers. Ledger line is flat & grep-decidable (no `|` — Gotcha #2).
rl_append_round() {
    # args: ledger round reviewer content_hash verdict ground ts findings_count
    [ $# -eq 8 ] || { echo "review-ledger: rl_append_round needs 8 args" >&2; return 2; }
    printf 'round=%s reviewer=%s content_hash=%s verdict=%s ground=%s ts=%s findings=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$1"
}

rl_round_count() {
    [ -f "$1" ] || { echo 0; return 0; }
    grep -c '^round=' "$1" 2>/dev/null || echo 0
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 11 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-ledger.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): A ledger append/read — flat grep-decidable record"
```

---

## Task 4: B — strict 3-consecutive-PASS convergence predicate

**Files:**
- Modify: `scripts/lib/review-ledger.sh` (`rl_convergence_streak`, `rl_is_converged`)
- Test: `tests/test_review_loop.sh`

Spec (CONTEXT.md "Converged"): exactly 3 consecutive `PASS`; ANY non-PASS round (`WARN/BLOCKED/USER_DECISION/ERROR/N-A`) resets the streak to 0. A WARN is NOT a pass.

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 4: convergence ---
mk_led() { local p="$WORK/L$$"; : > "$p"; local i=1; for v in "$@"; do
  bash -c '. "'"$LIB"'"; rl_append_round "'"$p"'" '"$i"' r h '"$v"' - t 0'; i=$((i+1)); done; echo "$p"; }
streak() { bash -c '. "'"$LIB"'"; rl_convergence_streak "'"$1"'"'; }
conv()   { bash -c '. "'"$LIB"'"; rl_is_converged "'"$1"'" && echo Y || echo N'; }
assert_exit "PASS PASS PASS -> streak 3"  0 "$([ "$(streak "$(mk_led PASS PASS PASS)")" = 3 ] && echo 0 || echo 1)"
assert_contains "PASS PASS PASS converged" "$(conv "$(mk_led PASS PASS PASS)")" "Y"
assert_contains "PASS WARN PASS PASS NOT converged (only 2)" "$(conv "$(mk_led PASS WARN PASS PASS)")" "N"
assert_exit "WARN resets: P P W P -> streak 1" 0 "$([ "$(streak "$(mk_led PASS PASS WARN PASS)")" = 1 ] && echo 0 || echo 1)"
assert_contains "4 PASS still converged" "$(conv "$(mk_led PASS PASS PASS PASS)")" "Y"
assert_contains "empty ledger NOT converged" "$(conv "$WORK/empty-$$")" "N"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `rl_convergence_streak: command not found`.

- [ ] **Step 3: Implement** — append to `scripts/lib/review-ledger.sh`:

```bash
# B: streak of trailing consecutive PASS. Any non-PASS resets to 0 (CONTEXT.md
# "Converged"). Grep-decidable; verdict token is bounded by " ground=".
rl_convergence_streak() {
    local led="$1" streak=0 v line
    [ -f "$led" ] || { echo 0; return 0; }
    while IFS= read -r line; do
        case "$line" in round=*) ;; *) continue ;; esac
        v=$(printf '%s\n' "$line" | sed -n 's/.* verdict=\([A-Z_-]*\) ground=.*/\1/p')
        if [ "$v" = "PASS" ]; then streak=$((streak + 1)); else streak=0; fi
    done < "$led"
    echo "$streak"
}

rl_is_converged() { [ "$(rl_convergence_streak "$1")" -ge 3 ]; }
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 17 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-ledger.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): B convergence — strict 3-consecutive-PASS, non-PASS resets"
```

---

## Task 5: C — orchestrator validation (distrust self-reported verdict)

**Files:**
- Modify: `scripts/lib/review-ledger.sh` (`rl_validate_round`)
- Test: `tests/test_review_loop.sh`

Spec (CONTEXT.md "Orchestrator validation"): a verdict with no `content_hash`, an out-of-enum verdict, or any finding lacking a `file:line` citation → recorded as `ERROR` (neither accepted nor silently discarded). `rl_validate_round` returns the *effective* verdict (the claimed one, or `ERROR`).

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 5: orchestrator validation (C) ---
val() { bash -c '. "'"$LIB"'"; rl_validate_round "$1" "$2" "$3"' _ "$1" "$2" "$3"; }
GOOD="$WORK/f-good"; printf 'scripts/x.sh:42 bad thing\nlib/y.sh:7 other\n' > "$GOOD"
BAD="$WORK/f-bad";  printf 'scripts/x.sh:42 ok\nno-location-here\n' > "$BAD"
EMPTY="$WORK/f-empty"; : > "$EMPTY"
assert_contains "valid PASS no findings -> PASS"        "$(val abc PASS "$EMPTY")" "PASS"
assert_contains "valid WARN well-formed findings -> WARN" "$(val abc WARN "$GOOD")" "WARN"
assert_contains "missing content_hash -> ERROR"          "$(val '' PASS "$EMPTY")" "ERROR"
assert_contains "content_hash '-' -> ERROR"              "$(val - PASS "$EMPTY")" "ERROR"
assert_contains "out-of-enum verdict -> ERROR"           "$(val abc LGTM "$EMPTY")" "ERROR"
assert_contains "finding without file:line -> ERROR"     "$(val abc PASS "$BAD")" "ERROR"
assert_contains "USER_DECISION is in enum"               "$(val abc USER_DECISION "$EMPTY")" "USER_DECISION"
assert_contains "N-A is in enum"                          "$(val abc N-A "$EMPTY")" "N-A"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `rl_validate_round: command not found`.

- [ ] **Step 3: Implement** — append to `scripts/lib/review-ledger.sh`:

```bash
# C: orchestrator does not trust self-report. Returns effective verdict:
# the claimed verdict, or ERROR if the round is unvalidatable. Never silently
# drops — the caller records whatever this returns (CONTEXT.md).
rl_validate_round() {
    # args: content_hash claimed_verdict findings_file
    local ch="$1" v="$2" ff="$3"
    if [ -z "$ch" ] || [ "$ch" = "-" ]; then echo "ERROR"; return 0; fi
    case "$v" in
        PASS|WARN|BLOCKED|USER_DECISION|ERROR|N-A) ;;
        *) echo "ERROR"; return 0 ;;
    esac
    if [ -n "$ff" ] && [ -s "$ff" ]; then
        # every non-empty finding line must start with `path:line ` (file:line cite)
        if grep -qvE '^[^:[:space:]]+:[0-9]+ ' "$ff"; then echo "ERROR"; return 0; fi
    fi
    echo "$v"
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 25 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-ledger.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): C orchestrator validation — unvalidatable round -> ERROR"
```

---

## Task 6: E — credential/privacy veto detection

**Files:**
- Modify: `scripts/lib/review-ledger.sh` (`rl_is_credential_privacy_veto`)
- Test: `tests/test_review_loop.sh`

Spec (ADR-0006): a single reviewer `BLOCKED` on **credential** or **privacy** grounds is the one-vote veto. Detection is pure; escalation/override *policy* is the CLI's job (Task 9). This function only answers "is this round that veto?".

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 6: E veto detection ---
veto() { bash -c '. "'"$LIB"'"; rl_is_credential_privacy_veto "$1" "$2" && echo Y || echo N' _ "$1" "$2"; }
assert_contains "BLOCKED+credential -> veto"   "$(veto BLOCKED credential)" "Y"
assert_contains "BLOCKED+privacy -> veto"      "$(veto BLOCKED privacy)" "Y"
assert_contains "BLOCKED+other -> NOT veto"    "$(veto BLOCKED style)" "N"
assert_contains "WARN+credential -> NOT veto"  "$(veto WARN credential)" "N"
assert_contains "PASS+- -> NOT veto"           "$(veto PASS -)" "N"
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `rl_is_credential_privacy_veto: command not found`.

- [ ] **Step 3: Implement** — append to `scripts/lib/review-ledger.sh`:

```bash
# E: the one-vote veto = BLOCKED raised on credential|privacy grounds (ADR-0006).
# Pure predicate; tier policy (machinery-never / Boss-explicit) is in review-loop.sh.
rl_is_credential_privacy_veto() {
    # args: verdict ground  -> exit 0 iff this is the credential/privacy veto
    [ "$1" = "BLOCKED" ] || return 1
    [ "$2" = "credential" ] || [ "$2" = "privacy" ]
}
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 30 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/review-ledger.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): E veto detection — BLOCKED on credential/privacy grounds"
```

---

## Task 7: CLI — `start` + `status` (scratch lifecycle)

**Files:**
- Modify: `scripts/review-loop.sh` (replace the `*)` stub with a dispatch + `start`/`status`)
- Test: `tests/test_review_loop.sh`

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 7: CLI start/status ---
cd "$WORK" || exit 1
echo "code v1" > src.txt
assert_exit "start ok" 0 "$(bash "$CLI" start --topic demo "$WORK/src.txt" >/dev/null 2>&1; echo $?)"
assert_file_exists "scratch ledger created" "$WORK/.review-loop/current/ledger.tsv"
assert_contains "state ACTIVE" "$(cat "$WORK/.review-loop/current/state" 2>/dev/null)" "ACTIVE"
assert_exit "double start refused (exit 2)" 2 "$(bash "$CLI" start --topic demo "$WORK/src.txt" >/dev/null 2>&1; echo $?)"
assert_contains "status shows state" "$(bash "$CLI" status 2>&1)" "ACTIVE"
assert_contains "status shows streak 0" "$(bash "$CLI" status 2>&1)" "streak=0"
cd "$ROOT_DIR" || exit 1
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `start` hits the `not yet implemented` stub (exit 2 but no scratch dir; `assert_file_exists` fails).

- [ ] **Step 3: Implement** — in `scripts/review-loop.sh` replace the `case` block's `*)` arm with full dispatch:

```bash
RL_DIR=".review-loop/current"

rl_die() { echo "❌ $1" >&2; exit "${2:-1}"; }

case "$cmd" in
    -h|--help|help) usage; exit 0 ;;

    start)
        topic=""
        files=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --topic) topic="${2:-}"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) files+=("$1"); shift ;;
            esac
        done
        [ -n "$topic" ] || rl_die "start needs --topic <slug>" 2
        [ ${#files[@]} -ge 1 ] || rl_die "start needs >=1 content file" 2
        [ -d "$RL_DIR" ] && rl_die "a loop is already active ($RL_DIR) — finalize it first" 2
        ch=$(rl_content_hash "${files[@]}") || rl_die "content hash failed" 1
        mkdir -p "$RL_DIR"
        : > "$RL_DIR/ledger.tsv"
        printf 'ACTIVE\n' > "$RL_DIR/state"
        printf 'topic=%s\ncontent_hash=%s\n' "$topic" "$ch" > "$RL_DIR/meta"
        echo "✅ loop started: topic=$topic content_hash=${ch%${ch#????????}}…"
        ;;

    status)
        [ -d "$RL_DIR" ] || rl_die "no active loop" 1
        st=$(cat "$RL_DIR/state" 2>/dev/null)
        n=$(rl_round_count "$RL_DIR/ledger.tsv")
        s=$(rl_convergence_streak "$RL_DIR/ledger.tsv")
        echo "state=$st rounds=$n streak=$s"
        ;;

    *) rl_die "not yet implemented: $cmd" 2 ;;
esac
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 36 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/review-loop.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): CLI start/status — scratch lifecycle, double-start refused"
```

---

## Task 8: CLI — `record` (wires C → E → B + iteration cap)

**Files:**
- Modify: `scripts/review-loop.sh` (add `record` arm)
- Test: `tests/test_review_loop.sh`

Order of operations per round: recompute `content_hash` of the passed files → `rl_validate_round` (C) yields effective verdict → append round → if effective verdict is the E veto, set `VETOED` + escalate exit 3 → else if round count > `--max-rounds` (default 12) without convergence, set `CAPPED` + escalate exit 3 → else if `rl_is_converged`, set `CONVERGED`. Print streak.

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 8: CLI record ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic demo "$WORK/s.txt" >/dev/null 2>&1
rec() { bash "$CLI" record --reviewer "$1" --verdict "$2" --ground "${3:--}" "$WORK/s.txt"; }
assert_exit "record PASS exit 0" 0 "$(rec a PASS >/dev/null 2>&1; echo $?)"
rec b PASS >/dev/null 2>&1; rec c PASS >/dev/null 2>&1
assert_contains "3xPASS -> CONVERGED" "$(cat "$WORK/.review-loop/current/state")" "CONVERGED"
# C: a finding without file:line is recorded as ERROR, not the claimed PASS
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d2 "$WORK/s.txt" >/dev/null 2>&1
BADF="$WORK/bf"; printf 'no-location bug\n' > "$BADF"
bash "$CLI" record --reviewer a --verdict PASS --findings "$BADF" "$WORK/s.txt" >/dev/null 2>&1
assert_contains "self-report w/o file:line -> ERROR round" "$(cat "$WORK/.review-loop/current/ledger.tsv")" "verdict=ERROR"
# E: BLOCKED+credential -> VETOED + exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d3 "$WORK/s.txt" >/dev/null 2>&1
ec=$(bash "$CLI" record --reviewer a --verdict BLOCKED --ground credential "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "E veto escalates exit 3" 3 "$ec"
assert_contains "E veto -> state VETOED" "$(cat "$WORK/.review-loop/current/state")" "VETOED"
# cap: max-rounds exceeded without convergence -> CAPPED + exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d4 "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1
ec2=$(bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "cap exceeded escalates exit 3" 3 "$ec2"
assert_contains "cap -> state CAPPED" "$(cat "$WORK/.review-loop/current/state")" "CAPPED"
cd "$ROOT_DIR" || exit 1
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `record` hits `not yet implemented` (exit 2).

- [ ] **Step 3: Implement** — add a `record)` arm before the `*)` arm in `scripts/review-loop.sh`:

```bash
    record)
        reviewer=""; verdict=""; ground="-"; findings=""; maxr=12
        files=()
        while [ $# -gt 0 ]; do
            case "$1" in
                --reviewer)   reviewer="${2:-}"; shift 2 ;;
                --verdict)    verdict="${2:-}"; shift 2 ;;
                --ground)     ground="${2:--}"; shift 2 ;;
                --findings)   findings="${2:-}"; shift 2 ;;
                --max-rounds) maxr="${2:-12}"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) files+=("$1"); shift ;;
            esac
        done
        [ -d "$RL_DIR" ] || rl_die "no active loop — run 'start' first" 1
        [ "$(cat "$RL_DIR/state")" = "ACTIVE" ] || rl_die "loop not ACTIVE (state=$(cat "$RL_DIR/state")) — finalize/override first" 1
        [ -n "$reviewer" ] || rl_die "record needs --reviewer <id>" 2
        [ -n "$verdict" ] || rl_die "record needs --verdict <V>" 2
        [ ${#files[@]} -ge 1 ] || rl_die "record needs the content file(s) under review" 2
        ch=$(rl_content_hash "${files[@]}") || rl_die "content hash failed" 1
        # C: distrust self-report — effective verdict may be downgraded to ERROR
        eff=$(rl_validate_round "$ch" "$verdict" "$findings")
        n=$(( $(rl_round_count "$RL_DIR/ledger.tsv") + 1 ))
        ts=$(date "+%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/')
        fc=0; [ -n "$findings" ] && [ -s "$findings" ] && fc=$(grep -c '' "$findings")
        rl_append_round "$RL_DIR/ledger.tsv" "$n" "$reviewer" "$ch" "$eff" "$ground" "$ts" "$fc"
        [ -n "$findings" ] && [ -s "$findings" ] && cp "$findings" "$RL_DIR/round-$n.findings"
        s=$(rl_convergence_streak "$RL_DIR/ledger.tsv")
        # E: credential/privacy veto — machinery hard-stops, escalate to Boss
        if rl_is_credential_privacy_veto "$eff" "$ground"; then
            printf 'VETOED\n' > "$RL_DIR/state"
            echo "🛑 credential/privacy VETO (reviewer=$reviewer). Machinery cannot override." >&2
            echo "   Escalated to Boss. To lift: review-loop.sh override --reason <text> (Boss only)." >&2
            exit 3
        fi
        if rl_is_converged "$RL_DIR/ledger.tsv"; then
            printf 'CONVERGED\n' > "$RL_DIR/state"
            echo "✅ converged: 3 consecutive PASS (round $n, streak=$s)"
            exit 0
        fi
        if [ "$n" -ge "$maxr" ]; then
            printf 'CAPPED\n' > "$RL_DIR/state"
            echo "🛑 iteration cap reached ($n ≥ $maxr) without convergence. Escalated to Boss (no auto-continue — Decision 0009/0010)." >&2
            exit 3
        fi
        echo "recorded round=$n verdict=$eff streak=$s"
        ;;
```

> Note `ts`: `date +%z` gives `+0800`; the `sed` inserts the ISO colon → `+08:00` (TZ-qualified per the user §5 timestamp rule; this is a write-format detail, it does NOT feed convergence which is ordinal/streak-based).

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 44 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/review-loop.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): CLI record — C validate -> E veto -> B converge -> cap"
```

---

## Task 9: CLI — `finalize` (A durable line) + `override` (E Boss tier)

**Files:**
- Modify: `scripts/review-loop.sh` (add `finalize` + `override` arms)
- Test: `tests/test_review_loop.sh`

Spec: A — on convergence the verbose ledger is **discarded**; the only durable trace is **one distilled line** the operator folds into a `Handoff_Logs/` Dev Log (ADR-0003). `finalize` emits that line to stdout + `outcome.txt`; with explicit `--devlog <path>` it appends a `> ` quoted line into that file (explicit path, no git, no auto-numbering — §1). E — `override` is a **separate manual subcommand**, valid only when `state=VETOED`, requires `--reason`, records the override into the durable outcome (never silent, never auto-invoked by machinery — ADR-0006).

- [ ] **Step 1: Write the failing test** — append before `summary`:

```bash
# --- Task 9: finalize + override ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic fin "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer c --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
DL="$WORK/devlog.md"; printf '### log\n' > "$DL"
out=$(bash "$CLI" finalize --devlog "$DL" 2>&1)
assert_contains "finalize emits CONVERGED outcome" "$out" "CONVERGED"
assert_contains "outcome.txt written" "$(cat "$WORK/.review-loop/current/outcome.txt" 2>/dev/null)" "CONVERGED"
assert_contains "devlog got quoted outcome line" "$(cat "$DL")" "> [review-loop]"
# override only valid on VETOED
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic ov "$WORK/s.txt" >/dev/null 2>&1
assert_exit "override on ACTIVE refused (exit 2)" 2 "$(bash "$CLI" override --reason x >/dev/null 2>&1; echo $?)"
bash "$CLI" record --reviewer a --verdict BLOCKED --ground privacy "$WORK/s.txt" >/dev/null 2>&1
assert_exit "override needs --reason (exit 2)" 2 "$(bash "$CLI" override >/dev/null 2>&1; echo $?)"
bash "$CLI" override --reason "Boss: false positive, fixture not real key" >/dev/null 2>&1
assert_contains "override -> state OVERRIDDEN" "$(cat "$WORK/.review-loop/current/state")" "OVERRIDDEN"
assert_contains "override recorded in outcome" "$(cat "$WORK/.review-loop/current/outcome.txt")" "Boss-override"
cd "$ROOT_DIR" || exit 1
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bash tests/test_review_loop.sh`
Expected: FAIL — `finalize`/`override` hit `not yet implemented`.

- [ ] **Step 3: Implement** — add `finalize)` and `override)` arms before `*)`:

```bash
    finalize)
        devlog=""; cap=0
        while [ $# -gt 0 ]; do
            case "$1" in
                --devlog) devlog="${2:-}"; shift 2 ;;
                --cap) cap=1; shift ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) rl_die "unexpected arg: $1" 2 ;;
            esac
        done
        [ -d "$RL_DIR" ] || rl_die "no active loop" 1
        st=$(cat "$RL_DIR/state")
        if [ "$st" = "ACTIVE" ]; then
            [ "$cap" = "1" ] || rl_die "loop still ACTIVE (not converged) — pass --cap to force-close + escalate" 1
            printf 'CAPPED\n' > "$RL_DIR/state"; st="CAPPED"
        fi
        n=$(rl_round_count "$RL_DIR/ledger.tsv")
        reason=""
        [ "$st" = "VETOED" ] && reason=" reason=credential/privacy-veto-unresolved"
        [ "$st" = "CAPPED" ] && reason=" reason=iteration-cap-no-convergence"
        line="[review-loop] verdict=$st rounds=$n$reason"
        printf '%s\n' "$line" > "$RL_DIR/outcome.txt"
        echo "$line"
        if [ -n "$devlog" ]; then
            [ -f "$devlog" ] || rl_die "devlog not found: $devlog" 1
            printf '> %s\n' "$line" >> "$devlog"
            echo "↳ appended to $devlog"
        fi
        echo "ℹ ephemeral ledger kept at $RL_DIR until you 'rm -rf' it; only this line is durable (ADR-0003)."
        ;;

    override)
        reason=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --reason) reason="${2:-}"; shift 2 ;;
                -*) rl_die "unknown flag: $1" 2 ;;
                *) rl_die "unexpected arg: $1" 2 ;;
            esac
        done
        [ -d "$RL_DIR" ] || rl_die "no active loop" 1
        [ "$(cat "$RL_DIR/state")" = "VETOED" ] || rl_die "override valid only on a VETOED loop (state=$(cat "$RL_DIR/state"))" 2
        [ -n "$reason" ] || rl_die "override needs --reason <text> — Boss override must be explicit + recorded (ADR-0006)" 2
        n=$(rl_round_count "$RL_DIR/ledger.tsv")
        line="[review-loop] verdict=OVERRIDDEN rounds=$n Boss-override reason=$reason"
        printf '%s\n' "$line" > "$RL_DIR/outcome.txt"
        printf 'OVERRIDDEN\n' > "$RL_DIR/state"
        echo "⚠ credential/privacy veto OVERRIDDEN by explicit Boss action. Recorded:"
        echo "  $line"
        echo "ℹ fold this line into the Handoff_Logs/ Dev Log outcome — it is durable evidence (ADR-0006)."
        ;;
```

- [ ] **Step 4: Run — expect PASS**

Run: `bash tests/test_review_loop.sh`
Expected: `─── 53 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add scripts/review-loop.sh tests/test_review_loop.sh
git commit -m "feat(review-loop): finalize (A durable line) + override (E Boss-only tier)"
```

---

## Task 10: shellcheck clean + run_all integration + suite-count drift sync

**Files:**
- Verify: `tests/test_shellcheck.sh` covers the 2 new scripts (it globs `scripts/`)
- Modify: `HANDOFF.md` + any canonical doc carrying `<N> 套件` / assertion totals

`tests/run_all.sh` auto-discovers `test_*.sh` — no registration needed. BUT adding `tests/test_review_loop.sh` bumps the suite count, and `tests/test_doc_freshness.sh` Test 15/16 assert every canonical doc's `<N> 套件` equals `ls tests/test_*.sh | wc -l`. This is the recursive-drift coupling v2.1.5 hit (Dev Log 0045) — must fix in the same change.

- [ ] **Step 1: Run shellcheck on the new scripts**

Run: `bash tests/test_shellcheck.sh`
Expected: PASS. If `review-loop.sh` flags SC1090 (non-constant source), confirm the `# shellcheck source=` directive is present (it is, Task 1 Step 3). Fix any real warnings (match repo: severity=error must be 0; warnings 0).

- [ ] **Step 2: Run the freshness guard to see the drift it now detects**

Run: `bash tests/test_doc_freshness.sh`
Expected: FAIL — Test 15 reports `<N> 套件` mismatch (docs say old N, actual is N+1).

- [ ] **Step 3: Recount and update every canonical doc**

```bash
NSUITE=$(ls tests/test_*.sh | wc -l | tr -d ' ')
NASSERT=$(bash tests/run_all.sh 2>/dev/null | grep -oE '[0-9]+ passed' | awk '{s+=$1} END{print s}')
echo "suites=$NSUITE assertions=$NASSERT"
```

Update the `<N> 套件 / <M> 断言` figures in `HANDOFF.md` (Project Overview 当前版本/构建状态 + Testing 合计) and any other canonical doc Test 15 scans (README / INSTALL / CONTRIBUTING / TEST-SCENARIOS / Mac Project Transfer — only those that actually carry the count). Use the recomputed `$NSUITE`/`$NASSERT`. Do NOT hand-guess — paste the computed values.

- [ ] **Step 4: Run the full suite + freshness — expect green**

Run: `bash tests/run_all.sh`
Expected: all suites pass, including `test_review_loop.sh` and `test_doc_freshness.sh` (Test 15/16 now consistent).

- [ ] **Step 5: Commit**

```bash
git add HANDOFF.md tests/
git commit -m "test(review-loop): integrate suite + sync canonical suite/assertion counts (v2.1.5 drift coupling)"
```

---

## Task 11: P0 self-bootstrap review + handoff cutover (0020 open#2 coupling (a))

**Files:**
- No code. Cross-agent review of Tasks 1-10 + a Dev Log outcome line.

The loop cannot review its own genesis (coupling (a)). Bootstrap with the **existing** ad-hoc mechanism, then cut over to self-hosting.

- [ ] **Step 1: Independent review via the pre-existing mechanism**

The Codex stop-time gate is already live on this repo (it fired 11× this session). Let it review the P0 commits; additionally dispatch a superpowers code-reviewer subagent over `scripts/lib/review-ledger.sh` + `scripts/review-loop.sh` + `tests/test_review_loop.sh`. This is authoring/review separation per §4 (the loop's author cannot self-approve it — same doctrine the loop mechanizes).

- [ ] **Step 2: Address findings via the normal TDD cycle**

For each finding: RED test reproducing it → fix → GREEN → commit. Do NOT mark Task 11 done with open Critical/Important findings.

- [ ] **Step 3: Dogfood once — run P0 on itself**

Manually drive one real loop: `review-loop.sh start --topic p0-self scripts/lib/review-ledger.sh scripts/review-loop.sh` then `record` the bootstrap reviewers' verdicts. Confirm convergence/veto mechanics behave on real input (Gotcha #20: mechanically verify on the real artifact, not synthetic only).

- [ ] **Step 4: Record the cutover in a Dev Log**

Via `/handoff`: a Dev Log entry stating P0 review-loop shipped, bootstrapped by ad-hoc cross-agent review, now self-hosting; future cyclic reviews use `review-loop.sh`. Fold the loop's own `finalize` outcome line into that Dev Log (the durable trace, ADR-0003). Note P1/P2/perf remain per the 0020 open#2 locked order.

- [ ] **Step 5: Commit / push gate**

Do not push without explicit Boss authorization (§4 — push authorization does not carry forward). Report ready-to-push state.

---

## Self-Review

**1. Spec coverage:**
- A two-tier ledger (ADR-0003): content-hash Task 2, ephemeral ledger Tasks 3/7, discard-on-finalize + single durable line Task 9, gitignored scratch Task 1, never `.skill`/dual-sourced — stated in Architecture + File Structure. ✅
- B 6-state ladder + strict 3-consecutive-PASS (CONTEXT.md): enum enforced in C (Task 5), convergence + reset Task 4, wired in `record` Task 8. ✅
- C orchestrator distrust (CONTEXT.md): `rl_validate_round` Task 5, wired so a self-reported verdict lacking content_hash / file:line becomes an ERROR round (not silently dropped) Task 8. ✅
- E credential/privacy veto tiers (ADR-0006): detection Task 6; machinery-never-overrides (hard-stop + exit 3, no auto-continue) Task 8; Boss-may-explicitly-and-recorded `override` Task 9. ✅
- Iteration cap → escalate, no auto-continue (Decision 0009/0010, ADR-0006 consequence): Task 8 + finalize `--cap` Task 9. ✅
- §1 git-orthogonal: content-hash is file-content sha256 not git rev (Task 2); scope = explicit file args; ledger gitignored, never tracked. ✅
- 0020 open#2 coupling (a) self-bootstrap: Task 11 explicit. ✅
- Out-of-scope (P1/P2/perf/D) — none introduced; Scope lock + Task 11 Step 4 restate the locked order. ✅

**2. Placeholder scan:** No TBD/TODO; every code step has complete bash; every test step has runnable assertions with expected counts. ✅

**3. Type/name consistency:** `rl_content_hash`, `rl_append_round`, `rl_round_count`, `rl_convergence_streak`, `rl_is_converged`, `rl_validate_round`, `rl_is_credential_privacy_veto` — defined once (Tasks 2-6), consumed with identical names in CLI (Tasks 7-9). Scratch dir `.review-loop/current` and state tokens `ACTIVE|CONVERGED|VETOED|CAPPED|OVERRIDDEN` consistent across Tasks 7-9. Ledger field order identical in `rl_append_round` (Task 3) and the `verdict=…  ground=` sed anchor (Task 4). ✅

Assertion-count expectations are cumulative (3→7→11→17→25→30→36→44→53) assuming tasks done in order; if executed out of order, treat the per-task delta as the contract, not the running total.

---

## Execution Handoff

Plan complete and saved to `docs/2026-05-17-p0-review-loop-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review between tasks, fast iteration. Best fit here: it structurally enforces the §4 authoring/review separation the P0 loop itself is about (and satisfies coupling (a)'s bootstrap intent).
2. **Inline Execution** — execute tasks in this session via executing-plans, batch with checkpoints.

Which approach?

## Post-implementation note

Assertion-total drift (N1 finding, 2026-05-17): the doc-freshness guard (Test 15/16 in `test_doc_freshness.sh`) covers suite file-count (`<N> 套件`) and `<N>/<N> ✅` platform-compat claims, but does NOT guard per-suite or total assertion figures. These drifted from 653→677 across HANDOFF.md, README.md, README_CN.md, CONTRIBUTING.md, and TEST-SCENARIOS.md without automated detection. Recommend adding a structural guard for per-suite and total assertion figures as a BACKLOG item (v2.1.5-style structural guard, scope: 0019/0020 follow-on — out of P0 scope-lock, do not build now).
