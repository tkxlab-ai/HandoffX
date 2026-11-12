#!/bin/bash
# test_bundle_sync.sh — meta-test: command-shims/ and references/ directories
# between dev (skills/handoffx/) and installed bundle must be byte-identical.
# Prevents the class of bug where slash command behavior drifts from its spec
# (Gotcha #5 sibling: dual-copy divergence for non-script files).
# v2.1.3: command-shims/ was renamed from commands/ to make the role explicit
# (these are install.sh shim sources, NOT a Claude Code read path — Gotcha #5).
source "$(dirname "$0")/common.sh"

BUNDLE_CMDS="$ROOT_DIR/skills/handoffx/command-shims"
BUNDLE_REFS="$ROOT_DIR/skills/handoffx/references"

# ── commands: existence ──
assert_file_exists "dev command-shims/ exists" "$BUNDLE_CMDS/handoffx.md"
assert_file_exists "dev command-shims/ handoffx-recall.md" "$BUNDLE_CMDS/handoffx-recall.md"
assert_file_exists "dev command-shims/ handoffx-tidy.md" "$BUNDLE_CMDS/handoffx-tidy.md"
assert_file_exists "dev command-shims/ handoffx-memory.md" "$BUNDLE_CMDS/handoffx-memory.md"
assert_file_exists "dev command-shims/ handoffx-init.md" "$BUNDLE_CMDS/handoffx-init.md"

# ── commands: dev bundle self-check ──
# Since commands live only in the skill directory (no separate dev copy),
# verify all 5 shims exist and are non-empty
for f in handoffx.md handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md; do
    if [ -s "$BUNDLE_CMDS/$f" ]; then
        echo "  ✅ command-shims/$f exists and non-empty"
        PASS=$((PASS+1))
    else
        echo "  ❌ command-shims/$f missing or empty"
        FAIL=$((FAIL+1))
    fi
done

# ── commands: exact shim set (P2.2 hard-cut: the five NEW names only, no pre-rename shim left) ──
actual_shims=$(cd "$BUNDLE_CMDS" 2>/dev/null && ls -1 | LC_ALL=C sort | tr '\n' ' ')
expected_shims="handoffx-init.md handoffx-memory.md handoffx-recall.md handoffx-tidy.md handoffx.md "
assert_exit "command-shims/ exact set [$actual_shims]" 0 "$([ "$actual_shims" = "$expected_shims" ] && echo 0 || echo 1)"

# ── commands: content integrity (each file has required sections) ──
# All command shims must have frontmatter with name/description
for f in handoffx.md handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md; do
    if head -2 "$BUNDLE_CMDS/$f" | grep -q "^---"; then
        echo "  ✅ command-shims/$f has frontmatter"
        PASS=$((PASS+1))
    else
        echo "  ❌ command-shims/$f missing frontmatter"
        FAIL=$((FAIL+1))
    fi
done

# ── references: existence ──
for f in handoffx-write.md handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md; do
    if [ -s "$BUNDLE_REFS/$f" ]; then
        echo "  ✅ references/$f exists and non-empty"
        PASS=$((PASS+1))
    else
        echo "  ❌ references/$f missing or empty"
        FAIL=$((FAIL+1))
    fi
done

# ── references: content integrity ──
# Each reference must have a title (## header) and at least 10 lines
for f in handoffx-write.md handoffx-recall.md handoffx-tidy.md handoffx-memory.md handoffx-init.md; do
    lines=$(wc -l < "$BUNDLE_REFS/$f" | tr -d ' ')
    hdr=$(head -5 "$BUNDLE_REFS/$f" | grep -c "^## " || true)
    if [ "$lines" -ge 10 ] && [ "$hdr" -ge 1 ]; then
        echo "  ✅ references/$f has content ($lines lines, $hdr headers)"
        PASS=$((PASS+1))
    else
        echo "  ❌ references/$f too short or no header ($lines lines, $hdr headers)"
        FAIL=$((FAIL+1))
    fi
done

# ── install.sh contains command-shims/ in its copy list ──
# Verify install.sh references the command-shims directory for installation
if grep -q "command-shims" "$ROOT_DIR/install.sh"; then
    echo "  ✅ install.sh references command-shims/"
    PASS=$((PASS+1))
else
    echo "  ❌ install.sh does not reference command-shims/"
    FAIL=$((FAIL+1))
fi

summary
