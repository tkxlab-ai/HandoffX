#!/bin/bash
# handoff-sync.sh — shared names for the cross-machine backup directory.
#
# .agent-sessions-sync-hx/ is a BACKUP and a cross-machine reading area, never
# a client's runtime directory (Boss 2026-11-22): each machine writes only
# machines/<its name>/ (one writer per file, so Syncthing never sees two
# machines editing the same file), and recall only reads the others.
# Sourced by sync-memory.sh (writer) and handoff-runtime.sh (recall reader).

HX_SYNC_DIR=".agent-sessions-sync-hx"

# hx_machine_name — this machine's directory name: LocalHostName on macOS,
# short hostname elsewhere; lowercased, anything outside [a-z0-9-] becomes '-'.
# HX_SYNC_MACHINE overrides it (tests, or a machine whose hostname changes).
hx_machine_name() {
    local n="${HX_SYNC_MACHINE:-}"
    if [ -z "$n" ]; then
        n=$(scutil --get LocalHostName 2>/dev/null) || n=""
        [ -n "$n" ] || n=$(hostname -s 2>/dev/null) || n=""
    fi
    n=$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')
    [ -n "$n" ] || return 1
    printf '%s\n' "$n"
}
