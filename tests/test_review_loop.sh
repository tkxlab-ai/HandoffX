#!/bin/bash
# test_review_loop.sh — P0 review-loop (A/B/C/E) TDD suite.
source "$(dirname "$0")/common.sh"

LIB="$ROOT_DIR/tools/lib/review-ledger.sh"
CLI="$ROOT_DIR/tools/review-loop.sh"
WORK="$TMP_DIR/review-loop-$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

assert_file_exists "review-ledger.sh exists" "$LIB"
assert_file_exists "review-loop.sh exists"  "$CLI"
assert_exit "cli help exits 0" 0 "$(bash "$CLI" help >/dev/null 2>&1; echo $?)"

# --- Task 2: content hash ---
echo "alpha" > "$WORK/a.txt"; echo "beta" > "$WORK/b.txt"
H1=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/a.txt" "'"$WORK"'/b.txt"')
H2=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/b.txt" "'"$WORK"'/a.txt"')
assert_contains "hash is 64-hex" "$H1" "$(printf '%s' "$H1" | grep -oE '^[0-9a-f]{64}$')"
assert_exit "hash order-stable (sorted input)" 0 "$([ "$H1" = "$H2" ] && echo 0 || echo 1)"
echo "alpha-changed" > "$WORK/a.txt"
H3=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/a.txt" "'"$WORK"'/b.txt"')
assert_exit "hash changes with content" 0 "$([ "$H1" != "$H3" ] && echo 0 || echo 1)"
assert_exit "missing file -> exit 2" 2 "$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/nope.txt"' >/dev/null 2>&1; echo $?)"

# --- Task 3: ledger append/read ---
LED="$WORK/ledger.tsv"; : > "$LED"
bash -c '. "'"$LIB"'"; rl_append_round "'"$LED"'" 1 codex abc PASS - 2026-05-17T18:00:00+08:00 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$LED"'" 2 spcr def WARN - 2026-05-17T18:05:00+08:00 3'
assert_contains "round 1 line" "$(cat "$LED")" "round=1 reviewer=codex content_hash=abc verdict=PASS ground=- ts=2026-05-17T18:00:00+08:00 findings=0"
assert_contains "round 2 verdict" "$(cat "$LED")" "verdict=WARN"
assert_exit "round count = 2" 0 "$([ "$(bash -c '. "'"$LIB"'"; rl_round_count "'"$LED"'"')" = 2 ] && echo 0 || echo 1)"
assert_exit "round count missing file = 0" 0 "$([ "$(bash -c '. "'"$LIB"'"; rl_round_count "'"$WORK"'/none"')" = 0 ] && echo 0 || echo 1)"

# --- Task 4: convergence ---
mk_led() { local p="$WORK/L$$"; : > "$p"; local i=1; for v in "$@"; do
  bash -c '. "'"$LIB"'"; rl_append_round "'"$p"'" '"$i"' r h '"$v"' - t 0'; i=$((i+1)); done; echo "$p"; }
streak() { bash -c '. "'"$LIB"'"; rl_convergence_streak "'"$1"'"'; }
conv()   { bash -c '. "'"$LIB"'"; rl_is_converged "'"$1"'" && echo Y || echo N'; }
assert_exit "PASS PASS PASS -> streak 3"  0 "$([ "$(streak "$(mk_led PASS PASS PASS)")" = 3 ] && echo 0 || echo 1)"
assert_contains "PASS PASS PASS converged" "$(conv "$(mk_led PASS PASS PASS)")" "Y"
assert_contains "PASS WARN PASS PASS NOT converged (only 2)" "$(conv "$(mk_led PASS WARN PASS PASS)")" "N"
assert_exit "WARN resets: P P W P -> streak 1" 0 "$([ "$(streak "$(mk_led PASS PASS WARN PASS)")" = 1 ] && echo 0 || echo 1)"
assert_contains "4 PASS still converged" "$(conv "$(mk_led PASS PASS PASS PASS)")" "Y"
assert_contains "empty ledger NOT converged" "$(conv "$WORK/empty-$$")" "N"

# --- Task 5: orchestrator validation (C) ---
val() { bash -c '. "'"$LIB"'"; rl_validate_round "$1" "$2" "$3"' _ "$1" "$2" "$3"; }
GOOD="$WORK/f-good"; printf 'scripts/x.sh:42 bad thing\nlib/y.sh:7 other\n' > "$GOOD"
BAD="$WORK/f-bad";  printf 'scripts/x.sh:42 ok\nno-location-here\n' > "$BAD"
EMPTY="$WORK/f-empty"; : > "$EMPTY"
assert_contains "valid PASS no findings -> PASS"        "$(val abc PASS "$EMPTY")" "PASS"
assert_contains "valid WARN well-formed findings -> WARN" "$(val abc WARN "$GOOD")" "WARN"
assert_contains "missing content_hash -> ERROR"          "$(val '' PASS "$EMPTY")" "ERROR"
assert_contains "content_hash '-' -> ERROR"              "$(val - PASS "$EMPTY")" "ERROR"
assert_contains "out-of-enum verdict -> ERROR"           "$(val abc LGTM "$EMPTY")" "ERROR"
assert_contains "finding without file:line -> ERROR"     "$(val abc PASS "$BAD")" "ERROR"
assert_contains "USER_DECISION is in enum"               "$(val abc USER_DECISION "$EMPTY")" "USER_DECISION"
assert_contains "N-A is in enum"                          "$(val abc N-A "$EMPTY")" "N-A"

# --- Task 6: E veto detection ---
veto() { bash -c '. "'"$LIB"'"; rl_is_credential_privacy_veto "$1" "$2" && echo Y || echo N' _ "$1" "$2"; }
assert_contains "BLOCKED+credential -> veto"   "$(veto BLOCKED credential)" "Y"
assert_contains "BLOCKED+privacy -> veto"      "$(veto BLOCKED privacy)" "Y"
assert_contains "BLOCKED+other -> NOT veto"    "$(veto BLOCKED style)" "N"
assert_contains "WARN+credential -> NOT veto"  "$(veto WARN credential)" "N"
assert_contains "PASS+- -> NOT veto"           "$(veto PASS -)" "N"

# --- Task 7: CLI start/status ---
cd "$WORK" || exit 1
echo "code v1" > src.txt
assert_exit "start ok" 0 "$(bash "$CLI" start --topic demo "$WORK/src.txt" >/dev/null 2>&1; echo $?)"
assert_file_exists "scratch ledger created" "$WORK/.review-loop/current/ledger.tsv"
assert_contains "state ACTIVE" "$(cat "$WORK/.review-loop/current/state" 2>/dev/null)" "ACTIVE"
assert_exit "double start refused (exit 2)" 2 "$(bash "$CLI" start --topic demo "$WORK/src.txt" >/dev/null 2>&1; echo $?)"
assert_contains "status shows state" "$(bash "$CLI" status 2>&1)" "ACTIVE"
assert_contains "status shows streak 0" "$(bash "$CLI" status 2>&1)" "streak=0"
cd "$ROOT_DIR" || exit 1

# --- Task 8: CLI record ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic demo "$WORK/s.txt" >/dev/null 2>&1
rec() { bash "$CLI" record --reviewer "$1" --verdict "$2" --ground "${3:--}" "$WORK/s.txt"; }
assert_exit "record PASS exit 0" 0 "$(rec a PASS >/dev/null 2>&1; echo $?)"
rec b PASS >/dev/null 2>&1; rec c PASS >/dev/null 2>&1
assert_contains "3xPASS -> CONVERGED" "$(cat "$WORK/.review-loop/current/state")" "CONVERGED"
# C: a finding without file:line is recorded as ERROR, not the claimed PASS
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d2 "$WORK/s.txt" >/dev/null 2>&1
BADF="$WORK/bf"; printf 'no-location bug\n' > "$BADF"
bash "$CLI" record --reviewer a --verdict PASS --findings "$BADF" "$WORK/s.txt" >/dev/null 2>&1
assert_contains "self-report w/o file:line -> ERROR round" "$(cat "$WORK/.review-loop/current/ledger.tsv")" "verdict=ERROR"
# E: BLOCKED+credential -> VETOED + exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d3 "$WORK/s.txt" >/dev/null 2>&1
ec=$(bash "$CLI" record --reviewer a --verdict BLOCKED --ground credential "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "E veto escalates exit 3" 3 "$ec"
assert_contains "E veto -> state VETOED" "$(cat "$WORK/.review-loop/current/state")" "VETOED"
# cap: max-rounds exceeded without convergence -> CAPPED + exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic d4 "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1
ec2=$(bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "cap exceeded escalates exit 3" 3 "$ec2"
assert_contains "cap -> state CAPPED" "$(cat "$WORK/.review-loop/current/state")" "CAPPED"
cd "$ROOT_DIR" || exit 1

# --- rl_round_count empty-existing-file regression (latent bug found in Task 8) ---
EMPTYLED="$WORK/rc-empty"; : > "$EMPTYLED"
RC_EMPTY=$(bash -c '. "'"$LIB"'"; rl_round_count "'"$EMPTYLED"'"')
assert_exit "round_count empty-existing file is single clean 0" 0 "$([ "$RC_EMPTY" = "0" ] && echo 0 || echo 1)"
assert_exit "round_count empty file not multiline" 0 "$([ "$(printf '%s' "$RC_EMPTY" | wc -l | tr -d ' ')" = "0" ] && echo 0 || echo 1)"

# --- Task 9: finalize + override ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic fin "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer c --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
DL="$WORK/devlog.md"; printf '### log\n' > "$DL"
out=$(bash "$CLI" finalize --devlog "$DL" 2>&1)
assert_contains "finalize emits CONVERGED outcome" "$out" "CONVERGED"
assert_contains "outcome.txt written" "$(cat "$WORK/.review-loop/current/outcome.txt" 2>/dev/null)" "CONVERGED"
assert_contains "devlog got quoted outcome line" "$(cat "$DL")" "> [review-loop]"
# override only valid on VETOED
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic ov "$WORK/s.txt" >/dev/null 2>&1
assert_exit "override on ACTIVE refused (exit 2)" 2 "$(bash "$CLI" override --reason x >/dev/null 2>&1; echo $?)"
bash "$CLI" record --reviewer a --verdict BLOCKED --ground privacy "$WORK/s.txt" >/dev/null 2>&1
assert_exit "override needs --reason (exit 2)" 2 "$(bash "$CLI" override >/dev/null 2>&1; echo $?)"
bash "$CLI" override --reason "Boss: false positive, fixture not real key" >/dev/null 2>&1
assert_contains "override -> state OVERRIDDEN" "$(cat "$WORK/.review-loop/current/state")" "OVERRIDDEN"
assert_contains "override recorded in outcome" "$(cat "$WORK/.review-loop/current/outcome.txt")" "Boss-override"
cd "$ROOT_DIR" || exit 1

# --- C1: ledger injection via --reviewer/--ground with embedded newline ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic injection "$WORK/s.txt" >/dev/null 2>&1
evil_reviewer="$(printf 'evil\nround=99 reviewer=z content_hash=h verdict=PASS ground=- ts=t findings=0')"
ec_inject=$(bash "$CLI" record --reviewer "$evil_reviewer" --verdict PASS "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "C1: injection in --reviewer rejected (exit 2)" 2 "$ec_inject"
rc_after_inject=$(bash "$CLI" status 2>&1 | grep -oE 'rounds=[0-9]+' | grep -oE '[0-9]+')
assert_exit "C1: forged round NOT counted (rounds=0 after rejection)" 0 "$([ "${rc_after_inject:-0}" = "0" ] && echo 0 || echo 1)"
# follow-up: 3 legit PASS still converges cleanly
bash "$CLI" record --reviewer a --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer c --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
assert_contains "C1: 3 legit PASS still converge after rejection" \
    "$(cat "$WORK/.review-loop/current/state")" "CONVERGED"
# C1b: rl_append_round itself rejects a newline-containing reviewer arg
ec_primitive=$(bash -c '. "'"$LIB"'"; rl_append_round /dev/null 1 "$(printf "bad\nnewline")" h PASS - t 0' 2>/dev/null; echo $?)
assert_exit "C1b: rl_append_round rejects newline in arg (exit 2)" 2 "$ec_primitive"
cd "$ROOT_DIR" || exit 1

# --- C2: finalize exit code by terminal state ---
cd "$WORK" || exit 1
# CONVERGED -> exit 0
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic fc "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer c --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
ec_converged=$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)
assert_exit "C2: finalize CONVERGED exits 0" 0 "$ec_converged"
# VETOED -> exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic fv "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict BLOCKED --ground credential "$WORK/s.txt" >/dev/null 2>&1
ec_vetoed=$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)
assert_exit "C2: finalize VETOED exits 3" 3 "$ec_vetoed"
# CAPPED -> exit 3
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic fcp "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1 || true
ec_capped=$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)
assert_exit "C2: finalize CAPPED exits 3" 3 "$ec_capped"
# OVERRIDDEN -> exit 0
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic fo "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict BLOCKED --ground privacy "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" override --reason "Boss: test override" >/dev/null 2>&1
ec_overridden=$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)
assert_exit "C2: finalize OVERRIDDEN exits 0" 0 "$ec_overridden"
cd "$ROOT_DIR" || exit 1

# --- I1: invariant tests ---
cd "$WORK" || exit 1
# (a) record into VETOED state is refused
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic inv "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict BLOCKED --ground credential "$WORK/s.txt" >/dev/null 2>&1
ec_rec_vetoed=$(bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "I1a: record into VETOED state refused (non-zero)" 0 "$([ "$ec_rec_vetoed" != "0" ] && echo 0 || echo 1)"
# (b) finalize exit codes covered by C2 tests above
# (c) ERROR resets streak: P,P,ERROR-inducing(via bad findings),P,P,P -> converged at 6th
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic streak "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer b --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
BADF2="$WORK/bf2"; printf 'no-location bad\n' > "$BADF2"
bash "$CLI" record --reviewer c --verdict PASS --findings "$BADF2" "$WORK/s.txt" >/dev/null 2>&1
# after 3 rounds (2 PASS + 1 ERROR), NOT converged
st5=$(cat "$WORK/.review-loop/current/state")
assert_contains "I1c: 2xPASS+ERROR -> NOT CONVERGED yet" "$st5" "ACTIVE"
bash "$CLI" record --reviewer d --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer e --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
st7=$(cat "$WORK/.review-loop/current/state")
assert_contains "I1c: 2 more PASS after ERROR -> still not CONVERGED (need 3 clean)" "$st7" "ACTIVE"
bash "$CLI" record --reviewer f --verdict PASS "$WORK/s.txt" >/dev/null 2>&1
assert_contains "I1c: 3 consecutive PASS after ERROR -> CONVERGED" \
    "$(cat "$WORK/.review-loop/current/state")" "CONVERGED"
cd "$ROOT_DIR" || exit 1

# --- I2: blank line in findings file -> WARN not ERROR ---
FINDBLANK="$WORK/f-blank"
printf 'scripts/x.sh:42 real bug\n\nlib/y.sh:7 other\n' > "$FINDBLANK"
val_blank=$(bash -c '. "'"$LIB"'"; rl_validate_round abc WARN "'"$FINDBLANK"'"')
assert_contains "I2: blank line in findings -> WARN (not ERROR)" "$val_blank" "WARN"
# still ERROR if a non-blank line is malformed
FINDMIXED="$WORK/f-mixed"
printf 'scripts/x.sh:42 ok\n\nno-location-here\n' > "$FINDMIXED"
val_mixed=$(bash -c '. "'"$LIB"'"; rl_validate_round abc PASS "'"$FINDMIXED"'"')
assert_contains "I2: malformed non-blank line still -> ERROR" "$val_mixed" "ERROR"

# --- I3: --max-rounds 0 / negative / non-integer rejected ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic mr "$WORK/s.txt" >/dev/null 2>&1
ec_mr0=$(bash "$CLI" record --reviewer a --verdict PASS --max-rounds 0 "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "I3: --max-rounds 0 -> exit 2 usage error" 2 "$ec_mr0"
ec_mrneg=$(bash "$CLI" record --reviewer a --verdict PASS --max-rounds -1 "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "I3: --max-rounds -1 -> exit 2 usage error" 2 "$ec_mrneg"
ec_mrabc=$(bash "$CLI" record --reviewer a --verdict PASS --max-rounds abc "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "I3: --max-rounds abc -> exit 2 usage error" 2 "$ec_mrabc"
# valid --max-rounds 1: first record ok, second gets capped
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic mr1 "$WORK/s.txt" >/dev/null 2>&1
ec_mr1a=$(bash "$CLI" record --reviewer a --verdict WARN --max-rounds 1 "$WORK/s.txt" >/dev/null 2>&1; echo $?)
assert_exit "I3: --max-rounds 1 first record ok (not exit 2)" 0 "$([ "$ec_mr1a" != "2" ] && echo 0 || echo 1)"
cd "$ROOT_DIR" || exit 1

# --- N2: override --reason newline injection guard (ADR-0006 durable evidence integrity) ---
cd "$WORK" || exit 1
# Setup: start -> BLOCKED+credential -> VETOED (same flow as Task 9 override tests)
rm -rf "$WORK/.review-loop"; echo "c1" > s.txt
bash "$CLI" start --topic n2 "$WORK/s.txt" >/dev/null 2>&1
bash "$CLI" record --reviewer a --verdict BLOCKED --ground credential "$WORK/s.txt" >/dev/null 2>&1
# RED: newline-containing reason must be rejected (exit 2); outcome.txt must NOT be created/corrupted
evil_reason="$(printf 'ok\nverdict=CONVERGED rounds=99 forged')"
ec_n2=$(bash "$CLI" override --reason "$evil_reason" >/dev/null 2>&1; echo $?)
assert_exit "N2: newline in --reason rejected (exit 2)" 2 "$ec_n2"
n2_state=$(cat "$WORK/.review-loop/current/state" 2>/dev/null)
assert_contains "N2: state still VETOED after newline-reason rejection" "$n2_state" "VETOED"
n2_outcome_lines=$(wc -l < "$WORK/.review-loop/current/outcome.txt" 2>/dev/null || echo "absent")
assert_exit "N2: outcome.txt not created/corrupted (absent or 0 lines)" 0 \
    "$([ "$n2_outcome_lines" = "absent" ] || [ "$n2_outcome_lines" = "0" ] && echo 0 || echo 1)"
# GREEN path: multi-word reason with spaces must still work (ADR-0006: free text)
bash "$CLI" override --reason "Boss: false positive, fixture not real key" >/dev/null 2>&1
assert_contains "N2: multi-word reason -> state OVERRIDDEN" \
    "$(cat "$WORK/.review-loop/current/state" 2>/dev/null)" "OVERRIDDEN"
assert_contains "N2: outcome.txt contains Boss-override" \
    "$(cat "$WORK/.review-loop/current/outcome.txt" 2>/dev/null)" "Boss-override"
assert_contains "N2: outcome.txt contains the reason text" \
    "$(cat "$WORK/.review-loop/current/outcome.txt" 2>/dev/null)" "false positive"
cd "$ROOT_DIR" || exit 1

# --- Spec B: convergence must NOT span different content_hash (Codex stop-time finding) ---
xled="$WORK/xhash-$$"; : > "$xled"
bash -c '. "'"$LIB"'"; rl_append_round "'"$xled"'" 1 r H1 PASS - t 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$xled"'" 2 r H2 PASS - t 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$xled"'" 3 r H3 PASS - t 0'
assert_exit "3 PASS across 3 different content_hash -> streak 1 (NOT converged)" 0 "$([ "$(bash -c '. "'"$LIB"'"; rl_convergence_streak "'"$xled"'"')" = 1 ] && echo 0 || echo 1)"
assert_contains "cross-content 3xPASS NOT converged" "$(bash -c '. "'"$LIB"'"; rl_is_converged "'"$xled"'" && echo Y || echo N')" "N"
sled="$WORK/shash-$$"; : > "$sled"
bash -c '. "'"$LIB"'"; rl_append_round "'"$sled"'" 1 r SAME PASS - t 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$sled"'" 2 r SAME PASS - t 0'
bash -c '. "'"$LIB"'"; rl_append_round "'"$sled"'" 3 r SAME PASS - t 0'
assert_contains "3xPASS same content_hash -> converged" "$(bash -c '. "'"$LIB"'"; rl_is_converged "'"$sled"'" && echo Y || echo N')" "Y"
mled="$WORK/mixed-$$"; : > "$mled"
for spec in "1 H1 PASS" "2 H1 PASS" "3 H2 PASS" "4 H2 PASS" "5 H2 PASS"; do
  set -- $spec; bash -c '. "'"$LIB"'"; rl_append_round "'"$mled"'" '"$1"' r '"$2"' '"$3"' - t 0'
done
assert_contains "P(H1)P(H1)P(H2)P(H2)P(H2) -> converged only at 3rd on H2" "$(bash -c '. "'"$LIB"'"; rl_is_converged "'"$mled"'" && echo Y || echo N')" "Y"
mled2="$WORK/mixed2-$$"; : > "$mled2"
for spec in "1 H1 PASS" "2 H1 PASS" "3 H2 PASS" "4 H2 PASS"; do
  set -- $spec; bash -c '. "'"$LIB"'"; rl_append_round "'"$mled2"'" '"$1"' r '"$2"' '"$3"' - t 0'
done
assert_contains "P(H1)P(H1)P(H2)P(H2) -> NOT converged (only 2 on H2)" "$(bash -c '. "'"$LIB"'"; rl_is_converged "'"$mled2"'" && echo Y || echo N')" "N"

# --- CD1: a round attests the loop's WHOLE start set — subset/superset PASS must not converge ---
# (2026-10-30 convergence-defect audit: record recomputed the hash from the caller's file
#  list and never compared it with the set `start` was given; 3 PASS on one file of two
#  reached CONVERGED while the other file was never reviewed.)
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt; printf 'beta\n' > b.txt; printf 'gamma\n' > c.txt
bash "$CLI" start --topic cd1 b.txt a.txt >/dev/null 2>&1
assert_exit "CD1: meta records the sorted start set as file= lines" 0 \
    "$([ "$(sed -n 's/^file=//p' .review-loop/current/meta | tr '\n' ' ')" = "a.txt b.txt " ] && echo 0 || echo 1)"
ec_sub=$(bash "$CLI" record --reviewer r1 --verdict PASS a.txt >/dev/null 2>&1; echo $?)
assert_exit "CD1: record on a subset of the start set -> exit 2" 2 "$ec_sub"
msg_sub=$(bash "$CLI" record --reviewer r1 --verdict PASS a.txt 2>&1 >/dev/null)
assert_contains "CD1: subset refusal shows the start set" "$msg_sub" "b.txt"
for r in r1 r2 r3; do bash "$CLI" record --reviewer $r --verdict PASS a.txt >/dev/null 2>&1; done
assert_contains "CD1: 3xPASS on a subset -> still ACTIVE, not CONVERGED" "$(cat .review-loop/current/state)" "ACTIVE"
assert_exit "CD1: subset rounds are not recorded (rounds=0)" 0 \
    "$([ "$(bash "$CLI" status 2>&1 | grep -oE 'rounds=[0-9]+')" = "rounds=0" ] && echo 0 || echo 1)"
ec_sup=$(bash "$CLI" record --reviewer r1 --verdict PASS a.txt b.txt c.txt >/dev/null 2>&1; echo $?)
assert_exit "CD1: record on a superset of the start set -> exit 2" 2 "$ec_sup"
bash "$CLI" record --reviewer r1 --verdict PASS b.txt a.txt >/dev/null 2>&1
bash "$CLI" record --reviewer r2 --verdict PASS a.txt b.txt >/dev/null 2>&1
bash "$CLI" record --reviewer r3 --verdict PASS a.txt b.txt >/dev/null 2>&1
assert_contains "CD1: 3xPASS on the whole set (any order) -> CONVERGED" "$(cat .review-loop/current/state)" "CONVERGED"
# meta without file= lines (loop started by an older review-loop) -> refuse, never silently accept
rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic cd1old a.txt >/dev/null 2>&1
grep -v '^file=' .review-loop/current/meta > .review-loop/current/meta.new && mv .review-loop/current/meta.new .review-loop/current/meta
ec_old=$(bash "$CLI" record --reviewer r1 --verdict PASS a.txt >/dev/null 2>&1; echo $?)
assert_exit "CD1: meta without a start set -> record refused (exit 1)" 1 "$ec_old"
cd "$ROOT_DIR" || exit 1

# --- CD2: rl_content_hash — file boundary and path are part of the hash; read failure is exit 2 ---
printf '1\n2\n' > "$WORK/h1.txt"; : > "$WORK/h2.txt"
HX=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h2.txt"')
printf '1\n' > "$WORK/h1.txt"; printf '2\n' > "$WORK/h2.txt"
HY=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h2.txt"')
assert_exit "CD2: moving a line between files changes the hash" 0 "$([ "$HX" != "$HY" ] && echo 0 || echo 1)"
cp "$WORK/h2.txt" "$WORK/h3.txt"
HZ=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h3.txt"')
assert_exit "CD2: renaming a file changes the hash" 0 "$([ "$HY" != "$HZ" ] && echo 0 || echo 1)"
HD=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h2.txt" "'"$WORK"'/h1.txt"')
assert_exit "CD2: a path listed twice counts once (set semantics)" 0 "$([ -n "$HD" ] && [ "$HD" = "$HY" ] && echo 0 || echo 1)"
NLF="$WORK/$(printf 'nl\nname')"; printf 'q\n' > "$NLF"
assert_exit "CD2: path containing a newline -> exit 2" 2 "$(bash -c '. "'"$LIB"'"; rl_content_hash "$1"' _ "$NLF" >/dev/null 2>&1; echo $?)"

# --- CD3: ledger that exists but cannot be read/written is an error, never "0 rounds" / "recorded" ---
# root-immune shape: the ledger path is a directory (read and append both fail even for root)
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
bash "$CLI" start --topic cd3 a.txt >/dev/null 2>&1
rm -f .review-loop/current/ledger.tsv; mkdir .review-loop/current/ledger.tsv
out_cd3=$(bash "$CLI" record --reviewer r1 --verdict WARN --max-rounds 2 a.txt 2>&1); ec_cd3=$?
assert_exit "CD3: record with an unreadable ledger -> exit 1" 1 "$ec_cd3"
assert_not_contains "CD3: no 'recorded round=' claim on ledger failure" "$out_cd3" "recorded round="
assert_contains "CD3: the loop-shape gate (not the append gate) refused" "$out_cd3" "ledger is not a regular file"
assert_not_contains "CD3: refusal happened before any append attempt" "$out_cd3" "ledger append failed"
assert_contains "CD3: state untouched (ACTIVE)" "$(cat .review-loop/current/state)" "ACTIVE"
assert_exit "CD3: status with an unreadable ledger -> exit 1 (not rounds=0)" 1 "$(bash "$CLI" status >/dev/null 2>&1; echo $?)"
assert_exit "CD3: finalize --cap with an unreadable ledger -> exit 1" 1 "$(bash "$CLI" finalize --cap >/dev/null 2>&1; echo $?)"
assert_exit "CD3: failed finalize writes no outcome.txt" 0 "$([ ! -e .review-loop/current/outcome.txt ] && echo 0 || echo 1)"
assert_contains "CD3: failed finalize leaves state ACTIVE (not CAPPED)" "$(cat .review-loop/current/state)" "ACTIVE"
printf 'VETOED\n' > .review-loop/current/state
assert_exit "CD3: override with an unreadable ledger -> exit 1" 1 "$(bash "$CLI" override --reason x >/dev/null 2>&1; echo $?)"
assert_exit "CD3: failed override writes no outcome.txt" 0 "$([ ! -e .review-loop/current/outcome.txt ] && echo 0 || echo 1)"
LEDDIR="$WORK/led-dir"; mkdir -p "$LEDDIR"
assert_exit "CD3: rl_round_count on a non-file ledger -> exit 2" 2 "$(bash -c '. "'"$LIB"'"; rl_round_count "'"$LEDDIR"'"' >/dev/null 2>&1; echo $?)"
assert_exit "CD3: rl_convergence_streak on a non-file ledger -> exit 2" 2 "$(bash -c '. "'"$LIB"'"; rl_convergence_streak "'"$LEDDIR"'"' >/dev/null 2>&1; echo $?)"
cd "$ROOT_DIR" || exit 1

# --- CD4: --findings must be a readable file; missing / non-file is an error, never "no findings" ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
bash "$CLI" start --topic cd4 a.txt >/dev/null 2>&1
assert_exit "CD4: --findings missing file -> exit 2" 2 \
    "$(bash "$CLI" record --reviewer r1 --verdict PASS --findings "$WORK/no-such-findings" a.txt >/dev/null 2>&1; echo $?)"
mkdir -p "$WORK/findings-dir"
assert_exit "CD4: --findings directory -> exit 2" 2 \
    "$(bash "$CLI" record --reviewer r1 --verdict PASS --findings "$WORK/findings-dir" a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD4: nothing recorded after findings refusals (rounds=0)" 0 \
    "$([ "$(bash "$CLI" status 2>&1 | grep -oE 'rounds=[0-9]+')" = "rounds=0" ] && echo 0 || echo 1)"
assert_contains "CD4: rl_validate_round with a missing findings path -> ERROR" \
    "$(bash -c '. "'"$LIB"'"; rl_validate_round abc PASS "'"$WORK"'/no-such-findings"')" "ERROR"
assert_contains "CD4: rl_validate_round with a non-file findings path -> ERROR" \
    "$(bash -c '. "'"$LIB"'"; rl_validate_round abc PASS "'"$WORK"'/findings-dir"')" "ERROR"
cd "$ROOT_DIR" || exit 1

# --- CD2/CD3/CD4 mode-bit shapes (root bypasses chmod; the directory shapes above stay root-immune) ---
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ CD2/CD3/CD4 chmod shapes SKIPPED (root bypasses mode bits; directory shapes above cover the contract)"
else
    chmod 000 "$WORK/h1.txt"
    out_unr=$(bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h2.txt"' 2>/dev/null); ec_unr=$?
    chmod 644 "$WORK/h1.txt"
    assert_exit "CD2: unreadable content file -> exit 2" 2 "$ec_unr"
    assert_exit "CD2: unreadable content file -> no hash on stdout" 0 "$([ -z "$out_unr" ] && echo 0 || echo 1)"
    cd "$WORK" || exit 1
    rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
    bash "$CLI" start --topic cd3w a.txt >/dev/null 2>&1
    chmod 444 .review-loop/current/ledger.tsv
    out_ro=$(bash "$CLI" record --reviewer r1 --verdict WARN a.txt 2>&1); ec_ro=$?
    chmod 644 .review-loop/current/ledger.tsv
    assert_exit "CD3: ledger append failure -> exit 1" 1 "$ec_ro"
    assert_not_contains "CD3: no 'recorded round=' claim on append failure" "$out_ro" "recorded round="
    assert_exit "CD3: append failure leaves the ledger empty" 0 "$([ ! -s .review-loop/current/ledger.tsv ] && echo 0 || echo 1)"
    chmod 000 .review-loop/current/ledger.tsv
    out_000=$(bash "$CLI" record --reviewer r1 --verdict WARN a.txt 2>&1); ec_000=$?
    chmod 644 .review-loop/current/ledger.tsv
    assert_exit "CD3: unreadable (chmod 000) ledger -> exit 1" 1 "$ec_000"
    assert_contains "CD3: the readability gate (not the append gate) refused" "$out_000" "ledger unreadable:"
    assert_not_contains "CD3: readability refusal happened before any append attempt" "$out_000" "ledger append failed"
    FUNR="$WORK/f-unreadable"; printf 'no-location bug\n' > "$FUNR"; chmod 000 "$FUNR"
    assert_exit "CD4: --findings unreadable file -> exit 2" 2 \
        "$(bash "$CLI" record --reviewer r1 --verdict PASS --findings "$FUNR" a.txt >/dev/null 2>&1; echo $?)"
    assert_contains "CD4: rl_validate_round with an unreadable findings file -> ERROR" \
        "$(bash -c '. "'"$LIB"'"; rl_validate_round abc PASS "'"$FUNR"'"' 2>/dev/null)" "ERROR"
    chmod 644 "$FUNR"
    # findings copy must land before the ledger line: unwritable scratch dir -> exit 1, no round appended
    GOODF="$WORK/f-good2"; printf 'scripts/x.sh:1 note\n' > "$GOODF"
    chmod 555 .review-loop/current
    out_cp=$(bash "$CLI" record --reviewer r1 --verdict WARN --findings "$GOODF" a.txt 2>&1); ec_cp=$?
    chmod 755 .review-loop/current
    assert_exit "CD4: findings copy failure -> exit 1" 1 "$ec_cp"
    assert_exit "CD4: findings copy failure appends no round" 0 "$([ ! -s .review-loop/current/ledger.tsv ] && echo 0 || echo 1)"
    cd "$ROOT_DIR" || exit 1
fi

# --- CD5: a broken digest tool must not yield an empty hash (sha256sum | awk returned awk's 0) ---
STUB="$WORK/stub"; mkdir -p "$STUB"
printf '#!/bin/sh\necho broken >&2; exit 2\n' > "$STUB/sha256sum"; cp "$STUB/sha256sum" "$STUB/shasum"; chmod +x "$STUB"/*
out_sha=$(PATH="$STUB:$PATH" bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h2.txt"' 2>/dev/null); ec_sha=$?
assert_exit "CD5: digest tool failure -> rl_content_hash exit 2" 2 "$ec_sha"
assert_exit "CD5: digest tool failure -> no hash on stdout" 0 "$([ -z "$out_sha" ] && echo 0 || echo 1)"
printf '#!/bin/sh\necho "not-a-digest  -"\n' > "$STUB/sha256sum"; cp "$STUB/sha256sum" "$STUB/shasum"
assert_exit "CD5: digest tool emitting a non-hex token -> exit 2" 2 \
    "$(PATH="$STUB:$PATH" bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h2.txt"' >/dev/null 2>&1; echo $?)"
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
printf '#!/bin/sh\necho broken >&2; exit 2\n' > "$STUB/sha256sum"; cp "$STUB/sha256sum" "$STUB/shasum"
assert_exit "CD5: start with a broken digest tool -> exit 1" 1 "$(PATH="$STUB:$PATH" bash "$CLI" start --topic cd5 a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD5: failed start creates no loop dir" 0 "$([ ! -d .review-loop ] && echo 0 || echo 1)"
# digest tool that fails only on its first call: the per-file `|| exit 2` must catch it even though the
# final manifest digest succeeds (otherwise the manifest silently carries an empty digest for that file)
cat > "$STUB/sha256sum" <<EOF
#!/bin/sh
if [ ! -e "$STUB/.once" ]; then : > "$STUB/.once"; exit 2; fi
PATH="\${PATH#*:}"
if command -v sha256sum >/dev/null 2>&1; then exec sha256sum "\$@"; else exec shasum -a 256 "\$@"; fi
EOF
rm -f "$STUB/shasum" "$STUB/.once"
assert_exit "CD5: digest tool failing on the first file only -> exit 2" 2 \
    "$(PATH="$STUB:$PATH" bash -c '. "'"$LIB"'"; rl_content_hash "'"$WORK"'/h1.txt" "'"$WORK"'/h2.txt"' >/dev/null 2>&1; echo $?)"
rm -f "$STUB/.once"
# grep failure inside rl_round_count must not fold into 0
printf '#!/bin/sh\nexit 2\n' > "$STUB/grep"; chmod +x "$STUB/grep"
LED1="$WORK/led-one"; printf 'round=1 reviewer=r content_hash=h verdict=PASS ground=- ts=t findings=0\n' > "$LED1"
out_rc=$(PATH="$STUB:$PATH" bash -c '. "'"$LIB"'"; rl_round_count "'"$LED1"'"' 2>/dev/null); ec_rc=$?
rm -f "$STUB/grep"
assert_exit "CD5: grep failure in rl_round_count -> exit 2" 2 "$ec_rc"
assert_exit "CD5: grep failure in rl_round_count -> no count on stdout" 0 "$([ -z "$out_rc" ] && echo 0 || echo 1)"
cd "$ROOT_DIR" || exit 1

# --- CD6: inside an ACTIVE loop the ledger must exist as a regular file (deleted/dangling is corruption, not "0 rounds") ---
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
bash "$CLI" start --topic cd6 a.txt >/dev/null 2>&1
bash "$CLI" record --reviewer r1 --verdict BLOCKED --ground style a.txt >/dev/null 2>&1
rm -f .review-loop/current/ledger.tsv
assert_exit "CD6: status with a deleted ledger -> exit 1" 1 "$(bash "$CLI" status >/dev/null 2>&1; echo $?)"
assert_exit "CD6: record with a deleted ledger -> exit 1" 1 "$(bash "$CLI" record --reviewer r2 --verdict PASS a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD6: deleted ledger is not recreated by record" 0 "$([ ! -e .review-loop/current/ledger.tsv ] && echo 0 || echo 1)"
assert_exit "CD6: finalize --cap with a deleted ledger -> exit 1" 1 "$(bash "$CLI" finalize --cap >/dev/null 2>&1; echo $?)"
ln -s nowhere .review-loop/current/ledger.tsv
assert_exit "CD6: status with a dangling ledger symlink -> exit 1" 1 "$(bash "$CLI" status >/dev/null 2>&1; echo $?)"
# state file missing: status/finalize must not print/record an empty verdict
rm -f .review-loop/current/ledger.tsv; : > .review-loop/current/ledger.tsv; rm -f .review-loop/current/state
assert_exit "CD6: status with a missing state file -> exit 1" 1 "$(bash "$CLI" status >/dev/null 2>&1; echo $?)"
assert_exit "CD6: finalize with a missing state file -> exit 1" 1 "$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)"
assert_exit "CD6: finalize with a missing state writes no outcome.txt" 0 "$([ ! -e .review-loop/current/outcome.txt ] && echo 0 || echo 1)"
# state must be one of the five enum values: empty / blank / junk / multi-line is corruption
for bad in '' '   ' 'CONVERGEDX' "$(printf 'VETOED\n[review-loop] verdict=CONVERGED rounds=9')"; do
    printf '%s\n' "$bad" > .review-loop/current/state
    assert_exit "CD6: non-enum state ($(printf '%s' "$bad" | tr '\n' '|' | cut -c1-12)) -> status exit 1" 1 "$(bash "$CLI" status >/dev/null 2>&1; echo $?)"
done
DLM="$WORK/devlog-multi.md"; printf '### log\n' > "$DLM"
assert_exit "CD6: multi-line state -> finalize exit 1" 1 "$(bash "$CLI" finalize --devlog "$DLM" >/dev/null 2>&1; echo $?)"
assert_exit "CD6: multi-line state -> devlog untouched" 0 "$([ "$(cat "$DLM")" = "### log" ] && echo 0 || echo 1)"
# a credential/privacy BLOCKED round in the ledger while state is still ACTIVE = veto never reached disk
printf 'ACTIVE\n' > .review-loop/current/state
printf 'round=1 reviewer=r1 content_hash=h verdict=BLOCKED ground=credential ts=t findings=0\n' > .review-loop/current/ledger.tsv
out_uv=$(bash "$CLI" record --reviewer r2 --verdict PASS a.txt 2>&1); ec_uv=$?
assert_exit "CD6: unresolved veto in ledger + ACTIVE state -> record exit 1" 1 "$ec_uv"
assert_contains "CD6: refusal names the unresolved veto" "$out_uv" "unresolved"
assert_exit "CD6: refused round not appended (rounds=1)" 0 "$([ "$(grep -c '^round=' .review-loop/current/ledger.tsv)" = 1 ] && echo 0 || echo 1)"
cd "$ROOT_DIR" || exit 1

# --- CD7: argument boundaries — topic is a single token; a value flag without a value is a usage error, not a hang ---
# run_bounded: run a CLI invocation with a 5 s budget; prints its exit code, or HUNG (and kills it)
run_bounded() { "$@" >/dev/null 2>&1 & local _p=$! _i
    for _i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$_p" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$_p" 2>/dev/null; then kill "$_p" 2>/dev/null; wait "$_p" 2>/dev/null; echo HUNG; else wait "$_p"; echo $?; fi; }
cd "$WORK" || exit 1
rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
assert_exit "CD7: --topic with a newline (forged file= line) -> exit 2" 2 \
    "$(bash "$CLI" start --topic "$(printf 't\nfile=evil')" a.txt >/dev/null 2>&1; echo $?)"
rm -rf "$WORK/.review-loop"
assert_exit "CD7: --topic with whitespace -> exit 2" 2 "$(bash "$CLI" start --topic "two words" a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD7: refused start creates no loop dir" 0 "$([ ! -d .review-loop ] && echo 0 || echo 1)"
# a non-directory object at the loop path is not ours to delete: refuse, leave it intact
mkdir -p .review-loop; printf 'keep me\n' > .review-loop/current
assert_exit "CD7: regular file at the loop path -> start exit 2" 2 "$(bash "$CLI" start --topic cd7f a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD7: that file is left intact" 0 "$([ "$(cat .review-loop/current 2>/dev/null)" = "keep me" ] && echo 0 || echo 1)"
rm -f .review-loop/current; ln -s /nonexistent-target .review-loop/current
assert_exit "CD7: dangling symlink at the loop path -> start exit 2" 2 "$(bash "$CLI" start --topic cd7l a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD7: that symlink is left intact" 0 "$([ -L .review-loop/current ] && echo 0 || echo 1)"
rm -rf "$WORK/.review-loop"
# CAPPED hint must point at a command that works on a CAPPED loop (override only lifts VETOED)
bash "$CLI" start --topic cd7c a.txt >/dev/null 2>&1
bash "$CLI" record --reviewer r1 --verdict WARN --max-rounds 1 a.txt >/dev/null 2>&1
msg_cap=$(bash "$CLI" record --reviewer r2 --verdict WARN a.txt 2>&1 >/dev/null)
assert_not_contains "CD7: CAPPED refusal does not point at override" "$msg_cap" "override"
assert_contains "CD7: CAPPED refusal points at finalize" "$msg_cap" "finalize"
rm -rf "$WORK/.review-loop"
assert_exit "CD7: start --topic without a value -> exit 2 (no hang)" 2 "$(run_bounded bash "$CLI" start a.txt --topic)"
rm -rf "$WORK/.review-loop"
bash "$CLI" start --topic cd7 a.txt >/dev/null 2>&1
assert_exit "CD7: trailing --findings without a value -> exit 2 (no hang)" 2 "$(run_bounded bash "$CLI" record --reviewer r1 --verdict PASS a.txt --findings)"
assert_exit "CD7: --findings '' -> exit 2 (not 'no findings')" 2 \
    "$(bash "$CLI" record --reviewer r1 --verdict PASS --findings "" a.txt >/dev/null 2>&1; echo $?)"
assert_exit "CD7: refused records leave rounds=0" 0 \
    "$([ "$(bash "$CLI" status 2>&1 | grep -oE 'rounds=[0-9]+')" = "rounds=0" ] && echo 0 || echo 1)"
mkdir -p "$WORK/adir"; rm -rf "$WORK/.review-loop"
msg_dir=$(bash "$CLI" start --topic cd7d "$WORK/adir" 2>&1 >/dev/null)
assert_contains "CD7: directory as content path is reported as not a regular file" "$msg_dir" "not a regular file"
cd "$ROOT_DIR" || exit 1

# --- CD8/CD9 mode-bit shapes: state/outcome/devlog writes must be checked (root bypasses chmod) ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    cd "$WORK" || exit 1
    rm -rf "$WORK/.review-loop"; printf 'alpha\n' > a.txt
    bash "$CLI" start --topic cd8 a.txt >/dev/null 2>&1
    chmod 444 .review-loop/current/state
    out_v=$(bash "$CLI" record --reviewer r1 --verdict BLOCKED --ground credential a.txt 2>&1); ec_v=$?
    assert_exit "CD8: veto whose state write fails -> exit 1 (not 3)" 1 "$ec_v"
    assert_not_contains "CD8: no 'Escalated' claim when the veto did not persist" "$out_v" "Escalated"
    chmod 644 .review-loop/current/state
    # the veto round is in the ledger; the loop must not forget it and converge later
    for r in r2 r3 r4; do bash "$CLI" record --reviewer $r --verdict PASS a.txt >/dev/null 2>&1; done
    assert_contains "CD8: PASS rounds after an unpersisted veto are refused (state stays ACTIVE)" "$(cat .review-loop/current/state)" "ACTIVE"
    assert_exit "CD8: no PASS round appended after the unpersisted veto (rounds=1)" 0 \
        "$([ "$(bash "$CLI" status 2>&1 | grep -oE 'rounds=[0-9]+')" = "rounds=1" ] && echo 0 || echo 1)"
    # start whose first write fails must not leave a half-created loop dir behind
    rm -rf "$WORK/.review-loop"
    assert_exit "CD8: start under umask 277 (ledger creation fails) -> exit 1" 1 "$( (umask 277; bash "$CLI" start --topic cd8u a.txt) >/dev/null 2>&1; echo $?)"
    assert_exit "CD8: failed start leaves no half-created loop dir" 0 "$([ ! -d .review-loop/current ] && echo 0 || echo 1)"
    assert_exit "CD8: a normal start works right after the failed one" 0 "$(bash "$CLI" start --topic cd8u a.txt >/dev/null 2>&1; echo $?)"
    rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic cd8c a.txt >/dev/null 2>&1
    bash "$CLI" record --reviewer r1 --verdict PASS a.txt >/dev/null 2>&1
    bash "$CLI" record --reviewer r2 --verdict PASS a.txt >/dev/null 2>&1
    chmod 444 .review-loop/current/state
    out_c=$(bash "$CLI" record --reviewer r3 --verdict PASS a.txt 2>&1); ec_c=$?
    assert_exit "CD8: converged but state write fails -> exit 1 (not 0)" 1 "$ec_c"
    assert_not_contains "CD8: no 'converged' claim when CONVERGED did not persist" "$out_c" "converged"
    chmod 644 .review-loop/current/state
    printf 'VETOED\n' > .review-loop/current/state; chmod 444 .review-loop/current/state
    out_o=$(bash "$CLI" override --reason x 2>&1); ec_o=$?
    assert_exit "CD8: override whose state write fails -> exit 1" 1 "$ec_o"
    assert_not_contains "CD8: no 'OVERRIDDEN' claim when the state did not persist" "$out_o" "OVERRIDDEN by"
    chmod 644 .review-loop/current/state; printf 'ACTIVE\n' > .review-loop/current/state
    chmod 444 .review-loop/current/state
    assert_exit "CD8: finalize --cap whose state write fails -> exit 1" 1 "$(bash "$CLI" finalize --cap >/dev/null 2>&1; echo $?)"
    chmod 644 .review-loop/current/state
    # CD9: devlog append / outcome write failures must not be reported as success
    rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic cd9 a.txt >/dev/null 2>&1
    for r in r1 r2 r3; do bash "$CLI" record --reviewer $r --verdict PASS a.txt >/dev/null 2>&1; done
    DLRO="$WORK/devlog-ro.md"; printf '### log\n' > "$DLRO"; chmod 444 "$DLRO"
    out_dl=$(bash "$CLI" finalize --devlog "$DLRO" 2>&1); ec_dl=$?
    chmod 644 "$DLRO"
    assert_exit "CD9: finalize --devlog append failure -> exit 1" 1 "$ec_dl"
    assert_not_contains "CD9: no 'appended to' claim on devlog failure" "$out_dl" "appended to"
    assert_exit "CD9: devlog left untouched" 0 "$([ "$(cat "$DLRO")" = "### log" ] && echo 0 || echo 1)"
    rm -f .review-loop/current/outcome.txt; chmod 555 .review-loop/current
    assert_exit "CD9: finalize whose outcome.txt write fails -> exit 1" 1 "$(bash "$CLI" finalize >/dev/null 2>&1; echo $?)"
    chmod 755 .review-loop/current
    # CD5 companion: append failure must not leave an orphan round-N.findings
    rm -rf "$WORK/.review-loop"; bash "$CLI" start --topic cd5o a.txt >/dev/null 2>&1
    GOODF3="$WORK/f-good3"; printf 'scripts/x.sh:1 note\n' > "$GOODF3"
    chmod 444 .review-loop/current/ledger.tsv
    bash "$CLI" record --reviewer r1 --verdict WARN --findings "$GOODF3" a.txt >/dev/null 2>&1
    chmod 644 .review-loop/current/ledger.tsv
    assert_exit "CD5: append failure leaves no orphan round-1.findings" 0 "$([ ! -e .review-loop/current/round-1.findings ] && echo 0 || echo 1)"
    cd "$ROOT_DIR" || exit 1
fi

summary
