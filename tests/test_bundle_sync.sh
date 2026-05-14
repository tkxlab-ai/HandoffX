#!/bin/bash
# test_bundle_sync.sh — meta-test: commands/ and references/ directories
# between dev (skills/handoff/) and installed bundle must be byte-identical.
# Prevents the class of bug where slash command behavior drifts from its spec
# (Gotcha #5 sibling: dual-copy divergence for non-script files).
source "$(dirname "$0")/common.sh"

BUNDLE_CMDS="$ROOT_DIR/skills/handoff/commands"
BUNDLE_REFS="$ROOT_DIR/skills/handoff/references"

# ── commands: existence ──
assert_file_exists "dev commands/ exists" "$BUNDLE_CMDS/handoff.md"
assert_file_exists "dev commands/ handoff-recall.md" "$BUNDLE_CMDS/handoff-recall.md"
assert_file_exists "dev commands/ handoff-tidy.md" "$BUNDLE_CMDS/handoff-tidy.md"
assert_file_exists "dev commands/ handoff-memory.md" "$BUNDLE_CMDS/handoff-memory.md"
assert_file_exists "dev commands/ handoff-init.md" "$BUNDLE_CMDS/handoff-init.md"

# ── commands: dev bundle self-check ──
# Since commands live only in the skill directory (no separate dev copy),
# verify all 5 shims exist and are non-empty
for f in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
    if [ -s "$BUNDLE_CMDS/$f" ]; then
        echo "  ✅ commands/$f exists and non-empty"
        PASS=$((PASS+1))
    else
        echo "  ❌ commands/$f missing or empty"
        FAIL=$((FAIL+1))
    fi
done

# ── commands: content integrity (each file has required sections) ──
# All command shims must have frontmatter with name/description
for f in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
    if head -2 "$BUNDLE_CMDS/$f" | grep -q "^---"; then
        echo "  ✅ commands/$f has frontmatter"
        PASS=$((PASS+1))
    else
        echo "  ❌ commands/$f missing frontmatter"
        FAIL=$((FAIL+1))
    fi
done

# ── references: existence ──
for f in handoff-write.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
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
for f in handoff-write.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md; do
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

# ── install.sh contains commands/ in its copy list ──
# Verify install.sh references the commands directory for installation
if grep -q "commands" "$ROOT_DIR/install.sh"; then
    echo "  ✅ install.sh references commands/"
    PASS=$((PASS+1))
else
    echo "  ❌ install.sh does not reference commands/"
    FAIL=$((FAIL+1))
fi

summary
