#!/bin/bash
# Regression contract for the 2026-11-18 review of the Codex delivery
# (wip/reviews/2026-11-18-codex-delivery-review.md, findings 1-10).
# Bash 3.2 compatible; every fixture lives in one mktemp sandbox.
set -uo pipefail
unset CDPATH
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
RT="$ROOT/scripts/handoff-runtime.sh"
HX="$ROOT/scripts/hx.sh"
BOX=$(mktemp -d "${TMPDIR:-/tmp}/hx-review-fixes.XXXXXX") || exit 2
BOX=$(cd "$BOX" && pwd -P)
trap 'rm -rf "$BOX"' EXIT
PASS=0 FAIL=0 RC=0
ok() { PASS=$((PASS+1)); echo "  ✅ $1"; }
no() { FAIL=$((FAIL+1)); echo "  ❌ $1"; [ ! -s "$BOX/err" ] || sed 's/^/     stderr: /' "$BOX/err" | head -3; }
t() { local d=$1; shift; if "$@"; then ok "$d"; else no "$d"; fi; }
run() { local cwd=$1; shift; RC=0; (cd "$cwd" && bash "$@") >"$BOX/out" 2>"$BOX/err" || RC=$?; }
rc_is() { [ "$RC" -eq "$1" ]; }
out_has() { grep -qF -- "$1" "$BOX/out"; }
err_has() { grep -qF -- "$1" "$BOX/err"; }

mkproj() { mkdir -p "$1"; run "$1" "$RT" init; [ "$RC" -eq 0 ] || { echo "fixture init failed: $1"; cat "$BOX/err"; exit 2; }; }
# mklog DIR NUM SUMMARY_BYTES [EXTRA_SUMMARY_LINE]
mklog() {
    local d=$1 n=$2 size=$3 extra=${4:-} f line i=0
    f="$d/Handoffx_Logs/$n-2026-11-18T00$(printf '%02d' "$((10#$n % 60))")-log-$n.md"
    line=$(printf '%096d' 0 | tr 0 x)
    {
        printf -- '---\nschema: 2\ntype: dev-log\ndate: 2026-11-18T00:%02d\nepoch: %s\nnumber: %s\ntitle: log %s\n---\n\n' \
            "$((10#$n % 60))" "$((1795000000 + 10#$n))" "$n" "$n"
        printf '### 2026-11-18 00:%02d — log %s\n\n' "$((10#$n % 60))" "$n"
        if [ "$size" -gt 0 ]; then
            printf '<!-- hx:recall -->\n'
            while [ "$i" -lt "$size" ]; do printf -- '- %s\n' "$line"; i=$((i + 99)); done
            [ -z "$extra" ] || printf '%s\n' "$extra"
            printf '<!-- /hx:recall -->\n\n'
        fi
        printf '**触发**: t\n\n**改动**:\n- `HANDOFFX.md` — t\n\n**验证**:\n- t\n\n**关联**: 无\n'
    } > "$f"
    printf '%s' "$f"
}
set_recent() { printf '%s\n' "$2" > "$BOX/recent.txt"; run "$1" "$HX" block set recent --from "$BOX/recent.txt"; }

echo "=== #1 log summaries degrade to metadata within the 24576-byte budget"
P1="$BOX/p1"; mkproj "$P1"
set_recent "$P1" "$(printf '%011000d' 0 | tr 0 r | fold -w 100)"
for n in 0001 0002 0003 0004 0005 0006; do mklog "$P1" "$n" 1950 >/dev/null; done
run "$P1" "$RT" recall ""
t "#1 recall succeeds when six maximal summaries do not fit" rc_is 0
t "#1 older summaries are explicitly deferred" out_has 'log_status=summary_deferred_budget'
t "#1 output stays within 24576 bytes" test "$(wc -c < "$BOX/out")" -le 24576
t "#1 newest log is loaded as summary, not deferred" sh -c "grep -A1 -F -- '--- Handoffx_Logs/0006-' '$BOX/out' | grep -qx 'log_status=summary'"
set_recent "$P1" "$(printf '%013000d' 0 | tr 0 r | fold -w 100)"
run "$P1" "$RT" recall ""
t "#1 oversized current state still fails closed" rc_is 2
t "#1 oversized state emits no stdout" test ! -s "$BOX/out"

echo "=== #2 finalize runs the recall preflight before regen writes"
P2="$BOX/p2"; mkproj "$P2"
bad=$(mklog "$P2" 0001 300 '<!-- hx:recall -->')
mklog "$P2" 0002 0 >/dev/null
cp "$P2/HANDOFFX.md" "$BOX/p2.before"
: "${bad:?}"
run "$P2" "$RT" finalize --log "Handoffx_Logs/$(cd "$P2/Handoffx_Logs" && ls 0002-*)"
t "#2 finalize fails on an invalid recall summary" rc_is 2
t "#2 main file untouched when the preflight fails" cmp -s "$BOX/p2.before" "$P2/HANDOFFX.md"

echo "=== #3 callers pass --expect-root to write-gated tools"
# Behaviour is covered by the N2/N3 upgrade cases below; these pin the wiring.
t "#3 upgrade forwards the explicit root to the migrator" grep -qF 'MIGRATOR=(bash "$SD/tidy-handoff.sh" ${UP_EXPECT_ARGS[@]+' "$ROOT/scripts/handoffx-upgrade.sh"
t "#3 upgrade forwards the explicit root to postflight" grep -qF 'handoff-postflight.sh" ${UP_EXPECT_ARGS[@]+' "$ROOT/scripts/handoffx-upgrade.sh"
t "#3 no skill doc runs postflight without --expect-root" sh -c "! grep -hE 'bash [^ ]*handoff-postflight\.sh' '$ROOT'/skills/handoffx/references/*.md '$ROOT'/skills/handoffx/SKILL.md | grep -v -- '--expect-root' | grep -q ."

echo "=== #4 tag-style list items are not ambiguous tasks"
P4="$BOX/p4"; mkproj "$P4"
printf '%s\n' '- [P0] credential rotation note' '- [security] scanner scope' >> "$P4/HANDOFFX.md"
run "$P4" "$RT" recall ""
t "#4 recall accepts bracket labels outside pending" rc_is 0
printf '%s\n' '- [-] half-done thing' >> "$P4/HANDOFFX.md"
run "$P4" "$RT" recall ""
t "#4 one-symbol checkbox outside pending still fails closed" rc_is 2

echo "=== #5 tidy schema-upgrade resolves a symlinked cwd physically"
P5="$BOX/p5"; mkproj "$P5"; ln -s "$P5" "$BOX/p5link"
run "$P5" "$ROOT/scripts/tidy-handoff.sh" schema-upgrade --apply; phys_rc=$RC
run "$BOX/p5link" "$ROOT/scripts/tidy-handoff.sh" schema-upgrade --apply
t "#5 symlinked cwd is not rejected as a symlink path" sh -c "! grep -qF 'contains a symlink' '$BOX/err'"
t "#5 physical-cwd baseline itself succeeds" test "$phys_rc" -eq 0
t "#5 symlinked cwd behaves like the physical cwd" test "$RC" -eq "$phys_rc"

echo "=== GLM-A unreadable title/date metadata never blocks a recall that fits"
PA="$BOX/pa"; mkproj "$PA"
fa=$(mklog "$PA" 0001 300)
python3 - "$fa" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
s = s.replace('\ntitle: log 0001\n', '\ntitle: log 0001\ntitle: duplicate\n', 1)
open(p, 'w', encoding='utf-8').write(s)
PY
run "$PA" "$RT" recall ""
t "GLM-A duplicate title in a log does not fail recall" rc_is 0
t "GLM-A that log still shows its summary" sh -c "grep -A1 -F -- '--- Handoffx_Logs/0001-' '$BOX/out' | grep -qx 'log_status=summary'"

echo "=== GLM-C single-character bracket labels are labels, single symbols are not"
PC="$BOX/pc"; mkproj "$PC"
printf '%s\n' '- [P] priority label' '- [A1] area label' >> "$PC/HANDOFFX.md"
run "$PC" "$RT" recall ""
t "GLM-C single alphanumeric label outside pending is accepted" rc_is 0

echo "=== #6 only the log's verification section is compared"
P6="$BOX/p6"; mkproj "$P6"
run "$P6" "$RT" verification --source runner_report --command 'bash t.sh' --result '6 passed'
decl=$(cat "$BOX/out")
set_recent "$P6" "$decl"
f6=$(mklog "$P6" 0001 200 "$decl")
python3 - "$f6" "$decl" <<'PY'
import sys
p, decl = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read().replace('**验证**:\n- t\n', '**验证**:\n' + decl + '\n', 1)
open(p, 'w', encoding='utf-8').write(s)
PY
run "$P6" "$RT" verification-check --current --match-file "Handoffx_Logs/${f6##*/}"
t "#6 a summary copy of the declaration does not break matching" rc_is 0

echo "=== #7 unbound distributed skill copies need an explicit write root"
cp -R "$ROOT/skills/handoffx" "$BOX/cfg-skill"
mkdir -p "$BOX/elsewhere"
run "$BOX/elsewhere" "$BOX/cfg-skill/scripts/handoff-runtime.sh" init
t "#7 unbound copy refuses an implicit write" rc_is 2
t "#7 refused init created nothing" test ! -e "$BOX/elsewhere/HANDOFFX.md"
run "$BOX/elsewhere" "$BOX/cfg-skill/scripts/handoff-runtime.sh" --expect-root "$BOX/elsewhere" init
t "#7 explicit --expect-root still allows the write" rc_is 0
mkdir -p "$BOX/h7/.codex/skills" "$BOX/h7/proj"
cp -R "$ROOT/skills/handoffx" "$BOX/h7/.codex/skills/handoffx"
run "$BOX/h7/proj" "$BOX/h7/.codex/skills/handoffx/scripts/handoff-runtime.sh" context
t "#7 legacy ~/.codex/skills copy is told to reinstall" err_has 'reinstall'

echo "=== #8 a dotfiles-symlinked host base with a valid global peer"
H8="$BOX/h8"; mkdir -p "$H8/proj" "$BOX/dot/claude/skills" "$H8/.agents/skills"
cp -R "$ROOT/skills/handoffx" "$BOX/dot/claude/skills/handoffx"
cp -R "$ROOT/skills/handoffx" "$H8/.agents/skills/handoffx"
manifest() { printf 'schema=1\nscope=global\nproject_root=\nskill_root=%s\nhost=%s\n' "$1" "$2" > "$1/.handoffx-install-context"; }
manifest "$BOX/dot/claude/skills/handoffx" claude
manifest "$H8/.agents/skills/handoffx" codex
ln -s "$BOX/dot/claude" "$H8/.claude"
RC=0; (cd "$H8/proj" && HOME="$H8" bash "$H8/.agents/skills/handoffx/scripts/handoff-runtime.sh" context) >"$BOX/out" 2>"$BOX/err" || RC=$?
t "#8 codex runtime works beside a symlinked ~/.claude peer" rc_is 0
rm "$BOX/dot/claude/skills/handoffx/.handoffx-install-context"
printf 'schema=1\nscope=project\nproject_root=%s\nskill_root=%s\nhost=claude\n' "$H8" "$BOX/dot/claude/skills/handoffx" > "$BOX/dot/claude/skills/handoffx/.handoffx-install-context"
RC=0; (cd "$H8/proj" && HOME="$H8" bash "$H8/.agents/skills/handoffx/scripts/handoff-runtime.sh" context) >"$BOX/out" 2>"$BOX/err" || RC=$?
t "#8 a symlinked project-local shadow is still refused" rc_is 2

echo "=== R1 (2nd review) remaining logs keep room for their metadata"
PR="$BOX/pr1"; mkproj "$PR"
recent_bytes=${R1_RECENT_BYTES:-8900}
set_recent "$PR" "$(printf "%0${recent_bytes}d" 0 | tr 0 r | fold -w 100)"
for n in 0001 0002 0003 0004 0005 0006; do
    f=$(mklog "$PR" "$n" 1950 "$(printf '%059d' 0 | tr 0 y)")
    python3 - "$f" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding='utf-8').read()
s = s.replace('\ntitle: log ', '\ntitle: ' + 'T' * 480 + ' log ', 1)
open(p, 'w', encoding='utf-8').write(s)
PY
done
run "$PR" "$RT" recall ""
t "R1 long titles plus maximal summaries still recall" rc_is 0
t "R1 output stays within 24576 bytes" test "$(wc -c < "$BOX/out")" -le 24576

echo "=== N1 (2nd review) fenced example headings are not the verification field"
PN="$BOX/pn1"; mkproj "$PN"
run "$PN" "$RT" verification --source runner_report --command 'bash t.sh' --result '6 passed'
decl=$(cat "$BOX/out"); set_recent "$PN" "$decl"
fn=$(mklog "$PN" 0001 0)
{ printf '\nExample:\n```text\n**Verification**:\n%s\n**Related**: x\n```\n' "$decl"; } >> "$fn"
run "$PN" "$RT" verification-check --current --match-file "Handoffx_Logs/${fn##*/}"
t "N1 a declaration only inside a code fence does not match recent" rc_is 2

echo "=== N2/N3 (2nd review) upgrade root handling"
# Legacy names come from the schema single source (Decision 0025), never literals.
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/handoff-schema.sh"
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/handoff-v2.sh"
mkv3() { mkdir -p "$1/$HX_LEGACY_LOGS_DIR" "$1/$HX_LEGACY_DEC_DIR"; printf '%s\n# Handoff\n' "$HANDOFF_V2_MARKER" > "$1/$HX_LEGACY_MAIN_FILE"; printf '# Known Gotchas\n' > "$1/$HX_GOTCHAS_FILE"; }
PU="$BOX/pu"; mkv3 "$PU"
run "$PU" "$BOX/cfg-skill/scripts/handoffx-upgrade.sh" --apply --no-backup --sync-paused
t "N2 unbound copy upgrade without --root is refused" rc_is 2
t "N2 refused upgrade left the legacy layout untouched" test -f "$PU/$HX_LEGACY_MAIN_FILE"
t "N2 refused upgrade took no lock" test ! -e "$PU/$HX_LEGACY_LOGS_DIR/.lock.d"
# v1 single-file layout takes the migrate-to-v2.sh branch; same gate (Codex re-review).
PV="$BOX/pv1"; mkdir -p "$PV"; printf '# Handoff\n\n## Development Log\n' > "$PV/$HX_LEGACY_MAIN_FILE"
run "$PV" "$BOX/cfg-skill/scripts/handoffx-upgrade.sh" --apply --no-backup --sync-paused
t "N2-v1 unbound copy v1 upgrade without --root is refused" rc_is 2
t "N2-v1 refused v1 upgrade wrote no new layout" test ! -e "$PV/$HX_MAIN_FILE"
PL="$BOX/pl"; mkv3 "$PL"; ln -s "$PL" "$BOX/pllink"
run "$BOX/pllink" "$ROOT/scripts/handoffx-upgrade.sh" --apply --no-backup --sync-paused --root "$BOX/pllink"
t "N3 upgrade through a symlinked root migrates" test -f "$PL/HANDOFFX.md"
t "N3 no symlink rejection on the migrator path" sh -c "! grep -qF 'contains a symlink' '$BOX/err'"

echo "=== N4 (2nd review) symlinked HOME base without a manifest is not a free peer"
H9="$BOX/h9"; mkdir -p "$H9/proj" "$BOX/dot9/claude/skills" "$H9/.agents/skills"
cp -R "$ROOT/skills/handoffx" "$BOX/dot9/claude/skills/handoffx"
cp -R "$ROOT/skills/handoffx" "$H9/.agents/skills/handoffx"
manifest "$H9/.agents/skills/handoffx" codex
ln -s "$BOX/dot9/claude" "$H9/.claude"
RC=0; (cd "$H9/proj" && HOME="$H9" bash "$H9/.agents/skills/handoffx/scripts/handoff-runtime.sh" context) >"$BOX/out" 2>"$BOX/err" || RC=$?
t "N4 symlinked legacy peer without manifest is refused" rc_is 2

echo "=== #10 shared parsers have a single definition"
t "#10 one awk fence_line definition across scripts" test "$(grep -rh 'function fence_line' "$ROOT/scripts" | wc -l | tr -d ' ')" -eq 1
t "#10 no hand-copied --expect-root parser left in scripts" sh -c "! grep -lE 'if \\[ \"\\\$\\{1:-\\}\" = --expect-root \\]' '$ROOT'/scripts/*.sh"

echo "─── $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
