#!/bin/bash
# P2.2a rename-guard mutation harness (0058 bguard pattern, Gotcha #25).
# The repo is pre-rename (guard RED today), so the fixture is a POST-RENAME
# SIMULATION: copy the manifest's files into mktemp, apply every manifest R row
# old→new mechanically (scratch only — never the repo), assert the real guard
# is GREEN there, then six mutations must each turn it RED. Every assertion is
# keyed on the guard's exit code + verdict line, never on its diagnostics.
source "$(dirname "$0")/common.sh"
RT="$ROOT_DIR"
M="$RT/tests/fixtures/p2_2_rename_manifest.txt"
GUARD_REL="tests/test_p2_2_rename_manifest.sh"
export LC_ALL=C
BASE=$(mktemp -d "${TMPDIR:-/tmp}/p22bg.XXXXXX")
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/p22stage.XXXXXX")
MUT=""
trap 'rm -rf "$BASE" "$STAGE" "$MUT"' EXIT INT TERM
[ -r "$M" ] || { echo "  ❌ manifest unreadable: $M"; exit 1; }

# ── build: manifest file set from the PRE-rename source + the guard under test ──
# P2.2a renames the repo in place, so the working tree stops being a pre-rename
# source after Task 0. The frozen tree is the commit that FIRST added the
# manifest (2afca49); the manifest must stay a pure function of (that tree,
# current predicates) — asserted below — so reviewed reclassifications regenerate
# it from there. No git (exported copy) → the working tree is the source.
SRC="$RT"
FROZEN=$(git -C "$RT" log --diff-filter=A --format=%H -- tests/fixtures/p2_2_rename_manifest.txt 2>/dev/null | tail -1)
if [ -n "$FROZEN" ]; then
    git -C "$RT" archive "$FROZEN" | (cd "$STAGE" && tar xf -) && SRC="$STAGE"
    cp "$RT/tests/lib/p2_2_rename_inventory.sh" "$STAGE/tests/lib/p2_2_rename_inventory.sh"
    if P22_ROOT="$STAGE" bash "$STAGE/tests/lib/p2_2_rename_inventory.sh" | cmp -s - "$M"; then rp=0; else rp=1; fi
    assert_exit "manifest reproduces byte-for-byte from frozen tree ${FROZEN%"${FROZEN#???????}"} + current predicates" 0 "$rp"
fi
awk -F: '{ print $1 }' "$M" | sort -u > "$BASE.list"
echo tests/common.sh >> "$BASE.list"
(cd "$SRC" && tar cf - -T "$BASE.list" 2>/dev/null) | (cd "$BASE" && tar xf -)
rm -f "$BASE.list"
for g in tests/lib/p2_2_rename_inventory.sh "$GUARD_REL" tests/fixtures/p2_2_rename_manifest.txt \
         tests/fixtures/p2_2_rename_exceptions.txt tests/fixtures/p2_2_rename_refactored.txt \
         tests/fixtures/p2_2_rename_relocations.txt; do
    mkdir -p "$BASE/$(dirname "$g")"; cp "$RT/$g" "$BASE/$g"
done
# The live exception table is line-keyed to the CURRENT (partly renamed) tree and
# is checked by the real guard run. The simulation needs the table for the frozen
# tree under CURRENT predicates, i.e. the same pure function as the manifest:
# seed it from the manifest (p22_exception_seed) and freeze its own count.
EB="$BASE/tests/fixtures/p2_2_rename_exceptions.txt"
( . "$RT/tests/lib/p2_2_rename_inventory.sh"; p22_exception_seed < "$M" ) > "$EB.rows"
{ echo "# frozen-rows: $(wc -l < "$EB.rows" | tr -d ' ')"; cat "$EB.rows"; } > "$EB"; rm -f "$EB.rows"

# ── simulate the rename: content rows right-to-left per line, then path moves ──
SIMBAD=$(awk -v ROOT="$BASE" '
function flush(    i, j, t, ln) {
    if (cur == "") return
    f = ROOT "/" cur; n = 0
    while ((getline t < f) > 0) LN[++n] = t
    close(f)
    for (k = 1; k <= nr; k++) {
        ln = RL[k]; t = LN[ln]; s = RC[k] - (index(tolower(RO[k]), "handoff") - 1)
        if (substr(t, s, length(RO[k])) != RO[k]) { bad++; continue }
        LN[ln] = substr(t, 1, s - 1) RN[k] substr(t, s + length(RO[k]))
    }
    printf "" > f
    for (i = 1; i <= n; i++) print LN[i] > f
    close(f); delete LN; nr = 0
}
BEGIN { FS = "\t"; bad = 0 }
{
    split($1, h, ":"); if (h[2] == "" || h[4] !~ /^R/) next
    if (h[1] != cur) { flush(); cur = h[1] }
    rest = substr($1, length(h[1] h[2] h[3] h[4]) + 5); k = index(rest, "→")
    nr++; RL[nr] = h[2]; RC[nr] = h[3]; RO[nr] = substr(rest, 1, k - 1); RN[nr] = substr(rest, k + 3)
}
END { flush(); print bad }' <(awk -F'\t' '{ split($1, h, ":"); print h[1] "\t" h[2] "\t" h[3] "\t" $0 }' "$M" \
        | sort -t "$(printf '\t')" -k1,1 -k2,2n -k3,3nr | cut -f4-))
assert_exit "sim: every manifest R row's old token found at its column" 0 "$([ "$SIMBAD" = 0 ] && echo 0 || echo 1)"
awk -F: '$2 == "" && $3 ~ /^R/ { r = substr($0, length($1) + length($3) + 4); split(r, a, "→"); print a[1] "\t" a[2] }' "$M" \
| while IFS="$(printf '\t')" read -r old new; do
    [ "$old" = "$new" ] && continue
    mkdir -p "$BASE/$(dirname "$new")"
    if [ -e "$BASE/$new" ]; then cat "$BASE/$old" >> "$BASE/$new" && rm -f "$BASE/$old"   # tidy merge (plan §4)
    else mv "$BASE/$old" "$BASE/$new"; fi
done
[ -d "$BASE/skills/handoff" ] && find "$BASE/skills/handoff" -depth -type d -empty -exec rmdir {} \;

# run_guard <tree> → sets OUT / RC
run_guard() { OUT=$(P22_ROOT="$1" bash "$1/$GUARD_REL" 2>&1); RC=$?; }
# is_red: the ONLY load-bearing key — non-zero exit AND ❌ verdict AND no ✅ verdict.
is_red() { [ "$RC" -ne 0 ] && echo "$OUT" | grep -q '^❌ manifest:' && ! echo "$OUT" | grep -q '^✅ manifest:'; }
expect_red() { if is_red; then assert_exit "$1" 0 0; else assert_exit "$1" 0 1; echo "$OUT" | tail -12 | sed 's/^/      /'; fi; }
fresh_mut() { rm -rf "$MUT"; MUT=$(mktemp -d "${TMPDIR:-/tmp}/p22mut.XXXXXX"); cp -R "$BASE/." "$MUT/"; }

# ── GREEN on the unmutated post-rename simulation ──
run_guard "$BASE"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^✅ manifest:'; then g=0; else g=1; echo "$OUT" | tail -25 | sed 's/^/      /'; fi
assert_exit "baseline: guard GREEN (exit 0 + ✅ verdict) on post-rename simulation" 0 "$g"

# first R content row (mechanical pick) → file in the renamed tree + its anchor
pick_row() {
    awk -F'\t' -v want="$1" '{ split($1, h, ":"); if (h[2] != "" && h[4] ~ want) { print; exit } }' "$M"
}
newpath() {
    local p="$1" np
    np=$(awk -F: -v p="$1" '$1 == p && $2 == "" && $3 ~ /^R/ { r = substr($0, length($1) + length($3) + 4); split(r, a, "→"); print a[2] }' "$M")
    echo "${np:-$p}"
}
# revert_nth <file> <needle-new> <needle-old> <n>: rewrite the n-th occurrence only.
revert_nth() {
    awk -v NEW="$2" -v OLD="$3" -v N="$4" '{
        out = ""; s = $0
        while ((q = index(s, NEW)) > 0) { c++; if (c == N) { out = out substr(s, 1, q - 1) OLD; s = substr(s, q + length(NEW)); continue }
            out = out substr(s, 1, q + length(NEW) - 1); s = substr(s, q + length(NEW)) }
        print out s }' "$1" > "$1.t" && mv "$1.t" "$1"
}

# needle for a manifest row: left + new core token + right (same as guard (b)).
row_needles() {   # prints: path<TAB>new-needle<TAB>old-needle
    awk -F'\t' '{ split($1, h, ":"); rest = substr($1, length(h[1] h[2] h[3] h[4]) + 5)
        k = index(rest, "→"); nw = substr(rest, k + 3)
        match(nw, /[Hh][Aa][Nn][Dd][Oo][Ff][Ff][xX]/); core = substr(nw, RSTART, 8)
        print h[1] "\t" $2 core $3 "\t" $2 substr(core, 1, 7) $3 }'
}

# (i) re-plant one old token (first R2 row) → RED
IFS="$(printf '\t')" read -r p nn on <<EOF
$(pick_row '^R2$' | row_needles)
EOF
fresh_mut; f="$MUT/$(newpath "$p")"
revert_nth "$f" "$nn" "$on" 1
run_guard "$MUT"; expect_red "(i) re-plant one old token ($p) → guard RED"

# (ii) rename the L1 adjacency trap → RED (hits (c))
fresh_mut
mv "$MUT/skills/handoffx/scripts/handoff-postflight.sh" "$MUT/skills/handoffx/scripts/handoffx-postflight.sh"
run_guard "$MUT"; expect_red "(ii) rename L1 handoff-postflight.sh → guard RED"

# (iii) neutralise the verdict (violations forced 0, diagnostics kept) + mutation (i):
#       the guard now prints ❌ diagnostics but a ✅ verdict / exit 0 — so is_red,
#       the bguard's sole key, must report NOT red (i.e. every expect_red above
#       would turn this harness RED if the real guard ever lost its verdict).
fresh_mut; f="$MUT/$(newpath "$p")"
revert_nth "$f" "$nn" "$on" 1
awk '{ sub(/^violations=\$\(\(va \+ vb \+ vc \+ vd \+ ve \+ vf\)\)$/, "violations=0"); print }' \
    "$MUT/$GUARD_REL" > "$MUT/g.t" && mv "$MUT/g.t" "$MUT/$GUARD_REL"
assert_contains "(iii) self-check: verdict neutralisation landed" "$(cat "$MUT/$GUARD_REL")" "violations=0"
run_guard "$MUT"
assert_contains "(iii) neutralised guard still emits ❌ diagnostics" "$OUT" "❌ (a) R occurrences not excepted"
assert_exit "(iii) neutralised verdict → is_red reports NOT red (bguard keyed on verdict, would RED)" 1 "$(is_red && echo 0 || echo 1)"

# (iv) delete one exception row / add one duplicate row → RED (hits (d))
fresh_mut; E="$MUT/tests/fixtures/p2_2_rename_exceptions.txt"
awk '!/^#/ && !d { d = 1; next } { print }' "$E" > "$E.t" && mv "$E.t" "$E"
run_guard "$MUT"; expect_red "(iv-a) delete one exception row → guard RED"
fresh_mut; E="$MUT/tests/fixtures/p2_2_rename_exceptions.txt"
awk '{ print } !/^#/ && !d { d = 1; print }' "$E" > "$E.t" && mv "$E.t" "$E"
run_guard "$MUT"; expect_red "(iv-b) add one exception row → guard RED"

# (v) delete one →new target (first R path row whose basename is renamed) → RED (hits (b))
tgt=$(awk -F: '$2 == "" && $3 ~ /^R/ { r = substr($0, length($1) + length($3) + 4); split(r, a, "→")
      ob = a[1]; nb = a[2]; sub(/.*\//, "", ob); sub(/.*\//, "", nb); if (ob != nb) { print a[2]; exit } }' "$M")
fresh_mut; rm -f "$MUT/$tgt"
run_guard "$MUT"; expect_red "(v) delete renamed target $tgt → guard RED"

# (vi) two same-token occurrences in one file, revert only the second → RED
# prefer the hard case: identical anchor twice in one file (only the guard's
# occurrence COUNT can see one of them reverted); else any 2nd row of a file.
rows_r() { awk -F'\t' '{ split($1, h, ":"); if (h[2] != "" && h[4] ~ /^R/) print }' "$M" | row_needles; }
dup=$(rows_r | awk 'c[$0]++ == 1 { print; exit }')
[ -n "$dup" ] || dup=$(rows_r | awk -F'\t' 'c[$1]++ == 1 { print; exit }')
IFS="$(printf '\t')" read -r p2 nn2 on2 <<EOF
$dup
EOF
fresh_mut; revert_nth "$MUT/$(newpath "$p2")" "$nn2" "$on2" 2
[ "$(grep -cF -- "$on2" "$MUT/$(newpath "$p2")")" -ge 1 ] && r6=0 || r6=1
assert_exit "(vi) self-check: exactly the 2nd occurrence was reverted" 0 "$r6"
run_guard "$MUT"; expect_red "(vi) revert only the 2nd of two same-token occurrences ($p2) → guard RED"

# (vii) refactored-row tolerance is narrow: list a row (mechanical pick: the
#       only R row in its file, new token ends at the core, token occurs once).
#       Anchor broken but token kept → GREEN; token deleted → RED.
RF="tests/fixtures/p2_2_rename_refactored.txt"
bump_ref() {   # bump_ref <tree> <row> : append row + frozen-rows+1
    awk -v row="$2" '/^# frozen-rows: / { sub(/[0-9]+$/, $3 + 1) } { print } END { print row }' "$1/$RF" > "$1/rf.t" \
        && mv "$1/rf.t" "$1/$RF"
}
CORE='[Hh][Aa][Nn][Dd][Oo][Ff][Ff][xX]'
cand=""
while IFS="$(printf '\t')" read -r rid nw cp nn; do
    f="$BASE/$(newpath "$cp")"
    case "$nw" in *handoffx|*HandoffX) ;; *) continue ;; esac
    [ "$(grep -o -F -- "$nw" "$f" | wc -l | tr -d ' ')" = 1 ] || continue
    cand="$rid	$nw	$cp	$nn"; break
done < <(awk -F'\t' '{ split($1, h, ":"); if (h[2] == "" || h[4] !~ /^R/) next
          n[h[1]]++; row[h[1]] = $0 }
          END { for (p in n) if (n[p] == 1) print row[p] }' "$M" | sort \
        | awk -F'\t' '{ split($1, h, ":"); rest = substr($1, length(h[1] h[2] h[3] h[4]) + 5)
          k = index(rest, "→"); nw = substr(rest, k + 3); match(nw, /[Hh][Aa][Nn][Dd][Oo][Ff][Ff][xX]/)
          print h[1] ":" h[2] ":" h[3] ":" h[4] "\t" nw "\t" h[1] "\t" $2 substr(nw, RSTART, 8) $3 }')
assert_exit "(vii) self-check: a single-occurrence candidate row exists" 0 "$([ -n "$cand" ] && echo 0 || echo 1)"
IFS="$(printf '\t')" read -r rid7 nw7 p7 nn7 <<< "$cand"
fresh_mut; f="$MUT/$(newpath "$p7")"; bump_ref "$MUT" "$rid7:bguard (vii) listed refactor"
# break the anchor right after the core token (keeps the new token intact)
tail7="${nn7#*$CORE}"
revert_nth "$f" "$nn7" "${nn7%"$tail7"}~$tail7" 1
run_guard "$MUT"
if [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^✅ manifest:'; then g=0; else g=1; echo "$OUT" | tail -12 | sed 's/^/      /'; fi
assert_exit "(vii-a) listed refactor, anchor broken, new token kept ($p7) → guard GREEN" 0 "$g"
awk -v T="$nw7" '{ o = ""; s = $0; while ((q = index(s, T)) > 0) { o = o substr(s, 1, q - 1); s = substr(s, q + length(T)) } print o s }' \
    "$f" > "$f.t" && mv "$f.t" "$f"
run_guard "$MUT"; expect_red "(vii-b) listed refactor whose new token is gone from the file → guard RED"

# (viii) a refactored row naming no manifest R row → RED (ratchet in (d))
fresh_mut; bump_ref "$MUT" "nonexistent/file.md:1:1:R1:bguard (viii) bogus row"
run_guard "$MUT"; expect_red "(viii) refactored row not in the manifest → guard RED"

# (ix)–(xii) reviewed path relocation (P2.2b Task 0). $BASE comes from the FROZEN
#   tree, so it still holds the review loop at its original path and the guard
#   never needs the fallback there. Each case therefore first moves its OWN fresh
#   copy into the relocated shape (file taken from the live tree), then mutates.
#   A case whose setup did not land fails outright — it never counts as RED.
RLO="scripts/review-loop.sh"; RLN="tools/review-loop.sh"
RLF="tests/fixtures/p2_2_rename_relocations.txt"
moved_mut() {
    fresh_mut
    rm "$MUT/$RLO" && mkdir -p "$MUT/tools" && cp "$RT/$RLN" "$MUT/tools/" \
        && [ ! -e "$MUT/$RLO" ] && [ -f "$MUT/$RLN" ] && [ -f "$MUT/$RLF" ]
}
red_case() {   # red_case <setup-rc> <label>
    if [ "$1" -eq 0 ]; then run_guard "$MUT"; expect_red "$2"; else assert_exit "$2 (setup did not land)" 0 1; fi
}

# (ix) relocated, unmutated → GREEN (manifest row $RLO:3 resolves via the table)
moved_mut; s=$?
run_guard "$MUT"
if [ "$s" -eq 0 ] && [ "$RC" -eq 0 ] && echo "$OUT" | grep -q '^✅ manifest:'; then g=0; else g=1; echo "$OUT" | tail -12 | sed 's/^/      /'; fi
assert_exit "(ix) review loop relocated to $RLN, table lists it → guard GREEN" 0 "$g"

# (x) relocated file re-plants the old token on the manifest row's line → RED
IFS="$(printf '\t')" read -r _ nn10 on10 <<EOF
$(awk -F'\t' -v k="$RLO:3:40:R1:" 'index($1, k) == 1' "$M" | row_needles)
EOF
moved_mut; s=$?
if [ "$s" -eq 0 ] && [ -n "$nn10" ]; then
    revert_nth "$MUT/$RLN" "$nn10" "$on10" 1
    [ "$(grep -cF -- "$nn10" "$MUT/$RLN")" = 0 ] && grep -qF -- "$on10" "$MUT/$RLN" || s=1
else s=1; fi
red_case "$s" "(x) relocated $RLN line 3 back to the old token → guard RED (anchor-missing)"

# (xi) relocated file deleted (neither path exists) → RED
moved_mut; s=$?
[ "$s" -eq 0 ] && rm "$MUT/$RLN" || s=1
red_case "$s" "(xi) relocated $RLN deleted → guard RED"

# (xii) relocation row dropped (header 0, ratchet satisfied) → RED: the original
#       path is gone and nothing maps it
moved_mut; s=$?
if [ "$s" -eq 0 ]; then
    awk '/^# frozen-rows: / { $0 = "# frozen-rows: 0" } !/^#/ && /→/ { next } { print }' "$MUT/$RLF" > "$MUT/rl.t" \
        && mv "$MUT/rl.t" "$MUT/$RLF"
    [ "$(grep -v '^#' "$MUT/$RLF" | grep -vc '^$')" = 0 ] && grep -qx '# frozen-rows: 0' "$MUT/$RLF" || s=1
fi
red_case "$s" "(xii) relocation row removed (frozen-rows 0) → guard RED"

# (xiii)/(xiv) relocation target that is not a file: macOS awk dies on `getline < dir`
#   inside the guard's (b)/(d) awk, so every anchor check after it is skipped — the
#   guard must turn that into RED, never a ✅ over unchecked rows.
set_reloc() {   # set_reloc <new-target> : rewrite the single relocation row's target
    awk -v o="$RLO" -v n="$1" '!/^#/ && /→/ { $0 = o "→" n } { print }' "$MUT/$RLF" > "$MUT/rl.t" \
        && mv "$MUT/rl.t" "$MUT/$RLF" && grep -qxF -- "${RLO}→$1" "$MUT/$RLF"
}
moved_mut; s=$?
[ "$s" -eq 0 ] && set_reloc "tools/" || s=1
red_case "$s" "(xiii) relocation target is a directory (tools/) → guard RED"

moved_mut; s=$?
[ "$s" -eq 0 ] && set_reloc "" || s=1
red_case "$s" "(xiv) relocation target empty → guard RED"

summary
