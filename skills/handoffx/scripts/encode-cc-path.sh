#!/bin/bash
# encode-cc-path.sh — encode an absolute filesystem path to Claude Code's
# project-directory naming scheme used under ~/.claude/projects/.
#
# Rule (empirically verified): replace `/`, `_`, and `.` with `-`.
#   /Users/<user>/tkbox/Cloud_Coding/Handoff
#     → -Users-<user>-tkbox-Cloud-Coding-Handoff
#
# Usage:  encode-cc-path.sh <path>
#         encode-cc-path.sh "$PWD"
# Exit:   0 ok / 1 missing arg / 2 invalid

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 <path>"
        echo "Encodes a filesystem path to Claude Code's projects/ directory name."
        echo "Rule: '/', '_', '.' → '-'"
        echo "Example: $0 /Users/<user>/My_Project"
        echo "  → -Users-<user>-My-Project"
        exit 0
        ;;
esac

if [ -z "${1:-}" ]; then
    echo "❌ missing path argument" >&2
    echo "   Usage: $0 <path>" >&2
    exit 1
fi

# Normalize: strip trailing slashes so "/a/b" and "/a/b/" collapse to the same
# encoding. CC 的 projects/ 目录名来自规范化路径，pwd 在某些 shell / 变量展开下
# 会带末尾 `/`——不处理会生成 `-a-b-` 错过真正的记忆源。
input="$1"
# strip trailing slashes (POSIX sed)
input=$(printf '%s' "$input" | sed 's|/\{1,\}$||')
# guard: if entire path was just slashes, keep a single "/"
[ -z "$input" ] && input="/"

# tr is POSIX, fast, handles all three substitutions in one pass
printf '%s' "$input" | tr '/_.' '-'
