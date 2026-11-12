#!/bin/bash
# sync-codex-skills.sh — remove legacy ~/.codex/skills duplicates
# usage: sync-codex-skills.sh
set -e

AGENTS_SKILLS="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
CODEX_SKILLS="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

echo "ℹ️  Codex official user skills path: $AGENTS_SKILLS"

if [ ! -d "$CODEX_SKILLS" ]; then
    echo "✅ legacy duplicates removed: 0"
    exit 0
fi

removed=0
if [ -d "$AGENTS_SKILLS" ]; then
    for skill_dir in "$AGENTS_SKILLS"/*; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        case "$skill_name" in
            .* ) continue ;;
        esac
        if [ -e "$CODEX_SKILLS/$skill_name" ]; then
            rm -rf "${CODEX_SKILLS:?}/$skill_name"
            removed=$((removed+1))
        fi
        if [ -d "$skill_dir/commands" ]; then
            for command_file in "$skill_dir"/commands/*.md; do
                [ -f "$command_file" ] || continue
                alias_name=$(basename "$command_file" .md)
                [ "$alias_name" = "$skill_name" ] && continue
                if [ -e "$CODEX_SKILLS/$alias_name" ]; then
                    rm -rf "${CODEX_SKILLS:?}/$alias_name"
                    removed=$((removed+1))
                fi
            done
        fi
    done
fi

echo "✅ legacy duplicates removed: $removed"
