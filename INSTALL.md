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
- [支持矩阵（v4.2.0）](#支持矩阵v420)
- [8. Troubleshooting](#8-troubleshooting)

---

## 0. File location cheat sheet

### Development update: location binding

The current development source writes `.handoffx-install-context` inside each installed skill. Use `bash install.sh --project <absolute-project-root>` (or the normal global installer) to create it. Run the installed skill from that exact physical project root. A moved installation, a legacy/manual copy without the manifest, or a global skill shadowed by a local skill is refused: reinstall from the chosen source; do not hand-edit the binding or silently switch to a parent project.

This changes the manual-copy and direct `.skill` workflows below: they distribute files but **do not establish the new binding** in a standard host skill directory. Complete installation with `install.sh` before use. Unbound source-tool copies are explicitly reported as `source_unbound`, not authenticated installations. The manifest is a path consistency check, not a signature, authorization boundary, or Git identity check. It does not prevent an agent bypassing helpers and writing files directly.

Read-only diagnosis, from the intended project directory:
```bash
bash <installed-skill-root>/scripts/handoff-runtime.sh context \
  --root "<absolute-project-root>" --skill-root "<installed-skill-root>"
```


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

**Claude configuration root:** the tree and manual commands use the default `~/.claude/`. A non-empty `CLAUDE_CONFIG_DIR` overrides the installer’s global Claude root, so the skill and shims go to `$CLAUDE_CONFIG_DIR/skills/` and `$CLAUDE_CONFIG_DIR/commands/`. This override wins on WSL too; without it, the existing Windows-Claude detection / `$HOME/.claude` fallback remains. `--project` still targets `<project>/.claude/`. Adjust manual copy and verification paths when using a custom root. `sync-memory.sh` does **not** currently use this override for its source: it still reads `$HOME/.claude/projects/<encoded>/memory/`.

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
./install.sh --template /path    # Also fill missing v2 four-piece scaffold; preserve existing pieces
./install.sh --uninstall         # Remove all global installs
./install.sh --dry-run           # Preview without writing
./install.sh --force             # Overwrite (re-install over existing)
./install.sh --help              # Full flag reference
```

> ⚠️ **OpenCode users (1.14+)**: OpenCode also discovers skills under `~/.claude/skills/**` and `~/.agents/skills/**` — recursively, hidden directories included — and resolves duplicate skill names last-wins in a nondeterministic load order. After a complete three-CLI install the three `handoffx` copies are byte-identical, so this is harmless; it stops being harmless the moment one copy is edited or a different version is installed per-project. Either install only `--opencode`, or set `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` so OpenCode reads `~/.config/opencode/skills` alone. Old-name skill directories nested under those roots (e.g. a stale backup such as `~/.agents/skills/.backup-*/`) are reported by `install.sh` as ⚠️ but never deleted — remove them by hand.

The installer renders the unified TKX banner across all targeted CLIs (output of `./install.sh --claude` — the live install path):

```
===============================================================
  📦  handoffx Installation  v4.2.1
===============================================================
🔍  Checkpoint 1 — Preflight: targets detected
    ✅ Claude Code   targeted
📂  Checkpoint 2 — Global install
🧹  ...per-CLI install + legacy cleanup phases...
✓   Checkpoint N — Validation
===============================================================
  🎉  handoffx v4.2.1 installed
===============================================================
```

> handoffx's checkpoint count is dynamic because the multi-CLI install (`--claude` / `--opencode` / `--codex` separately) means different runs hit different phases. The top + bottom banners remain identical to the other 4 TKX skills (gitx-release / mac-release / 1by1 / ClaudeMeX).

### 1.2 Method B — Single `.skill` file

For out-of-band distribution (email, shared drive, scp). The archive unpacks to a single top-level directory — that release's skill directory (`unzip -l` shows it); `<skill-dir>` below stands for it, and the shims live in its `command-shims/`.

```bash
mkdir -p ~/.claude/skills ~/.claude/commands
unzip -o handoffx-v<VERSION>.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
# Next: bind the command shims using the manual recipe below.
```

> **Recommended for both installation and upgrades:** put `install.sh` and the `.skill` from the **same build** in a dedicated directory, then run `bash ./install.sh --claude` (add `--opencode --codex` for those CLIs). The `.skill` itself does not contain an installer; obtain the matching installer from that build's source or extracted full bundle. Do not mix a new skill with an old installer: generated aliases can retain old behavior.
>
> Without a source tree, the installer accepts at most one `handoffx-*.skill` and at most one `handoffx-*-source.tar.gz` beside it. Multiple files of either type are rejected before installation, even for `--dry-run`; it never guesses the newest version. With one of each, `.skill` takes priority and the source tarball is the fallback for an incompatible ZIP root. A complete source tree takes precedence over adjacent archives. Extract a full tarball before running its installer.

**Manual shim binding (required after manual extraction/copy):** source command files are templates, not installed commands. Replace the literal root token using the actual absolute skill path; do not shell-evaluate command arguments. The normal installer does this automatically, including custom configuration roots and project installs. Reinstall/rebind after moving the skill. Do not copy a rendered shim from another CLI or machine.

```bash
SKILL_ROOT="$HOME/.claude/skills/<skill-dir>" # actual extracted directory
COMMAND_ROOT="$HOME/.claude/commands"       # adjust for custom/project config
mkdir -p "$COMMAND_ROOT"
for name in handoffx-recall handoffx-tidy handoffx-memory handoffx-init; do
  HX_ROOT="$SKILL_ROOT" awk '{ t="@HANDOFFX_ROOT@"; p=index($0,t); if(p) print substr($0,1,p-1) ENVIRON["HX_ROOT"] substr($0,p+length(t)); else print }' \
    "$SKILL_ROOT/command-shims/$name.md" > "$COMMAND_ROOT/$name.md"
done
# After successful binding, remove template command sources from the installed
# skill (the standard installer does this too, to avoid duplicate registration).
rm -rf "$SKILL_ROOT/command-shims" "$SKILL_ROOT/commands"
```

This manual recipe targets Claude only. It does not update OpenCode/Codex copies or perform the standard installer's legacy cleanup and rollback. Prefer the installer for upgrades, especially on multi-CLI machines.

### 1.3 Method C — Manual directory copy

**For upgrades, use the standard installer instead of repeating a directory copy:**

```bash
bash ./install.sh --claude
# Add --opencode --codex to update those CLIs in the same transaction.
# Project-level installation:
bash ./install.sh --claude --project /path/to/project
```

`cp -R skills/handoffx <existing>/handoffx` nests the new files under `handoffx/handoffx/` rather than replacing the active skill. Do not use it as an upgrade command. The installer replaces the old tree, rebinds command paths, regenerates aliases and keeps a restore backup.

Manual copying is only for a **new, absent destination**. This guarded example refuses existing directories, files and dangling symlinks:

```bash
(
  set -e
  SKILL_ROOT="$HOME/.claude/skills/handoffx"
  # For a project, instead use /path/to/project/.claude/skills/handoffx.
  if [ -e "$SKILL_ROOT" ] || [ -L "$SKILL_ROOT" ]; then
    printf '%s\n' "Refusing existing destination; use the standard installer: $SKILL_ROOT" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$SKILL_ROOT")"
  cp -R skills/handoffx "$SKILL_ROOT"
  chmod +x "$SKILL_ROOT"/scripts/*.sh
)
# Only after a successful fresh copy: bind shims and remove template command
# sources using Method B. Adjust COMMAND_ROOT for project/custom config paths.
```

### 1.4 Method D — curl one-liner

**Not supported as a pure `curl install.sh | bash` one-liner.** The installer requires the full bundle (SKILL.md, scripts/, scripts/lib/install-output-style.sh, command-shims/, references/, assets/). Use **Method B** (`.skill` download + unzip) or **Method A** (clone) instead.

If a fetch-and-install one-liner is needed, combine Method B with a curl step:

Download through the release-asset URL `releases/download/<tag>/<file>` (what the releases API returns as `browser_download_url`). A private repo needs a token header; the `/attachments/<id>` links some forge web UIs show can answer HTTP 500 on some instances, so do not script against them.

```bash
VER=v4.2.1
curl -fsSL -H "Authorization: token $RELEASE_TOKEN" \
  "https://<your-release-host>/<owner>/<repo>/releases/download/${VER}/handoffx-${VER}.skill" -o /tmp/h.skill
unzip -o /tmp/h.skill -d ~/.claude/skills/
chmod +x ~/.claude/skills/<skill-dir>/scripts/*.sh
# Next: bind the command shims using the manual recipe below.
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

Claude copies the v2 template (with `<!-- HANDOFF v2 schema -->` marker + the three pointer-stat blocks) and creates the empty GOTCHAS.md + Handoffx_Logs/ + Handoffx_Decisions/ siblings, then walks you through the canonical continuity area in Project Overview, current handoff context, and Architecture. The template is a skeleton, not proof of semantic completeness; unknowns stay “not recorded/to confirm,” never invented.

### 2.2 Via install.sh `--template`

```bash
./install.sh --template /path/to/project
```

**In addition to** the selected/default CLI installation, this fills whichever of the four pieces are missing: `HANDOFFX.md` and `GOTCHAS.md` from templates, plus empty `Handoffx_Logs/` and `Handoffx_Decisions/` directories. It does not change the install mode or provide a template-only install. Existing pieces are skipped without overwriting content, even with `--force`; project-specific fields still need to be filled in.

Preflight refuses legacy layouts, conflicting path types, and symlinks at the four canonical paths. File templates are staged beside their destinations and published without clobbering existing files. Scaffold creation happens after the CLI install commits and is **not one batch transaction**: a later creation failure returns nonzero and reports incomplete scaffolding, but does not undo the CLI install or pieces already created.

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

Put the new `.skill` and its matching `install.sh` in a dedicated download directory (see Method B), then run:

```bash
bash ./install.sh --claude
# Add --opencode --codex if those CLIs must also be upgraded.
```

Do not upgrade with repeated `cp -R` or by copying only the skill while keeping an older installer. Plain `unzip -o` overlays files but does not remove obsolete files or refresh existing aliases; use the standard installer for a replace-and-rebind upgrade. If no matching installer is available, obtain the complete matching source/full bundle first.

Then `/reload-plugins` (or quit and reopen the host).

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

For a read-only **basic** diagnosis of a project:

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoffx/scripts/hx.sh" doctor --root /path/to/project
```

`doctor` reports the project root, script source, discovered CLI executable paths, and `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` as the Claude config path. It rejects missing or symlinked four-piece paths, requires `HANDOFFX.md` and `GOTCHAS.md` to be readable regular files, and requires `Handoffx_Logs/` and `Handoffx_Decisions/` to be directories with read and traversal permissions (`r+x`). If those checks pass, it runs `validate-handoff.sh --check-stats --readiness`: structure validation, **per-entry lint** (called by `--readiness`), and the **Dev Log pointer-count check**. `--check-stats` rejects a missing, linked, unreadable, or untraversable Logs directory rather than treating it as empty. This remains read-only basic diagnosis: no repairs, credential scanning, or credential-rotation checks, and no claim that the full postflight is clean. It also does not resolve every active skill copy. Its reported default config path is not the installer’s WSL Windows-path discovery. Substitute the actual installed skill path when needed.

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

**Default command replies:** Show `🚀启动handoffX项目交接流程.` once; avoid repeated normal progress notices. Normal `/handoffx` write confirmations keep the total 200-character visible budget (including punctuation and paths), with no code or command dumps. Recall bodies are not subject to the 120/200-character write-confirmation limits. Errors, necessary confirmations, and explicitly requested details are not suppressed. Required checks are not reduced, and failures must not be presented as success.

The write workflow finishes with `handoff-runtime.sh --expect-root <project> finalize --log <latest-log>`, which checks the bound project and verification declarations, regenerates indexes, preflights recall, and runs postflight before returning one fixed confirmation within 120 Unicode code points. Normal output is forwarded verbatim; warnings remain visible. The helper cannot intercept a model rewriting its final message, so host tests separately compare the actual reply and reject subsequent tool activity. This does not hide host tool cards or guarantee suppression of mandatory preambles: acceptance counts **all** visible assistant messages. The same runtime parses recall arguments (including `3。说明`) and returns project direction, current state (12288 bytes maximum) and the latest six bounded log summaries by default (2048 bytes per summary; 24576 UTF-8 bytes total including metadata/newlines); GOTCHAS details and optional background are on demand. Oversized mandatory context fails without partial stdout, never with silently omitted tasks. Recall reports end with the stop point, next action and current TODO list; first-time writes initialize once instead of recursively invoking commands. Unknown test coverage or deployment status must stay unknown, not become asserted facts.

**Continuity contract (schema 2 unchanged):** Keep one canonical `<!-- hx:continuity -->` … `<!-- /hx:continuity -->` block inside Project Overview, ≤4096 UTF-8 bytes. It contains overall goal/beneficiaries/problem, success criteria, scope/non-goals, technical/security/compatibility constraints and authorization gates, and effective decisions with reasons/sources. The original block is returned as `continuity_status=explicit_unverified`; without a block, the entire legacy Overview ≤4096 bytes is preserved as `continuity_status=legacy_unverified`. A larger legacy Overview fails nonzero with empty stdout, never deferred wholesale. Duplicate, misplaced, unclosed or damaged markers fail; blocks cannot cross sections and fenced examples are not markers.

Legacy preservation covers only the Overview section, ending at the next unfenced `#` or `##` heading—not the whole main file. Use `###` or deeper subheadings inside Overview: a sibling `## Goals` is outside this boundary, so missing goals/criteria must still be reported under legacy_unverified. Recall never folds headings into Overview; restructuring requires authorized write/tidy.

Empty or whitespace-only blocks fail; incomplete nonempty blocks still require a semantic gap report. `overview_outside_continuity_bytes=N` counts outside-block Overview bytes (heading/background included, markers excluded), not meaning or coverage; N>0 warrants a brief optional-background-not-loaded notice. Both statuses certify structural extraction only, not semantic completeness. Keep phase target/acceptance, work location/unfinished changes, stop point, validation command/date/scope, and blockers/dependencies/risks/unknowns in `hx:recent`; `hx:pending` is the sole current TODO source. Its entire content is retained, including checked lines that may still contain live approvals, risks or unresolved decisions. Only the explicitly separated `hx:done` history is excluded by default. Large legacy pending blocks can exceed the unchanged budget and require explicit organization; no checkbox-based content loss is accepted. Do not duplicate mutable facts or create another state snapshot; active critical facts must not exist only in deferred material. Maintain continuity only during write/init or authorized organization; recall never repairs documents.

Reports enumerate missing/conflicting coverage for goal, phase, success criteria, scope, constraints, effective decisions/reasons/sources, work location/unfinished changes, validation, and blockers/unknowns before the final stop → next → TODO area. Unknown does not mean none; do not guess direction from a title/TODO or choose between conflicting Overview/recent facts by the newest timestamp. Ask before goal-changing or irreversible action when direction is missing/conflicting, without blocking every harmless task.

For timestamps, `bash <skill-path>/scripts/hx.sh now` retains the three lines `human=…`, `fm=…`, and `fn=…`. Use `now --epoch` to append the optional fourth line `epoch=<Unix seconds>` from the same clock read. New log entries may store this optional `epoch:` field; duplicate checks prefer it, while older entries without it still use `date:` interpreted in the local timezone.

🧪 Opt-in memory sync stages files in `./memory/.sync-memory.*`, scans the staged files and local `.md` files that will remain, then publishes by per-file rename. Pre-publication failure preserves old copies. This is **not a batch transaction**: a later publication failure leaves earlier published files in place. Credential hits return exit 1; sync I/O, publication, or scan-unavailable failures return exit 2. A first `on` creates `.sync-enabled` before syncing; a failed sync does not automatically turn it off. See `skills/handoffx/references/handoffx-memory.md`.

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

## 支持矩阵（v4.2.0）

| 维度 | 项 | 状态 |
|------|----|------|
| OS | macOS（bash 3.2） | ✅ 主测 |
| OS | Ubuntu 22.04 容器 | ✅ 容器实测（v4.1.1：38 套件全绿，见 Dev Log 0081；每次切版前重跑 `tests/linux-container.sh`） |
| OS | WSL | ⚠️ 未实机测（install.sh 有 WSL 分支，仅模拟测试） |
| OS | Windows 原生 | ❌ 不支持 |
| 调用 shell | bash | ✅ |
| 调用 shell | zsh 工具 shell | 只能 `bash <script>`（不能 source 到 zsh） |
| CLI | Claude Code / Codex / OpenCode | ✅ 原生安装 |
| CLI | Gemini | 仅安装提示（非安装目标） |
| 项目形态 | git 项目 | ✅ |
| 项目形态 | 非 git 项目 | ✅（升级自动打 tar 备份） |
| 项目形态 | Syncthing / Dropbox / iCloud 目录 | 升级需 `--sync-paused` |

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

Compatibility note for the unreleased continuity contract: preflight may refuse old files with oversized mandatory context or open/ambiguous checkboxes outside pending. Organize only with authorization, preserve task text and unknown status, and rerun the bounded preflight; do not mark old items done just to make the check pass. No installed copy is upgraded merely by editing repository sources.
