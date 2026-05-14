# INSTALL — Complete install / upgrade / uninstall / maintenance reference for handoff

> README.md describes **what handoff is** (project-level handoff documentation system with HANDOFF.md + GOTCHAS.md + per-file Dev Log + Decision Log). This document describes **how to install, upgrade, uninstall, and maintain it** — every command annotated.

---

## 📖 Table of Contents

- [0. File location cheat sheet](#0-file-location-cheat-sheet)
- [1. Install](#1-install)
  - [1.1 Method A — Source + install.sh (recommended)](#11-method-a--source--installsh-recommended)
  - [1.2 Method B — Single `.skill` file](#12-method-b--single-skill-file)
  - [1.3 Method C — Manual directory copy](#13-method-c--manual-directory-copy)
  - [1.4 Method D — curl one-liner](#14-method-d--curl-one-liner)
  - [1.5 Remote / SSH deployment](#15-remote--ssh-deployment)
- [2. First-time project initialization (v2 four-file layout)](#2-first-time-project-initialization-v2-four-file-layout)
- [3. Upgrade](#3-upgrade)
- [4. Uninstall](#4-uninstall)
- [5. Verify / Self-check](#5-verify--self-check)
- [6. Release (developers)](#6-release-developers)
- [7. Daily maintenance commands](#7-daily-maintenance-commands)
- [8. Troubleshooting](#8-troubleshooting)

---

## 0. File location cheat sheet

```
~/.claude/                              # Claude Code target
├── skills/handoff/                     # Skill body (installed globally)
│   ├── SKILL.md                        # Skill entry / system prompt
│   ├── VERSION                         # Sidecar version
│   ├── references/*.md                 # Command specs
│   ├── scripts/                        # Helpers
│   │   ├── *.sh                        # scan-credentials / validate-handoff / etc.
│   │   └── lib/install-output-style.sh # Unified install.sh output helper
│   ├── command-shims/*.md              # Slash command shims source
│   └── assets/HANDOFF.template.md      # HANDOFF.md skeleton
└── commands/                           # Slash shims (so /handoff-* are not fuzzy-matched to /handoff)
    ├── handoff-recall.md
    ├── handoff-tidy.md
    ├── handoff-memory.md
    └── handoff-init.md

~/.config/opencode/skills/handoff       # OpenCode target (when --opencode)
~/.agents/skills/handoff                # Codex target (when --codex; Codex CLI native discovery)

<project-root>/                         # Per-project state (v2 four-file layout)
├── HANDOFF.md                          # Main file (header: <!-- HANDOFF v2 schema -->)
├── GOTCHAS.md                          # Known Gotchas knowledge base (v2 sibling)
├── Handoff_Logs/                       # Dev Log per-file (v2)
│   └── <NNNN>-<timestamp>-<slug>.md
├── Handoff_Decisions/                  # Decision Log per-file (v2)
│   └── <NNNN>-<date>-<slug>.md
├── Handoff_Logs.archive/               # Yearly archive (v2 replaces HANDOFF.archive.md)
│   └── <YYYY>/
└── .claude/skills/handoff/             # (optional) project-level install; overrides global
```

> v1 users → run `/handoff-tidy` in your project root: it detects the v1 single-file layout and prompts for atomic migration to v2. Failed migrations auto-roll back. See `MIGRATION_GUIDE_v2.md`.

---

## 1. Install

### 1.1 Method A — Source + install.sh (recommended)

For long-term upgrades, team deployment, or CI.

```bash
git clone https://github.com/tkxlab-ai/handoff.git
cd handoff
./install.sh                     # auto-detect installed CLIs (Claude / OpenCode / Codex)
./install.sh --claude            # Claude Code only
./install.sh --opencode          # OpenCode only
./install.sh --codex             # Codex CLI only
./install.sh --project /path     # Project-level install (Claude Code in <project>/.claude/)
./install.sh --template /path    # Create HANDOFF.md in <path> without installing skill body
./install.sh --uninstall         # Remove all global installs
./install.sh --dry-run           # Preview without writing
./install.sh --force             # Overwrite (re-install over existing)
./install.sh --help              # Full flag reference
```

The installer renders the unified TKX banner across all targeted CLIs (output of `./install.sh --claude` — the live install path):

```
===============================================================
  📦  handoff Installation  v2.2.2
===============================================================
🔍  Checkpoint 1 — Preflight: targets detected
    ✅ Claude Code   targeted
📂  Checkpoint 2 — Global install
🧹  ...per-CLI install + legacy cleanup phases...
✓   Checkpoint N — Validation
===============================================================
  🎉  handoff v2.2.2 installed
===============================================================
```

> handoff's checkpoint count is dynamic because the multi-CLI install (`--claude` / `--opencode` / `--codex` separately) means different runs hit different phases. The top + bottom banners remain identical to the other 4 TKX skills (gitx-release / mac-release / 1by1 / ClaudeMeX).

### 1.2 Method B — Single `.skill` file

For out-of-band distribution (email, shared drive, scp).

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o handoff-v<VERSION>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp ~/.claude/skills/handoff/command-shims/handoff-{recall,tidy,memory,init}.md ~/.claude/commands/
```

> `install.sh` from the same source repo (or any newer .skill bundle) auto-bootstraps from a `handoff-*.skill` or `handoff-*-source.tar.gz` placed next to it. So you can also run `./install.sh --claude` against a freshly-downloaded .skill if you keep the unpacked installer adjacent.

### 1.3 Method C — Manual directory copy

Maximum transparency, zero install script.

```bash
# Global
cp -R skills/handoff ~/.claude/skills/handoff
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp skills/handoff/command-shims/handoff-{recall,tidy,memory,init}.md ~/.claude/commands/

# Project-level (overrides global for that project)
cp -R skills/handoff /path/to/project/.claude/skills/handoff
chmod +x /path/to/project/.claude/skills/handoff/scripts/*.sh
```

### 1.4 Method D — curl one-liner

**Not supported as a pure `curl install.sh | bash` one-liner.** The installer requires the full bundle (SKILL.md, scripts/, scripts/lib/install-output-style.sh, command-shims/, references/, assets/). Use **Method B** (`.skill` download + unzip) or **Method A** (clone) instead.

If a fetch-and-install one-liner is needed, combine Method B with a curl step:

```bash
VER=v2.2.2
curl -fsSL https://<your-release-host>/releases/handoff-${VER}/handoff-${VER}.skill -o /tmp/h.skill
unzip -o /tmp/h.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp ~/.claude/skills/handoff/command-shims/handoff-{recall,tidy,memory,init}.md ~/.claude/commands/
```

### 1.5 Remote / SSH deployment

```bash
# Push source then install
scp -r handoff/ user@remote:~/
ssh user@remote 'cd ~/handoff && ./install.sh'

# Or push .skill bundle
scp Release/handoff-v<VERSION>/handoff-v<VERSION>.skill user@remote:~/
ssh user@remote 'mkdir -p ~/.claude/skills && unzip -o ~/handoff-v<VERSION>.skill -d ~/.claude/skills/'
```

---

## 2. First-time project initialization (v2 four-file layout)

The skill installs once per host. Each project that uses handoff needs its own v2 four-file scaffold: `HANDOFF.md` + `GOTCHAS.md` + `Handoff_Logs/` + `Handoff_Decisions/`.

### 2.1 Let Claude create it (most natural)

In a Claude Code session opened to the project root:

```
/handoff-init
```

Claude copies the v2 template (with `<!-- HANDOFF v2 schema -->` marker + the three pointer-stat blocks) and creates the empty GOTCHAS.md + Handoff_Logs/ + Handoff_Decisions/ siblings, then walks you through Project Overview + Architecture.

### 2.2 Via install.sh `--template`

```bash
./install.sh --template /path/to/project
```

Creates the v2 four-file scaffold without installing the skill body (useful when the skill is already installed globally).

### 2.3 Manual copy

```bash
cp ~/.claude/skills/handoff/assets/HANDOFF.template.md /path/to/project/HANDOFF.md
mkdir -p /path/to/project/Handoff_Logs /path/to/project/Handoff_Decisions
touch /path/to/project/GOTCHAS.md
```

> If the project already has a v1 single-file `HANDOFF.md` (no v2 marker, inline Dev Log entries), **do not** use `--template`. Run `/handoff-tidy` instead — it detects v1 layout and triggers atomic migration to v2.

---

## 3. Upgrade

### 3.1 Source users

```bash
cd ~/handoff
git pull
./install.sh                     # idempotent re-install
```

Then inside Claude Code: `/reload-plugins` (or quit + reopen).

### 3.2 `.skill` single-file users

```bash
unzip -o handoff-v<NEW>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/handoff/scripts/*.sh
cp ~/.claude/skills/handoff/command-shims/handoff-{recall,tidy,memory,init}.md ~/.claude/commands/
```

Then `/reload-plugins`.

### 3.3 Sync existing project HANDOFF.md to new template

When the skill upgrades, each project's HANDOFF.md is NOT auto-rewritten. In the project root inside Claude Code:

```
/handoff-tidy
```

This:
- Adds missing sections to match the new template
- Re-sorts Dev Log entries (most recent first), fills missing fields
- Runs the four post-hooks: scan-credentials, validate-handoff, rotation-reminder, archive-devlog
- Backs up the original to `HANDOFF.md.bak`

### 3.4 Post-upgrade verification

```bash
head -5 ~/.claude/skills/handoff/SKILL.md      # Confirm new version
cat ~/.claude/skills/handoff/VERSION           # → v<NEW>
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh \
     ~/.claude/skills/handoff/assets/HANDOFF.template.md
# Expected: HANDOFF.md structure OK
```

---

## 4. Uninstall

### 4.1 Full uninstall (keeps project data)

```bash
cd ~/handoff
./install.sh --uninstall
```

Removes:
- `~/.claude/skills/handoff/`
- `~/.config/opencode/skills/handoff/`
- `~/.agents/skills/handoff/` (Codex)
- All `~/.claude/commands/handoff-*.md` shims
- Codex skill aliases under `~/.agents/skills/handoff-*/`
- v0.4-era `~/.claude/handoff-scripts/` residue

**Preserves:** every `HANDOFF.md` / `GOTCHAS.md` / `Handoff_Logs/` / `Handoff_Decisions/` in your projects.

### 4.2 Project-level only

```bash
rm -rf /path/to/project/.claude/skills/handoff
```

### 4.3 Wipe project data (DESTRUCTIVE)

```bash
rm -f /path/to/project/HANDOFF.md /path/to/project/GOTCHAS.md
rm -rf /path/to/project/Handoff_Logs /path/to/project/Handoff_Decisions
```

> This destroys all handoff state for that project. Only do this if you have backups or have deliberately decided to start over.

---

## 5. Verify / Self-check

### 5.1 Inside Claude Code

```
/                    # /handoff / /handoff-init / /handoff-recall / /handoff-tidy / /handoff-memory should appear
do a handoff         # Natural-language trigger
```

### 5.2 Command line

```bash
# Check skill files
ls ~/.claude/skills/handoff/SKILL.md && echo "skill present"
ls ~/.claude/commands/handoff-recall.md && echo "shims present"

# Validate template structure
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh \
     ~/.claude/skills/handoff/assets/HANDOFF.template.md
# Expected: HANDOFF.md structure OK

# Scan-credentials should run cleanly on an empty input
bash ~/.claude/skills/handoff/scripts/scan-credentials.sh /dev/null
echo "scan-credentials exit=$?"
```

---

## 6. Release (developers)

### 6.1 One command

handoff is shipped via gitx-release (the TKX meta-skill). From the handoff repo root:

```bash
PROJECT_ROOT="$(pwd)" PROJECT_NAME=handoff SKILL_NAME=handoff \
  bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh
# or with explicit version:
PROJECT_ROOT="$(pwd)" PROJECT_NAME=handoff SKILL_NAME=handoff \
  bash ~/.agents/skills/gitx-release/scripts/release.sh v<VERSION>
```

### 6.2 What the gitx-release pipeline does

1. Preflight (version consistency, CHANGELOG gate)
2. Run regression tests (`bash tests/run_all.sh`)
3. Dual-source byte-identical check (root vs `skills/handoff/`)
4. Build `.skill` + source tarball + full tarball
5. Sanity scan (staging + bundle, both must pass)
6. Flatten docs + generate attestations (SBOM + TOKEN_USAGE)
7. Deep Audit (40+ checks must all pass, includes §0b unified-install-standard gate)
8. Atomic `Release/latest` symlink update

### 6.3 Sanity is unskippable

No `FORCE=1` bypass. Failure aborts release with non-zero exit.

---

## 7. Daily maintenance commands

### 7.1 Full project self-check

```bash
cd /path/to/project
bash ~/.claude/skills/handoff/scripts/scan-credentials.sh HANDOFF.md
bash ~/.claude/skills/handoff/scripts/validate-handoff.sh --readiness HANDOFF.md
bash ~/.claude/skills/handoff/scripts/rotation-reminder.sh HANDOFF.md
bash ~/.claude/skills/handoff/scripts/archive-devlog.sh HANDOFF.md
```

Or the bundled four-in-one post-flight:

```bash
bash ~/.claude/skills/handoff/scripts/handoff-postflight.sh /path/to/project
```

### 7.2 Force-archive Dev Log entries

```bash
bash ~/.claude/skills/handoff/scripts/archive-devlog.sh /path/to/project 20
# Keep the most recent 20 entries, move the rest to Handoff_Logs.archive/<YYYY>/
```

### 7.3 Tidy HANDOFF.md structure (without entering Claude)

```bash
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh /path/to/project/HANDOFF.md
# Auto-fixes: excess blank lines / missing anchors
# Diagnoses: missing sections / out-of-order Dev Log / missing fields (AI fixes those)
```

### 7.4 Run the full regression test suite (developers)

```bash
cd ~/handoff
bash tests/run_all.sh
```

### 7.5 Clean up legacy Codex mirror entries

```bash
bash ~/.claude/skills/handoff/scripts/sync-codex-skills.sh
```

The official Codex user-skills path is `~/.agents/skills`. This script only removes duplicate-mirror entries left by older versions; it never creates new mirror directories.

---

## 8. Troubleshooting

### 8.1 `/handoff` not in the command list

```bash
ls -la ~/.claude/skills/handoff/SKILL.md      # confirm install
claude --version                              # ensure skills are supported
# Inside Claude Code: /reload-plugins
```

### 8.2 "permission denied" running a script

```bash
chmod +x ~/.claude/skills/handoff/scripts/*.sh
```

### 8.3 `/handoff-recall` fuzzy-matched to `/handoff`

Confirm shims are installed:

```bash
ls ~/.claude/commands/handoff*.md
# Should see: handoff-recall.md  handoff-tidy.md  handoff-memory.md  handoff-init.md
# (/handoff itself is registered via SKILL.md name, no shim needed)
```

If missing, run `./install.sh` again.

### 8.4 Old version state clashes with new install

```bash
./install.sh --uninstall    # clear all global state
./install.sh                # reinstall fresh
```

### 8.5 HANDOFF.md structure broken

Inside Claude Code:

```
/handoff-tidy
```

Or command line:

```bash
bash ~/.claude/skills/handoff/scripts/tidy-handoff.sh /path/to/project/HANDOFF.md
```

### 8.6 Lost Dev Log entries after archive (rare)

`archive-devlog.sh` is atomic, so loss is unusual. If it happens:

```bash
# Tidy auto-creates a backup
ls /path/to/project/HANDOFF.md.bak

# The archive file holds the moved entries
cat /path/to/project/HANDOFF.archive.md
```

Merge the two to recover.

---

More design context in [README.md](./README.md).
