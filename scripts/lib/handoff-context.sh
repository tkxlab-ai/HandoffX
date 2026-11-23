#!/bin/bash
# Bash 3.2, source-only, read-only location contract. No git identity or
# authorization is authenticated: the manifest itself is not a trust anchor.
# hx_context_check SCRIPT_DIR [EXPECTED_ROOT] [EXPECTED_SKILL_ROOT]
# Empty optional arguments mean unspecified (allows a third-argument-only check).
# stdout is a key=value record on success only; diagnostics go to stderr.

_hx_context_error() {
    printf 'handoffx context: %s\n' "$1" >&2
    return 1
}

_hx_context_clean_path() {
    case "$1" in
        *$'\n'*|*$'\r'*|*$'\t'*)
            _hx_context_error 'path contains newline, CR or Tab'; return 1 ;;
    esac
}

_hx_context_pwd() {
    local result
    # The sentinel preserves trailing newlines in directory names for rejection.
    result=$(builtin pwd -P && printf '.') || {
        _hx_context_error 'cannot determine physical cwd'; return 1;
    }
    result=${result%.}
    result=${result%$'\n'}
    _hx_context_clean_path "$result" || return 1
    printf '%s\n' "$result"
}

_hx_context_dir() (
    local path="$1" rest part prefix='' target result
    _hx_context_clean_path "$path" || return 1
    [ -n "$path" ] || { _hx_context_error 'empty directory path'; return 1; }
    case "$path" in
        /*) ;;
        *) result=$(_hx_context_pwd) || return 1; path="${result%/}/$path" ;;
    esac
    # A leading "//" survives `cd -P` and `pwd -P` in bash (POSIX leaves it
    # implementation-defined), so a project at "/" resolved to "//" and never
    # matched its expected root "/". Collapse leading slashes to one.
    while :; do case "$path" in //*) path=${path#/} ;; *) break ;; esac; done
    # Inspect every component BEFORE resolving it, including components before
    # '..'. A trailing slash or '/.' must not hide a root-directory symlink.
    rest=${path#/}
    while [ -n "$rest" ]; do
        part=${rest%%/*}
        case "$rest" in */*) rest=${rest#*/} ;; *) rest='' ;; esac
        [ -n "$part" ] || continue
        prefix="$prefix/$part"
        if [ -L "$prefix" ]; then
            target=$(readlink "$prefix") || return 1
            # Only the standard macOS system aliases are exempt. User-created
            # aliases elsewhere, including aliases of the project root, fail.
            case "$prefix:$target" in
                /var:private/var|/var:/private/var|/tmp:private/tmp|/tmp:/private/tmp|/etc:private/etc|/etc:/private/etc)
                    prefix="/private/${prefix#/}" ;;
                *) _hx_context_error 'directory path contains a symlink'; return 1 ;;
            esac
        fi
        [ -d "$prefix" ] || { _hx_context_error 'directory does not exist'; return 1; }
        # Normalize only after inspecting the component. This also makes the
        # alias exemption work with repeated slashes and leading /./ segments.
        case "$part" in
            .) prefix=${prefix%/.} ;;
            ..) prefix=${prefix%/..}; prefix=${prefix%/*} ;;
        esac
    done
    # cd is isolated in this subshell, solely for canonicalization. The caller's
    # cwd is never changed, and no project binding is repaired by changing cwd.
    builtin cd -P -- "$path" 2>/dev/null || {
        _hx_context_error 'cannot resolve directory'; return 1;
    }
    _hx_context_pwd
)

# Private strict reader. These five output variables are dynamically scoped
# Bash locals declared by BOTH callers below; no shell text is evaluated and
# nothing is printed on success. Reuse exactly the same grammar for ancestors.
_hx_context_read_binding() {
    local manifest="$1" skill_root="$2" physical
    local raw line key value seen='|' count=0
    schema='' scope='' project_root='' recorded_skill='' host=''
    if [ -L "$manifest" ] || [ ! -f "$manifest" ] || [ ! -r "$manifest" ]; then
        _hx_context_error 'manifest must be a readable non-symlink regular file'
        return 1
    fi
    # Bound both the read and allocation (16 KiB). Map NUL to forbidden CR
    # BEFORE Bash can silently discard NUL bytes. Never source/eval the record.
    raw=$(head -c 16385 "$manifest" | tr '\000' '\r' && printf '.') || {
        _hx_context_error 'cannot read manifest'; return 1;
    }
    raw=${raw%.}
    if [ "${#raw}" -gt 16384 ]; then
        _hx_context_error 'manifest exceeds 16384 bytes'; return 1
    fi
    case "$raw" in
        *$'\r'*|*$'\t'*) _hx_context_error 'manifest contains forbidden control bytes'; return 1 ;;
    esac
    # Stream the original bytes: Bash 3.2 here-strings/here-documents create
    # temporary files and fail in read-only sandboxes. Keep the terminating LF;
    # read's fallback handles no final LF, while extra blank lines still fail.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *=*) key=${line%%=*}; value=${line#*=} ;;
            *) _hx_context_error 'malformed manifest field'; return 1 ;;
        esac
        case "$key" in
            schema|scope|project_root|skill_root|host) ;;
            *) _hx_context_error 'unknown manifest field'; return 1 ;;
        esac
        case "$seen" in
            *"|$key|"*) _hx_context_error 'duplicate manifest field'; return 1 ;;
        esac
        seen="$seen$key|"
        count=$((count + 1))
        case "$key" in
            schema) schema=$value ;;
            scope) scope=$value ;;
            project_root) project_root=$value ;;
            skill_root) recorded_skill=$value ;;
            host) host=$value ;;
        esac
    done < <(printf '%s' "$raw")
    [ "$count" -eq 5 ] || { _hx_context_error 'missing manifest field'; return 1; }
    [ "$schema" = 1 ] || { _hx_context_error 'unsupported manifest schema'; return 1; }
    case "$scope" in project|global) ;; *) _hx_context_error 'invalid manifest scope'; return 1 ;; esac
    case "$host" in
        claude|codex|opencode) ;;
        *) _hx_context_error 'invalid manifest host'; return 1 ;;
    esac
    case "$recorded_skill" in
        /*) ;;
        *) _hx_context_error 'manifest skill_root must be physical and absolute'; return 1 ;;
    esac
    physical=$(_hx_context_dir "$recorded_skill") || return 1
    if [ "$physical" != "$recorded_skill" ] || [ "$skill_root" != "$recorded_skill" ]; then
        _hx_context_error 'manifest skill_root mismatch (moved installation? reinstall)'
        return 1
    fi
    if [ "$scope" = project ]; then
        case "$project_root" in
            /*) ;;
            *) _hx_context_error 'project_root must be physical and absolute'; return 1 ;;
        esac
        physical=$(_hx_context_dir "$project_root") || return 1
        [ "$physical" = "$project_root" ] || {
            _hx_context_error 'manifest project_root must be physical'; return 1;
        }
    else
        [ -z "$project_root" ] || {
            _hx_context_error 'global manifest project_root must be empty'; return 1;
        }
    fi
}

# Except for the narrow legacy HOME-base rule below, a peer needs a valid
# global binding to its physical directory, not merely a scope=global line.
_hx_context_global_candidate() (
    local candidate="$1" ancestor="$2" home="$3" physical manifest
    local schema='' scope='' project_root='' recorded_skill='' host=''
    # A host base may be a dotfiles symlink (~/.claude -> ~/dotfiles/claude);
    # resolve physically, then still require a valid GLOBAL binding below.
    physical=$(CDPATH='' builtin cd -P -- "$candidate" 2>/dev/null && _hx_context_pwd) || {
        _hx_context_error "cannot resolve peer skill directory: $candidate"; return 1;
    }
    manifest="$physical/.handoffx-install-context"
    # Legacy global installs at the physical HOME's standard Claude/Codex bases
    # are not evidence of a parent project. This narrowly classifies a PEER;
    # executing that legacy install still fails the main missing-manifest gate.
    # Never ignore an existing (even invalid) manifest or a project declaration.
    if [ -n "$home" ] && [ "$ancestor" = "$home" ] && [ "$physical" = "$candidate" ] \
        && [ ! -e "$manifest" ] && [ ! -L "$manifest" ]; then
        case "$candidate" in
            "$home/.claude/skills/handoffx"|"$home/.agents/skills/handoffx") return 0 ;;
        esac
    fi
    _hx_context_read_binding "$manifest" "$physical" || return 1
    [ "$scope" = global ] || {
        _hx_context_error 'ancestor project-local skill shadows global installation; use the bound project root'
        return 1;
    }
)

hx_context_check() (
    # Keep shell options, locale, variables and cwd private to this invocation.
    set -o pipefail
    local LC_ALL=C
    export LC_ALL
    local script_dir skill_root cwd expected_root expected_skill manifest
    local schema='' scope='' project_root='' recorded_skill='' host='' physical
    local host_dir shadow ancestor home
    if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
        _hx_context_error 'usage: hx_context_check SCRIPT_DIR [EXPECTED_ROOT] [EXPECTED_SKILL_ROOT]'
        return 1
    fi
    cwd=$(_hx_context_pwd) || return 1
    # Check cwd's physical path too; the logical $PWD spelling is not authority.
    physical=$(_hx_context_dir "$cwd") || return 1
    script_dir=$(_hx_context_dir "$1") || return 1
    case "$script_dir" in
        */scripts) ;;
        *) _hx_context_error 'SCRIPT_DIR must be the actual scripts directory'; return 1 ;;
    esac
    [ -d "$script_dir/lib" ] || {
        _hx_context_error 'scripts/lib is missing'; return 1;
    }
    skill_root=$(_hx_context_dir "$script_dir/..") || return 1
    if [ -n "${2:-}" ]; then
        expected_root=$(_hx_context_dir "$2") || return 1
        [ "$cwd" = "$expected_root" ] || {
            _hx_context_error 'cwd does not match EXPECTED_ROOT'; return 1;
        }
    fi
    if [ -n "${3:-}" ]; then
        expected_skill=$(_hx_context_dir "$3") || return 1
        [ "$skill_root" = "$expected_skill" ] || {
            _hx_context_error 'current skill root does not match EXPECTED_SKILL_ROOT'; return 1;
        }
    fi
    manifest="$skill_root/.handoffx-install-context"
    if [ ! -e "$manifest" ] && [ ! -L "$manifest" ]; then
        case "$skill_root" in
            # OpenCode global uses <XDG_CONFIG_HOME>/opencode, normally
            # ~/.config/opencode; match the suffix without trusting env vars.
            # .codex/skills is the pre-.agents Codex location (Gotcha #7).
            */.claude/skills/handoffx|*/.agents/skills/handoffx|*/.codex/skills/handoffx|*/.opencode/skills/handoffx|*/opencode/skills/handoffx)
                # Typical cause: the release notes' "skill only" option (unzip the
                # .skill) — it writes no binding. Name the recovery, not just "reinstall".
                _hx_context_error "installed skill has no context manifest; reinstall (请重新安装): run the same release's install.sh next to the .skill (unzipping the .skill alone writes no binding)"
                return 1 ;;
        esac
        # Any copied source layout has unknown identity, not project authority.
        printf 'scope=source_unbound\nproject_root=\nskill_root=%s\ncontext_contract=1\nproject_binding=unverified\n' "$skill_root"
        return 0
    fi
    _hx_context_read_binding "$manifest" "$skill_root" || return 1
    if [ "$scope" = project ]; then
        [ "$cwd" = "$project_root" ] || {
            _hx_context_error 'cwd does not match manifest project_root'; return 1;
        }
    else
        # No git boundary: a project installation also owns nested/non-git cwd.
        # host is only the FIRST installation owner, so inspect every local-host
        # layout at every physical ancestor through /. A legitimate global peer
        # is not a local shadow, and finding one never ends the ancestor scan.
        home=''
        if [ -n "${HOME:-}" ]; then
            home=$(_hx_context_dir "$HOME" 2>/dev/null) || home=''
        fi
        ancestor="$cwd"
        while :; do
            for host_dir in .claude .agents .opencode; do
                shadow="${ancestor%/}/$host_dir/skills/handoffx"
                if [ -e "$shadow" ] || [ -L "$shadow" ]; then
                    # Main binding is already validated. Host-base symlinks
                    # may point back to self; only that physical equality is
                    # exempt. _hx_context_pwd preserves control-byte rejection.
                    if physical=$(CDPATH='' builtin cd -P -- "$shadow" 2>/dev/null && _hx_context_pwd); then
                        [ "$physical" != "$skill_root" ] || continue
                    fi
                    _hx_context_global_candidate "$shadow" "$ancestor" "$home" || return 1
                fi
            done
            [ "$ancestor" != / ] || break
            ancestor=${ancestor%/*}
            [ -n "$ancestor" ] || ancestor=/
        done
    fi
    printf 'scope=%s\nproject_root=%s\nskill_root=%s\ncontext_contract=1\n' "$scope" "$project_root" "$skill_root"
)

# Per-operation intent, not a remembered authorization from a prior context call.
# Installed globals have no project_root in their manifest, so a write must carry
# its own explicit expected root. Project installs remain bound without a flag;
# source helpers remain visibly unbound for explicit library/development use.
hx_context_write_check() {
    local context expected="${2:-}"
    if [ -n "$expected" ]; then
        case "$expected" in /*) ;; *) _hx_context_error '--expect-root must be absolute'; return 1 ;; esac
    fi
    hx_context_check_memo "$1" "$expected" || return 1
    context=$HX_CTX_MEMO
    hx_context_write_policy "$context" "$expected"
}

# hx_context_check_memo SCRIPT_DIR [EXPECTED_ROOT]: hx_context_check cached
# per (physical cwd, script dir, expected root) in THIS shell (call it
# directly, not inside $(...), to keep the cache). Never shared across
# processes: a child re-checks its own context.
HX_CTX_MEMO='' HX_CTX_MEMO_KEY=''
hx_context_check_memo() {
    local cwd key
    # Exact physical cwd (sentinel-preserving, control bytes rejected); a
    # plain $(pwd -P) would strip trailing newlines and alias two directories.
    cwd=$(_hx_context_pwd 2>/dev/null) || cwd=''
    key="$cwd|$1|${2:-}"
    if [ -n "$cwd" ] && [ "$key" = "$HX_CTX_MEMO_KEY" ]; then return 0; fi
    HX_CTX_MEMO=$(hx_context_check "$1" "${2:-}") || return 1
    HX_CTX_MEMO_KEY=$key
}

# hx_context_write_policy CONTEXT_RECORD [EXPECTED_ROOT]: decide on an already
# checked context. A distributed skill copy (SKILL.md at its root) without a
# manifest has unknown identity; like a global install it must name its write
# target. Repository source scripts (no SKILL.md) keep library/test use.
hx_context_write_policy() {
    local context="$1" expected="${2:-}" skill
    [ -z "$expected" ] || return 0
    case "$context" in
        scope=global$'\n'*)
            _hx_context_error 'global writes require --expect-root ABSOLUTE_PROJECT_ROOT before the command'
            return 1 ;;
        scope=source_unbound$'\n'*)
            skill=$(printf '%s\n' "$context" | sed -n 's/^skill_root=//p')
            if [ -f "$skill/SKILL.md" ]; then
                _hx_context_error 'unbound skill copy writes require --expect-root ABSOLUTE_PROJECT_ROOT (or reinstall with install.sh)'
                return 1
            fi ;;
    esac
}

# Shared leading --expect-root parser for every write-capable entry point.
# hx_context_take_expect_root MESSAGE_PREFIX ARGS... sets HX_TAKEN_ROOT and
# HX_TAKEN_SHIFT (0 or 2); returns 2 on a missing/relative root.
# shellcheck disable=SC2034  # results are read by the sourcing entry script
hx_context_take_expect_root() {
    local prefix="$1"; shift
    HX_TAKEN_ROOT='' HX_TAKEN_SHIFT=0
    [ "${1:-}" = --expect-root ] || return 0
    [ "$#" -ge 2 ] && [ -n "$2" ] || { printf '%s--expect-root requires an absolute root\n' "$prefix" >&2; return 2; }
    case "$2" in /*) ;; *) printf '%s--expect-root must be absolute\n' "$prefix" >&2; return 2 ;; esac
    HX_TAKEN_ROOT=$2 HX_TAKEN_SHIFT=2
}
