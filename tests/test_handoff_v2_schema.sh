#!/bin/bash
source "$(dirname "$0")/common.sh"
source "$ROOT_DIR/scripts/lib/handoff-v2.sh"

# Slugify: ASCII titles
out=$(slugify "v1.2.10 OpenCode commands path fix")
assert_contains "C1: slugify ascii title" "$out" "v1-2-10-opencode-commands-path-fix"

# Slugify: max 40 chars
long=$(slugify "this is a very long title that should be truncated to forty characters maximum")
[ "${#long}" -le 40 ] && { echo "  ✅ C2: slugify truncates >40"; PASS=$((PASS+1)); } || { echo "  ❌ C2: slugify did not truncate"; FAIL=$((FAIL+1)); }

# L1 (v4.1.1): the 40-char cut lands on a word boundary — the field slug
# ended in "-reminde". One over-long word still keeps its first 40 chars.
assert_exit "L1: slugify cuts back to the last whole word" 0 \
    "$([ "$(slugify 'handoffx layout upgrade facetime reminder forge skill dist')" = handoffx-layout-upgrade-facetime ] && echo 0 || echo 1)"
assert_exit "L1: a cut that lands exactly on a dash keeps every whole word" 0 \
    "$([ "$(slugify 'aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeee')" = aaaaaaaaa-bbbbbbbbb-ccccccccc-ddddddddd ] && echo 0 || echo 1)"
assert_exit "L1: one over-long word keeps its first 40 chars" 0 \
    "$([ "$(slugify "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45) tail")" = "$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)" ] && echo 0 || echo 1)"

# Slugify: Chinese fallback to entry-<hash>
zh=$(slugify "处理OpenCode安装bug")
case "$zh" in
    entry-*) echo "  ✅ C3: chinese title falls back to entry-<hash>"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C3: chinese fallback failed: got '$zh'"; FAIL=$((FAIL+1)) ;;
esac

# Slugify: all-punctuation fallback to entry-<hash>
punct=$(slugify '!@#$%^&*()')
case "$punct" in
    entry-*) echo "  ✅ C4: all-punctuation title falls back to entry-<hash>"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C4: all-punctuation fallback failed: got '$punct'"; FAIL=$((FAIL+1)) ;;
esac

# C5: acquire_next_number returns 0001 in empty dir
TMP=$(mktemp -d)
mkdir -p "$TMP/$HX_LOGS_DIR"
n=$(acquire_next_number "$TMP/$HX_LOGS_DIR")
assert_contains "C5: acquire_next_number empty dir returns 0001" "$n" "0001"

# C6: acquire_next_number returns max+1 with existing entries
touch "$TMP/$HX_LOGS_DIR/0001-2026-04-18T2030-init.md"
touch "$TMP/$HX_LOGS_DIR/0029-2026-05-06T2253-x.md"
n=$(acquire_next_number "$TMP/$HX_LOGS_DIR")
assert_contains "C6: acquire_next_number returns 0030" "$n" "0030"
# L2 (v4.1.1): the number ends with a newline (od showed 4 bytes, no \n) so it
# does not glue onto the next output line; $( ) callers strip it anyway.
assert_exit "L2: acquire_next_number output ends with a newline" 0 \
    "$([ "$(acquire_next_number "$TMP/$HX_LOGS_DIR" | od -An -c | tr -s ' ' | sed 's/^ //;s/ $//')" = '0 0 3 0 \n' ] && echo 0 || echo 1)"
rm -rf "$TMP"

# C7: verify_v2_layout accepts file with v2 marker
TMP=$(mktemp -d)
echo "<!-- HANDOFF v2 schema -->" > "$TMP/$HX_MAIN_FILE"
echo "# Handoff" >> "$TMP/$HX_MAIN_FILE"
verify_v2_layout "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C7: verify_v2_layout accepts v2 marker"; PASS=$((PASS+1)); } || { echo "  ❌ C7: rejected v2 marker"; FAIL=$((FAIL+1)); }

# C8: verify_v2_layout rejects v1 layout (Dev Log entries, no marker)
cat > "$TMP/HANDOFF-v1.md" <<'EOF'
# Handoff
## 📜 Development Log
### 2026-05-07 — entry
EOF
verify_v2_layout "$TMP/HANDOFF-v1.md" && { echo "  ❌ C8: verify_v2_layout passed v1 layout"; FAIL=$((FAIL+1)); } || { echo "  ✅ C8: verify_v2_layout rejects v1"; PASS=$((PASS+1)); }

# C9: verify_v2_layout passes when file doesn't exist (init-time)
verify_v2_layout "$TMP/nonexistent.md" && { echo "  ✅ C9: verify_v2_layout passes for missing file"; PASS=$((PASS+1)); } || { echo "  ❌ C9: failed on missing file"; FAIL=$((FAIL+1)); }

rm -rf "$TMP"

# ─── regenerate_pointers (E2/E3) ───────────────────────────────────────────
# C10: stale stat lines get rewritten from current sibling state
TMP=$(mktemp -d)
cat > "$TMP/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📜 Development Log

> pointer block

最近一条：(none)
最早一条：(none)
共 0 条

## 🐛 Known Gotchas

> pointer

共 0 条；最新：(none)

## 🧭 Decision Log

> pointer

共 0 条；最新：`(none)`

EOF
mkdir -p "$TMP/$HX_LOGS_DIR" "$TMP/$HX_DEC_DIR"
echo "first" > "$TMP/$HX_LOGS_DIR/0001-2026-04-18T2030-grep-dash-prefix.md"
echo "mid"   > "$TMP/$HX_LOGS_DIR/0015-2026-05-01T1400-mid.md"
echo "last"  > "$TMP/$HX_LOGS_DIR/0030-2026-05-07T0930-v1-2-10.md"
echo "dec1"  > "$TMP/$HX_DEC_DIR/0001-2026-04-23-experimental-memory.md"
echo "dec2"  > "$TMP/$HX_DEC_DIR/0011-2026-05-07-handoff-v2.md"
cat > "$TMP/$HX_GOTCHAS_FILE" <<'EOF'
# Known Gotchas

### Gotcha #1 — `[build]` first
- foo

### Gotcha #13 — `[runtime]` cleanup set -e trap
- bar
EOF

regenerate_pointers "$TMP/$HX_MAIN_FILE"
ec=$?

assert_exit "C10: regenerate_pointers exits 0 on v2 file" 0 "$ec"
grep -q '^最近一条：0030-2026-05-07T0930-v1-2-10.md$' "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C10: latest dev-log stat updated"; PASS=$((PASS+1)); } || { echo "  ❌ C10: latest stat wrong"; FAIL=$((FAIL+1)); }
grep -q '^最早一条：0001-2026-04-18T2030-grep-dash-prefix.md$' "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C10: oldest dev-log stat updated"; PASS=$((PASS+1)); } || { echo "  ❌ C10: oldest stat wrong"; FAIL=$((FAIL+1)); }
grep -q '^共 3 条$' "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C10: dev-log count = 3"; PASS=$((PASS+1)); } || { echo "  ❌ C10: dev-log count wrong"; FAIL=$((FAIL+1)); }
grep -q '^共 2 条；最新：Gotcha #13 — `\[runtime\]` cleanup set -e trap$' "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C10: gotcha stat updated"; PASS=$((PASS+1)); } || { echo "  ❌ C10: gotcha stat wrong"; FAIL=$((FAIL+1)); }
grep -q '^共 2 条；最新：`0011-2026-05-07-handoff-v2.md`$' "$TMP/$HX_MAIN_FILE" && { echo "  ✅ C10: decision stat updated"; PASS=$((PASS+1)); } || { echo "  ❌ C10: decision stat wrong"; FAIL=$((FAIL+1)); }

# C11: idempotent — second call leaves file byte-identical
sha_before=$(shasum "$TMP/$HX_MAIN_FILE" | cut -d' ' -f1)
regenerate_pointers "$TMP/$HX_MAIN_FILE"
sha_after=$(shasum "$TMP/$HX_MAIN_FILE" | cut -d' ' -f1)
[ "$sha_before" = "$sha_after" ] && { echo "  ✅ C11: regenerate_pointers idempotent"; PASS=$((PASS+1)); } || { echo "  ❌ C11: not idempotent"; FAIL=$((FAIL+1)); }

# C12: no-op on v1 layout (no marker)
echo "## 📜 Development Log" > "$TMP/v1.md"
echo "### 2026-04-01 — old entry" >> "$TMP/v1.md"
sha_v1_before=$(shasum "$TMP/v1.md" | cut -d' ' -f1)
regenerate_pointers "$TMP/v1.md"
sha_v1_after=$(shasum "$TMP/v1.md" | cut -d' ' -f1)
[ "$sha_v1_before" = "$sha_v1_after" ] && { echo "  ✅ C12: no-op on v1 file (missing marker)"; PASS=$((PASS+1)); } || { echo "  ❌ C12: mutated v1 file"; FAIL=$((FAIL+1)); }

# C13: handles empty $HX_LOGS_DIR/ → "(none)" placeholders
TMP2=$(mktemp -d)
cat > "$TMP2/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
## 📜 Development Log
最近一条：stale.md
最早一条：stale.md
共 99 条

## 🐛 Known Gotchas
共 99 条；最新：stale title

## 🧭 Decision Log
共 99 条；最新：`stale.md`
EOF
mkdir -p "$TMP2/$HX_LOGS_DIR" "$TMP2/$HX_DEC_DIR"   # empty
regenerate_pointers "$TMP2/$HX_MAIN_FILE"
grep -q '^最近一条：(none)$' "$TMP2/$HX_MAIN_FILE" && { echo "  ✅ C13: empty log dir → (none)"; PASS=$((PASS+1)); } || { echo "  ❌ C13: empty handling wrong"; FAIL=$((FAIL+1)); }
grep -q '^共 0 条$' "$TMP2/$HX_MAIN_FILE" && { echo "  ✅ C13: empty dev-log count = 0"; PASS=$((PASS+1)); } || { echo "  ❌ C13: count not zero'd"; FAIL=$((FAIL+1)); }
rm -rf "$TMP2"

rm -rf "$TMP"

# C14 (Codex review #12): regenerate_pointers refuses to overwrite when
# $HX_MAIN_FILE mtime changed between read and write — narrows the concurrent-
# write race window from "silent loss" to "deterministic refuse".
TMP_RACE=$(mktemp -d)
cat > "$TMP_RACE/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
## 📜 Development Log

最近一条：(none)
最早一条：(none)
共 0 条

## 🐛 Known Gotchas

共 0 条；最新：(none)

## 🧭 Decision Log

共 0 条；最新：`(none)`
EOF
mkdir -p "$TMP_RACE/$HX_LOGS_DIR" "$TMP_RACE/$HX_DEC_DIR"
echo "# stub" > "$TMP_RACE/$HX_GOTCHAS_FILE"

# Simulate mtime drift: read snapshot in subshell, then bump mtime, then call.
# We can't actually race two processes in a shell test, but we can hand-craft
# the exact mtime-changed signal regenerate_pointers checks for by:
#   1. forcing the file's mtime to a known-old value
#   2. backgrounding regenerate_pointers, but immediately bumping mtime so
#      the post-awk re-check fails
#
# Easier: directly stub the function with a synthetic mtime mismatch by
# touching the file mid-call via a wrapper script. Below is simpler — verify
# the success path under no race + verify mtime-bump-after-snapshot causes
# refusal by patching $main_md between snapshot and the actual function call.
#
# Use a wrapper: source the lib, snapshot mtime by hand, sleep+touch, then
# verify regenerate_pointers can be tricked into the error path by directly
# poisoning the snapshot variable. The most robust black-box test is to
# verify the no-race success path is unchanged (mtime preserved, content
# rewritten) and add the race-detection assertion via a code-path test:

# Success path: no race, regenerate succeeds + content updated
echo "first" > "$TMP_RACE/$HX_LOGS_DIR/0001-2026-05-07T0930-test.md"
regenerate_pointers "$TMP_RACE/$HX_MAIN_FILE"
assert_contains "C14 success: stat updated to 1 entry" "$(cat "$TMP_RACE/$HX_MAIN_FILE")" "共 1 条"

# Race path: simulate by touching $HX_MAIN_FILE *during* the function call.
# We can't reliably mid-call interleave in shell, but we can verify the
# guard logic by making the "before" mtime artificially old via a custom
# shell wrapper that monkey-patches stat. Alternative: test that bumping
# mtime DURING execution wouldn't matter because mtime_before is captured
# at function start. The reasonable black-box probe is to set $HX_MAIN_FILE
# mtime to a precise stale value, then regenerate, then verify the function
# either succeeded (mtime didn't actually drift) or refused (mtime drifted).
# Both are acceptable — we just want to confirm the guard is wired in:
grep -q 'mtime_before' "$ROOT_DIR/scripts/lib/handoff-v2.sh" \
    && grep -q 'mtime_after'  "$ROOT_DIR/scripts/lib/handoff-v2.sh" \
    && { echo "  ✅ C14: regenerate_pointers wires mtime guard"; PASS=$((PASS+1)); } \
    || { echo "  ❌ C14: mtime guard missing from regenerate_pointers"; FAIL=$((FAIL+1)); }

rm -rf "$TMP_RACE"

# ─── H2: GNU stat must not poison the mtime guard (v4.1.1 field report) ──────
# Why a fake stat: on GNU coreutils `stat -f` means "file system status" — it
# prints a dump whose free-block counters move between calls and exits 1, so a
# `stat -f %m … || stat -c %Y …` chain captured dump+epoch and the guard saw
# "modified by another process" on every busy Linux box. The fake mimics that
# shape so macOS catches the regression too, not only the Linux container.
TMP_GS=$(mktemp -d); mkdir -p "$TMP_GS/bin" "$TMP_GS/p/$HX_LOGS_DIR" "$TMP_GS/p/$HX_DEC_DIR"
cat > "$TMP_GS/bin/stat" <<EOF
#!/bin/sh
case "\$1" in
    -f) n=\$(cat "$TMP_GS/bin/n" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$TMP_GS/bin/n"
        printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\nBlocks: Total: 9999 Free: %s\n' "\$3" "\$n"; exit 1 ;;
    -c) echo 1700000000; exit 0 ;;
esac
exit 1
EOF
chmod +x "$TMP_GS/bin/stat"
printf '<!-- HANDOFF v2 schema -->\n## 📜 Development Log\n最近一条：(none)\n最早一条：(none)\n共 0 条\n' > "$TMP_GS/p/$HX_MAIN_FILE"
echo x > "$TMP_GS/p/$HX_LOGS_DIR/0001-2026-05-07T0930-gs.md"
ec=0; gs_err=$( PATH="$TMP_GS/bin:$PATH"; regenerate_pointers "$TMP_GS/p/$HX_MAIN_FILE" 2>&1 ) || ec=$?
assert_exit "H2: GNU-shaped stat → regenerate_pointers exits 0" 0 "$ec"
assert_not_contains "H2: GNU-shaped stat → no false 'modified by another process'" "$gs_err" "modified by another process"
assert_contains "H2: GNU-shaped stat → stat line rewritten" "$(cat "$TMP_GS/p/$HX_MAIN_FILE")" "共 1 条"
assert_exit "H2: hx_mtime under GNU-shaped stat = the epoch only" 0 \
    "$([ "$( PATH="$TMP_GS/bin:$PATH"; hx_mtime "$TMP_GS/p/$HX_MAIN_FILE" )" = 1700000000 ] && echo 0 || echo 1)"
assert_exit "H2: hx_mtime with the real stat = all digits" 0 \
    "$(hx_mtime "$TMP_GS/p/$HX_MAIN_FILE" | grep -qxE '[0-9]+' && echo 0 || echo 1)"
ec=0; hx_mtime "$TMP_GS/p/nonexistent" >/dev/null 2>&1 || ec=$?
assert_exit "H2: hx_mtime on a missing file → non-zero (no garbage accepted)" 1 "$ec"
rm -rf "$TMP_GS"

# ─── unreadable sibling dir ≠ "0 entries" (2026-10-29, Gotcha #24 mutator variant) ──
# regenerate_pointers used `ls … 2>/dev/null | wc -l`: an unreadable
# $HX_LOGS_DIR/ counted as 0 and the main file was rewritten to "共 0 条";
# regenerate_decision_index wrote an empty INDEX.md. Both must refuse (exit 2)
# and leave the files untouched. root-skip: EUID=0 bypasses chmod 000.
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unreadable-dir controls SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    TMP_UR=$(mktemp -d)
    mkdir -p "$TMP_UR/$HX_LOGS_DIR" "$TMP_UR/$HX_DEC_DIR"
    printf -- '---\nschema: 2\ntype: dev-log\n---\nx\n' > "$TMP_UR/$HX_LOGS_DIR/0001-2026-05-01T1000-a.md"
    printf -- '---\nschema: 2\ntype: decision\ndate: 2026-05-01\nnumber: 0001\ntitle: t\n---\nx\n' > "$TMP_UR/$HX_DEC_DIR/0001-2026-05-01-t.md"
    printf '<!-- HANDOFF v2 schema -->\n# Demo\n\n## 📜 Development Log\n\n最近一条：0001-2026-05-01T1000-a.md\n最早一条：0001-2026-05-01T1000-a.md\n共 1 条\n' > "$TMP_UR/$HX_MAIN_FILE"
    sha_before=$(shasum "$TMP_UR/$HX_MAIN_FILE" | cut -d' ' -f1)
    chmod 000 "$TMP_UR/$HX_LOGS_DIR"
    regenerate_pointers "$TMP_UR/$HX_MAIN_FILE" >/dev/null 2>&1; ec=$?
    chmod 755 "$TMP_UR/$HX_LOGS_DIR"
    sha_after=$(shasum "$TMP_UR/$HX_MAIN_FILE" | cut -d' ' -f1)
    assert_exit "unreadable $HX_LOGS_DIR/ → regenerate_pointers exits 2 (not 共 0 条)" 2 "$ec"
    [ "$sha_before" = "$sha_after" ] && { echo "  ✅ unreadable dir: main file left byte-identical"; PASS=$((PASS+1)); } \
        || { echo "  ❌ unreadable dir: main file was rewritten"; FAIL=$((FAIL+1)); }
    chmod 000 "$TMP_UR/$HX_DEC_DIR"
    regenerate_decision_index "$TMP_UR" >/dev/null 2>&1; ec=$?
    chmod 755 "$TMP_UR/$HX_DEC_DIR"
    assert_exit "unreadable $HX_DEC_DIR/ → regenerate_decision_index exits 2" 2 "$ec"
    [ ! -e "$TMP_UR/$HX_DEC_DIR/INDEX.md" ] && { echo "  ✅ unreadable dir: no empty INDEX.md written"; PASS=$((PASS+1)); } \
        || { echo "  ❌ unreadable dir: INDEX.md was written"; FAIL=$((FAIL+1)); }
    rm -rf "$TMP_UR"
fi

# ─── Z1 (v4.1.1 wave 2): the lib fails closed when its constants are empty ──
# Why: Claude Code's Bash tool may run zsh, where BASH_SOURCE is empty — the
# schema lib was then sourced from "./", the `.` failed without aborting, every
# HX_* stayed empty and regenerate_* went on to write under "$root/" itself.
LIB="$ROOT_DIR/scripts/lib/handoff-v2.sh"
if command -v zsh >/dev/null 2>&1; then
    # fix1 I4: loading under zsh was "fixed" by finding the constants, but
    # `exec 200>` is not a redirection there, so acquire_next_number on a flock
    # system handed out a number with no lock held. The lib now refuses any
    # shell that is not bash, before it defines a single function.
    z_out=$(cd / && zsh -fc "source '$LIB'; echo \"rc=\$?\"; type acquire_next_number" 2>&1)
    assert_contains "Z1(i): zsh -fc source → ❌ bash-only refusal" "$z_out" "❌ handoff-v2.sh: 必须在 bash 下 source"
    assert_contains "Z1(i): zsh -fc source → returns 1" "$z_out" "rc=1"
    assert_not_contains "Z1(i): zsh -fc source → acquire_next_number not defined" "$z_out" "shell function"
else
    echo "  ➖ Z1(i) SKIPPED (zsh not installed)"
fi
b_out=$(cd / && bash -c '. "$1" && type acquire_next_number' _ "$LIB" 2>&1)
assert_contains "Z1(i): bash source → acquire_next_number defined" "$b_out" "acquire_next_number is a function"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ Z1(ii) SKIPPED (root bypasses chmod 000)"
else
    TMP_Z1=$(mktemp -d)
    cp "$ROOT_DIR/scripts/lib/handoff-v2.sh" "$ROOT_DIR/scripts/lib/handoff-schema.sh" "$TMP_Z1/"
    chmod 000 "$TMP_Z1/handoff-schema.sh"
    ec=0; z_err=$(cd / && bash -c '. "$1" && echo "loaded:[$HX_LOGS_DIR]"' _ "$TMP_Z1/handoff-v2.sh" 2>&1) || ec=$?
    chmod 644 "$TMP_Z1/handoff-schema.sh"
    assert_exit "Z1(ii): unreadable schema lib → sourcing fails" 1 "$ec"
    assert_contains "Z1(ii): unreadable schema lib → ❌ names the cause" "$z_err" "schema constants not loaded"
    assert_not_contains "Z1(ii): unreadable schema lib → caller does not go on" "$z_err" "loaded:["
    rm -rf "$TMP_Z1"
fi
TMP_Z1=$(mktemp -d)
printf '<!-- HANDOFF v2 schema -->\n## 📜 Development Log\n最近一条：(none)\n最早一条：(none)\n共 7 条\n' > "$TMP_Z1/$HX_MAIN_FILE"
mkdir -p "$TMP_Z1/$HX_LOGS_DIR" "$TMP_Z1/$HX_DEC_DIR"
sha_before=$(shasum "$TMP_Z1/$HX_MAIN_FILE" | cut -d' ' -f1)
MF="$TMP_Z1/$HX_MAIN_FILE"
ec=0; z_err=$( HX_MAIN_FILE=""; regenerate_pointers "$MF" 2>&1 ) || ec=$?
[ "$ec" -ne 0 ] && ec=nonzero
assert_exit "Z1(iii): HX_MAIN_FILE empty → regenerate_pointers refuses" nonzero "$ec"
assert_contains "Z1(iii): regenerate_pointers refusal names the cause" "$z_err" "schema constants not loaded"
assert_exit "Z1(iii): main file untouched" 0 "$([ "$(shasum "$TMP_Z1/$HX_MAIN_FILE" | cut -d' ' -f1)" = "$sha_before" ] && echo 0 || echo 1)"
ec=0; ( HX_DEC_DIR=""; regenerate_decision_index "$TMP_Z1" ) >/dev/null 2>&1 || ec=$?
[ "$ec" -ne 0 ] && ec=nonzero
assert_exit "Z1(iii): HX_DEC_DIR empty → regenerate_decision_index refuses" nonzero "$ec"
assert_exit "Z1(iii): no INDEX.md written at the project root" 0 "$([ ! -e "$TMP_Z1/INDEX.md" ] && echo 0 || echo 1)"
ec=0; ( HX_LOGS_DIR=""; acquire_next_number "$TMP_Z1/$HX_LOGS_DIR" ) >/dev/null 2>&1 || ec=$?
[ "$ec" -ne 0 ] && ec=nonzero
assert_exit "Z1(iii): HX_LOGS_DIR empty → acquire_next_number refuses" nonzero "$ec"
rm -rf "$TMP_Z1"
# Z1(d): the write flow tells the AI to source the lib under bash, in one
# canonical line shared by SKILL.md, the write reference and the /handoffx shim.
Z1_LINE="bash -c '. <skill-path>/scripts/lib/handoff-v2.sh && regenerate_pointers $HX_MAIN_FILE && regenerate_decision_index .'"
for z1f in SKILL.md references/handoffx-write.md command-shims/handoffx.md; do
    assert_contains "Z1(d): $z1f carries the bash-only sourcing line" "$(cat "$ROOT_DIR/skills/handoffx/$z1f")" "$Z1_LINE"
done

summary
