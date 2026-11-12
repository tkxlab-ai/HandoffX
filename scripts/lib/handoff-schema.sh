#!/bin/bash
# handoff-schema.sh — THE single source of four-piece artifact path constants.
# Sourced, never executed. ⚠ P2 RENAME LOCUS (coupling b/c, Decision 0020):
# the future handoffx mega-program renames ONLY the values here; every consumer
# (xref-grammar lib + coupling-c scripts) sources this — never re-hardcodes.
[ -n "${_HX_SCHEMA_SOURCED:-}" ] && return 0
_HX_SCHEMA_SOURCED=1
HX_LOGS_DIR="Handoff_Logs"
HX_DEC_DIR="Handoff_Decisions"
HX_MAIN_FILE="HANDOFF.md"
HX_GOTCHAS_FILE="GOTCHAS.md"
