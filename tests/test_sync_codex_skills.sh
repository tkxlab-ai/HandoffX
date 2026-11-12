#!/bin/bash
# test_sync_codex_skills.sh — clean legacy ~/.codex/skills duplicates
source "$(dirname "$0")/common.sh"

SCRIPT="$SCRIPTS_DIR/sync-codex-skills.sh"

SANDBOX=$(mktemp -d)
export HOME="$SANDBOX"

mkdir -p "$SANDBOX/.agents/skills/git-release-pipeline/commands"
cat > "$SANDBOX/.agents/skills/git-release-pipeline/SKILL.md" <<'EOF'
---
name: git-release-pipeline
description: release pipeline
---

# Git Release Pipeline
EOF
cat > "$SANDBOX/.agents/skills/git-release-pipeline/commands/GitX-release.md" <<'EOF'
---
description: one command release
---

Run GitX release.
EOF

mkdir -p "$SANDBOX/.agents/skills/1by1"
cat > "$SANDBOX/.agents/skills/1by1/SKILL.md" <<'EOF'
---
name: 1by1
description: one by one
---

# 1by1
EOF

mkdir -p "$SANDBOX/.codex/skills/.system/keep"
cat > "$SANDBOX/.codex/skills/.system/keep/SKILL.md" <<'EOF'
# keep
EOF
mkdir -p "$SANDBOX/.codex/skills/git-release-pipeline"
cat > "$SANDBOX/.codex/skills/git-release-pipeline/SKILL.md" <<'EOF'
# old duplicate mirror
EOF
mkdir -p "$SANDBOX/.codex/skills/GitX-release"
cat > "$SANDBOX/.codex/skills/GitX-release/SKILL.md" <<'EOF'
# old generated alias
EOF
mkdir -p "$SANDBOX/.codex/skills/custom-only"
cat > "$SANDBOX/.codex/skills/custom-only/SKILL.md" <<'EOF'
# custom-only
EOF

output=$(bash "$SCRIPT" 2>&1)
ec=$?
assert_exit "sync exits 0" 0 "$ec"
assert_contains "sync reports official Codex path" "$output" ".agents/skills"
assert_contains "sync reports legacy cleanup" "$output" "legacy duplicates removed"

if [ -e "$SANDBOX/.codex/skills/git-release-pipeline" ]; then
    echo "  ❌ duplicate skill mirror was not removed"
    FAIL=$((FAIL+1))
else
    echo "  ✅ duplicate skill mirror removed"
    PASS=$((PASS+1))
fi
if [ -e "$SANDBOX/.codex/skills/GitX-release" ]; then
    echo "  ❌ duplicate command alias was not removed"
    FAIL=$((FAIL+1))
else
    echo "  ✅ duplicate command alias removed"
    PASS=$((PASS+1))
fi
assert_file_exists "existing Codex system skill preserved" \
    "$SANDBOX/.codex/skills/.system/keep/SKILL.md"
assert_file_exists "custom .codex-only skill preserved" \
    "$SANDBOX/.codex/skills/custom-only/SKILL.md"

rm -rf "$SANDBOX"
unset HOME

summary
