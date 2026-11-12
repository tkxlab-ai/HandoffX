<div align="center">

# HandoffX — Project Handoff System for AI Coding Agents

**Crystallize the tacit knowledge scattered across chat history, personal memory, and private AI caches into one plain-markdown handoff a teammate can pick up in 10 minutes.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v4.1.0-blue.svg)](https://github.com/tkxlab-ai/HandoffX/releases)
[![Tests](https://img.shields.io/badge/tests-38%20suites%20%2F%201260%2B%20assertion%20sites-brightgreen.svg)](#testing)
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
| **Test-Driven Development** | Beck, *Test-Driven Development: By Example* (2002) | New behavior ships only with a RED test first; 38 suites / 1260+ assertion sites gate every change |
| **Trust-boundary threat modeling** | Schneier, threat modeling | `scan-credentials.sh` hard-blocks 11 secret-prefix classes before any write reaches disk |
| **Adversarial review loop** | Multi-round independent code review | Releases pass an N-round Codex adversarial-review cycle until consecutive clean rounds (see Decision Log) |

### The post-write safety chain (runs on every write)

```
scan-credentials.sh   → hard-block plaintext credentials (11 prefix classes)
validate-handoff.sh   → structural integrity (REQUIRED fail / RECOMMENDED warn)
handoff-lint.sh       → per-file frontmatter + body fields (v2)
rotation-reminder.sh  → credential-expiry warning (expired / 7d / 30d)
archive-devlog.sh     → v2: yearly archive of Handoffx_Logs/ (keeps current + previous year)
handoff-xref-lint.sh  → cross-reference check on this write's files (only with --files=)
```

---

## 4. Logical Model

Every piece of information in `HANDOFFX.md` lives in exactly one quadrant, defined by its time dimension and read/write mode:

| Information type | Section | Time dimension | Write mode |
|------------------|---------|----------------|-----------|
| Project context (*why it exists*) | Project Overview / Milestones / Features | low-frequency | manual, rarely edited |
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
├── GOTCHAS.md             all Known Gotchas (single knowledge base; recall reads it)
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
| `/handoffx-memory` | 🧪 Experimental opt-in: migrate local experience entries into the project | Labs |

Natural-language triggers ("hand this off", "pick up where we left off") also activate the skill in Claude Code.

---

## 7. Install / Upgrade / Uninstall

```bash
# Method A — from source (multi-CLI: --claude / --opencode / --codex)
./install.sh --claude

# Method B — single .skill file (offline distribution)
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o handoffx-v4.1.0.skill -d ~/.claude/skills/   # its single top-level dir is <skill-dir> (unzip -l shows it)
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
cp ~/.claude/skills/<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md ~/.claude/commands/

# Method C — manual directory copy (maximum transparency)
cp -R skills/handoffx ~/.claude/skills/handoffx
```

Releases (`.skill` + checksums + SBOM) are published on the **[Releases](https://github.com/tkxlab-ai/HandoffX/releases)** page. See [`INSTALL.md`](INSTALL.md) for the full matrix and uninstall steps.

- **Projects still on a pre-v4 handoff layout**: `/handoffx`, `/handoffx-recall`, `/handoffx-tidy` and `/handoffx-init` detect it, show a dry-run and ask before upgrading; on a yes they run `scripts/handoffx-upgrade.sh --apply` (atomic, rolls back on failure, then validate + postflight + a list of other files still naming the old paths). The fixed order for multi-machine / multi-CLI projects is in [`MIGRATION_GUIDE_v2.md`](MIGRATION_GUIDE_v2.md) §5.6.

---

## 8. Testing

| Type | Coverage | Command |
|------|----------|---------|
| Script units | ~100% (all entry points + boundaries) | `bash tests/run_all.sh` |
| Template structure | 100% (REQUIRED + RECOMMENDED) | `tests/test_validate_handoff.sh` |
| Dual-copy consistency | 100% (dev vs bundle byte-identical) | `tests/test_scripts_sync.sh` |
| Static analysis | 0 warnings at severity=warning | `tests/test_shellcheck.sh` |
| Structural drift guards | cross-doc count/version/asset parity | `tests/test_doc_freshness.sh` (Test 15–17) |

**Total: 38 suites / 1260+ assertion sites / 0 failures**, green on macOS bash 3.2; Linux mawk/POSIX-safe (container-verified at v2.1.2, see Gotcha #15 / Decision 0016; not re-verified in container since). TDD discipline: new behavior ships only after a RED test exists.

---

## 9. Compatibility

| Platform | Status |
|----------|--------|
| macOS (bash 3.2+) | Primary, fully tested |
| Linux (Ubuntu 22.04, mawk) | Container-verified at v2.1.2 (2026-05-11; see Gotcha #15 / Decision 0016); not re-verified in container since; macOS green (needs shellcheck + ruby + unzip + zip + rsync + `LANG=C.UTF-8`) |
| Claude Code / OpenCode / Codex | Native skill install via `install.sh` |
| Droid / Cursor / Copilot / any agent | Compatible via the plain-markdown document layer |

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
