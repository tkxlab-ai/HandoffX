# Agent Team Heuristic Audit — Handoff

**Date**: 2026-04-30  
**Scope**: Handoff skill source, docs, scripts, tests, install/release flow, dogfood `HANDOFF.md`  
**Method**: 5 expert personas x 5 review rounds + local evidence verification + 3 synthesis rounds  
**Output**: findings, score, feature pruning, must-add features, iteration roadmap

---

## 1. Expert Team

| Expert | Persona | Primary Lens | Score |
|---|---|---|---:|
| Expert 1 | Don Norman + Julie Zhuo | UX, onboarding, feedback loops | 76 |
| Expert 2 | Dijkstra + Lamport | invariants, shell semantics, formal state | 74 |
| Expert 3 | Nonaka + Weick | tacit knowledge, sensemaking, SECI | 78 |
| Expert 4 | Jobs + Christensen + Cagan | product strategy, JTBD, scope | 72 |
| Expert 5 | Liskov + Gene Kim + Majors | reliability, release integrity, operations | 68 |

**Aggregate score**: **73.6 / 100**  
**Verdict**: strong core concept and unusually good knowledge-transfer instincts, but trust is now constrained by release integrity, product-scope drift, and too many AI-only invariants that are not machine-checked.

---

## 2. Three Synthesis Rounds

**Round A — consensus**: the core promise is sharp, but the product is drifting from a lightweight ritual into a broader platform. All experts also agreed that "why" is captured better than it is reactivated.

**Round B — evidence**: local checks confirmed `validate-handoff.sh HANDOFF.md` exits 0 while `tidy-handoff.sh HANDOFF.md` exits 1; release dry-run includes `HANDOFF.md` and `memory/`; `--exclude='commands'` excludes `skills/handoff/commands/`; no visible CI workflow exists; `test_bundle_sync.sh` compares command paths against themselves.

**Round C — priority**: fix release privacy and command packaging first, then add machine-checkable handoff readiness, split Core/Labs, reduce first-use burden, and make recall surface related decisions.

---

## 3. Severity Findings

### P0-1: Release packaging can leak private project memory

**Evidence**:
- `release.sh:77-89` stages source via `rsync`; excludes omit `/HANDOFF.md`, `/HANDOFF.archive.md`, and `/memory/`.
- Dry-run output includes `HANDOFF.md`, `memory/.sync-enabled`, and `memory/*.md`.
- `CHANGELOG.md:23` claims this class was fixed in v1.0.

**Fix**:
- Add anchored excludes: `/HANDOFF.md`, `/HANDOFF.archive.md`, `/HANDOFF.md.bak`, `/memory/`.
- Add release staging test that fails if forbidden paths appear.
- Treat `memory/` as private-by-default in release rules.

### P0-2: `release.sh` can exclude skill command shims

**Evidence**:
- `release.sh:88` uses `--exclude='commands'`.
- `CHANGELOG.md:103-104` records a prior fix to anchor this as `--exclude='/commands'`.
- Dry-run did not include `skills/handoff/commands/*`.

**Fix**:
- Remove the exclude if no root `commands/` directory exists, or anchor it as `/commands`.
- Add package-content assertions for `skills/handoff/commands/handoff-recall.md`, `handoff-tidy.md`, and `handoff-memory.md`.

### P1-1: Validator passes files that are not recall-ready

**Evidence**:
- `validate-handoff.sh` only checks sections and global anchor presence.
- `tidy-handoff.sh` detects Dev Log order and required-field issues.
- Current dogfood `HANDOFF.md`: validate OK, tidy reports 9 ordering issues and 1 missing field.

**Fix**:
- Add `handoff-lint.sh` or extend validator with `--readiness`.
- Check exactly one Dev Log section, exactly one anchor inside it, reverse ordering, required entry fields, and duplicate header collisions.

### P1-2: Core product promise is stale

**Evidence**:
- `README.md:59` and `skills/handoff/SKILL.md:8` say "three commands, five scripts".
- Current product has `/handoff-memory` plus `encode-cc-path.sh` and `sync-memory.sh`, making 4 commands and 7 scripts.
- `HANDOFF.md:87` still says 3 auxiliary scripts in one place.

**Fix**:
- Reframe docs as **Core**: `/handoff`, `/handoff-recall`, `/handoff-tidy`; **Labs**: `/handoff-memory`.
- Remove exact script counts from prose or generate/check them.

### P1-3: Too many important invariants are prose, not mechanisms

**Evidence**:
- Duplicate detection is specified in `handoff-write.md:11-31`, but no deterministic helper enforces it.
- Current State overwrite, Decision Log append, and post-check interpretation are AI behavior contracts.
- `archive-devlog.sh:130-164` deduplicates archive entries by header line only.

**Fix**:
- Add deterministic helpers for Dev Log insertion, duplicate detection, and Current State overwrite.
- Use stable entry IDs or full-body hashes for archive dedup, not minute-precision headers.

### P1-4: Recall underuses decision knowledge

**Evidence**:
- README treats decisions as highest-leverage "why" knowledge.
- `handoff-recall.md:28-35` excludes Decision Log by default unless the user asks.

**Fix**:
- During recall, include only decisions referenced by latest N Dev Log entries, capped at 1-3.
- If no links exist, show "Decision context skipped; ask to read Decision Log."

### P1-5: First-use burden is too high

**Evidence**:
- Template has 15 sections plus stakeholder hard questions, milestones, features, credentials, infra, testing, references, decisions, and logs.
- `install.sh:381` asks for Project Overview + Architecture; `SKILL.md:91` asks for Project Overview + Architecture + Coding Conventions.

**Fix**:
- Add `/handoff-init`: 3-minute guided minimal handoff.
- Minimal template: Project Overview, Current State, Build/Test, Known Gotchas, Development Log.
- Keep the full template as advanced expansion.

### P1-6: Memory sync changes the privacy and product boundary

**Evidence**:
- `handoff-memory.md:18-20` copies Claude Code memory into project `./memory/`.
- `sync-memory.sh:90-104` copies files before credential scanning.
- README positions cross-tool transparency, but memory implementation is Claude-path specific.

**Fix**:
- Move `/handoff-memory` to Labs or a separate extension.
- Add manifest metadata: source tool, timestamp, sensitivity, provenance.
- Scan before final placement by copying to temp first, then commit clean files.

### P2 Cluster

- Rotation reminder schema mismatch: template has service/location, while `rotation-reminder.sh:40-48` parses an expiry column. Add `过期日期` or explicit "no expiry column" messaging.
- Recall argument semantics conflict: reference rejects `0`/negative, while other docs fall back to 5. Choose one; recommended behavior is reject non-positive integers.
- Bundle sync test is not a real drift test: `tests/test_bundle_sync.sh:8-11` points dev and bundle command paths to the same directory.

---

## 4. Features To Prune Or Demote

- `/handoff-memory`: demote to Labs or extension; useful but expands privacy and state surface.
- Server / Infra Status SSH capture: remove from core write flow; surprising operational automation in a markdown tool.
- Manual install variants: move to appendix; canonical path should be `./install.sh`.
- Historical `Release/v*` directories: move to tags/releases long-term; active repo noise is high.
- `FORCE=1` release bypass: remove or hard-restrict; it conflicts with safety/auditability.

---

## 5. Must-Add Features

1. `release.sh --dry-run-audit`: validates staging without writing release artifacts.
2. Release manifest: expected files, forbidden files, checksums, generated timestamp.
3. `handoff-lint.sh`: formal well-formedness and recall-readiness checker.
4. `/handoff-init`: guided minimal first handoff.
5. `/handoff --preview`: show exact write before mutation.
6. `/handoff --undo`: revert last generated write using backup or structured marker.
7. Related-decision recall: pull linked decisions for latest Dev Logs.
8. `/handoff-doctor`: install and command registration diagnostics.
9. Spec drift test: compare prose claims for command/script counts against filesystem.
10. CI: shellcheck, `tests/run_all.sh`, release dry-run audit, artifact content checks.

---

## 6. Roadmap

- **v1.2 Trust / Release Integrity**: fix release excludes, package-content tests, manual install docs, and CI/local release gate.
- **v1.3 Formal Handoff Readiness**: add `handoff-lint.sh`, stronger anchor validation, stable Dev Log identity, and write-path fixture tests.
- **v1.4 Product Coherence**: split Core/Labs, demote `/handoff-memory`, replace stale "three commands/five scripts" copy.
- **v1.5 Activation**: add `/handoff-init`, preview, undo, related-decision recall, and recent Reader Notes recall.

---

## 7. Philosophical Finding

The project's strongest idea is not "a complete knowledge system." It is a ritual: when meaningful work ends, leave a durable note that future humans and agents can trust.

The current system captures tacit knowledge well, but it sometimes adds more containers instead of improving re-entry into practice. The next iteration should preserve the sharp core: small, safe, reversible, machine-checkable handoff.
