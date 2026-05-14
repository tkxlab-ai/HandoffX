#!/bin/bash
# test_skill_metadata_budget.sh — SKILL.md frontmatter must stay small and parseable
source "$(dirname "$0")/common.sh"

SCRIPT="$SCRIPTS_DIR/validate-skill-metadata.sh"

assert_file_exists "metadata validator script exists" "$SCRIPT"

TMP_SKILLS="$TMP_DIR/metadata_budget_$$"
rm -rf "$TMP_SKILLS"
mkdir -p "$TMP_SKILLS/too-long"

cat > "$TMP_SKILLS/too-long/SKILL.md" <<'EOF'
---
name: too-long
description: This description is intentionally much too long for palette and context-budget use. It should fail because SKILL.md descriptions are only lightweight trigger indexes, not documentation bodies or trigger keyword dumps.
---

# Too Long
EOF

"$SCRIPT" "$TMP_SKILLS" >/dev/null 2>&1
assert_exit "budget gate rejects overlong descriptions" 1 "$?"

"$SCRIPT" "$ROOT_DIR/skills" >/dev/null 2>&1
assert_exit "project skill metadata passes budget" 0 "$?"

rm -rf "$TMP_SKILLS"

summary
