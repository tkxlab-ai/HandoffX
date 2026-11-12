# INSTALL — Complete install / upgrade / uninstall / maintenance reference for handoffx

> README.md describes **what handoffx is** (project-level handoff documentation system with HANDOFFX.md + GOTCHAS.md + per-file Dev Log + Decision Log). This document describes **how to install, upgrade, uninstall, and maintain it** — every command annotated.

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
├── skills/handoffx/                     # Skill body (installed globally)
│   ├── SKILL.md                        # Skill entry / system prompt
│   ├── VERSION                         # Sidecar version
│   ├── references/*.md                 # Command specs
│   ├── scripts/                        # Helpers
│   │   ├── *.sh                        # scan-credentials / validate-handoff / etc.
│   │   └── lib/install-output-style.sh # Unified install.sh output helper
│   ├── command-shims/*.md              # Slash command shims source
│   └── assets/HANDOFFX.template.md     # HANDOFFX.md skeleton
└── commands/                           # Slash shims (so /handoffx-* are not fuzzy-matched to /handoffx)
    ├── handoffx-recall.md
    ├── handoffx-tidy.md
    ├── handoffx-memory.md
    └── handoffx-init.md

~/.config/opencode/skills/handoffx       # OpenCode target (when --opencode)
~/.agents/skills/handoffx                # Codex target (when --codex; Codex CLI native discovery)

<project-root>/                         # Per-project state (v2 four-file layout)
├── HANDOFFX.md                         # Main file (header: <!-- HANDOFF v2 schema -->)
├── GOTCHAS.md                          # Known Gotchas knowledge base (v2 sibling)
├── Handoffx_Logs/                      # Dev Log per-file (v2)
│   └── <NNNN>-<timestamp>-<slug>.md
├── Handoffx_Decisions/                 # Decision Log per-file (v2)
│   └── <NNNN>-<date>-<slug>.md
├── Handoffx_Logs.archive/              # Yearly archive (v2 replaced the legacy HANDOFF.archive.md)
│   └── <YYYY>/
└── .claude/skills/handoffx/             # (optional) project-level install; overrides global
```

> Upgrading from an older layout (a legacy `HANDOFF.md`, with or without `Handoff_Logs/` / `Handoff_Decisions/`)? v4.0.0 renamed the produced files to `HANDOFFX.md` / `Handoffx_Logs/` / `Handoffx_Decisions/`, and nothing is renamed for you. Run `/handoffx-tidy` in your project root: it classifies the layout by content and names the command (v1 single file → `migrate-to-v2.sh`; old four-piece layout → `/handoffx-tidy schema-upgrade --dry-run`, then `--apply`). Failed migrations roll back. See `MIGRATION_GUIDE_v2.md` §5.

---

## 1. Install

### 1.1 Method A — Source + install.sh (recommended)

For long-term upgrades, team deployment, or CI.

```bash
git clone https://github.com/tkxlab-ai/handoffx.git
cd handoffx
./install.sh                     # auto-detect installed CLIs (Claude / OpenCode / Codex)
./install.sh --claude            # Claude Code only
./install.sh --opencode          # OpenCode only
./install.sh --codex             # Codex CLI only
./install.sh --project /path     # Project-level install (Claude Code in <project>/.claude/)
./install.sh --template /path    # Create HANDOFFX.md in <path> without installing skill body
./install.sh --uninstall         # Remove all global installs
./install.sh --dry-run           # Preview without writing
./install.sh --force             # Overwrite (re-install over existing)
./install.sh --help              # Full flag reference
```

> ⚠️ **OpenCode users (1.14+)**: OpenCode also discovers skills under `~/.claude/skills/**` and `~/.agents/skills/**` — recursively, hidden directories included — and resolves duplicate skill names last-wins in a nondeterministic load order. After a complete three-CLI install the three `handoffx` copies are byte-identical, so this is harmless; it stops being harmless the moment one copy is edited or a different version is installed per-project. Either install only `--opencode`, or set `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` so OpenCode reads `~/.config/opencode/skills` alone. Old-name skill directories nested under those roots (e.g. a stale backup such as `~/.agents/skills/.backup-*/`) are reported by `install.sh` as ⚠️ but never deleted — remove them by hand.

The installer renders the unified TKX banner across all targeted CLIs (output of `./install.sh --claude` — the live install path):

```
===============================================================
  📦  handoffx Installation  v4.1.1
===============================================================
🔍  Checkpoint 1 — Preflight: targets detected
    ✅ Claude Code   targeted
📂  Checkpoint 2 — Global install
🧹  ...per-CLI install + legacy cleanup phases...
✓   Checkpoint N — Validation
===============================================================
  🎉  handoffx v4.1.1 installed
===============================================================
```

> handoffx's checkpoint count is dynamic because the multi-CLI install (`--claude` / `--opencode` / `--codex` separately) means different runs hit different phases. The top + bottom banners remain identical to the other 4 TKX skills (gitx-release / mac-release / 1by1 / ClaudeMeX).

### 1.2 Method B — Single `.skill` file

For out-of-band distribution (email, shared drive, scp). The archive unpacks to a single top-level directory — that release's skill directory (`unzip -l` shows it); `<skill-dir>` below stands for it, and the shims live in its `command-shims/`.

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o handoffx-v<VERSION>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
cp ~/.claude/skills/<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md ~/.claude/commands/
```

> `install.sh` from the same source repo (or any newer .skill bundle) auto-bootstraps from a `handoffx-*.skill` or `handoffx-*-source.tar.gz` placed next to it. So you can also run `./install.sh --claude` against a freshly-downloaded .skill if you keep the unpacked installer adjacent.

### 1.3 Method C — Manual directory copy

Maximum transparency, zero install script.

```bash
# Global
cp -R skills/handoffx ~/.claude/skills/handoffx
chmod +x ~/.claude/skills/handoffx/scripts/*.sh
cp skills/handoffx/command-shims/handoffx-{recall,tidy,memory,init}.md ~/.claude/commands/

# Project-level (overrides global for that project)
cp -R skills/handoffx /path/to/project/.claude/skills/handoffx
chmod +x /path/to/project/.claude/skills/handoffx/scripts/*.sh
```

### 1.4 Method D — curl one-liner

**Not supported as a pure `curl install.sh | bash` one-liner.** The installer requires the full bundle (SKILL.md, scripts/, scripts/lib/install-output-style.sh, command-shims/, references/, assets/). Use **Method B** (`.skill` download + unzip) or **Method A** (clone) instead.

If a fetch-and-install one-liner is needed, combine Method B with a curl step:

Download through the release-asset URL `releases/download/<tag>/<file>` (what the releases API returns as `browser_download_url`). A private repo needs a token header; the `/attachments/<id>` links some forge web UIs show can answer HTTP 500 on some instances, so do not script against them.

```bash
VER=v4.1.1
curl -fsSL -H "Authorization: token $RELEASE_TOKEN" \
  "https://<your-release-host>/<owner>/<repo>/releases/download/${VER}/handoffx-${VER}.skill" -o /tmp/h.skill
unzip -o /tmp/h.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
cp ~/.claude/skills/<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md ~/.claude/commands/
```

### 1.5 Remote / SSH deployment

```bash
# Push source then install
scp -r handoffx/ user@remote:~/
ssh user@remote 'cd ~/handoffx && ./install.sh'

# Or push .skill bundle
scp Release/handoffx-v<VERSION>/handoffx-v<VERSION>.skill user@remote:~/
ssh user@remote 'mkdir -p ~/.claude/skills && unzip -o ~/handoffx-v<VERSION>.skill -d ~/.claude/skills/'
```

---

## 2. First-time project initialization (v2 four-file layout)

The skill installs once per host. Each project that uses handoffx needs its own v2 four-file scaffold: `HANDOFFX.md` + `GOTCHAS.md` + `Handoffx_Logs/` + `Handoffx_Decisions/`.

### 2.1 Let Claude create it (most natural)

In a Claude Code session opened to the project root:

```
/handoffx-init
```

Claude copies the v2 template (with `<!-- HANDOFF v2 schema -->` marker + the three pointer-stat blocks) and creates the empty GOTCHAS.md + Handoffx_Logs/ + Handoffx_Decisions/ siblings, then walks you through Project Overview + Architecture.

### 2.2 Via install.sh `--template`

```bash
./install.sh --template /path/to/project
```

Creates a `HANDOFFX.md` from the template in `<dir>` **in addition to** the normal global install (it does not change the install mode and does not create `GOTCHAS.md` / `Handoffx_Logs/` / `Handoffx_Decisions/` — use `/handoffx-init` for the full four-file scaffold).

### 2.3 Manual copy

```bash
cp ~/.claude/skills/handoffx/assets/HANDOFFX.template.md /path/to/project/HANDOFFX.md
mkdir -p /path/to/project/Handoffx_Logs /path/to/project/Handoffx_Decisions
touch /path/to/project/GOTCHAS.md
```

> If the project root has a legacy `HANDOFF.md` (a v1 single file, or the old four-piece layout), **do not** use `--template`: it refuses a legacy-layout target. Run `/handoffx-tidy` instead — it classifies the layout by content and names the upgrade command.

---

## 3. Upgrade

### 3.1 Source users

```bash
cd ~/handoffx
git pull
./install.sh                     # idempotent re-install
```

Then inside Claude Code: `/reload-plugins` (or quit + reopen).

### 3.2 `.skill` single-file users

```bash
unzip -o handoffx-v<NEW>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
cp ~/.claude/skills/<skill-dir>/command-shims/*-{recall,tidy,memory,init}.md ~/.claude/commands/
```

Then `/reload-plugins`.

### 3.3 Sync existing project HANDOFFX.md to new template

> Guided path: on a legacy layout the `/handoffx*` commands show `scripts/handoffx-upgrade.sh --dry-run` output and ask; a yes runs `--apply` (fixed multi-machine order: `MIGRATION_GUIDE_v2.md` §5.6).

When the skill upgrades, each project's HANDOFFX.md is NOT auto-rewritten. (A project still on a legacy `HANDOFF.md` layout needs the upgrade from the layout note near the top of this document first — `/handoffx-tidy` exits 2 and names the command until then.) In the project root inside Claude Code:

```
/handoffx-tidy
```

This:
- Adds missing sections to match the new template
- Re-sorts Dev Log entries (most recent first), fills missing fields
- Runs the five post-flight checks: scan-credentials, validate-handoff, handoff-lint, rotation-reminder, archive-devlog
- Backs up the original to `HANDOFFX.md.bak`

### 3.4 Post-upgrade verification

```bash
head -5 ~/.claude/skills/handoffx/SKILL.md      # Confirm new version
cat ~/.claude/skills/handoffx/VERSION           # → v<NEW>
bash ~/.claude/skills/handoffx/scripts/validate-handoff.sh \
     ~/.claude/skills/handoffx/assets/HANDOFFX.template.md
# Expected: HANDOFFX.md structure OK
```

---

## 4. Uninstall

### 4.1 Full uninstall (keeps project data)

```bash
cd ~/handoffx
./install.sh --uninstall
```

Removes:
- `~/.claude/skills/handoffx/`
- `~/.config/opencode/skills/handoffx/`
- `~/.agents/skills/handoffx/` (Codex)
- All `~/.claude/commands/handoffx-*.md` shims
- Codex skill aliases under `~/.agents/skills/handoffx-*/`
- v0.4-era `~/.claude/handoff-scripts/` residue

**Preserves:** every `HANDOFFX.md` / `GOTCHAS.md` / `Handoffx_Logs/` / `Handoffx_Decisions/` in your projects.

### 4.2 Project-level only

```bash
rm -rf /path/to/project/.claude/skills/handoffx
```

### 4.3 Wipe project data (DESTRUCTIVE)

```bash
rm -f /path/to/project/HANDOFFX.md /path/to/project/GOTCHAS.md
rm -rf /path/to/project/Handoffx_Logs /path/to/project/Handoffx_Decisions
```

> This destroys all handoff state for that project. Only do this if you have backups or have deliberately decided to start over.

---

## 5. Verify / Self-check

### 5.1 Inside Claude Code

```
/                    # /handoffx / /handoffx-init / /handoffx-recall / /handoffx-tidy / /handoffx-memory should appear
do a handoff         # Natural-language trigger
```

### 5.2 Command line

```bash
# Check skill files
ls ~/.claude/skills/handoffx/SKILL.md && echo "skill present"
ls ~/.claude/commands/handoffx-recall.md && echo "shims present"

# Validate template structure
bash ~/.claude/skills/handoffx/scripts/validate-handoff.sh \
     ~/.claude/skills/handoffx/assets/HANDOFFX.template.md
# Expected: HANDOFFX.md structure OK

# Scan-credentials on a clean file exits 0 (/dev/null is neither a file nor a
# directory and exits 2 "usage error"; empty stdin also exits 2 by design)
printf 'clean\n' > /tmp/handoff-clean.md
bash ~/.claude/skills/handoffx/scripts/scan-credentials.sh /tmp/handoff-clean.md
echo "scan-credentials exit=$?"   # expect 0
```

---

## 6. Release (developers)

### 6.1 One command

handoffx is shipped via gitx-release (the TKX meta-skill). From the HandoffX repo root:

```bash
COPYFILE_DISABLE=1 PROJECT_ROOT="$(pwd)" PROJECT_NAME=handoffx SKILL_NAME=handoffx \
  bash ~/.agents/skills/gitx-release/scripts/gitx-release.sh
# or with explicit version:
COPYFILE_DISABLE=1 PROJECT_ROOT="$(pwd)" PROJECT_NAME=handoffx SKILL_NAME=handoffx \
  bash ~/.agents/skills/gitx-release/scripts/release.sh v<VERSION>
```

Pass `PROJECT_NAME` and `SKILL_NAME` explicitly: without them gitx derives the names from the root directory (lowercased) and `skills/<dir>`, so a checkout with an unusual directory name would produce a non-canonical release layout.

Keep `COPYFILE_DISABLE=1`: gitx unpacks the source tarball, injects `CHANGELOG.md` and re-packs it with the system `tar`. On macOS that `tar` adds a `._*` AppleDouble member for every file carrying an extended attribute; v4.1.0 shipped 52 of them in the full tarball and 194 in the source tarball. Our own producers (`release.sh`, `scripts/scrub-tarball.sh`) set the variable themselves, but gitx's re-pack only sees the caller's environment. `tests/test_release_artifact_content.sh` fails on any `._*` / `__MACOSX/` member. (Plain `tar tzf` on macOS hides these members; the test lists them with `tar --options '!mac-ext'`.)

### 6.2 What the gitx-release pipeline does

1. Preflight (version consistency, CHANGELOG gate)
2. Run regression tests (`bash tests/run_all.sh`)
3. Dual-source byte-identical check (root vs `skills/handoffx/`)
4. Build `.skill` + source tarball + full tarball
5. Sanity scan (staging + bundle, both must pass)
6. Flatten docs + generate attestations (SBOM + TOKEN_USAGE)
7. Deep Audit (40+ checks must all pass, includes §0b unified-install-standard gate)
8. Atomic `Release/latest` symlink update

### 6.3 Sanity is unskippable

No `FORCE=1` bypass. Failure aborts release with non-zero exit.

### 6.4 Verifying a downloaded release

`checksums.txt` paths are relative to the release directory (after extracting the full tarball, that is `handoffx-vX.Y.Z/`), so verify from inside it:

```bash
cd handoffx-vX.Y.Z && shasum -a 256 -c checksums.txt   # Linux: sha256sum -c checksums.txt
```

The line for `handoffx-vX.Y.Z-full.tar.gz` is expected to read `FAILED open or read` there — the full tarball is not inside itself. Every other line must be `OK`. (gitx, the release pipeline, writes that self-entry; HandoffX cannot change the producer.)

---

## 7. Daily maintenance commands

### 7.1 Full project self-check

```bash
cd /path/to/project
bash ~/.claude/skills/handoffx/scripts/scan-credentials.sh .   # directory mode: HANDOFFX.md + GOTCHAS.md + Handoffx_Logs/ + Handoffx_Decisions/ (+ their .archive/ subtrees)
bash ~/.claude/skills/handoffx/scripts/validate-handoff.sh --readiness HANDOFFX.md
bash ~/.claude/skills/handoffx/scripts/handoff-lint.sh HANDOFFX.md
bash ~/.claude/skills/handoffx/scripts/rotation-reminder.sh HANDOFFX.md
bash ~/.claude/skills/handoffx/scripts/archive-devlog.sh HANDOFFX.md
```

Or the bundled five-check post-flight:

```bash
bash ~/.claude/skills/handoffx/scripts/handoff-postflight.sh /path/to/project/HANDOFFX.md
```

### 7.2 Archive Dev Log entries by year

```bash
bash ~/.claude/skills/handoffx/scripts/archive-devlog.sh /path/to/project
# v2: moves Handoffx_Logs/<NNNN>-<YYYY>-* older than last year to Handoffx_Logs.archive/<YYYY>/
# (idempotent; the numeric threshold argument is ignored in v2 directory mode)
```

### 7.3 Tidy HANDOFFX.md structure (without entering Claude)

```bash
bash ~/.claude/skills/handoffx/scripts/tidy-handoff.sh /path/to/project/HANDOFFX.md
# Auto-fixes: excess blank lines / missing anchors
# Diagnoses: missing sections / out-of-order Dev Log / missing fields (AI fixes those)
```

### 7.4 Run the full regression test suite (developers)

```bash
cd ~/handoffx
bash tests/run_all.sh
```

### 7.5 Clean up legacy Codex mirror entries

```bash
bash ~/.claude/skills/handoffx/scripts/sync-codex-skills.sh
```

The official Codex user-skills path is `~/.agents/skills`. This script only removes duplicate-mirror entries left by older versions; it never creates new mirror directories.

---

## 8. Troubleshooting

### 8.1 `/handoffx` not in the command list

```bash
ls -la ~/.claude/skills/handoffx/SKILL.md      # confirm install
claude --version                              # ensure skills are supported
# Inside Claude Code: /reload-plugins
```

### 8.2 "permission denied" running a script

```bash
chmod +x ~/.claude/skills/handoffx/scripts/*.sh
```

### 8.3 `/handoffx-recall` fuzzy-matched to `/handoffx`

Confirm shims are installed:

```bash
ls ~/.claude/commands/handoffx*.md
# Should see: handoffx-recall.md  handoffx-tidy.md  handoffx-memory.md  handoffx-init.md
# (/handoffx itself is registered via SKILL.md name, no shim needed)
```

If missing, run `./install.sh` again.

### 8.4 Old version state clashes with new install

```bash
./install.sh --uninstall    # clear all global state
./install.sh                # reinstall fresh
```

### 8.5 HANDOFFX.md structure broken

Inside Claude Code:

```
/handoffx-tidy
```

Or command line:

```bash
bash ~/.claude/skills/handoffx/scripts/tidy-handoff.sh /path/to/project/HANDOFFX.md
```

### 8.6 Lost Dev Log entries after archive (rare)

`archive-devlog.sh` is atomic, so loss is unusual. If it happens:

```bash
# Tidy auto-creates a backup
ls /path/to/project/HANDOFFX.md.bak

# The yearly archive dirs hold the moved entries
ls /path/to/project/Handoffx_Logs.archive/*/
```

Merge the two to recover.

---

More design context in [README.md](./README.md).
