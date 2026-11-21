#!/usr/bin/env bash
# Offline only. All generated artifacts stay inside this checkout's wip/.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$ROOT/wip/logs"
LOG="$(mktemp "$ROOT/wip/logs/roundtrip-contract.XXXXXX")"
PYTHONDONTWRITEBYTECODE=1 python3 -B "$ROOT/tests/test_roundtrip_contract.py" 2>&1 | tee "$LOG"
printf 'Offline test log: %s\n' "$LOG"
