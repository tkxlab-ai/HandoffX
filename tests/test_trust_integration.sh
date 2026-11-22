#!/bin/bash
# Run: /bin/bash tests/test_trust_integration.sh (Bash 3.2 compatible).
# Real installer + shipped entry points, no models, global configuration or common.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
BASH_BIN=${BASH:-/bin/bash}
ORIGINAL_HOME=$(cd "${HOME:?}" && pwd -P)
mkdir -p "$ROOT/wip/tmp"
BOX=$(mktemp -d "$ROOT/wip/tmp/trust-integration.XXXXXX")
trap 'chmod -R u+rwX "$BOX"; rm -rf "$BOX"' EXIT
export TMPDIR="$BOX/tmp" HOME="$BOX/home" XDG_CONFIG_HOME="$BOX/home/.config"
export HANDOFF_TEST_WSL_HOME="$BOX/home/wsl" CODEX_HOME="$BOX/home/.codex"
unset CLAUDE_CONFIG_DIR HANDOFFX_INSTALL_FAIL_AT HANDOFF_TEST_PLATFORM
mkdir -p "$TMPDIR" "$HOME"
PASS=0 FAIL=0 RC=0
P="$BOX/空格 project 中文"
OTHER="$BOX/other project"
mkdir -p "$P/child" "$OTHER"
# shellcheck disable=SC1091
. "$ROOT/scripts/lib/handoff-schema.sh"

check() {
    local label="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); else
        printf 'FAIL: %s\n' "$label" >&2
        FAIL=$((FAIL + 1))
    fi
}
has() { grep -qF -- "$1" "$BOX/out"; }
lacks() { ! has "$1"; }
run() {
    local cwd="$1"; shift
    RC=0
    (cd "$cwd" && "$BASH_BIN" "$@") > "$BOX/out" 2> "$BOX/err" || RC=$?
}
good() {
    check "$1: exit 0 (got $RC)" test "$RC" -eq 0
    if [ "$RC" -ne 0 ]; then cat "$BOX/out" "$BOX/err" >&2; fi
}
# Include hidden install files and all user artifacts, plus directory/link inventory.
# Snapshots live outside the guarded trees; byte changes, additions, removals and
# replacement of a symlink by a file cannot hide behind a nonzero exit status.
snapshot() {
    local dir
    for dir in "$P" "$OTHER" "$HOME"; do
        printf '\nROOT %s\n' "$dir"
        (
            cd "$dir"
            find . -type d -print
            find . -type l -exec ls -ld {} \;
            find . -type f -exec cksum {} +
        ) | LC_ALL=C sort
    done
}
reject() {
    local label="$1"; shift
    snapshot > "$BOX/before"
    run "$@"
    check "$label: rejected (got $RC)" test "$RC" -ne 0
    check "$label: stdout empty, including newline" test ! -s "$BOX/out"
    check "$label: stderr diagnostic" test -s "$BOX/err"
    if [ "$RC" -eq 0 ] || [ -s "$BOX/out" ]; then
        printf '  Unexpected acceptance/output for: %s\n' "$label" >&2
        sed -n '1,12p' "$BOX/out" >&2
    fi
    snapshot > "$BOX/after"
    check "$label: every guarded file/tree unchanged" cmp -s "$BOX/before" "$BOX/after"
    if ! cmp -s "$BOX/before" "$BOX/after"; then
        diff -u "$BOX/before" "$BOX/after" >&2 || true
    fi
}
fixture() {
    mkdir -p "$1/$HX_LOGS_DIR" "$1/$HX_DEC_DIR"
    cp "$ROOT/skills/handoffx/assets/HANDOFFX.template.md" "$1/$HX_MAIN_FILE"
    cp "$ROOT/skills/handoffx/assets/GOTCHAS.template.md" "$1/$HX_GOTCHAS_FILE"
    printf 'unrelated user data\n' > "$1/user.txt"
}

# Install from this checkout, not a synthetic manifest. Never invoke host CLIs.
run "$BOX" "$ROOT/install.sh" --project "$P"
good 'project installation'
S="$P/.claude/skills/handoffx"
RT="$S/scripts/handoff-runtime.sh"
HX="$S/scripts/hx.sh"
PF="$S/scripts/handoff-postflight.sh"
M="$S/.handoffx-install-context"
if [ "$RC" -ne 0 ] || [ ! -f "$M" ]; then
    printf 'Cannot exercise installed entry points: project install/manifest missing\n' >&2
    exit 1
fi
# All hosts that the real installer detected must have physical project bindings.
for host in claude codex opencode; do
    case "$host" in claude) config=.claude ;; codex) config=.agents ;; opencode) config=.opencode ;; esac
    skill="$P/$config/skills/handoffx"
    [ -d "$skill" ] || continue
    printf 'schema=1\nscope=project\nproject_root=%s\nskill_root=%s\nhost=%s\n' \
        "$P" "$skill" "$host" > "$BOX/manifest-expected"
    check "$host: installer manifest exact contract" cmp -s "$BOX/manifest-expected" "$skill/.handoffx-install-context"
done
for path in "$HOME/.claude/skills/handoffx" "$HOME/.agents/skills/handoffx" "$HOME/.codex/skills/handoffx" "$XDG_CONFIG_HOME/opencode/skills/handoffx"; do
    check 'project install leaves global skills absent' test ! -e "$path"
done
run "$P" "$RT" context --root "$P" --skill-root "$S"
good 'bound context at physical project root'
check 'context project scope' has 'scope=project'
check 'context contract' has 'context_contract=1'
check 'context bound root' has "project_root=$P"
# Exercise the no-write promise before any scaffold exists, not just a no-op
# init on a populated project. Reset only this sandbox after a buggy acceptance
# so the positive control below still tests a genuinely fresh initialization.
reject 'wrong cwd: fresh init must not repair cwd via --root' "$OTHER" "$RT" init --root "$P"
rm -rf "${P:?}/${HX_MAIN_FILE:?}" "${P:?}/${HX_GOTCHAS_FILE:?}" "${P:?}/${HX_LOGS_DIR:?}" "${P:?}/${HX_DEC_DIR:?}"
run "$P" "$RT" init
good 'bound runtime preflight/init'
check 'init writes scaffold' test -f "$P/$HX_MAIN_FILE"
fixture "$OTHER"
printf 'TRUST_INTEGRATION_RECENT\n' > "$BOX/recent"
run "$P" "$HX" block set recent --from "$BOX/recent" --file "$P/$HX_MAIN_FILE"
good 'bound block set explicit local file'
run "$P" "$HX" block get recent
good 'bound block get'
check 'block set actually changed intended file' has TRUST_INTEGRATION_RECENT
run "$P" "$HX" regen --root "$P"
good 'bound regen explicit local root'
run "$P" "$RT" recall
good 'bound recall'
check 'recall contains written state' has TRUST_INTEGRATION_RECENT
check 'legacy state remains explicitly unverified' has verification_status=legacy_unverified
run "$P" "$PF" --quiet "$P/$HX_MAIN_FILE"
good 'postflight explicit local FILE'

# A symlink to the scripts directory is only an entry-point spelling: all
# helpers must resolve the physical install root, without losing its binding.
LINK="$P/linked-scripts"
ln -s "$S/scripts" "$LINK"
cp "$M" "$BOX/manifest-before-symlink"
snapshot > "$BOX/symlink-before"
run "$P" "$RT" context
good 'direct context control for symlink entry point'
cp "$BOX/out" "$BOX/direct-context"
run "$P" "$LINK/handoff-runtime.sh" context
good 'runtime via scripts symlink'
check 'symlink runtime retains exact physical context' cmp -s "$BOX/direct-context" "$BOX/out"
check 'symlink runtime stays project-bound' has scope=project
check 'symlink runtime names physical skill root' has "skill_root=$S"
run "$P" "$LINK/hx.sh" now
good 'bound hx now via scripts symlink agrees with runtime'
check 'symlink hx now returns human time' grep -q '^human=' "$BOX/out"
check 'symlink hx now returns frontmatter time' grep -q '^fm=' "$BOX/out"
check 'symlink hx now returns filename time' grep -q '^fn=' "$BOX/out"
run "$P" "$LINK/handoff-postflight.sh" --quiet "$P/$HX_MAIN_FILE"
good 'postflight via scripts symlink agrees with runtime'
snapshot > "$BOX/symlink-after"
check 'symlink entry points do not rewrite files or bindings' cmp -s "$BOX/symlink-before" "$BOX/symlink-after"
check 'symlink entry point does not rewrite physical manifest' cmp -s "$BOX/manifest-before-symlink" "$M"
reject 'symlink runtime still rejects wrong cwd' "$OTHER" "$LINK/handoff-runtime.sh" context
reject 'symlink hx now still rejects wrong cwd' "$OTHER" "$LINK/hx.sh" now
rm "$LINK"

# CDPATH must not validate one root and then write to another. Here "other"
# is a real external root below P, while CDPATH finds X/other -> bound P first.
CDPATH_DIR="$BOX/cdpath-search"
mkdir -p "$CDPATH_DIR" "$P/other" "$BOX/cdpath-install-project"
fixture "$P/other"
ln -s "$P" "$CDPATH_DIR/other"
CDPATH_RUNNER="$BOX/cdpath-runtime.sh"
cat > "$CDPATH_RUNNER" <<'CDPATH_RUNTIME'
#!/bin/bash
export CDPATH="$1"
caller_record="$2"
shift 2
"$BASH" "$@"
rc=$?
printf '%s\n' "${CDPATH-unset}" > "$caller_record"
exit "$rc"
CDPATH_RUNTIME
printf '%s\n' "$CDPATH_DIR" > "$BOX/cdpath-expected"
# Verify that the fixture really triggers Bash's historical CDPATH behavior;
# do not rely on a regression test whose malicious search path is ineffective.
(cd "$P" && CDPATH="$CDPATH_DIR" "$BASH_BIN" -c 'cd other >/dev/null; pwd -P') > "$BOX/cdpath-control"
printf '%s\n' "$P" > "$BOX/bound-root-expected"
check 'CDPATH fixture redirects bare cd other into bound root' cmp -s "$BOX/bound-root-expected" "$BOX/cdpath-control"
reject 'CDPATH cannot authorize external regen root' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$HX" regen --root other
reject 'CDPATH cannot authorize external block write' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$HX" block set recent --from "$BOX/recent" --file "other/$HX_MAIN_FILE"
reject 'CDPATH cannot authorize external block read' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$HX" block get recent --file "other/$HX_MAIN_FILE"
reject 'CDPATH cannot authorize external runtime root' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$RT" context --root other
reject 'CDPATH cannot authorize external init root' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$RT" init --root other
reject 'CDPATH cannot authorize external postflight FILE' "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" "$PF" "other/$HX_MAIN_FILE"
check 'rejected children preserve caller CDPATH' cmp -s "$BOX/cdpath-expected" "$BOX/cdpath-caller"

# Even a CDPATH candidate pointing to the SAME scripts can corrupt SD with
# cd's unsolicited stdout. Bare relative entry names intentionally avoid ./.
ln -s "$S/scripts" "$P/relative-entry"
ln -s "$S/scripts" "$CDPATH_DIR/relative-entry"
snapshot > "$BOX/cdpath-relative-before"
run "$P" "$RT" context
good 'CDPATH relative context control'
cp "$BOX/out" "$BOX/cdpath-context-expected"
run "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" relative-entry/handoff-runtime.sh context
good 'CDPATH relative runtime entry succeeds'
check 'CDPATH relative runtime stdout exactly matches direct entry' cmp -s "$BOX/cdpath-context-expected" "$BOX/out"
run "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" relative-entry/hx.sh block get recent
good 'CDPATH relative hx block entry succeeds'
check 'CDPATH relative hx stdout contains only block bytes' cmp -s "$BOX/recent" "$BOX/out"
run "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" relative-entry/hx.sh now
good 'CDPATH relative hx now succeeds'
check 'CDPATH relative hx now has exactly three data lines' test "$(wc -l < "$BOX/out" | tr -d ' ')" -eq 3
check 'CDPATH relative hx now has only expected fields' test "$(grep -Ec '^(human|fm|fn)=' "$BOX/out")" -eq 3
run "$P" "$PF" --quiet "$P/$HX_MAIN_FILE"
good 'CDPATH relative postflight control'
cp "$BOX/out" "$BOX/cdpath-postflight-expected"
run "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" relative-entry/handoff-postflight.sh --quiet "$P/$HX_MAIN_FILE"
good 'CDPATH relative postflight entry succeeds'
check 'CDPATH relative postflight stdout exactly matches direct entry' cmp -s "$BOX/cdpath-postflight-expected" "$BOX/out"
snapshot > "$BOX/cdpath-relative-after"
check 'CDPATH relative read/check helpers leave files unchanged' cmp -s "$BOX/cdpath-relative-before" "$BOX/cdpath-relative-after"
check 'successful children preserve caller CDPATH' cmp -s "$BOX/cdpath-expected" "$BOX/cdpath-caller"

# Exercise the installer's relative self-location too, still installing only
# inside wip with the disposable HOME; never source it into the caller shell.
ln -s "$ROOT" "$P/installer-entry"
ln -s "$ROOT" "$CDPATH_DIR/installer-entry"
run "$P" "$CDPATH_RUNNER" "$CDPATH_DIR" "$BOX/cdpath-caller" installer-entry/install.sh --project "$BOX/cdpath-install-project"
good 'CDPATH relative installer entry succeeds'
check 'CDPATH installer stdout has no search-path cd echo' lacks "$CDPATH_DIR/installer-entry"
check 'installer child preserves caller CDPATH' cmp -s "$BOX/cdpath-expected" "$BOX/cdpath-caller"
printf 'schema=1\nscope=project\nproject_root=%s\nskill_root=%s\nhost=claude\n' \
    "$BOX/cdpath-install-project" "$BOX/cdpath-install-project/.claude/skills/handoffx" > "$BOX/cdpath-install-expected"
check 'CDPATH installer binds the actual physical project' cmp -s "$BOX/cdpath-install-expected" "$BOX/cdpath-install-project/.claude/skills/handoffx/.handoffx-install-context"
rm "$P/relative-entry" "$P/installer-entry"

# Both default paths and explicit attempts to redirect a bound helper must fail.
for cwd in "$OTHER" "$P/child"; do
    reject 'wrong cwd: context' "$cwd" "$RT" context --root "$P" --skill-root "$S"
    reject 'wrong cwd: preflight/init' "$cwd" "$RT" init
    reject 'wrong cwd: init must not repair cwd via --root' "$cwd" "$RT" init --root "$P"
    reject 'wrong cwd: recall' "$cwd" "$RT" recall
    reject 'wrong cwd: block' "$cwd" "$HX" block set recent --from "$BOX/recent" --file "$P/$HX_MAIN_FILE"
    reject 'wrong cwd: regen' "$cwd" "$HX" regen --root "$P"
    reject 'wrong cwd: postflight' "$cwd" "$PF" "$P/$HX_MAIN_FILE"
done
reject 'external expected root' "$P" "$RT" context --root "$OTHER"
reject 'external expected skill root' "$P" "$RT" context --skill-root "$OTHER"
reject 'external init root' "$P" "$RT" init --root "$OTHER"
reject 'external regen root' "$P" "$HX" regen --root "$OTHER"
reject 'external block target' "$P" "$HX" block set recent --from "$BOX/recent" --file "$OTHER/$HX_MAIN_FILE"
reject 'external block read target' "$P" "$HX" block get recent --file "$OTHER/$HX_MAIN_FILE"
reject 'external postflight FILE' "$P" "$PF" "$OTHER/$HX_MAIN_FILE"

# Moving the whole project leaves an old absolute binding; do not auto-repair it.
ORIGINAL_P=$P
mv "$P" "$P-moved"
P="$P-moved"
MS="$P/.claude/skills/handoffx/scripts"
reject 'moved project context' "$P" "$MS/handoff-runtime.sh" context
reject 'moved project preflight' "$P" "$MS/handoff-runtime.sh" init
reject 'moved project recall' "$P" "$MS/handoff-runtime.sh" recall
reject 'moved project block' "$P" "$MS/hx.sh" block set recent --from "$BOX/recent"
reject 'moved project regen' "$P" "$MS/hx.sh" regen
reject 'moved project postflight' "$P" "$MS/handoff-postflight.sh" "$P/$HX_MAIN_FILE"
mv "$P" "$ORIGINAL_P"
P=$ORIGINAL_P
# Copying just the installed skill must not downgrade it to source_unbound.
cp -R "$S" "$P/copied-skill"
reject 'copied installation binding' "$P" "$P/copied-skill/scripts/handoff-runtime.sh" context
rm -rf "$P/copied-skill"

mv "$M" "$BOX/saved-manifest"
reject 'missing manifest context' "$P" "$RT" context
reject 'missing manifest preflight' "$P" "$RT" init
reject 'missing manifest recall' "$P" "$RT" recall
reject 'missing manifest block' "$P" "$HX" block set recent --from "$BOX/recent"
reject 'missing manifest regen' "$P" "$HX" regen
reject 'missing manifest postflight' "$P" "$PF" "$P/$HX_MAIN_FILE"
mv "$BOX/saved-manifest" "$M"

# Use an actual global installation in the disposable HOME, not forged metadata.
# Only runtime children restore the incoming HOME so ancestor scanning can
# identify real legacy global peers above this wip sandbox. Installation and
# snapshot() retain the disposable HOME. This wrapper does not bypass context
# validation, alter manifests, or write to the real HOME/global installation.
GLOBAL_RUNNER="$BOX/global-runtime.sh"
cat > "$GLOBAL_RUNNER" <<'GLOBAL_RUNTIME'
#!/bin/bash
export HOME="$1"
shift
exec "$BASH" "$@"
GLOBAL_RUNTIME
run "$BOX" "$ROOT/install.sh" --claude
good 'isolated global installation'
GS="$HOME/.claude/skills/handoffx"
if [ "$RC" -ne 0 ] || [ ! -f "$GS/.handoffx-install-context" ]; then exit 1; fi
printf 'schema=1\nscope=global\nproject_root=\nskill_root=%s\nhost=claude\n' "$GS" > "$BOX/global-manifest"
check 'global manifest exact contract' cmp -s "$BOX/global-manifest" "$GS/.handoffx-install-context"
run "$OTHER" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/handoff-runtime.sh" context
good 'global helper without local shadow'
check 'global context scope' has scope=global
reject 'global/local collision: context' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/handoff-runtime.sh" context
reject 'global/local collision: init' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/handoff-runtime.sh" init
reject 'global/local collision: recall' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/handoff-runtime.sh" recall
reject 'global/local collision: block' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/hx.sh" block set recent --from "$BOX/recent"
reject 'global/local collision: regen' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/hx.sh" regen
reject 'global/local collision: postflight' "$P" "$GLOBAL_RUNNER" "$ORIGINAL_HOME" "$GS/scripts/handoff-postflight.sh" "$P/$HX_MAIN_FILE"
run "$P" "$RT" context
good 'local helper remains authoritative alongside global install'

# Provenance is a claim, not authentication; validate shape and avoid partial stdout.
run "$P" "$RT" verification --source runner_report --command 'fixture-only; no model execution' --result passed
# This record documents test data, not a claimed execution timestamp.
good 'verification render'
cp "$BOX/out" "$BOX/valid-verification"
check 'unknown event time remains unknown' has 'performed_at: unknown'
run "$P" "$HX" block set recent --from "$BOX/valid-verification"
good 'persist structured current verification'
run "$P" "$RT" verification-check --current --require
good 'current verification positive control'
check 'verification claims not authenticated' has verification_status=structured_claims_unverified
run "$P" "$RT" recall
good 'recall valid current verification'

# Duplicate field and unclosed marker exercise distinct malformed parser paths.
for malformed in duplicate-field unclosed-marker; do
    case "$malformed" in
        duplicate-field) sed '/^source: /a\
source: unknown
' "$BOX/valid-verification" > "$BOX/bad-verification" ;;
        unclosed-marker) sed '/^<!-- \/verification -->$/d' "$BOX/valid-verification" > "$BOX/bad-verification" ;;
    esac
    run "$P" "$HX" block set recent --from "$BOX/bad-verification"
    good "seed $malformed current verification"
    reject "$malformed: current verification" "$P" "$RT" verification-check --current --require
    reject "$malformed: recall current verification" "$P" "$RT" recall
done
run "$P" "$HX" block set recent --from "$BOX/valid-verification"
good 'restore valid current state'
LOG="$P/$HX_LOGS_DIR/0001-2026-01-01T0000-trust-fixture.md"
{
    printf '%s\n' '---' 'date: 2026-01-01T00:00' 'title: Trust fixture' '---' '<!-- recall-summary -->' 'TRUST_LOG_SUMMARY' '<!-- /recall-summary -->'
    cat "$BOX/valid-verification"
} > "$LOG"
run "$P" "$RT" recall 1
good 'recall valid selected log'
check 'selected log actually loaded' has TRUST_LOG_SUMMARY
# Corruption outside the bounded excerpt must still be checked before stdout.
printf '<!-- verification:v1 -->\nsource: unknown\n' >> "$LOG"
reject 'malformed selected log verification' "$P" "$RT" recall 1
rm "$LOG"

# Old standalone tools intentionally have no installed project authority.
run "$OTHER" "$ROOT/scripts/handoff-runtime.sh" context
good 'source context legacy compatibility'
check 'source identity explicitly unbound' has scope=source_unbound
run "$BOX" "$ROOT/scripts/handoff-runtime.sh" init --root "$OTHER"
good 'source init explicit root from another cwd'
run "$BOX" "$ROOT/scripts/hx.sh" block set recent --from "$BOX/recent" --file "$OTHER/$HX_MAIN_FILE"
good 'source block explicit external file compatibility'
run "$BOX" "$ROOT/scripts/hx.sh" regen --root "$OTHER"
good 'source regen explicit external root compatibility'
run "$BOX" "$ROOT/scripts/handoff-postflight.sh" --quiet "$OTHER/$HX_MAIN_FILE"
good 'source postflight explicit external FILE compatibility'
run "$OTHER" "$ROOT/scripts/handoff-runtime.sh" recall
good 'source recall compatibility'
check 'source recall updated target' has TRUST_INTEGRATION_RECENT
# Fault injection changes ONLY a disposable installer source copy. The
# renderer runs in command substitutions, so record calls on disk, not in a
# shell variable that would disappear when its subshell exits.
FAULT_SRC="$BOX/installer-source"
mkdir -p "$FAULT_SRC/skills"
cp "$ROOT/VERSION" "$FAULT_SRC/VERSION"
cp -R "$ROOT/skills/handoffx" "$FAULT_SRC/skills/handoffx"
cat > "$BOX/renderer-injection" <<'INJECTION'
    printf '%s\n' "${FUNCNAME[1]:-unknown}" >> "$HX_TRUST_RENDER_TRACE"
    case "$HX_TRUST_RENDER_PHASE:${FUNCNAME[1]:-unknown}" in
        put:*)
            printf 'trust-test: injected empty renderer failure at %s\n' "${FUNCNAME[1]:-unknown}" >&2
            return 73 ;;
        verify:verify_cli)
            # Return the EXACT stored bytes, then fail. A cmp against process
            # substitution alone would falsely succeed and lose this status.
            [ -s "$1/.handoffx-install-context" ] || {
                printf 'trust-test: verify fixture missing populated manifest\n' >&2
                return 74
            }
            cat "$1/.handoffx-install-context" || return 74
            printf 'trust-test: injected matching-output renderer failure at verify_cli\n' >&2
            return 73 ;;
    esac
INJECTION
# Fail loudly if the function anchor changes; never run an unpatched fixture
# and mistake an unrelated installer error for injected failure coverage.
awk 'FNR==NR { injection=injection $0 ORS; next }
    /^render_install_context\(\) \{/ { print; printf "%s", injection; count++; next }
    { print }
    END { if (count!=1) exit 2 }
' "$BOX/renderer-injection" "$ROOT/install.sh" > "$FAULT_SRC/install.sh"
"$BASH_BIN" -n "$FAULT_SRC/install.sh"

renderer_failure_case() {
    local phase="$1" state="$2" kind="${3:-context}" case_dir skill manifest writer success_message error_message
    case "$kind" in
        context) writer=put_skill; success_message='Skill →'; error_message='无法生成项目/技能根绑定' ;;
        shim) writer=put_shim; success_message='Command →'; error_message='无法生成绑定后的 shim' ;;
    esac
    case_dir="$BOX/renderer-$kind-$phase-$state"
    # Dynamic locals also scope snapshot()/run(); exports are restored when
    # this function returns. The original user's HOME is never an install root.
    local P="$case_dir/project" OTHER="$case_dir/other" HOME="$case_dir/home"
    local XDG_CONFIG_HOME="$HOME/.config" CODEX_HOME="$HOME/.codex"
    local HANDOFF_TEST_WSL_HOME="$HOME/wsl"
    local HX_TRUST_RENDER_PHASE="$phase" HX_TRUST_RENDER_TRACE="$case_dir/render-calls"
    export HOME XDG_CONFIG_HOME CODEX_HOME HANDOFF_TEST_WSL_HOME
    export HX_TRUST_RENDER_PHASE HX_TRUST_RENDER_TRACE
    mkdir -p "$P" "$OTHER" "$HOME"
    printf 'keep unrelated project data\n' > "$P/user-data.txt"
    skill="$P/.claude/skills/handoffx"
    manifest="$skill/.handoffx-install-context"
    if [ "$state" = reinstall ]; then
        run "$BOX" "$ROOT/install.sh" --project "$P"
        good "$kind/$phase renderer failure: prepare real prior install"
        if [ "$RC" -ne 0 ] || [ ! -s "$manifest" ]; then
            check "$kind/$phase renderer failure: prior manifest exists" test -s "$manifest"
            return 0
        fi
        # A failed reinstall must restore the previous skill AND generated
        # commands, not simply leave a fresh working installation behind.
        printf 'old skill contents must survive rollback\n' > "$skill/rollback-sentinel.txt"
        printf '\nold command contents must survive rollback\n' >> "$P/.claude/commands/handoffx-recall.md"
        cp "$manifest" "$case_dir/prior-manifest"
    fi
    snapshot > "$case_dir/before"
    run "$BOX" "$FAULT_SRC/install.sh" --project "$P"
    check "$kind/$phase/$state renderer failure: installer exits 1, not success" test "$RC" -eq 1
    check "$kind/$phase/$state renderer failure: no verification success claim" lacks '安装验证通过'
    check "$kind/$phase/$state renderer failure: no completion banner" lacks ' installed'
    check "$kind/$phase/$state renderer failure: no fallback completion banner" lacks 'handoffx installer complete'
    check "$kind/$phase/$state renderer failure: rollback completes" grep -qF '已还原到安装前状态' "$BOX/err"
    check "$kind/$phase/$state renderer failure: put stage actually reached" grep -qx "$writer" "$HX_TRUST_RENDER_TRACE"
    if [ "$phase" = put ]; then
        check "$kind/$phase/$state renderer failure: injected empty failure reached" \
            grep -qF "trust-test: injected empty renderer failure at $writer" "$BOX/err"
        check "$kind/$phase/$state renderer failure: no premature write success" lacks "$success_message"
        check "$kind/$phase/$state renderer failure: stops before verify" \
            test "$(cat "$HX_TRUST_RENDER_TRACE")" = "$writer"
    else
        check "$kind/$phase/$state renderer failure: verify actually reached" grep -qx verify_cli "$HX_TRUST_RENDER_TRACE"
        check "$kind/$phase/$state renderer failure: populated matching-output failure reached" \
            grep -qF 'trust-test: injected matching-output renderer failure at verify_cli' "$BOX/err"
        check "$kind/$phase/$state renderer failure: verify reports renderer error" \
            grep -qF "$error_message" "$BOX/err"
    fi
    snapshot > "$case_dir/after"
    check "$kind/$phase/$state renderer failure: project and HOME fully restored" cmp -s "$case_dir/before" "$case_dir/after"
    if ! cmp -s "$case_dir/before" "$case_dir/after"; then
        diff -u "$case_dir/before" "$case_dir/after" >&2 || true
    fi
    check "$kind/$phase/$state renderer failure: no stranded transaction directory" test ! -e "$HOME/.handoffx-install"
    if [ "$state" = reinstall ]; then
        check "$kind/$phase/$state renderer failure: prior manifest restored" cmp -s "$case_dir/prior-manifest" "$manifest"
        run "$P" "$skill/scripts/handoff-runtime.sh" context
        good "$kind/$phase/$state renderer failure: restored install still usable"
        check "$kind/$phase/$state renderer failure: restored install stays bound" has scope=project
    else
        check "$kind/$phase/$state renderer failure: no empty manifest or partial skill left" test ! -e "$skill"
    fi
}
for phase in put verify; do
    for state in fresh reinstall; do
        renderer_failure_case "$phase" "$state"
    done
done
# Repeat both transaction phases for command shims. Verification deliberately
# emits byte-identical output before returning failure, defeating cmp-only
# process-substitution checks. Only the copied installer gets this hook.
cat > "$BOX/shim-renderer-injection" <<'SHIM_INJECTION'
    printf '%s\n' "${FUNCNAME[1]:-unknown}" >> "$HX_TRUST_RENDER_TRACE"
    case "$HX_TRUST_RENDER_PHASE:${FUNCNAME[1]:-unknown}" in
        put:*)
            printf 'trust-test: injected empty renderer failure at %s\n' "${FUNCNAME[1]:-unknown}" >&2
            return 73 ;;
        verify:verify_cli)
            [ -s "$2" ] || {
                printf 'trust-test: verify fixture missing populated shim\n' >&2
                return 74
            }
            cat "$2" || return 74
            printf 'trust-test: injected matching-output renderer failure at verify_cli\n' >&2
            return 73 ;;
        trailing-newlines:*)
            printf 'shim fixture: preserve all trailing newlines\n\n\n'
            return 0 ;;
    esac
SHIM_INJECTION
awk 'FNR==NR { injection=injection $0 ORS; next }
    /^render_shim\(\) \{/ { print; printf "%s", injection; count++; next }
    { print }
    END { if (count!=1) exit 2 }
' "$BOX/shim-renderer-injection" "$ROOT/install.sh" > "$FAULT_SRC/install.sh"
"$BASH_BIN" -n "$FAULT_SRC/install.sh"
for phase in put verify; do
    for state in fresh reinstall; do
        renderer_failure_case "$phase" "$state" shim
    done
done

# Successful rendering must preserve trailing LF bytes too. Both put and
# verify run the copied renderer; compare stored bytes independently so that
# matching truncation bugs in those two consumers cannot hide each other.
mkdir "$BOX/shim-newline-project"
HX_TRUST_RENDER_PHASE=trailing-newlines HX_TRUST_RENDER_TRACE="$BOX/shim-newline-calls" \
    run "$BOX" "$FAULT_SRC/install.sh" --project "$BOX/shim-newline-project"
good 'shim sentinel preserves successful rendering'
check 'shim trailing-newline fixture reached writer' grep -qx put_shim "$BOX/shim-newline-calls"
check 'shim trailing-newline fixture reached verifier' grep -qx verify_cli "$BOX/shim-newline-calls"
printf 'shim fixture: preserve all trailing newlines\n\n\n' > "$BOX/shim-newline-expected"
for command in handoffx-recall handoffx-tidy handoffx-memory handoffx-init; do
    check "shim $command retains every trailing newline" cmp -s "$BOX/shim-newline-expected" "$BOX/shim-newline-project/.claude/commands/$command.md"
done
printf 'trust integration: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
