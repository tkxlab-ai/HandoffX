#!/bin/bash
# release-layout.sh — P2.2b release layout, single source of truth. Sourced, not
# executed. Dev-only (DEV_ONLY in tests/test_scripts_sync.sh): end users never
# cut releases, so it stays out of the .skill bundle.
# Why one lib: release.sh, the GitHub publishers and the contract test must agree
# on which versions keep the old `handoff-` prefix (everything already published,
# < RENAME_FROM) and which use `handoffx-` — re-deriving that rule in each caller
# is exactly how a published asset name silently drifts.

# idempotent source guard
[ -n "${_RL_LAYOUT_SOURCED:-}" ] && return 0
_RL_LAYOUT_SOURCED=1

# release_ver_ge <vA> <vB> → 0 A>=B / 1 A<B / 2 either operand not vX.Y.Z.
# Numeric per segment: a string compare would rank v2.10.0 below v2.9.0.
# Split by parameter expansion, not `read <<<`: bash 3.2 backs a here-string with a
# temp file, and if that cannot be created the empty fields fell through to "A>=B".
release_ver_ge() {
    local a="$1" b="$2" a1 a2 a3 b1 b2 b3 x
    local re='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    [[ "$a" =~ $re ]] || return 2
    [[ "$b" =~ $re ]] || return 2
    a="${a#v}"; a1="${a%%.*}"; a="${a#*.}"; a2="${a%%.*}"; a3="${a#*.}"
    b="${b#v}"; b1="${b%%.*}"; b="${b#*.}"; b2="${b%%.*}"; b3="${b#*.}"
    for x in "$a1" "$a2" "$a3" "$b1" "$b2" "$b3"; do
        case "$x" in ''|*[!0-9]*) return 2 ;; esac
    done
    if [ "$a1" -gt "$b1" ]; then return 0; elif [ "$a1" -lt "$b1" ]; then return 1; fi
    if [ "$a2" -gt "$b2" ]; then return 0; elif [ "$a2" -lt "$b2" ]; then return 1; fi
    if [ "$a3" -lt "$b3" ]; then return 1; fi
    return 0
}

# release_prefix <ver> → stdout handoff | handoffx; invalid <ver> or invalid
# RENAME_FROM → no output, return 2 (never silently "older").
release_prefix() {
    local rc
    # `if` form, not `cmd; rc=$?`: under a set -e caller (release.sh) the bare
    # call's return 1 — every legit pre-v3.0.0 version — would abort silently (Gotcha #6)
    if release_ver_ge "$1" "${RENAME_FROM:-v3.0.0}"; then rc=0; else rc=$?; fi
    case "$rc" in
        0) echo "handoffx" ;;
        1) echo "handoff" ;;
        *) return 2 ;;
    esac
}

# release_dir_for <ver> → Release/<prefix>-<ver>
release_dir_for() {
    local p
    p=$(release_prefix "$1") || return 2
    echo "Release/${p}-$1"
}

# release_asset <ver> skill|source|full → asset basename; unknown kind → return 2
release_asset() {
    local p
    p=$(release_prefix "$1") || return 2
    case "$2" in
        skill)  echo "${p}-$1.skill" ;;
        source) echo "${p}-$1-source.tar.gz" ;;
        full)   echo "${p}-$1-full.tar.gz" ;;
        *)      return 2 ;;
    esac
}

# verify_release_integrity <dir> <ver> → 0 ok / 1 broken. Ported from the
# publisher preflight: a 0-byte / bad zip / truncated tar / non-CycloneDX SBOM /
# stale checksums must abort before anything is pushed (supply-chain regression).
verify_release_integrity() {
    local rd="$1" v="$2" rc=0 a skill src
    [[ -d "$rd" ]] || { echo "❌ missing dir: $rd"; return 1; }
    skill=$(release_asset "$v" skill) || { echo "❌ invalid version: $v"; return 1; }
    src=$(release_asset "$v" source) || { echo "❌ invalid version: $v"; return 1; }
    for a in "$skill" "$src" "checksums.txt" "sbom.cyclonedx.json" "RELEASE_NOTES.md"; do
        if [[ ! -s "$rd/$a" ]]; then
            echo "❌ missing or empty: $rd/$a"; rc=1
        fi
    done
    [[ "$rc" -eq 0 ]] || return 1
    unzip -t "$rd/$skill" >/dev/null 2>&1 \
        || { echo "❌ corrupt .skill (unzip -t failed): $rd/$skill"; rc=1; }
    # a valid zip with the wrong root unpacks to ~/.claude/skills/<other>/ — installed
    # nowhere the loader looks; the root is the prefix in both eras
    local pfx root
    pfx=$(release_prefix "$v") || { echo "❌ invalid version: $v"; return 1; }
    root=$(unzip -l "$rd/$skill" 2>/dev/null | awk 'NR==4{print $NF}')
    case "$root" in
        "$pfx"/*) ;;
        *) echo "❌ .skill root is not ${pfx}/ (got: ${root:-none}): $rd/$skill"; rc=1 ;;
    esac
    tar tzf "$rd/$src" >/dev/null 2>&1 \
        || { echo "❌ corrupt source tarball: $rd/$src"; rc=1; }
    # A substring grep accepts a truncated SBOM: parse it when python3 exists, else a
    # structural fallback (closes with `}`, has bomFormat=CycloneDX and components)
    # so the lib still runs on a bare macOS/Linux toolchain.
    local sbom="$rd/sbom.cyclonedx.json" sbok=1 last
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("bomFormat")=="CycloneDX" else 1)' "$sbom" >/dev/null 2>&1; then
            sbok=0
        fi
    else
        last=$(tr -d '[:space:]' < "$sbom" | tail -c 1)
        if [ "$last" = "}" ] \
           && grep -q '"bomFormat"[[:space:]]*:[[:space:]]*"CycloneDX"' "$sbom" \
           && grep -q '"components"' "$sbom"; then
            sbok=0
        fi
    fi
    [ "$sbok" -eq 0 ] || { echo "❌ invalid SBOM (not complete CycloneDX JSON): $sbom"; rc=1; }
    # 覆盖：-c 只验"列出的行"，不验"该列的都列了"——换掉一个未列出的资产照样全 OK
    local cov=0 n ck ckrc nok
    for a in "$skill" "$src" "sbom.cyclonedx.json"; do
        n=$(awk -v n="$a" '$0 == $1 "  " n && length($1) == 64 && $1 ~ /^[0-9a-fA-F]+$/ {c++} END {print c+0}' "$rd/checksums.txt")
        if [ "$n" != "1" ]; then
            echo "❌ checksums.txt 未覆盖 ${a}（需恰好一行 <sha256>  ${a}，实际 ${n}）: $rd"; cov=1
        fi
    done
    [ "$cov" -eq 0 ] || rc=1
    # if/else, never `a && b || c`: a failing sha256sum must not fall through to shasum
    if ck=$( cd "$rd" || exit 1
         if command -v sha256sum >/dev/null 2>&1; then
             sha256sum -c checksums.txt 2>&1
         else
             shasum -a 256 -c checksums.txt 2>&1
         fi ); then
        ckrc=0
    else
        ckrc=$?
    fi
    # macOS /sbin/sha256sum -c exits 0 on zero well-formed lines: the exit code alone proves nothing
    nok=$(printf '%s\n' "$ck" | grep -c ': OK$') || nok=0
    if [ "$ckrc" -ne 0 ] || [ "$nok" -lt 3 ] || printf '%s\n' "$ck" | grep -q 'FAILED'; then
        echo "❌ checksums.txt 校验失败（资产被改/截断/陈旧，或有效行 ${nok} < 3）: $rd"; rc=1
    fi
    return "$rc"
}
