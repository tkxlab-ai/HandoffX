#!/bin/bash
# test_legacy_names_guard.sh — permanent guard: no pre-v4 name in any tracked
# text file outside the audited allowlist (tests/fixtures/legacy-names-allow.txt).
# Why permanent (it replaces the one-shot P2.2 rename manifest): the old
# registered names (the pre-v4 slash commands, skill dir and $-alias — built
# below from split literals) and the old four-piece names were swept once by
# hand; nothing stopped a later edit from
# reintroducing them, and a stale name in a doc or shim sends users to a
# command or file that v4 no longer has.
# Why fail closed on every read error: a file the guard cannot enumerate or read
# would otherwise count as "no hits" (GOTCHAS #334-338 — rc 2 ≠ rc 1).
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
ALLOW="$FIXTURES_DIR/legacy-names-allow.txt"

# Two pattern classes, matched separately so an allowlist row can exempt one
# without the other (a doc that must say the legacy main's name for upgrade
# routing has no business naming an old slash command):
#   registered  old registered names (not schema constants). The stem is split
#               (_h) so this file holds none of them literally and needs no
#               allowlist row of its own — a row would exempt the guard's own
#               prose from the very scan it runs.
#   fourpiece   the legacy four-piece names, derived from the schema lib.
_lng_ere() { printf '%s' "$1" | sed 's/\./\\./g'; }
_h=hand; _h="${_h}off"
REG_RE='(^|[^A-Za-z0-9_./-])/'"$_h"'(-recall|-tidy|-memory|-init)?([^A-Za-z0-9_-]|$)'
REG_RE="$REG_RE|skills/$_h/|$_h-(recall|tidy|memory|init|write)\\.md|\\\$$_h\\b|^name: $_h\$"
REG_RE="$REG_RE|\\.(claude|agents|codex)/skills/$_h\\b|opencode/skills/$_h\\b"
FP_RE="\\b$(_lng_ere "$HX_LEGACY_MAIN_FILE")\\b|\\b$HX_LEGACY_LOGS_DIR\\b|\\b$HX_LEGACY_DEC_DIR\\b"

# legacy_names_guard <root> <allowlist> — print diagnostics and exactly one
# verdict line; return 0 iff zero violations and zero errors.
# Why a function with a root argument: the negative controls below run the same
# code against scratch copies, so a mutation of the verdict is observable.
legacy_names_guard() {
    local root="$1" allow="$2" line n=0 rows=0 rules="" g c r t rest cl ok
    local err=0 viol=0 scanned=0 allowed=0 shown=0 lst f rc hits h xr xf re
    if [ ! -f "$allow" ] || [ ! -r "$allow" ]; then
        echo "  ❌ allowlist missing or unreadable: $allow"
        echo "❌ legacy-names guard: allowlist unusable (0 files scanned, 0 allowlisted)"
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        case "$line" in ''|'#'*) continue ;; esac
        t="${line//[!	]/}"
        g="${line%%	*}"; rest="${line#*	}"; c="${rest%%	*}"; r="${rest#*	}"
        if [ "${#t}" -ne 2 ] || [ -z "$g" ] || [ -z "${r//[[:space:]]/}" ]; then
            echo "  ❌ allowlist line $n malformed (need glob<TAB>classes<TAB>non-empty reason): $line"
            err=$((err + 1)); continue
        fi
        # classes: comma-separated subset of fourpiece / registered / all.
        # Anything else is an error, never "no exemption" — a typo here must
        # not quietly widen or narrow what the row means.
        ok=1
        case ",$c," in *,,*) ok=0 ;; esac
        for cl in ${c//,/ }; do
            case "$cl" in fourpiece|registered|all) ;; *) ok=0 ;; esac
        done
        if [ -z "$c" ] || [ "$ok" -eq 0 ]; then
            echo "  ❌ allowlist line $n has unknown classes '$c' (allowed: fourpiece, registered, all): $line"
            err=$((err + 1)); continue
        fi
        rows=$((rows + 1))
        rules="$rules$g	$c
"
    done < "$allow"
    if [ "$rows" -eq 0 ] && [ "$err" -eq 0 ]; then
        echo "  ❌ allowlist has no rows: $allow"
        err=$((err + 1))
    fi
    if [ "$err" -gt 0 ]; then
        echo "❌ legacy-names guard: allowlist unusable, $err error(s) (0 files scanned, 0 allowlisted)"
        return 1
    fi

    lst=$(mktemp "${TMPDIR:-/tmp}/lng.XXXXXX") || { echo "❌ legacy-names guard: mktemp failed"; return 1; }
    if ! git -C "$root" ls-files -z > "$lst" 2>/dev/null; then
        rm -f "$lst"
        echo "  ❌ git ls-files failed in $root"
        echo "❌ legacy-names guard: cannot enumerate tracked files (0 files scanned, 0 allowlisted)"
        return 1
    fi
    while IFS= read -r -d '' f; do
        [ -L "$root/$f" ] && continue
        if [ ! -e "$root/$f" ]; then
            echo "  ❌ tracked file missing: $f"; err=$((err + 1)); continue
        elif [ ! -f "$root/$f" ]; then
            echo "  ❌ tracked path is not a regular file: $f"; err=$((err + 1)); continue
        elif [ ! -r "$root/$f" ]; then
            echo "  ❌ tracked file unreadable: $f"; err=$((err + 1)); continue
        fi
        # Union of the classes every matching row exempts for this file.
        xr=0; xf=0
        while IFS='	' read -r g c; do
            [ -n "$g" ] || continue
            # shellcheck disable=SC2254  # unquoted on purpose: $g is a glob
            case "$f" in $g)
                case ",$c," in *,all,*) xr=1; xf=1 ;; esac
                case ",$c," in *,registered,*) xr=1 ;; esac
                case ",$c," in *,fourpiece,*) xf=1 ;; esac ;;
            esac
        done <<EOF
$rules
EOF
        if [ "$xr" -eq 1 ] && [ "$xf" -eq 1 ]; then allowed=$((allowed + 1)); continue; fi
        if [ "$xr" -eq 1 ]; then re="$FP_RE"; elif [ "$xf" -eq 1 ]; then re="$REG_RE"; else re="$REG_RE|$FP_RE"; fi
        # LC_ALL=C like the scan: in a UTF-8 locale GNU grep may call a file
        # with invalid UTF-8 "binary", and the guard would skip it unread (C3).
        rc=0; LC_ALL=C grep -Il '' -- "$root/$f" >/dev/null 2>&1 || rc=$?
        if [ "$rc" -eq 1 ]; then continue; fi          # binary or empty: nothing to read
        if [ "$rc" -ne 0 ]; then
            echo "  ❌ text probe failed (grep rc $rc): $f"; err=$((err + 1)); continue
        fi
        scanned=$((scanned + 1))
        rc=0; hits=$(LC_ALL=C grep -nE -- "$re" "$root/$f" 2>/dev/null) || rc=$?
        if [ "$rc" -eq 1 ]; then continue; fi
        if [ "$rc" -ne 0 ]; then
            echo "  ❌ scan failed (grep rc $rc): $f"; err=$((err + 1)); continue
        fi
        while IFS= read -r h; do
            viol=$((viol + 1))
            # Cap the listing, not the count: the pre-migration tree has
            # thousands of hits and the verdict already carries the total.
            if [ "$shown" -lt 50 ]; then
                echo "  ❌ $f:$(printf '%s' "$h" | LC_ALL=C cut -c1-200)"; shown=$((shown + 1))
            fi
        done <<EOF
$hits
EOF
    done < "$lst"
    rm -f "$lst"
    [ "$viol" -gt "$shown" ] && echo "  … $((viol - shown)) more violation(s) not listed"
    if [ "$scanned" -eq 0 ]; then
        echo "  ❌ 0 tracked text files scanned — nothing was checked"
        err=$((err + 1))
    fi
    if [ "$viol" -eq 0 ] && [ "$err" -eq 0 ]; then
        echo "✅ legacy-names guard: 0 violations ($scanned files scanned, $allowed allowlisted)"
        return 0
    fi
    echo "❌ legacy-names guard: $viol violation(s), $err error(s) ($scanned files scanned, $allowed allowlisted)"
    return 1
}

# Distribution contract: the source tarball has no .git, so there is nothing to
# enumerate — say so explicitly instead of passing on an empty file list. Only
# a structural absence skips; a git that fails in a real checkout is ❌ (C1).
case "$(hx_git_worktree_state "$ROOT_DIR")" in
    none)
        echo "  ➖ SKIPPED（不是 git 工作树）: legacy-names guard 需要 git ls-files"
        summary
        exit 0 ;;
    error)
        echo "  ❌ cannot tell whether $ROOT_DIR is a git checkout (git failed, see above) — refusing to skip the guard"
        FAIL=$((FAIL + 1))
        summary
        exit 1 ;;
esac

PASS_V="✅ legacy-names guard: 0 violations"
rc=0; out=$(legacy_names_guard "$ROOT_DIR" "$ALLOW") || rc=$?
printf '%s\n' "$out" | sed 's/^[^ ]/  &/'
assert_contains "tracked tree: verdict is 0 violations" "$out" "$PASS_V"
assert_exit "tracked tree: guard exit 0" 0 "$rc"

# ── Controls: same function, scratch clone of HEAD on the v4 layout ──
# Why migrate the clone: until the live repo migrates, HEAD is the legacy layout
# and could never give the clean baseline every control below is measured from.
# The clone's own migrator is used, so this is the committed candidate's code.
W=$(mktemp -d); C="$W/c"
trap 'chmod -R u+rwX "$W" 2>/dev/null; rm -rf "$W"' EXIT
# --no-hardlinks, not --local: an explicit --local makes git 2.34 fail outright
# ("Invalid cross-device link") when the scratch dir sits on another filesystem
# than the repo — the Linux container bind-mounts the tree and mktemp lands on
# the container disk, so the clone vanished and every control below went red.
git clone -q --no-hardlinks "$ROOT_DIR" "$C" >/dev/null 2>&1
if [ "$(hx_legacy_layout_kind "$C")" != none ]; then
    bash "$C/scripts/tidy-handoff.sh" schema-upgrade --apply --root "$C" >/dev/null 2>&1
    git -C "$C" add -A >/dev/null 2>&1
fi
assert_exit "controls: scratch clone is a v4 layout with $HX_MAIN_FILE" 0 \
    "$([ -f "$C/$HX_MAIN_FILE" ] && [ "$(hx_legacy_layout_kind "$C")" = none ] && echo 0 || echo 1)"
# c0 also proves the glob choice: tests/fixtures/* must span nested dirs, or the
# synthetic v2 fixture (tests/fixtures/p2-1-synthetic-v2/…, legacy content under
# neutral file names) would be a hit here.
o=$(legacy_names_guard "$C" "$ALLOW"); rc=$?
assert_contains "c0 baseline: clean clone → 0 violations" "$o" "$PASS_V"
assert_exit "c0 baseline: exit 0" 0 "$rc"
cp "$C/README.md" "$W/README.keep"

# (a) a legacy four-piece name planted in README → named and verdict red
printf '\nsee %s/ for the history\n' "$HX_LEGACY_LOGS_DIR" >> "$C/README.md"
o=$(legacy_names_guard "$C" "$ALLOW"); rc=$?
assert_contains "(a) planted $HX_LEGACY_LOGS_DIR/ → README.md:line named" "$o" "❌ README.md:"
assert_not_contains "(a) planted → verdict not 0 violations" "$o" "$PASS_V"
assert_exit "(a) planted → exit 1" 1 "$rc"
cp "$W/README.keep" "$C/README.md"
# (a2) an old registered command name → red too
printf '\nrun /%s-tidy first\n' "$_h" >> "$C/README.md"
o=$(legacy_names_guard "$C" "$ALLOW")
assert_not_contains "(a2) planted old tidy slash command → verdict not 0 violations" "$o" "$PASS_V"
cp "$W/README.keep" "$C/README.md"
# (b) script basenames that merely start with handoff- are not old names
printf '\nsee scripts/handoff-lint.sh and lib/handoff-v2.sh\n' >> "$C/README.md"
o=$(legacy_names_guard "$C" "$ALLOW")
assert_contains "(b) handoff-lint.sh / lib/handoff-v2.sh → still 0 violations" "$o" "$PASS_V"
cp "$W/README.keep" "$C/README.md"

# (c) unreadable / missing tracked file → named, verdict red (never "no hits")
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ (c) unreadable tracked file SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$C/VERSION"
    o=$(legacy_names_guard "$C" "$ALLOW")
    chmod 644 "$C/VERSION"
    assert_contains "(c) chmod 000 VERSION → named as unreadable" "$o" "tracked file unreadable: VERSION"
    assert_not_contains "(c) unreadable → verdict not 0 violations" "$o" "$PASS_V"
fi
mv "$C/VERSION" "$W/VERSION.keep"
o=$(legacy_names_guard "$C" "$ALLOW")
mv "$W/VERSION.keep" "$C/VERSION"
assert_contains "(c2) tracked file missing from the work tree → named" "$o" "tracked file missing: VERSION"
assert_not_contains "(c2) missing → verdict not 0 violations" "$o" "$PASS_V"

# (d) allowlist must be present, non-empty and well-formed
printf '# only a comment\n\n' > "$W/allow-empty"
o=$(legacy_names_guard "$C" "$W/allow-empty"); rc=$?
assert_contains "(d) empty allowlist → refused" "$o" "allowlist has no rows"
assert_exit "(d) empty allowlist → exit 1" 1 "$rc"
printf 'docs/*\tall\thistory\nREADME.md no tab here\n' > "$W/allow-bad"
o=$(legacy_names_guard "$C" "$W/allow-bad")
assert_contains "(d) row without a tab → line 2 named" "$o" "allowlist line 2 malformed"
printf 'docs/*\tall\t \n' > "$W/allow-noreason"
o=$(legacy_names_guard "$C" "$W/allow-noreason")
assert_contains "(d) row with a blank reason → refused" "$o" "allowlist line 1 malformed"
# C2: the old two-column form is malformed now (a row without classes would
# otherwise read as "exempt everything", the very fail-open being removed)
printf 'docs/*\thistory\n' > "$W/allow-2col"
o=$(legacy_names_guard "$C" "$W/allow-2col"); rc=$?
assert_contains "(d) two-column row → malformed" "$o" "allowlist line 1 malformed"
assert_exit "(d) two-column row → exit 1" 1 "$rc"
for bad in fourpeice 'fourpiece,' ',all' 'all,,registered' ''; do
    printf 'docs/*\t%s\treason\n' "$bad" > "$W/allow-cls"
    o=$(legacy_names_guard "$C" "$W/allow-cls"); rc=$?
    assert_contains "(d) classes '$bad' → refused as unknown classes" "$o" "allowlist line 1 has unknown classes"
    assert_not_contains "(d) classes '$bad' → verdict not 0 violations" "$o" "$PASS_V"
done
o=$(legacy_names_guard "$C" "$W/no-such-allowlist")
assert_contains "(d) missing allowlist → refused" "$o" "allowlist missing or unreadable"
assert_not_contains "(d) missing allowlist → verdict not 0 violations" "$o" "$PASS_V"

# (e) enumeration failure and an empty enumeration are errors, not a pass
mkdir "$W/plain"
o=$(legacy_names_guard "$W/plain" "$ALLOW")
assert_contains "(e) not a repo → git ls-files failure reported" "$o" "git ls-files failed"
git init -q "$W/empty" >/dev/null 2>&1
o=$(legacy_names_guard "$W/empty" "$ALLOW")
assert_contains "(e) zero tracked files → refused" "$o" "0 tracked text files scanned"
assert_not_contains "(e) zero tracked files → verdict not 0 violations" "$o" "$PASS_V"

# (f) grep rc 2 (read error) ≠ rc 1 (no match): a shim makes grep fail on VERSION
REAL_GREP=$(command -v grep); mkdir "$W/bin"
cat > "$W/bin/grep" <<SHIM
#!/bin/bash
for a in "\$@"; do last="\$a"; done
case "\$last" in */VERSION) case " \$* " in *" \$LNG_FAKE "*) exit 2 ;; esac ;; esac
exec "$REAL_GREP" "\$@"
SHIM
chmod +x "$W/bin/grep"
o=$(PATH="$W/bin:$PATH"; hash -r; LNG_FAKE=-nE; export LNG_FAKE; legacy_names_guard "$C" "$ALLOW")
assert_contains "(f) scan grep rc 2 → named as scan failure" "$o" "scan failed (grep rc 2): VERSION"
assert_not_contains "(f) scan rc 2 → verdict not 0 violations" "$o" "$PASS_V"
o=$(PATH="$W/bin:$PATH"; hash -r; LNG_FAKE=-Il; export LNG_FAKE; legacy_names_guard "$C" "$ALLOW")
assert_contains "(f) text probe grep rc 2 → named" "$o" "text probe failed (grep rc 2): VERSION"

# (g) mutation (#25): neutralise the verdict but keep the diagnostics. The
# planted tree then prints its ❌ lines AND a pass verdict, so the (a) verdict
# assertion — not the diagnostics — is what keeps this suite red.
mut=$(declare -f legacy_names_guard | sed -e 's/^legacy_names_guard ()/legacy_names_guard_mut ()/' \
    -e 's/if \[ "\$viol" -eq 0 \] && \[ "\$err" -eq 0 \]; then/if [ 0 -eq 0 ]; then/')
assert_contains "(g) self-check: the verdict condition was really neutralised" "$mut" "if [ 0 -eq 0 ]; then"
eval "$mut"
printf '\nsee %s/ for the history\n' "$HX_LEGACY_LOGS_DIR" >> "$C/README.md"
o=$(legacy_names_guard_mut "$C" "$ALLOW")
cp "$W/README.keep" "$C/README.md"
assert_contains "(g) mutant still prints the README diagnostic" "$o" "❌ README.md:"
assert_contains "(g) mutant reports a pass verdict → (a) would go red" "$o" "$PASS_V"

# (h) C1 skip predicate (tests/common.sh hx_git_worktree_state): ➖ only on a
# structural absence; a git that fails in a real checkout is an error (❌).
st() { hx_git_worktree_state "$@" 2>/dev/null; }
assert_exit "(h) clone root → worktree [got: $(st "$C")]" 0 "$([ "$(st "$C")" = worktree ] && echo 0 || echo 1)"
mkdir "$C/nested"
assert_exit "(h) dir nested inside another repo (no .git of its own) → none [got: $(st "$C/nested")]" 0 "$([ "$(st "$C/nested")" = none ] && echo 0 || echo 1)"
assert_exit "(h) plain dir, as in an extracted package → none [got: $(st "$W/plain")]" 0 "$([ "$(st "$W/plain")" = none ] && echo 0 || echo 1)"
mkdir "$W/nogit"
s_nogit=$(PATH="$W/nogit" st "$C")
assert_exit "(h) git missing from PATH while .git exists → error [got: $s_nogit]" 0 "$([ "$s_nogit" = error ] && echo 0 || echo 1)"
# m3 (fix wave 2): no git on PATH AND no .git — an extracted package on a
# machine without git — is a structural absence (➖), not an error.
s_nogit_pkg=$(PATH="$W/nogit" st "$W/plain")
assert_exit "(h) git missing from PATH, no .git → none [got: $s_nogit_pkg]" 0 "$([ "$s_nogit_pkg" = none ] && echo 0 || echo 1)"
s_bogus=$(GIT_DIR="$W/bogus-git-dir" st "$C")
assert_exit "(h) GIT_DIR pointed at a bogus dir → error [got: $s_bogus]" 0 "$([ "$s_bogus" = error ] && echo 0 || echo 1)"
# suite level: an error is ❌ + exit 1, never the ➖ skip
rc=0; o=$(GIT_DIR="$W/bogus-git-dir" bash "$0" 2>&1) || rc=$?
assert_exit "(h) suite under a bogus GIT_DIR → exit 1" 1 "$rc"
assert_contains "(h) suite under a bogus GIT_DIR → refuses to skip" "$o" "refusing to skip the guard"
assert_not_contains "(h) suite under a bogus GIT_DIR → no ➖ skip" "$o" "➖ SKIPPED"
# (h) mutation (#25): the old predicate folded every git failure into "not a
# checkout". A mutant that does that again must flip the error rows above.
mut=$(declare -f hx_git_worktree_state | sed -e 's/^hx_git_worktree_state ()/hx_git_worktree_state_mut ()/' -e 's/echo error/echo none/g')
assert_contains "(h) self-check: the error state was really neutralised" "$mut" "echo none"
eval "$mut"
assert_exit "(h) mutant reports none under a bogus GIT_DIR → the error row would go red" 0 \
    "$([ "$(GIT_DIR="$W/bogus-git-dir" hx_git_worktree_state_mut "$C" 2>/dev/null)" = none ] && echo 0 || echo 1)"

# (i) C2: an allowlist row exempts only its classes. SKILL.md is a fourpiece
# row (upgrade routing names the legacy main), so an old registered name there
# is still a violation; install.sh is a registered row, so a legacy four-piece
# name there is still a violation.
cp "$C/skills/handoffx/SKILL.md" "$W/SKILL.keep"; cp "$C/install.sh" "$W/install.keep"
printf '\nrun /%s-tidy first\n' "$_h" >> "$C/skills/handoffx/SKILL.md"
o=$(legacy_names_guard "$C" "$ALLOW"); rc=$?
assert_contains "(i) registered name in a fourpiece-only row → SKILL.md named" "$o" "❌ skills/handoffx/SKILL.md:"
assert_exit "(i) registered name in a fourpiece-only row → exit 1" 1 "$rc"
cp "$W/SKILL.keep" "$C/skills/handoffx/SKILL.md"
printf '\nsee %s/ for the history\n' "$HX_LEGACY_LOGS_DIR" >> "$C/skills/handoffx/SKILL.md"
o=$(legacy_names_guard "$C" "$ALLOW")
assert_contains "(i) fourpiece name in a fourpiece row → still 0 violations" "$o" "$PASS_V"
cp "$W/SKILL.keep" "$C/skills/handoffx/SKILL.md"
printf '\n# see %s\n' "$HX_LEGACY_MAIN_FILE" >> "$C/install.sh"
o=$(legacy_names_guard "$C" "$ALLOW")
assert_contains "(i) fourpiece name in a registered-only row → install.sh named" "$o" "❌ install.sh:"
cp "$W/install.keep" "$C/install.sh"
# (i) mutation (#25): collapse the classes back to "any matching row exempts
# the whole file" — the registered plant in SKILL.md must then pass, which is
# what makes the first (i) assertion the load-bearing one.
mut=$(declare -f legacy_names_guard | sed -e 's/^legacy_names_guard ()/legacy_names_guard_cls ()/' \
    -e 's/if \[ "\$xr" -eq 1 \] && \[ "\$xf" -eq 1 \]; then/if [ "$xr" -eq 1 ] || [ "$xf" -eq 1 ]; then/')
assert_contains "(i) self-check: class filtering was really neutralised" "$mut" '|| [ "$xf" -eq 1 ]; then'
eval "$mut"
printf '\nrun /%s-tidy first\n' "$_h" >> "$C/skills/handoffx/SKILL.md"
o=$(legacy_names_guard_cls "$C" "$ALLOW")
cp "$W/SKILL.keep" "$C/skills/handoffx/SKILL.md"
assert_contains "(i) mutant passes the registered plant → (i) would go red" "$o" "$PASS_V"

# (j) C2b: the migrated main file has no allowlist row; a legacy name planted
# in its Current State is a violation (it was exempt wholesale before).
cp "$C/$HX_MAIN_FILE" "$W/main.keep"
awk -v n="$HX_LEGACY_LOGS_DIR" '{ print } /^## .*Current State/ && !d { print "- 历史见 " n "/0001"; d = 1 }' "$W/main.keep" > "$C/$HX_MAIN_FILE"
assert_contains "(j) precondition: plant landed in Current State" "$(cat "$C/$HX_MAIN_FILE")" "历史见 $HX_LEGACY_LOGS_DIR/0001"
o=$(legacy_names_guard "$C" "$ALLOW"); rc=$?
assert_contains "(j) $HX_LEGACY_LOGS_DIR/ planted in $HX_MAIN_FILE Current State → named" "$o" "❌ $HX_MAIN_FILE:"
assert_exit "(j) planted in $HX_MAIN_FILE → exit 1" 1 "$rc"
cp "$W/main.keep" "$C/$HX_MAIN_FILE"
assert_exit "(j) the allowlist has no $HX_MAIN_FILE row and no row for this guard" 1 \
    "$(grep -qE "^($HX_MAIN_FILE|tests/test_legacy_names_guard\.sh)	" "$ALLOW" && echo 0 || echo 1)"

# (l) F2: the allowlist is fail-closed — a row exists only for a justified hit.
# On the migrated clone every row must match at least one tracked file that
# really holds a name of a class the row exempts; a dead row is an exemption
# waiting for a regression to hide in.
dead=""
while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    g="${line%%	*}"; rest="${line#*	}"; c="${rest%%	*}"
    case ",$c," in *,all,*) re="$REG_RE|$FP_RE" ;; *,registered,*,fourpiece,*|*,fourpiece,*,registered,*) re="$REG_RE|$FP_RE" ;; *,registered,*) re="$REG_RE" ;; *) re="$FP_RE" ;; esac
    live=0
    while IFS= read -r f; do
        # shellcheck disable=SC2254  # unquoted on purpose: $g is a glob
        case "$f" in $g) LC_ALL=C grep -qE -- "$re" "$C/$f" 2>/dev/null && { live=1; break; } ;; esac
    done < <(git -C "$C" ls-files)
    [ "$live" = 1 ] || dead="$dead $g"
done < "$ALLOW"
assert_exit "(l) every allowlist row exempts at least one real hit on the migrated clone (dead:${dead:- none})" 0 "$([ -z "$dead" ] && echo 0 || echo 1)"

# (k) C3: the text probe runs under LC_ALL=C like the scan. GNU grep in a
# UTF-8 locale calls a file with invalid UTF-8 "binary" (-I → rc 1) and the
# guard skipped it unread; the shim reproduces that on any platform.
printf 'ok\n\377\376 see %s/\n' "$HX_LEGACY_LOGS_DIR" > "$C/badutf8.txt"
git -C "$C" add badutf8.txt >/dev/null 2>&1
mkdir "$W/gnubin"
cat > "$W/gnubin/grep" <<SHIM
#!/bin/bash
case " \$* " in *" -Il "*) [ "\${LC_ALL:-}" = C ] || exit 1 ;; esac
exec "$REAL_GREP" "\$@"
SHIM
chmod +x "$W/gnubin/grep"
o=$(PATH="$W/gnubin:$PATH"; hash -r; LC_ALL=en_US.UTF-8; export LC_ALL; legacy_names_guard "$C" "$ALLOW")
assert_contains "(k) invalid-UTF-8 file under a UTF-8 locale is still scanned → named" "$o" "❌ badutf8.txt:"
git -C "$C" rm -q --cached badutf8.txt >/dev/null 2>&1; rm -f "$C/badutf8.txt"

summary
