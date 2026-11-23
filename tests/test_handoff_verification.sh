#!/bin/bash
# Pure provenance shape checks; passing does NOT authenticate the claim.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
. "$ROOT/scripts/lib/handoff-verification.sh"
mkdir -p "$ROOT/wip/tmp"
BOX=$(mktemp -d "$ROOT/wip/tmp/verification.XXXXXX")
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0 RC=0 OUT=''
assert_verification() { if "$@"; then PASS=$((PASS+1)); else printf 'FAIL: %s\n' "$*" >&2; FAIL=$((FAIL+1)); fi; }
run() { RC=0; "$@" > "$BOX/out" 2> "$BOX/err" || RC=$?; OUT=$(cat "$BOX/out"); }
bad() { assert_verification test "$RC" -eq 2; assert_verification test ! -s "$BOX/out"; assert_verification test -s "$BOX/err"; }
has() { case "$OUT" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
render() { hx_verification_render --source runner_report --command 'python3 -m unittest' --result '6 passed' "$@"; }
run render
assert_verification test "$RC" -eq 0
assert_verification has 'performed_at: unknown'
assert_verification has 'time_basis: not_provided'
assert_verification has 'time_evidence: not_provided'
cp "$BOX/out" "$BOX/good"
run hx_verification_check --file "$BOX/good" --require
assert_verification test "$RC" -eq 0
assert_verification has 'verification_status=structured_claims_unverified'
assert_verification has 'verification_count=1'
assert_verification has 'verification_unknown_event_times=1'
for source in agent_observed user_report runner_report historical_record unknown; do
 run hx_verification_render --source "$source" --command cmd --result reported; assert_verification test "$RC" -eq 0
done
for basis in explicit_report execution_receipt historical_event; do
 run render --performed-at '2026-01-01 (timezone not supplied)' --time-basis "$basis" --time-evidence 'original report section 2'
 assert_verification test "$RC" -eq 0
 assert_verification has 'performed_at: 2026-01-01 (timezone not supplied)'
done
run render --performed-at '2026-01-01'; bad
run render --time-basis explicit_report --time-evidence 'report'; bad
run render --performed-at '2026-01-01' --time-basis handoff_clock --time-evidence 'hx now'; bad
run render --performed-at '2026-01-01' --time-basis execution_receipt; bad
run render --evidence x --evidence y; bad
run render --bogus x; bad
run render --evidence; bad
run hx_verification_render --source runner_report --command cmd; bad
run hx_verification_render --source fabricated --command cmd --result ok; bad
for invalid in '' '   ' $'x\ny' $'x\ty' $'x\ry' $'x\033y' $'x\001y'; do
 run render --evidence "$invalid"; bad
done
long=$(printf '%2100s' x)
run render --evidence "$long"; bad
# Commands and evidence remain data, not executable shell.
run hx_verification_render --source runner_report --command "\$(touch '$BOX/EXECUTED')" --result '6 passed' --evidence '中文: $(false)'
assert_verification test "$RC" -eq 0; assert_verification test ! -e "$BOX/EXECUTED"; assert_verification has '中文: $(false)'
# Missing / duplicate / unknown / malformed fields or stanzas fail closed.
for variant in missing duplicate field nested open close version indent control; do
 case "$variant" in
 missing) sed '/^source:/d' "$BOX/good" > "$BOX/bad" ;;
 duplicate) sed '/^source:/p' "$BOX/good" > "$BOX/bad" ;;
 field) sed 's/^source:/bogus:/' "$BOX/good" > "$BOX/bad" ;;
 nested) { head -n 3 "$BOX/good"; cat "$BOX/good"; } > "$BOX/bad" ;;
 open) sed '/^<!-- \/verification -->/d' "$BOX/good" > "$BOX/bad" ;;
 close) printf '<!-- /verification -->\n' > "$BOX/bad" ;;
 version) sed 's/verification:v1/verification:v2/' "$BOX/good" > "$BOX/bad" ;;
 indent) sed 's/^<!--/ <!--/' "$BOX/good" > "$BOX/bad" ;;
 control) { head -n 3 "$BOX/good"; printf 'result: bad\033value\n'; tail -n 5 "$BOX/good"; } > "$BOX/bad" ;;
 esac
 run hx_verification_check --file "$BOX/bad"; bad
done
printf 'old unstructured assertions\n' > "$BOX/legacy"
run hx_verification_check --file "$BOX/legacy"; assert_verification test "$RC" -eq 0; assert_verification has legacy_unverified
run hx_verification_check --file "$BOX/legacy" --require; bad
for fence in '```' '~~~~'; do
 { printf '%smd\n' "$fence"; cat "$BOX/good"; printf '%s\n' "$fence"; } > "$BOX/example"
 run hx_verification_check --file "$BOX/example"; assert_verification test "$RC" -eq 0; assert_verification has legacy_unverified
 run hx_verification_check --file "$BOX/example" --require; bad
 cat "$BOX/good" >> "$BOX/example"
 run hx_verification_check --file "$BOX/example" --require; assert_verification test "$RC" -eq 0; assert_verification has 'verification_count=1'
done
cat "$BOX/good" "$BOX/good" > "$BOX/two"
run hx_verification_check --file "$BOX/two" --require; assert_verification test "$RC" -eq 0; assert_verification has 'verification_count=2'
ln -s "$BOX/good" "$BOX/link"
run hx_verification_check --file "$BOX/link"; bad
run hx_verification_check --file "$BOX/missing"; bad
run hx_verification_check --file "$BOX/good" --file "$BOX/good"; bad
assert_verification cmp -s "$ROOT/scripts/lib/handoff-verification.sh" "$ROOT/skills/handoffx/scripts/lib/handoff-verification.sh"
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
test "$FAIL" -eq 0
