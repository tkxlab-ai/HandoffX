<div align="center">

# HandoffX — Project Handoff System for AI Coding Agents

**Crystallize the tacit knowledge scattered across chat history, personal memory, and private AI caches into one plain-markdown handoff a teammate can pick up in 10 minutes.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v4.6.1-blue.svg)](https://github.com/tkxlab-ai/HandoffX/releases)
[![Tests](https://img.shields.io/badge/tests-49%20suites%20%2F%202965%2B%20assertion%20sites-brightgreen.svg)](#testing)
[![Platform](https://img.shields.io/badge/platform-macOS%20bash%203.2%2B%20%C2%B7%20Linux-lightgrey.svg)](#compatibility)
[![Pure Markdown](https://img.shields.io/badge/format-pure%20markdown%20%C2%B7%20no%20lock--in-success.svg)](#philosophy)

[English](README.md) · [中文](README_CN.md)

</div>

---

> 🔄 **Cross–AI-agent tool by design.** The handoff document is plain markdown — any agent that can read a file (Claude Code · [Codex](https://github.com/openai/codex) · [OpenCode](https://opencode.ai/) · [Droid](https://factory.ai/) · Cursor · Copilot) and any human can read it. The skill commands install natively on **Claude Code / OpenCode / Codex**; everything else stays compatible through the document layer.

---

## Table of Contents

- [1. Why HandoffX?](#1-why-handoffx)
- [2. Philosophy](#2-philosophy)
- [3. Methodology](#3-methodology)
- [4. Logical Model](#4-logical-model)
- [5. How It Works](#5-how-it-works)
- [6. Commands](#6-commands)
- [7. Install / Upgrade / Uninstall](#7-install--upgrade--uninstall)
- [8. Testing](#8-testing)
- [9. Compatibility](#9-compatibility)
- [10. References & Citations](#10-references--citations)
- [11. License & Contributing](#11-license--contributing)

---

## 1. Why HandoffX?

The hardest thing to transfer in software engineering is not code — it is **tacit knowledge**: why a choice was made, where the traps are, what step we are on, who the implicit expert is, what looks doable but is deliberately *not* done.

That knowledge usually hides in places that fail you:

| Hiding place | Fatal flaw |
|--------------|-----------|
| AI chat history | Private, easily lost, incompatible across tools (Cursor cannot see Claude's history) |
| Notion / Confluence | Drifts perennially, decouples from code; nobody trusts it a year later |
| Git commit messages | Fragmented, tells *what* but never *why* |
| The developer's brain | Gone when they leave; blurry after a two-week trip |

**HandoffX replaces all of these with one structurally-enforced markdown artifact.** `HANDOFFX.md` lives at the project root, evolves with the code, is transparent to every AI tool, and **a human can read it directly**.

> 💡 The unit of handoff is the markdown, not the conversation. Tools change; the document survives. A new owner runs `/handoffx-recall` and is contributing within 10 minutes.

---

## 2. Philosophy

HandoffX's design was reviewed against a panel of domain authorities. Each principle lands directly in code — not as aspiration but as executable assertion.

### Don Norman — *The Design of Everyday Things* (1988)

> "If users can't tell what your system did, it doesn't matter that it worked."

- **Gulf of Evaluation** — every write echoes *what it did* and *what the checks found*; the user never guesses.
- **Gulf of Execution** — the command name *is* the action (`/handoffx` = write, `/handoffx-recall` = read, `/handoffx-tidy` = reorganize); no manual required.
- **Feedback** — post-write checks use a **three-state** signal `✅ pass / ⚠️ found / ❌ failed`; a missing script counts as failed and is *never* disguised as "passed".

### Edsger W. Dijkstra — *A Discipline of Programming* (1976)

> "Program testing can be used to show the presence of bugs, but never to show their absence."

- **Invariants over conventions** — computable predicates replace fuzzy judgement (duplicate detection = *exact changed-file-set equality + 10-minute window*, not LLM similarity).
- **Atomic commits** — `archive-devlog.sh` writes the new archive and integrity-checks it *before* the atomic `mv`; a power loss mid-operation loses no data.
- **Separation of concerns** — Core / Init / Labs are layered; each entry point does exactly one thing, independently testable and composable.

### Ikujiro Nonaka — *The Knowledge-Creating Company* (1995), SECI model

> "The essence of creating knowledge is the conversion of tacit knowledge into explicit knowledge."

- **Externalization** (tacit → explicit) — the Decision Log enforces six fields: *context / options A·B·C / choice / rejection reason / cost-to-revert*.
- **Ba** (shared context) — a `Reader Notes` section lets later readers append `YYYY-MM-DD [name]: this Decision's assumption no longer holds` — the document becomes a dialogue, not a broadcast.
- **Respect for uncertainty** — an `Open Questions / Mysteries` section absorbs "seen but not understood" knowledge; *if you can't fill it, write `—`, never fabricate* is a hard rule.
- **Knowledge is not rewritten** — `/handoffx-tidy` may reorder and backfill missing fields with `—`, **but never merges, summarizes, or polishes** user-authored Dev Log / Decision / Gotcha prose. Tacit knowledge must not be paraphrased by an AI.

### Panel inspirations (5-persona audit)

The template and safety model additionally absorbed: **Kent Beck** — *Extreme Programming Explained* (TDD discipline, RED→GREEN→REFACTOR); **Bruce Schneier** — *Secrets and Lies* / threat-modeling (the credential-scan trust boundary); **Andrew S. Grove** — *High Output Management* (the handoff as a managerial leverage artifact).

---

## 3. Methodology

| Method | Source / inspiration | How HandoffX implements it |
|--------|----------------------|---------------------------|
| **SECI knowledge conversion** | Nonaka & Takeuchi, *The Knowledge-Creating Company* (1995) | `/handoffx` = Externalization, `/handoffx-recall` = Internalization, `/handoffx-tidy` = Combination/re-organization |
| **Computable invariants** | Dijkstra, *A Discipline of Programming* (1976) | Duplicate detection by exact set-equality + time window; no LLM similarity heuristics |
| **Atomic file operations** | Crash-safe systems design (write-verify-rename) | `archive-devlog.sh`: stage → integrity-check → atomic `mv` |
| **Discoverability / feedback** | Norman, *The Design of Everyday Things* (1988) | Verb-as-command naming; three-state post-write echo |
| **Test-Driven Development** | Beck, *Test-Driven Development: By Example* (2002) | New behavior ships only with a RED test first; 49 suites / 2965+ assertion sites gate every change |
| **Trust-boundary threat modeling** | Schneier, threat modeling | `scan-credentials.sh` detects 14 credential-pattern classes and returns a failure for callers to handle — vendor prefixes, PEM key headers, and self-hosted Git forge tokens written literally (`Authorization: token <value>`, `*GIT*_TOKEN=<40-hex>`); `$VAR` / `vault://` references and bare commit SHAs pass, a literal under a table column headed password / token / secret / 密码 is also blocked, and anything else outside the listed patterns is not detected (`--help`) |
| **Adversarial review loop** | Multi-round independent code review | Releases pass an N-round Codex adversarial-review cycle until consecutive clean rounds (see Decision Log) |

### The post-write safety chain (runs on every write)

```
scan-credentials.sh   → detect plaintext credentials (14 pattern classes)
validate-handoff.sh   → structural integrity (REQUIRED fail / RECOMMENDED warn)
handoff-lint.sh       → per-file frontmatter + body fields (v2)
rotation-reminder.sh  → credential-expiry warning (expired / 7d / 30d)
archive-devlog.sh     → v2: yearly archive of Handoffx_Logs/ (keeps current + previous year)
handoff-xref-lint.sh  → cross-reference check: automatic stable set for canonical v2 + explicit --files= additions
```

For a canonical `HANDOFFX.md` carrying the `<!-- HANDOFF v2 schema -->` marker only, postflight always includes the main file, `GOTCHAS.md`, and `Handoffx_Decisions/INDEX.md` when the index exists in its xref checks—even without `--files=`. Use `--files=` only to append this round’s logs, Decisions, and all other explicitly changed files outside that stable set; the combined set is deduplicated. Omitting it checks only the automatic stable set, not all historical logs or Decisions. Other ad-hoc/v1 targets retain explicit-`--files=`-only xref behavior, with no automatic set. An explicitly empty CSV or one containing empty items is rejected; the automatic set cannot turn invalid input into a passing result.

---

## 4. Logical Model

Every piece of information in `HANDOFFX.md` lives in exactly one quadrant, defined by its time dimension and read/write mode:

| Information type | Section | Time dimension | Write mode |
|------------------|---------|----------------|-----------|
| Project direction (*why it exists*) | Project Overview: canonical `hx:continuity`; other sections reference it | low-frequency | evidence-based write/init or authorized organization |
| Current state (*where are we now*) | Current State | refreshed every `/handoffx` | **overwrite** (latest only) |
| Work stream (*what happened*) | Development Log | strictly reverse-chronological | **append** (never overwrite) |
| Decision rationale (*why we chose A*) | Decision Log | on trade-off | **append** |
| Traps hit (*tacit pitfalls*) | Known Gotchas | on encounter, stable numbering | **append** (never renumber) |
| Unknown territory | Open Questions | on observation | **append** |
| Later-reader feedback | Reader Notes | any reader may annotate | **append** |
| Credentials / refs / conventions | Credentials / References | low-frequency | manual |

---

## 5. How It Works

Since v2.0.0, `HANDOFFX.md` is no longer a single file — a large project's single-file handoff measured 121K+ and ate 47% of the model context window. v2 splits it into a **four-piece set**:

```
<project root>/
├── HANDOFFX.md            v2 schema marker + 11 design sections
│                          + Dev Log / Decision / Gotchas pointer stats
├── GOTCHAS.md             all Known Gotchas (single knowledge base; details on demand)
├── Handoffx_Logs/         Dev Log, one file per entry
│   └── <NNNN>-<YYYY-MM-DDTHHMM>-<slug>.md
└── Handoffx_Decisions/    Decision Log, one file per entry
    └── <NNNN>-<YYYY-MM-DD>-<slug>.md
```

Result: main file compressed ~77%, `recall` token cost down ~63%, while full history stays addressable on demand.

---

## 6. Commands

| Command | Action | Cognitive activity |
|---------|--------|--------------------|
| `/handoffx` | Append current work to the Dev Log (+ Decision routing + post-checks) | Externalize |
| `/handoffx-recall` | Read & report; read-only, no git dependency | Internalize |
| `/handoffx-recall <N>` | Same, reading the latest N Dev Log entries | Internalize |
| `/handoffx-tidy` | Reorder / backfill skeleton — never merges or rewrites content | Re-organize |
| `/handoffx-init` | Create a minimal viable handoff starting point | Bootstrap |
| `/handoffx-memory` | Cross-machine memory backup: status / on / off / sync (on by default) | Labs |

Natural-language triggers ("hand this off", "pick up where we left off") also activate the skill in Claude Code.

**Short startup, bounded recall:** Show `🚀启动handoffX项目交接流程.` once. Normal write confirmations keep their 200-character visible budget; report necessary errors normally. Recall reports are not subject to the 120/200-character write-confirmation limit.

`/handoffx-recall [N]` defaults to project direction and current handoff context plus the latest six bounded log summaries. It does not load all GOTCHAS, completed history, optional background or recursively linked evidence. New logs may contain a `<!-- hx:recall -->` summary (2048 UTF-8 bytes maximum); unchanged legacy logs are returned whole only when small, otherwise metadata-only with an explicit warning that details were not loaded. Current pending tasks remain independent of N, including older blocked or deferred work. All pending content is retained, including checked items that may contain live constraints; only the explicitly separated `hx:done` history is excluded.

Accurate continuation without losing direction—not a compression ratio—is the acceptance criterion. Project Overview holds one canonical `<!-- hx:continuity -->` … `<!-- /hx:continuity -->` block (≤4096 UTF-8 bytes): overall goal, beneficiaries/problem, success criteria, scope/non-goals, technical/security/compatibility constraints and authorization gates, and effective decisions with reasons/sources. Its original text is retained as `continuity_status=explicit_unverified`. Without a block, the entire legacy Overview is retained unchanged at ≤4096 bytes as `continuity_status=legacy_unverified`; a larger legacy Overview fails with empty stdout, never deferred wholesale. Duplicate, misplaced, unclosed or damaged markers fail; blocks cannot cross sections, and fenced examples are not real markers.

Legacy preservation covers only the Overview section, ending at the next unfenced `#` or `##` heading—not the whole main file. Use `###` or deeper subheadings inside Overview: a sibling `## Goals` is outside this boundary, so missing goals/criteria must still be reported under legacy_unverified. Recall never folds headings into Overview; restructuring requires authorized write/tidy.

Empty or whitespace-only blocks fail; a nonempty but incomplete block remains explicit_unverified and requires visible semantic gap reporting. `overview_outside_continuity_bytes=N` counts Overview bytes outside the block, including heading/background but excluding markers—not meaning or coverage; when N>0, briefly disclose that optional background was not loaded.

Both statuses mean structural extraction only, not semantic completeness. `hx:recent` holds phase target/acceptance, stop point, work location/unfinished changes, validation command/date/scope and unverified boundaries, and current blockers/dependencies/risks/unknowns. `hx:pending` is the sole current TODO source; other sections reference it rather than create task copies. Maintain current directional facts only in continuity, not in a second snapshot; active critical facts cannot live only in deferred material. Update these areas only during write/init or explicitly authorized organization, never read-only recall; schema 2 is unchanged.

The runtime still caps current state at 12288 bytes, each log summary at 2048 bytes, and total stdout (including metadata/newlines) at 24576 bytes. Malformed summaries or oversized mandatory context fail nonzero with empty stdout, without truncating tasks. Do not bypass this by automatically reading whole files. These are UTF-8 byte limits, not model-token measurements. Only optional background outside continuity and historical detail are on demand; recall does not rewrite history.

The report starts with time and enumerates coverage gaps/conflicts in goal, phase target/acceptance, success criteria, scope, constraints, effective decisions/reasons/sources, work location/unfinished changes, validation command/date/scope, and blockers/unknowns. Missing means “not recorded/to confirm,” not “none”; do not infer goals from titles/TODOs or silently resolve Overview/recent conflicts by the latest timestamp. Ask before goal-changing or irreversible action if direction is missing/conflicting, without blocking every harmless task. The report then **ends with “Continue here”: where work stopped → current TODO list → next action (last)**. Put blockers beside their tasks; append no further summary, sources or risk chapter. Missing stop points stay unknown and suggested actions stay labeled suggestions. Use the newest numbered log epoch for date/timezone and elapsed time, never mtime. Historical tests are not current health checks. Recall is read-only; it does not run tasks/tests, hide host tool cards, or pass the report through `handoff-runtime.sh reply`.

**Per-write root intent:** installed global writers require a leading `--expect-root "<confirmed absolute project root>"`. Each invocation checks both its cwd and its selected target; an earlier context check does not authorize a later operation. Project installations remain manifest-bound. Unbound source tools retain explicit-target development use, without claiming identity authentication or a filesystem sandbox.

**Verification continuity:** after saving new structured claims, run `handoff-runtime.sh verification-check --current --require --match-file Handoffx_Logs/<latest-log>` to compare recent with the newest log. Pending-only claims, older logs, the main file and outside copies cannot satisfy that comparison. Success means matching declared fields, not proof of actual test execution; unspecified execution times remain unknown.

Script helpers (run with `bash <skill-path>/scripts/hx.sh …`):

| Helper | Actual scope |
|--------|--------------|
| `doctor --root <project>` | Read-only basic diagnostics: project/script paths, CLI discovery, and the reported Claude config path. Rejects missing/symlink four-piece paths; requires readable regular main/Gotchas files and readable/traversable (`r+x`) Logs/Decisions directories. Then runs structure validation, per-entry lint, and the Dev Log pointer-count check via `validate-handoff.sh --check-stats --readiness`. The count check rejects a missing, linked, or unreadable/untraversable Logs directory. No repairs, credential scan, or rotation check; not the full postflight. |
| `now` / `now --epoch` | `now` keeps its three output lines: `human=…`, `fm=…`, `fn=…`. `--epoch` adds an optional fourth line, `epoch=<Unix seconds>`, from the same clock read; new entries may store it as `epoch:` for timezone-safe duplicate checks. |

**Cross-machine backup (on by default):** every handoff exports this machine's Claude Code memory and a metadata-only session list (Claude Code, Codex and OpenCode sessions of this project) to `.agent-sessions-sync-hx/machines/<machine>/`; recall reads the other machines' backups (bounded, read-only) and never imports them into `~/.claude`. Files are staged and credential-scanned before per-file publication (**not a batch transaction**). A backup failure only warns; the handoff still succeeds. `/handoffx-memory off` turns it off. See `skills/handoffx/references/handoffx-memory.md`.

---

Compatibility: scattered unfinished/ambiguous checkboxes elsewhere in the main file now stop recall with a location; reconcile them explicitly rather than guessing that old items are done. Unanchored Current State prose is retained within budget. The entire pending block is retained, including standalone checked lines: a checkbox cannot prove that embedded approvals, risks or follow-up decisions are obsolete. Oversized pending fails closed rather than silently dropping context. A legacy log with an unclosed code fence and no hx:recall mention yields warning-labelled metadata only; ambiguous summary-bearing logs still fail.

## 7. Install / Upgrade / Uninstall

```bash
# Method A — from source (multi-CLI: --claude / --opencode / --codex / --gemini / --antigravity)
./install.sh --claude

# Method B — offline install/upgrade
# Place matching install.sh and one handoffx-v4.6.1.skill in a dedicated directory
bash ./install.sh --claude --opencode --codex
# Installer binds command-shims/*-{recall,tidy,memory,init}.md; do not copy verbatim.
# Repeated cp -R nests directories; copying only the skill leaves stale aliases.
# See INSTALL.md for guarded fresh manual installs; upgrade via the installer.

# Method C — Claude Code plugin (TKX marketplace; Claude Code only)
/plugin marketplace add tkxlab-ai/marketplace
/plugin install handoffx@tkxlab
# Plugin commands are namespaced (/handoffx:recall, /handoffx:write, …).
# Use either the plugin or install.sh for Claude Code, not both (install.sh warns when it finds the plugin).
```

Releases (`.skill` + checksums + SBOM) are published on the **[Releases](https://github.com/tkxlab-ai/HandoffX/releases)** page. See [`INSTALL.md`](INSTALL.md) for the full matrix and uninstall steps.

- **Projects still on a pre-v4 handoff layout**: `/handoffx`, `/handoffx-recall`, `/handoffx-tidy` and `/handoffx-init` detect it, show a dry-run and ask before upgrading; on a yes they run `scripts/handoffx-upgrade.sh --apply` (atomic, rolls back on failure, then validate + postflight + a list of other files still naming the old paths). The fixed order for multi-machine / multi-CLI projects is in [`MIGRATION_GUIDE_v2.md`](MIGRATION_GUIDE_v2.md) §5.6. Outside a git work tree it first packs the old pieces into a verified `.handoffx-pre-upgrade-<time>.tar.gz` (`--no-backup` opts out); `HANDOFFX_SCAN_PRUNE="dirA dirB"` adds directories the leftover scan skips.
- **Synced project trees** (Syncthing / Dropbox / iCloud): `handoffx-upgrade.sh` names the sync marker it finds above the project and `--apply` refuses until you pause the sync and pass `--sync-paused`.
- **Custom Claude config root**: a non-empty `CLAUDE_CONFIG_DIR` takes precedence for global Claude installation paths (`skills/` and `commands/`), including on WSL. Without it, the installer retains its WSL detection / `$HOME/.claude` fallback. Project installs still use `<project>/.claude/`; the manual examples above assume the default root and must be adjusted for a custom root. This does not relocate the memory-sync source, which still uses `$HOME/.claude/projects/<encoded>/memory/`.
- **Fill missing project pieces**: `./install.sh --template <project>` supplements the selected/default CLI installation with missing `HANDOFFX.md`, `GOTCHAS.md`, `Handoffx_Logs/`, and `Handoffx_Decisions/`. Existing pieces are preserved, even with `--force`; legacy layouts and path-type/symlink conflicts are refused. It does not fill in project-specific content or provide a batch-atomic scaffold rollback.
- **Install backups are kept**: what an install displaces stays in `~/.handoffx-install/bak.<ts>/`; the run ends with a one-line `install.sh --restore <bak>` and `--purge-backups` removes older backups.
- **Sourcing the shared lib**: `scripts/lib/handoff-v2.sh` must be sourced under bash (`bash -c '. <skill-path>/scripts/lib/handoff-v2.sh && …'`); under zsh or another shell it refuses to load (❌, no function defined) instead of writing with empty names or numbering without a lock. For the write flow use `scripts/hx.sh`; do not source the lib directly.

---

## 8. Testing

| Type | Coverage | Command |
|------|----------|---------|
| Script units | ~100% (all entry points + boundaries) | `bash tests/run_all.sh` |
| Template structure | 100% (REQUIRED + RECOMMENDED) | `tests/test_validate_handoff.sh` |
| Dual-copy consistency | 100% (dev vs bundle byte-identical) | `tests/test_scripts_sync.sh` |
| Static analysis | 0 warnings at severity=warning | `tests/test_shellcheck.sh` |
| Structural drift guards | cross-doc count/version/asset parity | `tests/test_doc_freshness.sh` (Test 15–17) |

**Current inventory: 49 suites / 2965+ static assertion sites.** The final closeout candidate passed full regression on macOS Bash 3.2 and Linux Ubuntu 22.04 non-root/mawk, including 71 Python driver tests on each platform. Linux skips only two macOS sandbox-exec checks. Real host results remain separate: model progress messages, unsupported command evidence and inherited MCP side effects can fail the strict end-to-end contract even when saved state and validators pass. Evidence: `wip/reviews/iteration-closeout/迭代结果.md`. TDD discipline: behavior changes retain RED/GREEN evidence.

The follow-up driver has 85 offline tests verified on macOS and in a non-root Linux container. Headless entry injection, initialized-host and protected cold-start results are recorded separately; see the host-mode section in `TEST-SCENARIOS.md` and `wip/acceptance-completion/FINAL-REPORT.md`.

---

## 9. Compatibility

| Platform | Status |
|----------|--------|
| macOS (bash 3.2+) | Primary, fully tested |
| Linux (Ubuntu 22.04, mawk) | Container-verified at v4.1.1 (non-root, all suites green at that version; see Dev Log 0081, Gotcha #15 / Decision 0016); macOS green (needs shellcheck + ruby + unzip + zip + rsync + `LANG=C.UTF-8`) |
| Claude Code / OpenCode / Codex | Native skill install via `install.sh` |
| Droid / Cursor / Copilot / any agent | Compatible via the plain-markdown document layer |

Support matrix (OS / shell / CLI / project shape): see the 支持矩阵 (support matrix) section in [`INSTALL.md`](INSTALL.md).

---

## 10. References & Citations

### Books & models

| Work | Author | Used for |
|------|--------|----------|
| *The Design of Everyday Things* (1988) | Donald A. Norman | Discoverability, Gulf of Execution/Evaluation, feedback model |
| *A Discipline of Programming* (1976) | Edsger W. Dijkstra | Computable invariants, atomic operations, separation of concerns |
| *The Knowledge-Creating Company* (1995) | Nonaka & Takeuchi | SECI tacit↔explicit conversion; Ba; the externalization template |
| *Test-Driven Development: By Example* (2002) | Kent Beck | RED→GREEN→REFACTOR release discipline |
| *Extreme Programming Explained* (1999) | Kent Beck | Continuous, small, verified change |
| *High Output Management* (1983) | Andrew S. Grove | The handoff as managerial leverage |
| Threat modeling / *Secrets and Lies* (2000) | Bruce Schneier | Credential-scan trust boundary |

### Cross-tool ecosystem referenced

- **[OpenAI Codex](https://github.com/openai/codex)** — terminal AI coding agent (native install target)
- **[OpenCode](https://opencode.ai/)** — MIT, provider-agnostic terminal agent (native install target)
- **[Factory Droid](https://factory.ai/)** — agent-native CLI (document-layer compatible)

### Internal knowledge assets

`Handoffx_Decisions/` (trade-off rationale, 18+ entries) · `Handoffx_Logs/` (development journal, 46+ entries) · `GOTCHAS.md` (accumulated pitfalls) — these are the project dogfooding its own methodology.

---

## 11. License & Contributing

- **License**: MIT — see [`LICENSE`](LICENSE).
- **Contributing**: this GitHub repository is a publish mirror; see [`CONTRIBUTING.md`](CONTRIBUTING.md). Bug reports via [Issues](https://github.com/tkxlab-ai/HandoffX/issues); security via [private advisory](https://github.com/tkxlab-ai/HandoffX/security/advisories/new) or the contact listed in [`SECURITY.md`](SECURITY.md).

---

<div align="center">

**[tkxlab-ai/HandoffX](https://github.com/tkxlab-ai/HandoffX)**

Pure markdown · No vendor lock-in · Built to be read by humans and every AI agent alike

</div>
