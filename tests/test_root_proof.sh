#!/bin/bash
# Regression of Opus-reviewed write intent and recent/log provenance gaps.
# No real global installation; all fixtures/temp/evidence live under wip.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "$ROOT/wip/tmp"
BOX=$(mktemp -d "$ROOT/wip/tmp/root-proof.XXXXXX")
trap 'if [ "$?" -eq 0 ]; then rm -rf "$BOX"; else echo "failed fixture: $BOX" >&2; fi' EXIT
export TMPDIR="$BOX"
PASS=0 FAIL=0 RC=0
check() { if "$@"; then PASS=$((PASS+1)); else echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); fi; }
run() { local cwd=$1; shift; RC=0; (cd "$cwd" && /bin/bash "$@") > "$BOX/out" 2> "$BOX/err" || RC=$?; }
bad() { check test "$RC" -ne 0; check test ! -s "$BOX/out"; }
# Build an actual installed global skill with an isolated installer HOME, then
# retain the caller HOME for runtime legacy-peer classification (no writes there).
unset CLAUDE_CONFIG_DIR HANDOFFX_INSTALL_FAIL_AT HANDOFF_TEST_PLATFORM
mkdir -p "$BOX/sandbox-home"
(HOME="$BOX/sandbox-home" XDG_CONFIG_HOME="$BOX/sandbox-home/.config" CODEX_HOME="$BOX/sandbox-home/.codex" \
 HANDOFF_TEST_WSL_APPDATA="$BOX/sandbox-home/wsl" /bin/bash "$ROOT/install.sh" --claude) > "$BOX/install.out" 2> "$BOX/install.err"
G="$BOX/sandbox-home/.claude/skills/handoffx/scripts"
P="$BOX/intended 中文"; OTHER="$BOX/other"; mkdir -p "$P" "$OTHER"
run "$P" "$G/handoff-runtime.sh" context --root "$P" --skill-root "$G/.."; check test "$RC" -eq 0
run "$OTHER" "$G/handoff-runtime.sh" init; bad; check test ! -e "$OTHER/HANDOFFX.md"
run "$OTHER" "$G/handoff-runtime.sh" --expect-root "$P" init; bad; check test ! -e "$OTHER/HANDOFFX.md"
run "$P" "$G/handoff-runtime.sh" --expect-root "$P" init; check test "$RC" -eq 0; check test -f "$P/HANDOFFX.md"
run "$P" "$G/handoff-runtime.sh" --expect-root "$P" init --root "$OTHER"; bad; check test ! -e "$OTHER/HANDOFFX.md"
run "$P" "$G/handoff-runtime.sh" --expect-root . init; bad
run "$P" "$G/handoff-runtime.sh" --expect-root "$P" --expect-root "$P" init; bad
# Snapshot remains exactly unchanged for all wrong-target writer invocations.
cp "$P/HANDOFFX.md" "$BOX/main-before"
printf 'changed\n' > "$BOX/recent"
for cwd in "$P" "$OTHER"; do
 run "$cwd" "$G/hx.sh" --expect-root "$P" block set recent --from "$BOX/recent" --file "$OTHER/HANDOFFX.md"; bad
 run "$cwd" "$G/hx.sh" --expect-root "$P" regen --root "$OTHER"; bad
 run "$cwd" "$G/handoff-postflight.sh" --expect-root "$P" "$OTHER/HANDOFFX.md"; bad
 check cmp -s "$BOX/main-before" "$P/HANDOFFX.md"
done
run "$P" "$G/hx.sh" block set recent --from "$BOX/recent"; bad
run "$P" "$G/hx.sh" regen; bad
run "$P" "$G/hx.sh" next-number logs; bad
run "$P" "$G/handoff-postflight.sh" HANDOFFX.md; bad
check cmp -s "$BOX/main-before" "$P/HANDOFFX.md"
run "$P" "$G/hx.sh" --expect-root "$P" block set recent --from "$BOX/recent"; check test "$RC" -eq 0
run "$P" "$G/hx.sh" --expect-root "$P" regen; check test "$RC" -eq 0
run "$P" "$G/hx.sh" --expect-root "$P" next-number logs; check test "$RC" -eq 0
run "$P" "$G/handoff-postflight.sh" --expect-root "$P" HANDOFFX.md; check test "$RC" -eq 0
run "$P" "$G/handoff-runtime.sh" recall; check test "$RC" -eq 0
# Project-local binding remains compatible and still rejects wrong cwd.
(HOME="$BOX/sandbox-home" XDG_CONFIG_HOME="$BOX/sandbox-home/.config" CODEX_HOME="$BOX/sandbox-home/.codex" /bin/bash "$ROOT/install.sh" --project "$P") > "$BOX/local-install.out" 2> "$BOX/local-install.err"
L="$P/.claude/skills/handoffx/scripts"
run "$P" "$L/handoff-runtime.sh" init; check test "$RC" -eq 0
run "$OTHER" "$L/handoff-runtime.sh" --expect-root "$P" init; bad
# Standard macOS aliases: resolve to this fixture, never initialize /var itself.
if [ -L /var ] && [ -d /private/var ]; then
 run "$P" "$L/handoff-runtime.sh" --expect-root "/var/../..$P" init --root "/var/../..$P"; check test "$RC" -eq 0
fi
# Verify both source and shipped mirrors, each with independent current state.
for S in "$ROOT/scripts" "$ROOT/skills/handoffx/scripts"; do
 Q="$BOX/v-$PASS"; mkdir "$Q"
 run "$Q" "$S/handoff-runtime.sh" --expect-root "$Q" init; check test "$RC" -eq 0
 cp "$Q/HANDOFFX.md" "$BOX/blank"
 run "$Q" "$S/handoff-runtime.sh" verification --source runner_report --command cmd --result old; check test "$RC" -eq 0
 cp "$BOX/out" "$BOX/stanza"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require; bad
 # Only pending has a declaration: cannot satisfy the recent requirement.
 run "$Q" "$S/hx.sh" --expect-root "$Q" block set pending --from "$BOX/stanza"; check test "$RC" -eq 0
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require; bad
 cp "$BOX/blank" "$Q/HANDOFFX.md"
 run "$Q" "$S/hx.sh" --expect-root "$Q" block set recent --from "$BOX/stanza"; check test "$RC" -eq 0
 cp "$BOX/stanza" "$Q/Handoffx_Logs/0001-test.md"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require --match-file Handoffx_Logs/0001-test.md; check test "$RC" -eq 0
 check grep -q 'verification_match=declared_fields_equal' "$BOX/out"
 # Self-comparison and external copies are not evidence of a new log.
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file HANDOFFX.md; bad
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file "$BOX/stanza"; bad
 cp "$BOX/stanza" "$Q/Handoffx_Logs/0002-new.md"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file Handoffx_Logs/0001-test.md; bad
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file Handoffx_Logs/0002-new.md; check test "$RC" -eq 0
 rm "$Q/Handoffx_Logs/0002-new.md"
 sed 's/result: old/result: new/' "$BOX/stanza" > "$Q/Handoffx_Logs/0001-test.md"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require --match-file Handoffx_Logs/0001-test.md; bad
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file absent; bad
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file; bad
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require --require; bad
 # Fenced examples, even identical, are not a current declaration.
 { printf '\140\140\140md\n'; cat "$BOX/stanza"; printf '\140\140\140\n'; } > "$BOX/fenced"
 run "$Q" "$S/hx.sh" --expect-root "$Q" block set recent --from "$BOX/fenced"; check test "$RC" -eq 0
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --require; bad
 # Multi-stanza sets must match, not just share one matching old claim.
 cat "$BOX/stanza" "$BOX/stanza" > "$BOX/two"
 run "$Q" "$S/hx.sh" --expect-root "$Q" block set recent --from "$BOX/two"; check test "$RC" -eq 0
 cp "$BOX/stanza" "$Q/Handoffx_Logs/0001-test.md"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file Handoffx_Logs/0001-test.md; bad
 cp "$BOX/two" "$Q/Handoffx_Logs/0001-test.md"
 run "$Q" "$S/handoff-runtime.sh" verification-check --current --match-file Handoffx_Logs/0001-test.md; check test "$RC" -eq 0
 # No new verification: legacy content is permitted without --require/match.
 printf 'historical unstructured facts\n' > "$BOX/old"
 run "$Q" "$S/hx.sh" --expect-root "$Q" block set recent --from "$BOX/old"; check test "$RC" -eq 0
 run "$Q" "$S/handoff-runtime.sh" verification-check --current; check test "$RC" -eq 0
 check grep -q legacy_unverified "$BOX/out"
done
# Unbound source CLI may target an explicit project outside cwd. Do not turn
# its inferred target into an expected invocation cwd at the child archive call.
Q="$BOX/source-target"; mkdir "$Q"
run "$Q" "$ROOT/scripts/handoff-runtime.sh" init; check test "$RC" -eq 0
run "$BOX" "$ROOT/scripts/handoff-postflight.sh" "$Q/HANDOFFX.md"; check test "$RC" -eq 0
# A distributed skill copy (SKILL.md, no manifest) may not write an implicit
# target: that was the review #7 fail-open. Only repository source keeps it.
run "$BOX" "$ROOT/skills/handoffx/scripts/handoff-postflight.sh" "$Q/HANDOFFX.md"; bad
run "$BOX" "$ROOT/scripts/handoff-postflight.sh" --expect-root "$Q" "$Q/HANDOFFX.md"; bad
# A logical shell PWD is not silently promoted into expected_root. Actual cwd
# still resolves physically; an explicit symlink root remains forbidden.
ln -s "$Q" "$BOX/logical-cwd"
run "$BOX/logical-cwd" "$ROOT/scripts/handoff-postflight.sh" HANDOFFX.md; check test "$RC" -eq 0
run "$BOX/logical-cwd" "$ROOT/scripts/handoff-postflight.sh" --expect-root "$Q" HANDOFFX.md; check test "$RC" -eq 0
printf 'root proof: %s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
