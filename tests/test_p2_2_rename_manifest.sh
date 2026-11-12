#!/bin/bash
# P2.2a rename guard (plan §2). Verdict = exit code + ONE `✅ manifest:` /
# `❌ manifest:` line computed from `violations` (Gotcha #25: callers and the
# bguard key on that, never on the per-check diagnostics above it).
# Pre-rename this is RED on (a)/(b): the R rows of the frozen manifest are the
# P2.2a scope. Inputs are mechanically generated (tests/lib/p2_2_rename_inventory.sh);
# every unreadable/empty input fails closed (Gotcha #24).
#
# Refactored rows (tests/fixtures/p2_2_rename_refactored.txt): hard-cut (T3)
# deletes old-name clauses next to an R token, and Task 2 rewrites install.sh,
# so some R rows' lines legitimately lose their anchor. Such a row is tolerated
# in (b) ONLY if it is listed there (keyed path:line:col:ROLE to the ORIGINAL
# manifest row, with a reason) AND its new token still occurs in the file —
# else "refactored row lost its rename". The list is ratcheted in (d): frozen
# row count + every row must name a real manifest R row. Gotcha #25: a
# tolerance must be reviewable and ratcheted, never a wildcard.
#
# Relocations (tests/fixtures/p2_2_rename_relocations.txt, old→new): files moved
# after the manifest was frozen (P2.2b Task 0: the review loop left scripts/ for
# tools/). The frozen manifest keeps the original path, so the rows are merged
# into the path map that (b)/(c)/(d) already fall back to; ratcheted in (d).
source "$(dirname "$0")/common.sh"
ROOT="${P22_ROOT:-$ROOT_DIR}"; export P22_ROOT="$ROOT"
MANIFEST="$ROOT/tests/fixtures/p2_2_rename_manifest.txt"
EXC="$ROOT/tests/fixtures/p2_2_rename_exceptions.txt"
LIB="$ROOT/tests/lib/p2_2_rename_inventory.sh"
REF="$ROOT/tests/fixtures/p2_2_rename_refactored.txt"
RELOC="$ROOT/tests/fixtures/p2_2_rename_relocations.txt"
for f in "$MANIFEST" "$EXC" "$LIB" "$REF" "$RELOC"; do
    [ -r "$f" ] || { echo "❌ manifest: unreadable input $f"; exit 1; }
done
# shellcheck source=tests/lib/p2_2_rename_inventory.sh
. "$LIB"
W=$(mktemp -d "${TMPDIR:-/tmp}/p22guard.XXXXXX")
trap 'rm -rf "$W"' EXIT INT TERM
export LC_ALL=C

# Show the first 20 items of a list file + total (diagnostics only).
diag() {
    local label="$1" file="$2" n
    n=$(wc -l < "$file" | tr -d ' ')
    [ "$n" -eq 0 ] && return 0
    echo "  ── $label: $n item(s); first 20:"
    head -20 "$file" | cut -c1-160 | sed 's/^/     /'
}

p22_inventory > "$W/fresh" || { echo "❌ manifest: inventory scanned zero files"; exit 1; }
grep -v '^#' "$EXC" | grep -v '^$' > "$W/exc"
grep -v '^#' "$REF" | grep -v '^$' > "$W/ref"
# path map old→new from the manifest's R path rows (resolves renamed files).
awk -F: '$2 == "" && $3 ~ /^R/ { r = substr($0, length($1) + length($3) + 4); split(r, a, "→"); print a[1] "\t" a[2] }' \
    "$MANIFEST" > "$W/pathmap" || { echo "❌ manifest: awk-failed (pathmap) rc=$?"; exit 1; }
grep -v '^#' "$RELOC" | grep -v '^$' | sed 's/→/\t/' >> "$W/pathmap"
mR=$(awk -F: '$4 ~ /^R/ || ($2 == "" && $3 ~ /^R/)' "$MANIFEST" | wc -l | tr -d ' ')
[ "$mR" -gt 0 ] || { echo "❌ manifest: frozen manifest has zero R rows (vacuous)"; exit 1; }

# (a) R occurrences in a FRESH inventory not covered by an exception row with
#     the same path:line:ROLE (a row of another role never covers an R hit).
awk -F: 'NR == FNR { k[$1 ":" $2 ":" $3] = 1; next }
         $4 ~ /^R/ && !(($1 ":" $2 ":" $4) in k) { print; next }
         $2 == "" && $3 ~ /^R/ { print }' "$W/exc" "$W/fresh" > "$W/a" || echo "awk-failed (a) rc=$?" >> "$W/a"
va=$(wc -l < "$W/a" | tr -d ' ')

# (b) occurrence-level positive: every manifest R row's anchor (12 bytes each
#     side of the NEW token, from the simulated post-rename line) must occur in
#     the current file at least as many times as the manifest expects it.
#     A miss on a row listed in refactored.txt is tolerated iff the row's new
#     token still occurs somewhere in the file (see header).
awk -v ROOT="$ROOT" -v MAP="$W/pathmap" -v REFL="$W/ref" '
BEGIN { FS = "\t"; while ((getline l < MAP) > 0) { split(l, a, "\t"); NEWP[a[1]] = a[2] }
        while ((getline l < REFL) > 0) { split(l, a, ":"); REFD[a[1] ":" a[2] ":" a[3] ":" a[4]] = 1 } }
{
    hdr = $1; split(hdr, h, ":")
    if (h[2] == "") {                       # path row
        if (h[3] !~ /^R/) next
        r = substr(hdr, length(h[1]) + length(h[3]) + 4); split(r, a, "→")
        if (a[2] == "" || system("test -e \"" ROOT "/" a[2] "\"") != 0) print "path-missing " h[1] " → " a[2]
        next
    }
    if (h[4] !~ /^R/) next
    rest = substr(hdr, length(h[1] h[2] h[3] h[4]) + 5); k = index(rest, "→")
    nw = (k > 0) ? substr(rest, k + 3) : ""
    if (!match(nw, /[Hh][Aa][Nn][Dd][Oo][Ff][Ff][xX]/) || NF < 3) { print "malformed-row " hdr; next }
    nd = $2 substr(nw, RSTART, 8) $3
    key = h[1] SUBSEP nd; if (!(key in NEED)) ORD[++no] = key
    NEED[key]++; ROW[key] = hdr
    rid = h[1] ":" h[2] ":" h[3] ":" h[4]; NR_[key]++; RID[key, NR_[key]] = rid; NWS[rid] = substr(rest, k + 3)
}
END {
    for (i = 1; i <= no; i++) { split(ORD[i], kk, SUBSEP); P[kk[1]] = 1 }
    for (p in P) {
        f = ROOT "/" p; if ((getline t < f) <= 0 && (p in NEWP)) f = ROOT "/" NEWP[p]; close(f)
        while ((getline t < f) > 0) { gsub(/\t/, " ", t); L[p, ++NL[p]] = t }
        close(f)
    }
    for (i = 1; i <= no; i++) {
        split(ORD[i], kk, SUBSEP); p = kk[1]; nd = kk[2]; c = 0
        for (j = 1; j <= NL[p]; j++) { s = L[p, j]; while ((q = index(s, nd)) > 0) { c++; s = substr(s, q + 1) } }
        miss = NEED[ORD[i]] - c
        for (r = 1; r <= NR_[ORD[i]] && miss > 0; r++) {
            rid = RID[ORD[i], r]; if (!(rid in REFD)) continue
            miss--; hit = 0
            for (j = 1; j <= NL[p] && !hit; j++) if (index(L[p, j], NWS[rid]) > 0) hit = 1
            if (!hit) print "refactored row lost its rename: " rid " (no " NWS[rid] " in file)"
        }
        for (m = 1; m <= miss; m++) print "anchor-missing (" c "/" NEED[ORD[i]] ") " ROW[ORD[i]]
    }
}' "$MANIFEST" > "$W/b" || echo "awk-failed (b) rc=$?" >> "$W/b"
vb=$(wc -l < "$W/b" | tr -d ' ')

# (c) LEAVE positives. Every *.sh basename the manifest saw (path rows whose last
#     segment holds the token) must still exist under that basename: at its
#     renamed directory once skills/handoffx/ exists, else at its current path.
#     The adjacency trap is asserted by name too. Schema constants unchanged.
NEWSKILL="$ROOT/skills/handoffx"
awk -F: '$2 == "" { b = $1; sub(/.*\//, "", b); if (tolower(b) ~ /handoff/ && b ~ /\.sh$/) print $1 }' \
    "$MANIFEST" > "$W/l1"; l1rc=$?
nl1=$(wc -l < "$W/l1" | tr -d ' ')
: > "$W/c"
[ "$l1rc" -eq 0 ] || echo "awk-failed (c) rc=$l1rc" >> "$W/c"
[ "$nl1" -gt 0 ] || echo "no-L1-basenames-in-manifest (vacuous)" >> "$W/c"
while IFS= read -r p; do
    np=$(awk -F'\t' -v p="$p" '$1 == p { print $2 }' "$W/pathmap") || echo "awk-failed (c) rc=$?" >> "$W/c"
    [ -n "$np" ] || np="$p"
    if [ -f "$ROOT/$np" ]; then continue; fi
    if [ ! -d "$NEWSKILL" ] && [ -f "$ROOT/$p" ]; then continue; fi
    echo "leave-missing $np (from $p)" >> "$W/c"
done < "$W/l1"
if [ -d "$NEWSKILL" ]; then trap_pf="$NEWSKILL/scripts/handoff-postflight.sh"
else trap_pf="$ROOT/skills/handoff/scripts/handoff-postflight.sh"; fi
[ -f "$trap_pf" ] || echo "adjacency-trap-missing ${trap_pf#"$ROOT"/}" >> "$W/c"
SCHEMA="$ROOT/scripts/lib/handoff-schema.sh"
for kv in 'HX_MAIN_FILE="HANDOFF.md"' 'HX_LOGS_DIR="Handoff_Logs"' \
          'HX_DEC_DIR="Handoff_Decisions"' 'HX_GOTCHAS_FILE="GOTCHAS.md"'; do
    grep -qxF -- "$kv" "$SCHEMA" 2>/dev/null || echo "schema-constant-changed $kv" >> "$W/c"
done
vc=$(wc -l < "$W/c" | tr -d ' ')

# (d) exception ratchet: row count == frozen header value, and every row still
#     hits an unrenamed token (handoff not followed by x/X) within ±5 lines of
#     its line, in its file or that file's renamed path.
frozen=$(sed -n 's/^# frozen-rows: \([0-9][0-9]*\)$/\1/p' "$EXC" | head -1)
nexc=$(wc -l < "$W/exc" | tr -d ' ')
: > "$W/d"
if [ -z "$frozen" ] || [ "$frozen" -eq 0 ]; then echo "frozen-rows header missing/zero" >> "$W/d"
elif [ "$nexc" -ne "$frozen" ]; then echo "row-count $nexc != frozen $frozen" >> "$W/d"; fi
awk -v ROOT="$ROOT" -v MAP="$W/pathmap" '
BEGIN { while ((getline l < MAP) > 0) { split(l, a, "\t"); NEWP[a[1]] = a[2] } }
{
    n = split($0, h, ":")
    if (n < 4 || h[2] !~ /^[0-9]+$/ || h[3] !~ /^(L[0-9]+|R[0-9])$/ || h[4] == "") { print "malformed " $0; next }
    p = h[1]
    if (!(p in SEEN)) {
        SEEN[p] = 1; f = ROOT "/" p
        if ((getline t < f) <= 0 && (p in NEWP)) f = ROOT "/" NEWP[p]
        close(f); c = 0
        while ((getline t < f) > 0) { c++; HIT[p, c] = (tolower(t) ~ /handoff([^x]|$)/) }
        close(f); NLN[p] = c
    }
    ok = 0
    for (j = h[2] - 5; j <= h[2] + 5; j++) if (j >= 1 && j <= NLN[p] && HIT[p, j]) ok = 1
    if (!ok) print "no-token-near " $0
}' "$W/exc" >> "$W/d" || echo "awk-failed (d) rc=$?" >> "$W/d"
# refactored.txt ratchet: count == frozen header (0 allowed: an empty
# tolerance list is legitimate), every row names a manifest R content row.
rfrozen=$(sed -n 's/^# frozen-rows: \([0-9][0-9]*\)$/\1/p' "$REF" | head -1)
nref=$(wc -l < "$W/ref" | tr -d ' ')
if [ -z "$rfrozen" ]; then echo "refactored: frozen-rows header missing" >> "$W/d"
elif [ "$nref" -ne "$rfrozen" ]; then echo "refactored: row-count $nref != frozen $rfrozen" >> "$W/d"; fi
awk -F: 'NR == FNR { if ($4 ~ /^R/) K[$1 ":" $2 ":" $3 ":" $4] = 1; next }
         { if (NF < 5 || $5 == "" || !(($1 ":" $2 ":" $3 ":" $4) in K)) print "refactored: not a manifest R row (or no reason): " $0 }' \
    "$MANIFEST" "$W/ref" >> "$W/d" || echo "awk-failed (d) rc=$?" >> "$W/d"
# relocations ratchet: count == frozen header (0 allowed, like refactored.txt).
lfrozen=$(sed -n 's/^# frozen-rows: \([0-9][0-9]*\)$/\1/p' "$RELOC" | head -1)
nreloc=$(grep -v '^#' "$RELOC" | grep -vc '^$')
if [ -z "$lfrozen" ]; then echo "relocations: frozen-rows header missing" >> "$W/d"
elif [ "$nreloc" -ne "$lfrozen" ]; then echo "relocations: row-count $nreloc != frozen $lfrozen" >> "$W/d"; fi
# per row: a count alone accepts `old→tools/` or `old→`, which (b)/(d) then hand to
# getline as a directory — macOS awk dies there and the anchor checks never run.
while IFS= read -r row; do
    case "$row" in *→*) ;; *) echo "relocations: row has no →: $row" >> "$W/d"; continue ;; esac
    old="${row%%→*}"; new="${row#*→}"
    if ! awk -F: -v p="$old" '$1 == p { f = 1; exit } END { exit !f }' "$MANIFEST"; then
        echo "relocations: old path not in the frozen manifest: $row" >> "$W/d"
    fi
    # new must be a file; the only other legal state is "not moved yet" (old still a
    # file, new absent) — the bguard's frozen-tree simulation predates the move
    if [ -z "$new" ] || [ "${new%/}" != "$new" ] \
       || { [ ! -f "$ROOT/$new" ] && { [ ! -f "$ROOT/$old" ] || [ -e "$ROOT/$new" ]; }; }; then
        echo "relocations: new path is not a file: $row" >> "$W/d"
    fi
done < <(grep -v '^#' "$RELOC" | grep -v '^$')
vd=$(wc -l < "$W/d" | tr -d ' ')

# (e) nothing unclassified in the fresh inventory.
grep ':UNCLASSIFIED:' "$W/fresh" > "$W/e"
ve=$(wc -l < "$W/e" | tr -d ' ')

# (f) exact OLD shim basenames absent from the renamed shim dir (skip pre-rename).
: > "$W/f"
SHIMS="$NEWSKILL/command-shims"
if [ -d "$SHIMS" ]; then
    for s in handoff.md handoff-recall.md handoff-tidy.md handoff-memory.md handoff-init.md hand-off.md; do
        [ -e "$SHIMS/$s" ] && echo "old-shim-present $s" >> "$W/f"
    done
    fnote=""
else fnote=" (skipped: pre-rename)"; fi
vf=$(wc -l < "$W/f" | tr -d ' ')

diag "(a) R occurrences not excepted" "$W/a"
diag "(b) new token missing at anchor" "$W/b"
diag "(c) LEAVE positives" "$W/c"
diag "(d) exception ratchet" "$W/d"
diag "(e) UNCLASSIFIED" "$W/e"
diag "(f) old shim basenames" "$W/f"
assert_exit "(a) R occurrences not excepted = 0 [$va]" 0 "$([ "$va" -eq 0 ] && echo 0 || echo 1)"
assert_exit "(b) every manifest R row has its new token at its anchor [$vb missing of $mR R rows]" 0 "$([ "$vb" -eq 0 ] && echo 0 || echo 1)"
assert_exit "(c) LEAVE positives: $nl1 *.sh basenames + adjacency trap + 4 schema constants [$vc]" 0 "$([ "$vc" -eq 0 ] && echo 0 || echo 1)"
assert_exit "(d) ratchets: exceptions $nexc == frozen ${frozen:-?} all still hit; refactored $nref == frozen ${rfrozen:-?} all manifest R rows; relocations $nreloc == frozen ${lfrozen:-?} [$vd]" 0 "$([ "$vd" -eq 0 ] && echo 0 || echo 1)"
assert_exit "(e) UNCLASSIFIED = 0 [$ve]" 0 "$([ "$ve" -eq 0 ] && echo 0 || echo 1)"
assert_exit "(f) old shim basenames absent$fnote [$vf]" 0 "$([ "$vf" -eq 0 ] && echo 0 || echo 1)"

role_counts() {
    awk -F: '{ r = ($2 == "") ? "path:" $3 : $4; c[r]++ } END { for (r in c) printf "%s=%d ", r, c[r] }' "$1" \
        | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' '
}
echo "  ── frozen manifest roles: $(role_counts "$MANIFEST")"
echo "  ── fresh inventory roles: $(role_counts "$W/fresh")"

violations=$((va + vb + vc + vd + ve + vf))
if [ "$violations" -eq 0 ]; then
    echo "✅ manifest: rename scope complete (a-f clean)"
    exit 0
fi
echo "❌ manifest: $violations violation(s) — a=$va b=$vb c=$vc d=$vd e=$ve f=$vf"
exit 1
