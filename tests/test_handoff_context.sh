#!/bin/bash
# Run: /bin/bash tests/test_handoff_context.sh (macOS /bin/bash is Bash 3.2).
# Child-shell programs intentionally expand their variables in the child.
# shellcheck disable=SC2016
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# common.sh's legacy setup creates tests/.tmp. Suppress only that mkdir;
# use its existing assertions/summary without creating anything outside wip/tmp.
# Invoked indirectly by common.sh.
# shellcheck disable=SC2329
mkdir() {
    if [ "$#" -eq 2 ] && [ "$1" = -p ] && [ "$2" = "$ROOT/tests/.tmp" ]; then
        return 0
    fi
    command mkdir "$@"
}
# shellcheck disable=SC1091
. "$ROOT/tests/common.sh"
unset -f mkdir
mkdir -p "$ROOT/wip/tmp"
export TMPDIR="$ROOT/wip/tmp"
TMP_DIR=$(mktemp -d "$TMPDIR/handoff-context.XXXXXX")
trap 'chmod -R u+rwX "$TMP_DIR"; rm -rf "$TMP_DIR"' EXIT
LIB="$ROOT/scripts/lib/handoff-context.sh"
MIRROR="$ROOT/skills/handoffx/scripts/lib/handoff-context.sh"
BASH_BIN="${BASH:-/bin/bash}"
RC=0 OUT='' ERR=''

ctx_assert() {
    local label="$1"; shift
    if "$@"; then PASS=$((PASS + 1)); else
        printf '  ❌ %s\n' "$label" >&2
        FAIL=$((FAIL + 1))
    fi
}
ctx_run() {
    local cwd="$1"; shift
    RC=0
    (cd "$cwd" && "$BASH_BIN" -eu -o pipefail -c '
        . "$1"; shift
        hx_context_check "$@"
    ' context-test "$LIB" "$@") > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr" || RC=$?
    OUT=$(cat "$TMP_DIR/stdout")
    ERR=$(cat "$TMP_DIR/stderr")
}
ctx_bad() {
    ctx_assert "$1: fails" test "$RC" -ne 0
    ctx_assert "$1: stdout completely empty" test ! -s "$TMP_DIR/stdout"
    ctx_assert "$1: stderr diagnostic" test -s "$TMP_DIR/stderr"
}
ctx_good() {
    assert_exit "$1: succeeds" 0 "$RC"
    ctx_assert "$1: stderr empty" test ! -s "$TMP_DIR/stderr"
    assert_contains "$1: contract" "$OUT" 'context_contract=1'
}
ctx_manifest() {
    local skill="$1" scope="$2" project="$3" host="${4:-claude}"
    printf 'schema=1\nscope=%s\nproject_root=%s\nskill_root=%s\nhost=%s\n' \
        "$scope" "$project" "$skill" "$host" > "$skill/.handoffx-install-context"
}
ctx_install() { mkdir -p "$1/scripts/lib"; }

ctx_assert 'mirrors byte-identical' cmp -s "$LIB" "$MIRROR"
ctx_assert 'primary syntax' "$BASH_BIN" -n "$LIB"
ctx_assert 'mirror syntax' "$BASH_BIN" -n "$MIRROR"
P="$TMP_DIR/空格 project 中文"
S="$P/.claude/skills/handoffx"
M="$S/.handoffx-install-context"
ctx_install "$S"
mkdir -p "$P-prefix" "$P/child" "$TMP_DIR/other"
ctx_manifest "$S" project "$P"
ctx_run "$P" "$S/scripts" "$P" "$S"
ctx_good 'bound project, spaces and Unicode'
assert_contains 'full project root' "$OUT" "project_root=$P"
assert_contains 'full skill root' "$OUT" "skill_root=$S"
assert_contains 'project scope' "$OUT" 'scope=project'
ctx_assert 'exact successful record' test "$OUT" = "$(printf 'scope=project\nproject_root=%s\nskill_root=%s\ncontext_contract=1' "$P" "$S")"

for wrong in "$TMP_DIR" "$P-prefix" "$P/child" "$TMP_DIR/other"; do
    ctx_run "$wrong" "$S/scripts"
    ctx_bad "wrong cwd: $wrong"
done
ctx_run "$P" "$S/scripts" "$TMP_DIR"
ctx_bad 'explicit root mismatch'
ctx_run "$P" "$S/scripts" "$P" "$TMP_DIR"
ctx_bad 'explicit skill mismatch'
ctx_run "$P" "$S/scripts" '' "$S"
ctx_good 'empty optional root placeholder'
ctx_run "$P" '.claude/skills/handoffx/scripts/./' './' '.claude/skills/handoffx/.'
ctx_good 'relative arguments canonicalized'
ctx_run "$P" "$S/scripts" "$P" "$S" extra
ctx_bad 'excess arguments'
ctx_run "$P"
ctx_bad 'missing argument'
ctx_run "$P" ''
ctx_bad 'empty scripts path'
ctx_run "$P" "$S"
ctx_bad 'not scripts directory'

# Pure library sourcing/checking must not mutate caller state or manifest.
BEFORE=$(cksum < "$M")
RC=0
(cd "$P" && "$BASH_BIN" -eu -o pipefail -c '
    before_pwd=$(pwd -P); before_opts=$-; before_umask=$(umask)
    before_locale=${LC_ALL-unset}; before_traps=$(trap -p)
    . "$1"; . "$1"
    hx_context_check "$2" "$before_pwd" > /dev/null
    test "$(pwd -P)" = "$before_pwd"
    test "$-" = "$before_opts"
    test "$(umask)" = "$before_umask"
    test "${LC_ALL-unset}" = "$before_locale"
    test "$(trap -p)" = "$before_traps"
    if hx_context_check "$2" "$3"; then exit 88; fi
    test "$(pwd -P)" = "$before_pwd"
' context-test "$LIB" "$S/scripts" "$TMP_DIR") > "$TMP_DIR/state-out" 2> "$TMP_DIR/state-err" || RC=$?
assert_exit 'source twice/check leaves cwd, options, locale, traps, umask intact' 0 "$RC"
ctx_assert 'manifest unchanged' test "$BEFORE" = "$(cksum < "$M")"
ctx_assert 'state check failure emits no stdout' test ! -s "$TMP_DIR/state-out"

# Bash 3.2 here-strings create implicit temporary files. Exercise bound
# checks with unusable TMPDIRs and (on macOS) kernel-enforced read-only access.
# The harness creates fixtures/captures output outside the restricted process;
# neither TMPDIR permissions nor the user's sandbox/configuration are changed.
RO_BOX="$TMP_DIR/readonly-context"
RO_PROJECT="$RO_BOX/project"
RO_SKILL="$RO_PROJECT/.agents/skills/handoffx"
ctx_install "$RO_SKILL"
mkdir -p "$RO_BOX/blocked-temp"
printf 'not a directory\n' > "$RO_BOX/temp-is-file"
printf 'retain this file\n' > "$RO_BOX/keep"
# /dev/null is an existing output device, not a writable file/tmp directory.
# Permit shell stderr suppression there; file creation/deletion remain denied.
RO_PROFILE='(version 1) (allow default) (deny file-write*) (allow file-write-data (literal "/dev/null"))'
RO_SANDBOX=$(command -v sandbox-exec || true)
if [ -n "$RO_SANDBOX" ]; then
    RC=0
    "$RO_SANDBOX" -p "$RO_PROFILE" "$BASH_BIN" -eu -c 'printf forbidden > "$1"' \
        readonly-probe "$RO_BOX/blocked-temp/forbidden" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr" || RC=$?
    ctx_assert 'read-only probe denies temporary file creation' test "$RC" -ne 0
    ctx_assert 'read-only probe created no file' test ! -e "$RO_BOX/blocked-temp/forbidden"
    RC=0
    "$RO_SANDBOX" -p "$RO_PROFILE" /bin/rm "$RO_BOX/keep" \
        > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr" || RC=$?
    ctx_assert 'read-only probe denies file deletion' test "$RC" -ne 0
    ctx_assert 'read-only probe retained existing file' test -f "$RO_BOX/keep"
    printf '  read-only sandbox: ordinary file writes denied, /dev/null device only; Bash %s\n' "$BASH_VERSION"
else
    printf '  ➖ sandbox-exec unavailable: testing unusable TMPDIR and file snapshots only\n'
fi
ctx_ro_snapshot() {
    (cd "$RO_BOX" && find . -print | LC_ALL=C sort)
    find "$RO_BOX" -type f -exec cksum {} \; | LC_ALL=C sort
}
ctx_ro_exec() (
    local tempdir="$1" lib="$2"
    local program='. "$1"; hx_context_check "$2" "$3" "$4"'
    cd "$RO_PROJECT"
    if [ -n "$RO_SANDBOX" ]; then
        TMPDIR="$tempdir" "$RO_SANDBOX" -p "$RO_PROFILE" "$BASH_BIN" -eu -o pipefail \
            -c "$program" readonly-context "$lib" "$RO_SKILL/scripts" "$RO_PROJECT" "$RO_SKILL"
    else
        TMPDIR="$tempdir" "$BASH_BIN" -eu -o pipefail \
            -c "$program" readonly-context "$lib" "$RO_SKILL/scripts" "$RO_PROJECT" "$RO_SKILL"
    fi
)
RO_LIB_BEFORE=$(cksum "$LIB" "$MIRROR")
for ro_lib in "$LIB" "$MIRROR"; do
    for ro_tmp in "$RO_BOX/blocked-temp" "$RO_BOX/temp-is-file" "$RO_BOX/missing-temp"; do
        for ending in final-LF no-final-LF extra-blank-line; do
            ctx_manifest "$RO_SKILL" project "$RO_PROJECT" codex
            case "$ending" in
                no-final-LF)
                    printf 'schema=1\nscope=project\nproject_root=%s\nskill_root=%s\nhost=codex' \
                        "$RO_PROJECT" "$RO_SKILL" > "$RO_SKILL/.handoffx-install-context" ;;
                extra-blank-line) printf '\n' >> "$RO_SKILL/.handoffx-install-context" ;;
            esac
            ro_before=$(ctx_ro_snapshot)
            RC=0
            ctx_ro_exec "$ro_tmp" "$ro_lib" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr" || RC=$?
            OUT=$(cat "$TMP_DIR/stdout"); ERR=$(cat "$TMP_DIR/stderr")
            label="read-only ${ro_tmp##*/} $ending ($ro_lib)"
            if [ "$ending" = extra-blank-line ]; then
                ctx_bad "$label"
                assert_contains 'extra blank line rejected by parser, not temp-file failure' "$ERR" 'malformed manifest field'
            else
                ctx_good "$label"
                ctx_assert 'read-only exact bound record' test "$OUT" = "$(printf 'scope=project\nproject_root=%s\nskill_root=%s\ncontext_contract=1' "$RO_PROJECT" "$RO_SKILL")"
            fi
            ctx_assert 'read-only no file additions, deletions or content changes' \
                test "$ro_before" = "$(ctx_ro_snapshot)"
        done
    done
done
ctx_assert 'read-only libraries unchanged' test "$RO_LIB_BEFORE" = "$(cksum "$LIB" "$MIRROR")"

# Source layouts remain usable but never imply an authorized/bound project.
for source_scripts in "$ROOT/scripts" "$ROOT/skills/handoffx/scripts"; do
    ctx_run "$P" "$source_scripts" "$P"
    ctx_good 'source layout from arbitrary cwd'
    assert_contains 'source scope' "$OUT" 'scope=source_unbound'
    assert_contains 'source binding disclaimer' "$OUT" 'project_binding=unverified'
    ctx_assert 'source project root empty' grep -qx 'project_root=' "$TMP_DIR/stdout"
done
COPY="$TMP_DIR/arbitrary copy"
ctx_install "$COPY"
cp "$LIB" "$COPY/scripts/lib/handoff-context.sh"
ctx_run "$P" "$COPY/scripts"
ctx_good 'unknown arbitrary source copy'
assert_contains 'copy not authenticated' "$OUT" 'scope=source_unbound'
ctx_run "$P" "$COPY/scripts" "$TMP_DIR"
ctx_bad 'source explicit root mismatch'
ctx_run "$P" "$COPY/scripts" "$P" "$ROOT"
ctx_bad 'source explicit skill mismatch'

# Missing manifests at every supported installed layout must fail closed.
for hostdir in .claude .agents .opencode .config/opencode custom-xdg/opencode; do
    install="$TMP_DIR/no manifest/$hostdir/skills/handoffx"
    ctx_install "$install"
    ctx_run "$P" "$install/scripts"
    ctx_bad "missing installed manifest: $hostdir"
    assert_contains 'reinstall diagnostic' "$ERR" 'reinstall'
done

# Global installations: host is the first installer owner, not necessarily the
# calling host. Any supported project-local installation blocks global bypass.
for host in claude codex opencode; do
    case "$host" in claude) hd=.claude ;; codex) hd=.agents ;; opencode) hd=.opencode ;; esac
    g="$TMP_DIR/global $host/$hd/skills/handoffx"
    work="$TMP_DIR/work $host"
    ctx_install "$g"
    mkdir -p "$work"
    ctx_manifest "$g" global '' "$host"
    ctx_run "$work" "$g/scripts"
    ctx_good "global $host"
    assert_contains 'global scope' "$OUT" 'scope=global'
    mkdir -p "$work/$hd/skills/handoffx"
    ctx_run "$work" "$g/scripts"
    ctx_bad "global $host local shadow"
    rmdir "$work/$hd/skills/handoffx"
    ln -s "$work/missing" "$work/$hd/skills/handoffx"
    ctx_run "$work" "$g/scripts"
    ctx_bad "global $host dangling local shadow"
    rm "$work/$hd/skills/handoffx"
    touch "$work/$hd/skills/handoffx"
    ctx_run "$work" "$g/scripts"
    ctx_bad "global $host file local shadow"
    rm "$work/$hd/skills/handoffx"
    ctx_run "$TMP_DIR/global $host" "$g/scripts"
    ctx_good "global $host same skill is not another shadow"
    ctx_manifest "$g" global "$work" "$host"
    ctx_run "$work" "$g/scripts"
    ctx_bad 'global nonempty project root'
done
ctx_manifest "$g" global '' opencode
ctx_run "$P" "$g/scripts"
ctx_bad 'other host local install also shadows global'

# OpenCode default and custom XDG global layouts fail closed without metadata,
# but still support valid global manifests. Source-like near misses stay unbound.
for layout in .config/opencode custom-xdg/opencode; do
    oc="$TMP_DIR/OpenCode home/$layout/skills/handoffx"
    oc_work="$TMP_DIR/OpenCode work $layout"
    ctx_install "$oc"
    mkdir -p "$oc_work"
    ctx_run "$oc_work" "$oc/scripts/../scripts/."
    ctx_bad "OpenCode $layout no manifest with dot segments"
    ctx_manifest "$oc" global '' opencode
    ctx_run "$oc_work" "$oc/scripts"
    ctx_good "OpenCode $layout valid global"
    mkdir -p "$oc_work/.opencode/skills/handoffx"
    ctx_run "$oc_work" "$oc/scripts"
    ctx_bad "OpenCode $layout project-local shadow"
done
for layout in .config/opencode-other/skills/handoffx .config/opencode/skills/handoffx-other; do
    near="$TMP_DIR/near miss/$layout"
    ctx_install "$near"
    ctx_run "$P" "$near/scripts"
    ctx_good "source near miss $layout"
    assert_contains 'near miss is explicitly unbound' "$OUT" 'scope=source_unbound'
done

# Reproduce a shared physical global directory: aliases exist, but the shims
# call the canonical physical skill root. Its manifest retains the first owner.
# No environment/home changes or external installation is needed for this test.
for owner in claude codex opencode; do
    shared_home="$TMP_DIR/shared home $owner"
    shared="$shared_home/.claude/skills/handoffx"
    shared_work="$TMP_DIR/shared work $owner"
    ctx_install "$shared"
    mkdir -p "$shared_home/.agents" "$shared_home/.config/opencode" "$shared_work"
    ln -s "$shared_home/.claude/skills" "$shared_home/.agents/skills"
    ln -s "$shared_home/.claude/skills" "$shared_home/.config/opencode/skills"
    ctx_manifest "$shared" global '' "$owner"
    shared_before=$(cksum < "$shared/.handoffx-install-context")
    ctx_run "$shared_work" "$shared/scripts"
    ctx_good "shared directory owner=$owner without shadows"
    # Run the full owner x local-host matrix, not just host=claude.
    for local_host in .claude .agents .opencode; do
        local_skill="$shared_work/$local_host/skills/handoffx"
        mkdir -p "$local_skill"
        ctx_run "$shared_work" "$shared/scripts"
        ctx_bad "shared owner=$owner local=$local_host directory"
        rmdir "$local_skill"
        touch "$local_skill"
        ctx_run "$shared_work" "$shared/scripts"
        ctx_bad "shared owner=$owner local=$local_host file"
        rm "$local_skill"
        ln -s "$shared_work/missing" "$local_skill"
        ctx_run "$shared_work" "$shared/scripts"
        ctx_bad "shared owner=$owner local=$local_host dangling symlink"
        rm "$local_skill"
    done
    # An absent exact name must not cause prefix or parent-directory matching.
    mkdir -p "$shared_work/.agents/skills/handoffx-other"
    ctx_run "$shared_work" "$shared/scripts"
    ctx_good "shared owner=$owner similarly named local skill is not shadow"
    ctx_assert "shared owner=$owner metadata not rewritten" test "$shared_before" = "$(cksum < "$shared/.handoffx-install-context")"
done

# Finding the same physical skill in the first directory is not an early
# success: a different local skill in a later host directory still blocks it.
same_home="$TMP_DIR/same skill boundary"
same="$same_home/.claude/skills/handoffx"
ctx_install "$same"
ctx_manifest "$same" global '' claude
ctx_run "$same_home" "$same/scripts"
ctx_good 'same physical local skill alone is allowed'
mkdir -p "$same_home/.opencode/skills/handoffx"
ctx_run "$same_home" "$same/scripts"
ctx_bad 'same physical skill does not mask another host shadow'

# Installer/shims can pass a physical skill root while its host base is a
# symlink. Only a link resolving to that same skill may bypass strict checking.
for own_host in claude codex opencode; do
    case "$own_host" in claude) own_hd=.claude ;; codex) own_hd=.agents ;; opencode) own_hd=.opencode ;; esac
    own_link_home="$TMP_DIR/own host link $own_host"
    own_base="$own_link_home/dotfiles/$own_host"
    own_skill="$own_base/skills/handoffx"
    ctx_install "$own_skill"
    mkdir -p "$own_link_home/project/nested"
    ctx_manifest "$own_skill" global '' "$own_host"
    ln -s "$own_base" "$own_link_home/$own_hd"
    ctx_run "$own_link_home/project/nested" "$own_skill/scripts"
    ctx_good "own-host-link $own_host ancestor resolves to self"
    ctx_assert 'own-host-link exact output skill_root' grep -qxF "skill_root=$own_skill" "$TMP_DIR/stdout"
    CDPATH="$TMP_DIR/other" ctx_run "$own_link_home" "$own_skill/scripts"
    ctx_good "own-host-link $own_host cwd resolves to self with CDPATH"
    # A different target remains forbidden even with a valid global manifest.
    case "$own_hd" in .agents) other_hd=.claude ;; *) other_hd=.agents ;; esac
    other_base="$TMP_DIR/other host target $own_host"
    ctx_install "$other_base/skills/handoffx"
    ctx_manifest "$other_base/skills/handoffx" global '' codex
    ln -s "$other_base" "$own_link_home/$other_hd"
    ctx_run "$own_link_home/project/nested" "$own_skill/scripts"
    ctx_good "other-target-link $own_host valid global peer resolves physically"
    rm "$own_link_home/$other_hd"
done
# pwd command substitution must not strip a target's trailing newline and
# accidentally compare a different physical directory equal to the self root.
ctx_install "$own_skill"$'\n'
mkdir -p "$own_link_home/$other_hd/skills"
ln -s "$own_skill"$'\n' "$own_link_home/$other_hd/skills/handoffx"
ctx_run "$own_link_home/project/nested" "$own_skill/scripts"
ctx_bad 'other-target-link trailing newline is not self'
rm "$own_link_home/$other_hd/skills/handoffx"

# A parent project owns its descendants even without a Git repository. A
# distinct, valid global installation at the same ancestor is not a project.
ancestor_global="$TMP_DIR/ancestor caller/.agents/skills/handoffx"
ctx_install "$ancestor_global"
ctx_manifest "$ancestor_global" global '' codex
for local_host in .claude .agents .opencode; do
    parent="$TMP_DIR/祖先 project $local_host"
    child="$parent/deep/non git child"
    parent_skill="$parent/$local_host/skills/handoffx"
    ctx_install "$parent_skill"
    mkdir -p "$child" "$parent-prefix/child"
    ctx_assert 'nested fixture has no git metadata' test ! -e "$parent/.git"
    ctx_manifest "$parent_skill" project "$parent" claude
    ctx_run "$child" "$ancestor_global/scripts" "$child"
    ctx_bad "ancestor $local_host project blocks nested global"
    ctx_run "$parent-prefix/child" "$ancestor_global/scripts"
    ctx_good "ancestor $local_host exact ancestry, not string prefix"
    rm "$parent_skill/.handoffx-install-context"
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_bad "ancestor $local_host unknown binding"
    ctx_manifest "$parent_skill" global '' codex
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_good "ancestor $local_host independently bound global"
    # A global-looking declaration is not enough: all original parser checks
    # still apply, including empty project_root and matching physical root.
    ctx_manifest "$parent_skill" global "$parent" codex
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_bad "ancestor $local_host invalid global project_root"
    ctx_manifest "$parent_skill" global '' codex
    printf 'scope=global\n' >> "$parent_skill/.handoffx-install-context"
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_bad "ancestor $local_host duplicate manifest field"
    ctx_manifest "$parent_skill" project "$TMP_DIR/other" codex
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_bad "ancestor $local_host inconsistent project binding"
    # A valid global at the nearer ancestor cannot hide a project farther up.
    ctx_manifest "$parent_skill" project "$parent" claude
    closer="$parent/deep/.agents/skills/handoffx"
    ctx_install "$closer"
    ctx_manifest "$closer" global '' codex
    ctx_run "$child" "$ancestor_global/scripts"
    ctx_bad "ancestor $local_host scan continues beyond legitimate global"
done

# Independent global installations under a synthetic home all have distinct
# physical skill roots. Keep the real HOME untouched: no developer setup edits.
multihome="$TMP_DIR/多端 global home"
mkdir -p "$multihome/projects/non git/deep"
for host in claude codex opencode; do
    case "$host" in claude) layout=.claude ;; codex) layout=.agents ;; opencode) layout=.config/opencode ;; esac
    multi="$multihome/$layout/skills/handoffx"
    ctx_install "$multi"
    ctx_manifest "$multi" global '' "$host"
done
for host in claude codex opencode; do
    case "$host" in claude) layout=.claude ;; codex) layout=.agents ;; opencode) layout=.config/opencode ;; esac
    multi="$multihome/$layout/skills/handoffx"
    ctx_run "$multihome/projects/non git/deep" "$multi/scripts"
    ctx_good "multiple physical home globals: $host from nested non-git cwd"
    ctx_run "$multihome" "$multi/scripts"
    ctx_good "multiple physical home globals: $host from home cwd"
    assert_contains 'main global output not overwritten by ancestor binding' "$OUT" "skill_root=$multi"
done
# Project metadata under HOME is not exempt merely because of its location.
ctx_manifest "$multihome/.claude/skills/handoffx" project "$multihome" claude
ctx_run "$multihome/projects/non git/deep" "$multihome/.agents/skills/handoffx/scripts"
ctx_bad 'home project binding takes precedence over global layout'
ctx_manifest "$multihome/.claude/skills/handoffx" global '' claude

# The same strict parser must be used for ancestor candidates, not a grep for
# scope=global. A copied or executable-looking manifest grants no exemption.
invalid_parent="$TMP_DIR/invalid ancestor"
invalid_skill="$invalid_parent/.agents/skills/handoffx"
ctx_install "$invalid_skill"
mkdir -p "$invalid_parent/child"
ctx_manifest "$invalid_skill" global '' codex
cp "$invalid_skill/.handoffx-install-context" "$TMP_DIR/ancestor-valid"
sed '/^skill_root=/d' "$TMP_DIR/ancestor-valid" > "$invalid_skill/.handoffx-install-context"
printf 'skill_root=%s\n' "$ancestor_global" >> "$invalid_skill/.handoffx-install-context"
ctx_run "$invalid_parent/child" "$ancestor_global/scripts"
ctx_bad 'ancestor copied global binding with mismatched skill_root'
cat "$TMP_DIR/ancestor-valid" > "$invalid_skill/.handoffx-install-context"
printf 'unknown=$(touch "%s")\n' "$TMP_DIR/ancestor-pwned" >> "$invalid_skill/.handoffx-install-context"
ctx_run "$invalid_parent/child" "$ancestor_global/scripts"
ctx_bad 'ancestor shell payload treated only as data'
ctx_assert 'ancestor payload not executed' test ! -e "$TMP_DIR/ancestor-pwned"
rm "$invalid_skill/.handoffx-install-context"
ln -s "$TMP_DIR/ancestor-valid" "$invalid_skill/.handoffx-install-context"
ctx_run "$invalid_parent/child" "$ancestor_global/scripts"
ctx_bad 'ancestor symlink manifest not trusted as global'
rm "$invalid_skill/.handoffx-install-context"
mkfifo "$invalid_skill/.handoffx-install-context"
ctx_run "$invalid_parent/child" "$ancestor_global/scripts"
ctx_bad 'ancestor FIFO manifest rejected without blocking'
rm "$invalid_skill/.handoffx-install-context"
rmdir "$invalid_skill/scripts/lib" "$invalid_skill/scripts" "$invalid_skill"
ln -s "$invalid_parent/missing" "$invalid_skill"
ctx_run "$invalid_parent/child" "$ancestor_global/scripts"
ctx_bad 'ancestor dangling skill symlink rejected'
rm "$invalid_skill"

# Test the narrow legacy HOME classification in isolation, without touching
# the user's HOME, changing shell configuration or depending on its contents.
ctx_candidate() {
    RC=0
    "$BASH_BIN" -eu -o pipefail -c '
        . "$1"; shift
        _hx_context_global_candidate "$@"
    ' context-candidate "$LIB" "$@" > "$TMP_DIR/stdout" 2> "$TMP_DIR/stderr" || RC=$?
    OUT=$(cat "$TMP_DIR/stdout"); ERR=$(cat "$TMP_DIR/stderr")
}
legacy_home="$TMP_DIR/legacy global home"
for layout in .claude .agents; do
    legacy="$legacy_home/$layout/skills/handoffx"
    ctx_install "$legacy"
    ctx_candidate "$legacy" "$legacy_home" "$legacy_home"
    assert_exit "legacy HOME $layout classified as global base" 0 "$RC"
    ctx_assert 'legacy classification emits no stdout' test ! -s "$TMP_DIR/stdout"
    ctx_assert 'legacy classification emits no stderr' test ! -s "$TMP_DIR/stderr"
    ctx_run "$P" "$legacy/scripts"
    ctx_bad "legacy HOME $layout direct execution still requires manifest"
    ctx_candidate "$legacy" "$legacy_home" "$TMP_DIR/other"
    ctx_bad "unknown $layout location outside physical HOME rejected"
    ctx_manifest "$legacy" project "$legacy_home" claude
    ctx_candidate "$legacy" "$legacy_home" "$legacy_home"
    ctx_bad "HOME $layout project binding overrides location exemption"
    : > "$legacy/.handoffx-install-context"
    ctx_candidate "$legacy" "$legacy_home" "$legacy_home"
    ctx_bad "HOME $layout existing corrupt manifest never exempt"
done
legacy="$legacy_home/.opencode/skills/handoffx"
ctx_install "$legacy"
ctx_candidate "$legacy" "$legacy_home" "$legacy_home"
ctx_bad 'HOME .opencode is not OpenCode global config base'

# Relocation cannot silently rebind an installed skill.
MOVED="$TMP_DIR/moved install"
mv "$S" "$MOVED"
ctx_run "$P" "$MOVED/scripts"
ctx_bad 'moved skill mismatch'
mv "$MOVED" "$S"
MOVED_P="$TMP_DIR/moved project"
mv "$P" "$MOVED_P"
ctx_run "$MOVED_P" "$MOVED_P/.claude/skills/handoffx/scripts"
ctx_bad 'moved project mismatch'
mv "$MOVED_P" "$P"

# Strict records: all five fields required exactly once, no shell evaluation.
cp "$M" "$TMP_DIR/valid"
for field in schema scope project_root skill_root host; do
    sed "/^$field=/d" "$TMP_DIR/valid" > "$M"
    ctx_run "$P" "$S/scripts"
    ctx_bad "missing $field"
    cat "$TMP_DIR/valid" > "$M"
    grep "^$field=" "$TMP_DIR/valid" >> "$M"
    ctx_run "$P" "$S/scripts"
    ctx_bad "duplicate $field"
done
for field in 'schema=2' 'scope=unknown' 'host=other' 'project_root=' 'project_root=relative' 'skill_root=relative'; do
    key=${field%%=*}
    sed "/^$key=/d" "$TMP_DIR/valid" > "$M"
    printf '%s\n' "$field" >> "$M"
    ctx_run "$P" "$S/scripts"
    ctx_bad "invalid $field"
done
for extra in 'unknown=value' '# comment' 'export schema=1' '' 'schema'; do
    cat "$TMP_DIR/valid" > "$M"
    printf '%s\n' "$extra" >> "$M"
    ctx_run "$P" "$S/scripts"
    ctx_bad "unexpected line: $extra"
done
for attack in "\$(touch '$TMP_DIR/pwned')" "\`touch '$TMP_DIR/pwned'\`" "'; touch '$TMP_DIR/pwned'; #"; do
    sed '/^project_root=/d' "$TMP_DIR/valid" > "$M"
    printf 'project_root=%s\n' "$attack" >> "$M"
    ctx_run "$P" "$S/scripts"
    ctx_bad 'shell payload in known field'
    ctx_assert 'payload was not executed' test ! -e "$TMP_DIR/pwned"
done
cat "$TMP_DIR/valid" > "$M"
printf 'touch "%s"\n' "$TMP_DIR/pwned" >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'standalone shell command'
ctx_assert 'standalone command not executed' test ! -e "$TMP_DIR/pwned"

# Ordinary shell punctuation (including '=') is literal path data, not code.
LITERAL="$TMP_DIR/\$(touch pwned) = literal"
ctx_install "$LITERAL/.agents/skills/handoffx"
ctx_manifest "$LITERAL/.agents/skills/handoffx" project "$LITERAL" codex
ctx_run "$LITERAL" "$LITERAL/.agents/skills/handoffx/scripts"
ctx_good 'literal shell punctuation and equals in real path'
ctx_assert 'literal command substitution not executed' test ! -e "$LITERAL/pwned"

for suffix in $'\r' $'\t' $'\n'; do
    ctx_run "$P" "$S/scripts$suffix"
    ctx_bad 'control character in scripts argument'
    ctx_run "$P" "$S/scripts" "$P$suffix"
    ctx_bad 'control character in expected root'
    ctx_run "$P" "$S/scripts" "$P" "$S$suffix"
    ctx_bad 'control character in expected skill'
    bad="$TMP_DIR/control${suffix}"
    mkdir "$bad"
    ctx_run "$bad" "$ROOT/scripts"
    ctx_bad 'control character in real physical cwd'
done
cat "$TMP_DIR/valid" > "$M"
printf '\000' >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'NUL byte rejected before shell strips it'
# Portable CR fixture (BSD sed does not interpret \r in replacements).
printf 'schema=1\r\nscope=project\nproject_root=%s\nskill_root=%s\nhost=claude\n' "$P" "$S" > "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'CRLF rejected'
cat "$TMP_DIR/valid" > "$M"
printf 'extra=\t\n' >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'Tab rejected'
head -c 17000 /dev/zero | tr '\000' x > "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'oversized manifest'
: > "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'empty manifest'
# Final newline optional; no accidental extra blank field.
printf 'host=claude\nskill_root=%s\nproject_root=%s\nscope=project\nschema=1' "$S" "$P" > "$M"
ctx_run "$P" "$S/scripts"
ctx_good 'reordered fields and no final newline'
cat "$TMP_DIR/valid" > "$M"
chmod 000 "$M"
if [ -r "$M" ]; then
    printf '  ➖ unreadable fixture skipped: current user can still read mode 000\n'
else
    ctx_run "$P" "$S/scripts"
    ctx_bad 'unreadable manifest'
fi
chmod 600 "$M"
rm "$M"
ln -s "$TMP_DIR/valid" "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'symlink manifest'
rm "$M"
ln -s "$TMP_DIR/missing" "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'dangling symlink manifest'
rm "$M"
mkdir "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'directory manifest'
rmdir "$M"
mkfifo "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'FIFO manifest rejected without blocking'
rm "$M"
cat "$TMP_DIR/valid" > "$M"

ln -s "$P" "$TMP_DIR/root-link"
for rootarg in "$TMP_DIR/root-link" "$TMP_DIR/root-link/" "$TMP_DIR/root-link/." "$TMP_DIR/root-link/../other"; do
    ctx_run "$P" "$S/scripts" "$rootarg"
    ctx_bad 'symlink expected root including slash/dot/parent forms'
done
ctx_run "$P" "$TMP_DIR/root-link/.claude/skills/handoffx/scripts"
ctx_bad 'symlink ancestor of script directory'
ln -s "$S" "$TMP_DIR/skill-link"
ctx_run "$P" "$S/scripts" "$P" "$TMP_DIR/skill-link"
ctx_bad 'symlink expected skill root'
ln -s "$S/scripts" "$TMP_DIR/scripts"
ctx_run "$P" "$TMP_DIR/scripts/"
ctx_bad 'symlink scripts directory'
sed '/^project_root=/d' "$TMP_DIR/valid" > "$M"
printf 'project_root=%s\n' "$TMP_DIR/root-link" >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'symlink manifest project root'
sed '/^project_root=/d' "$TMP_DIR/valid" > "$M"
printf 'project_root=%s/.\n' "$P" >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'nonphysical manifest project root'
sed '/^skill_root=/d' "$TMP_DIR/valid" > "$M"
printf 'skill_root=%s/.\n' "$S" >> "$M"
ctx_run "$P" "$S/scripts"
ctx_bad 'nonphysical manifest skill root'
cat "$TMP_DIR/valid" > "$M"
# Logical cwd symlink is not authority: actual pwd -P is the bound project.
ctx_run "$TMP_DIR/root-link" "$S/scripts" "$P"
ctx_good 'physical cwd wins over logical PWD'

# No filesystem writes outside wip/tmp even to test macOS system aliases.
for alias_name in var tmp etc; do
    if [ -L "/$alias_name" ] && [ -d "/private/$alias_name" ]; then
        alias_out=$("$BASH_BIN" -eu -c '. "$1"; _hx_context_dir "$2"' context-test "$LIB" "/$alias_name/.")
        ctx_assert "macOS /$alias_name alias canonicalized" test "$alias_out" = "/private/$alias_name"
        alias_out=$("$BASH_BIN" -eu -c '. "$1"; _hx_context_dir "$2"' context-test "$LIB" "/$alias_name/..")
        ctx_assert "macOS /$alias_name parent resolves physically" test "$alias_out" = /private
    fi
done
# Execute the exported API from the mirror too, not merely compare its bytes.
LIB="$MIRROR"
ctx_run "$P" "$S/scripts" "$P" "$S"
ctx_good 'mirror API bound project'
ctx_run "$TMP_DIR" "$S/scripts"
ctx_bad 'mirror API wrong cwd'
ctx_run "$P" "$TMP_DIR/no manifest/.config/opencode/skills/handoffx/scripts"
ctx_bad 'mirror API missing OpenCode global manifest'
ctx_run "$same_home" "$same/scripts"
ctx_bad 'mirror API cross-host shadow'
ctx_run "$child" "$ancestor_global/scripts"
ctx_bad 'mirror API ancestor project shadow'
ctx_run "$multihome/projects/non git/deep" "$multihome/.agents/skills/handoffx/scripts"
ctx_good 'mirror API multiple home globals'
ctx_run "$own_link_home/project/nested" "$own_skill/scripts"
ctx_good 'mirror API own-host-link'
ln -s "$other_base/skills/handoffx" "$own_link_home/$other_hd/skills/handoffx"
ctx_run "$own_link_home/project/nested" "$own_skill/scripts"
ctx_good 'mirror API other-target-link valid global peer'
summary
