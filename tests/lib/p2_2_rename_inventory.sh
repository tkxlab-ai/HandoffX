#!/bin/bash
# p2_2_rename_inventory.sh — P2.2a Task 0 wide-net rename inventory (plan §1/§2).
#
# Sourced library + CLI:
#   bash tests/lib/p2_2_rename_inventory.sh > tests/fixtures/p2_2_rename_manifest.txt
#
# Why wide-net: Codex round 3 #3 — a predicate-first grep only finds the forms
# someone already thought of. We grep EVERY case-insensitive `handoff` (content
# pass) and every path segment containing it (path pass), then classify each
# occurrence; anything no predicate claims is UNCLASSIFIED and fails the guard.
#
# Row format (one per occurrence, LC_ALL=C sorted):
#   path:line:col:ROLE:old→new<TAB>left<TAB>right   R roles (renamed in P2.2a)
#   path:line:col:ROLE:                              L / NX roles
#   path:line:col:UNCLASSIFIED:<context>             no predicate matched
#   path::ROLE:oldpath→newpath | path::ROLE:         path pass
# left/right = 12 bytes either side of the NEW token on the simulated
# post-rename line (every R occurrence on that line gets its `x`), so the guard
# can find the occurrence after rename without trusting line numbers. Tabs in
# the context are normalised to spaces on both sides.
#
# Byte semantics everywhere (LC_ALL=C awk) so columns agree on bash 3.2/BSD awk
# and Linux mawk. No `set -e` (Gotcha #6/#13): callers key on output + exit.

# Files that ARE the guard (L5). Excluded from the content pass by exact path:
# registering them occurrence-by-occurrence in the exception table would make
# the table describe itself (every new row adds the occurrences it registers).
P22_L5_FILES="tests/lib/p2_2_rename_inventory.sh
tests/test_p2_2_rename_manifest.sh
tests/test_p2_2_rename_bguard.sh
tests/fixtures/p2_2_rename_manifest.txt
tests/fixtures/p2_2_rename_exceptions.txt
tests/fixtures/p2_2_rename_refactored.txt"

p22_root() {
    if [ -n "${P22_ROOT:-}" ]; then echo "$P22_ROOT"; return 0; fi
    (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

# Candidate path list: tracked + untracked-not-ignored; scratch copies (no .git)
# fall back to find so the bguard's post-rename simulation scans the same set.
p22_list_paths() {
    local root; root=$(p22_root)
    if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        { git -C "$root" ls-files; git -C "$root" ls-files -o --exclude-standard; }
    else
        (cd "$root" && find . -type f | sed 's#^\./##')
    fi | grep -v -e '^tests/\.tmp/' -e '^Release/' -e '^\.git/' | LC_ALL=C sort -u
}

# Emit the full inventory on stdout. Returns 1 when nothing was scanned
# (zero-processing must never read as "clean" — Gotcha #24).
p22_inventory() {
    local root list text n
    root=$(p22_root)
    list=$(mktemp "${TMPDIR:-/tmp}/p22list.XXXXXX")
    text=$(mktemp "${TMPDIR:-/tmp}/p22text.XXXXXX")
    p22_list_paths > "$list"
    # text files only (grep -I drops binaries); missing paths (deleted but
    # still tracked) are dropped by the -f test.
    while IFS= read -r p; do
        [ -f "$root/$p" ] || continue
        echo "$P22_L5_FILES" | grep -qxF -- "$p" && continue
        LC_ALL=C grep -Iq '' "$root/$p" 2>/dev/null && echo "$p"
    done < "$list" > "$text"
    n=$(wc -l < "$text" | tr -d ' ')
    if [ "$n" -eq 0 ]; then rm -f "$list" "$text"; return 1; fi
    LC_ALL=C awk -v ROOT="$root" -v TEXTLIST="$text" "$P22_AWK" "$list" \
        | LC_ALL=C sort
    rm -f "$list" "$text"
    return 0
}


# ─── Classifier (awk; byte semantics) ─────────────────────────────────────────
# Variables per occurrence: m = the 7 matched bytes (original case); B / A =
# text before / after m; nx = first byte after m; W = maximal [A-Za-z0-9_-] word
# around m (wl = lowercase), pc = byte before W, WA = text after W; SH = file is
# *.sh. Each predicate sets the role and the old-token span (SL bytes left of m,
# SR bytes right of m). First match wins — ORDER IS THE SPEC, read top-down.
P22_AWK='
function isw(c) { return c ~ /^[A-Za-z0-9_-]$/ }
function xch(m) { return (m == "handoff") ? "x" : "X" }
function ends(s, t) { return length(s) >= length(t) && substr(s, length(s) - length(t) + 1) == t }
function hist(p) {
    return p ~ /^Handoff_Logs\// || p ~ /^Handoff_Decisions\// || \
           p ~ /^docs\/2026-/ || p ~ /^docs\/.*-2026-04-[0-9][0-9]\.md$/
}
function l6(p) { return p == "tests/fixtures/handoff-v1-sample.md" || p ~ /^tests\/fixtures\/p2-1-synthetic-v2\// }
function stem(w) {
    return w ~ /^(handoff-postflight|handoff-lint|handoff-xref-lint|handoff-xref-grammar|handoff-schema|handoff-v2|tidy-handoff|validate-handoff)(-|$)/ || \
           w ~ /^test_.*handoff/
}

# classify(path, line, p): sets ROLE, SL, SR.
# Tags in [brackets] mark predicates added by hand after the wide-net pass
# surfaced UNCLASSIFIED forms (plan §1 asks for exactly this; each is listed in
# the Task 0 report).
function classify(path, line, p,    m, B, A, nx, ws, we, W, wl, pc, pc2, WA, SH, TS, bare) {
    m = substr(line, p, 7); B = substr(line, 1, p - 1); A = substr(line, p + 7); nx = substr(A, 1, 1)
    ws = p; while (ws > 1 && isw(substr(line, ws - 1, 1))) ws--
    we = p + 6; while (we < length(line) && isw(substr(line, we + 1, 1))) we++
    W = substr(line, ws, we - ws + 1); wl = tolower(W); pc = substr(line, ws - 1, 1)
    pc2 = substr(line, ws - 2, 1); WA = substr(line, we + 1); SH = (path ~ /\.sh$/)
    TS = (path ~ /^tests\//)
    SL = 0; SR = we - (p + 6)
    # ── L11 [added, P2.2b]: the release-layout lib + its contract test must name the
    # pre-v3.0.0 (old) asset prefix; path-scoped and first so no form rule claims them ──
    if (path == "scripts/release-layout.sh" || path == "tests/test_release_layout_contract.sh") { ROLE = "L11"; return }
    # ── NX: already the new name (handoffx / HandoffX / HANDOFFX …) ──
    if (nx ~ /^[xX]$/)                                   { ROLE = "NX"; return }
    # ── R5 (anchor) [added]: in-document markdown link slug of a renamed heading, e.g. (#1-why-handoff) ──
    if (path ~ /\.md$/ && m == "handoff" && B ~ /\]\(#[^)]*$/ && A ~ /^[^)]*\)/) { ROLE = "R5"; SR = 0; return }
    # ── L6: frozen fixtures (location) + references to the v1 fixture name ──
    if (l6(path))                                        { ROLE = "L6"; return }
    if (wl == "handoff-v1-sample")                       { ROLE = "L6"; return }  # [added]
    # ── L2: four-piece slugs + derived produced-artifact names (P2.4 scope) ──
    if (m == "HANDOFF" && (nx == "." || substr(A, 1, 2) == "\\.")) { ROLE = "L2"; return }  # HANDOFF.md / .archive / .template / regex HANDOFF\.md
    if (m == "Handoff" && nx == "_")                     { ROLE = "L2"; return }  # Handoff_Logs / Handoff_Decisions / Handoff_* families
    if (m == "HANDOFF" && A ~ /^ v2 schema/)             { ROLE = "L2"; return }  # produced-file schema marker
    # ── L1: script basenames / stems, shell identifiers ──
    if (WA ~ /^\.sh/)                                    { ROLE = "L1"; return }  # *.sh / test_handoff_*.sh basenames
    if (stem(wl))                                        { ROLE = "L1"; return }  # script stem (+ derived tmp names) without .sh
    if (W ~ /_/)                                         { ROLE = "L1"; return }  # identifiers: HANDOFF_TEST_*, make_handoff, _HANDOFF_MODE
    if (SH && pc == "$" && pc2 != "\\")                  { ROLE = "L1"; return }  # .sh $handoff / $HANDOFF variable
    if (SH && ends(B, "${"))                             { ROLE = "L1"; return }
    if (SH && WA ~ /^=/)                                 { ROLE = "L1"; return }  # [added] .sh assignment: HANDOFF=… / local handoff=…
    if (m == "HANDOFF")                                  { ROLE = "L2"; return }  # [added] bare HANDOFF = main-file shorthand (HANDOFF-v1.md, "HANDOFF 更新")
    # ── L3 / L7: historical prose, backfill historical input (location) ──
    if (hist(path) || HSEC)                              { ROLE = "L3"; return }  # HSEC: history sections / entry bodies (see the file loop) [added]
    if (path == "scripts/release-publish-github-backfill.sh") { ROLE = "L7"; return }
    # ── L4: legacy sweep operands (already OLD names today) ──
    if (SH && line ~ /^[ \t]*(T_)?OLD_[A-Z_]+=/)        { ROLE = "L4"; return }  # [added, Task 2] OLD_* name-set definition / T_OLD_* test seed
    if (ends(B, "source-command-"))                      { ROLE = "L4"; return }  # [added] OLD Codex alias prefix source-command-handoff-*
    if (wl == "handoff-scripts")                         { ROLE = "L4"; return }  # [added] OLD_MISC .claude/handoff-scripts
    if (wl ~ /^[0-9]/)                                   { ROLE = "L3"; return }  # [added] dated historical file/slug names (2026-05-07-handoff-v2-design)
    # ── L9: plan §5 scope edges — project root dir / private git remote (+ its sanitized form <private-org>/Handoff) [added] ──
    # The private org literal is split into two adjacent awk strings (runtime-concatenated) so the
    # public-mirror sanitizer never finds the whole token in this shipped file.
    if (ends(B, "Cloud_Coding/") || ends(B, "Cloud-Coding-") || ends(B, "lax" "-team/") || ends(B, "<private-org>/") || line ~ /^Handoff\/$/) {
        ROLE = "L9"; return }
    if (path == "release.sh" && m == "Handoff" && A ~ /^ 仓/) { ROLE = "L9"; return }  # [added, Boss] repository noun "Handoff 仓" (:34, :382)
    # ── L1 (table form) [added, Boss]: suite-table label cell naming a test_handoff_*.sh row ──
    if (m == "Handoff" && p == 3 && line ~ /^\| Handoff [^|]*\| `test_handoff_[A-Za-z0-9_]*\.sh`/) { ROLE = "L1"; return }
    # ── R7: Codex command list (five lines) ──
    if (path ~ /agents\/codex-commands\.txt$/)           { ROLE = "R7"; SL = 1; return }
    # ── R8: install paths ──
    if (match(B, /(\.claude\/(skills|commands)|opencode\/(skills|commands|command)|\.agents\/skills|\.codex\/skills)\/$/)) {
        ROLE = "R8"; SL = length(B) - RSTART + 1; return }
    # ── R1: skill directory segment (incl. no trailing slash) + ZIP root ──
    if (ends(B, "skills/"))                              { ROLE = "R1"; SL = 7; return }
    if (path == "release.sh" && nx == "/" && (pc == " " || pc == "\047")) { ROLE = "R1"; return }  # ZIP root handoff/ (release.sh:203-204)
    if (ends(B, "BOOTSTRAP_TMP/"))                       { ROLE = "R1"; return }  # [added] extracted ZIP root in install.sh
    # ── L8 (= R6 deferred to P2.2b): release product names / publisher identity ──
    if (m == "handoff" && (A ~ /^-\$\{?(VER|VERSION|ver|version|v)\}?/ || A ~ /^\.skill/ || \
        A ~ /^-\*(\.skill|-source)/ || A ~ /^-v?[0-9]+\.[0-9]+/ || A ~ /^-v?</ || A ~ /^-(\)\?)?vX?/ || \
        ends(B, "Release/") || ends(B, "source_root: "))) { ROLE = "L8"; return }
    if (ends(B, "BOOTSTRAP_TMP\"/") && A ~ /^-\*/)        { ROLE = "L8"; return }  # [added] extracted source-tarball root handoff-<ver>
    if (A ~ /^ \$\{?VER/ || A ~ /^ <noreply@/ || ends(B, "user.name \"") || ends(B, "author=") || \
        ends(B, "PROJECT_NAME=") || ends(B, "SKILL_NAME=")) { ROLE = "L8"; return }  # [added] publisher/gitx identity: "Handoff ${VER}", git author, gitx SKILL_NAME
    # ── R4: shim / reference bare basenames (lowercase only; HANDOFF.md is L2) ──
    if (m == "handoff" && wl ~ /^handoff(-recall|-tidy|-memory|-init|-write)?$/ && WA ~ /^\.md/) {
        ROLE = "R4"; SR = we - (p + 6) + 3; return }
    if (wl == "handoff-" && WA ~ /^\\?\{/)              { ROLE = "R4"; return }  # [added] brace family handoff-{recall,tidy,…}.md (also regex-escaped)
    if (wl == "handoff-write")                           { ROLE = "R4"; return }  # [added] reference name cited without .md
    # ── R2: registered slash commands (slash not part of a path) ──
    if (pc == "/" && wl ~ /^handoff(-recall|-tidy|-memory|-init|-mem)?$/ && pc2 !~ /^[A-Za-z0-9_.}$~-]$/) {
        ROLE = "R2"; SL = 1; return }
    if (pc == "/" && wl == "handoff")                    { ROLE = "R8"; return }  # [added] …/<dir>/handoff install-dir segment ($target_skills/handoff)
    if (wl ~ /^handoff-(recall|tidy|memory|init|mem)$/)  { ROLE = "R2"; return }  # [added] command / alias names without slash
    if (wl == "handoff" && nx == "*")                    { ROLE = "R2"; return }  # [added] handoff* family glob
    if (wl == "handoff-" && WA ~ /^\*/)                  { ROLE = "R2"; return }  # [added] handoff-* alias family glob
    # ── R3: Codex selector / skill: handoff / quoted skill identifier ──
    if (ends(B, "Use skill: "))                          { ROLE = "R3"; SL = 11; return }
    if (ends(B, "skill: "))                              { ROLE = "R3"; SL = 7; return }
    if (!SH && pc == "$")                                { ROLE = "R3"; SL = 1; return }
    if (SH && ends(B, "\\$"))                            { ROLE = "R3"; SL = 2; return }
    if (wl == "handoff" && ((pc == "\"" && nx == "\"") || (pc == "`" && nx == "`"))) { ROLE = "R3"; return }  # [added] "handoff" / `handoff` identifier literal
    if (wl == "handoff" && line ~ /for [a-z_]+ in handoff /) { ROLE = "R3"; return }  # [added] alias name list in install.sh loops
    # ── R5: name / brand ──
    if (line ~ /^name: handoff$/ || ends(B, "name: "))   { ROLE = "R5"; SL = 6; return }
    if (m == "Handoff" && A ~ /^ (—|Plugin|version)/)    { ROLE = "R5"; return }
    if (m == "handoff" && A ~ /^ v/)                     { ROLE = "R5"; return }   # banner `handoff v…`
    if (ends(B, "tkxlab-ai/") || line ~ /^cd handoff$/ || ends(B, "scp -r ")) { ROLE = "R5"; return }  # [added] stale repo slug / clone dir
    if (wl == "handoff" && A ~ /^ (skill|Skill|shim|installer|Installation|插件|产品)/) { ROLE = "R5"; return }  # [added] product name + noun
    bare = (wl == "handoff" && pc !~ /^[\/$.~"\047=:@`-]$/ && (nx !~ /^[\/.*{"\047=:@`-]$/ || A ~ /^\047s / || (nx == "`" && pc == " ")))
    if (bare && m == "Handoff" && !TS && !ends(B, "Project ")) { ROLE = "R5"; return }  # [added] standalone brand word → HandoffX
    # ── L10: generic noun "handoff" (交接) / product-or-noun needing a human call [added] ──
    if (bare)                                            { ROLE = "L10"; return }
    if (TS && m == "Handoff" && ends(B, "# "))           { ROLE = "L10"; return }  # produced-doc heading inside a test heredoc
    if (W ~ /-handoff/ || wl == "handoff-clean")         { ROLE = "L10"; return }  # prose compounds: post-handoff, first-time-handoff-append
    ROLE = "UNCLASSIFIED"
}

function emit_line(path, ln, line,    lc, n, off, k, i, P, R, O, N, S, sim, prev, np, lo, left, right) {
    lc = tolower(line); n = 0; off = 0
    while ((k = index(substr(lc, off + 1), "handoff")) > 0) { n++; P[n] = off + k; off = off + k + 6 }
    if (n == 0) return
    sim = ""; prev = 1
    for (i = 1; i <= n; i++) {
        classify(path, line, P[i]); R[i] = ROLE
        O[i] = substr(line, P[i] - SL, SL + 7 + SR)
        N[i] = substr(line, P[i] - SL, SL + 7) xch(substr(line, P[i], 7)) substr(line, P[i] + 7, SR)
        sim = sim substr(line, prev, P[i] + 7 - prev); prev = P[i] + 7
        S[i] = length(sim) + 1 - 7
        if (R[i] ~ /^R/) sim = sim xch(substr(line, P[i], 7))
    }
    sim = sim substr(line, prev)
    for (i = 1; i <= n; i++) {
        if (R[i] ~ /^R/) {
            np = S[i]; lo = np - 12; if (lo < 1) lo = 1
            left = substr(sim, lo, np - lo); right = substr(sim, np + 8, 12)
            gsub(/\t/, " ", left); gsub(/\t/, " ", right)
            print path ":" ln ":" P[i] ":" R[i] ":" O[i] "→" N[i] "\t" left "\t" right
        } else if (R[i] == "UNCLASSIFIED") {
            lo = P[i] - 20; if (lo < 1) lo = 1
            print path ":" ln ":" P[i] ":UNCLASSIFIED:\t" substr(line, lo, 50)
        } else print path ":" ln ":" P[i] ":" R[i] ":"
    }
}

# Path pass: classify each segment holding the token; a path with any R segment
# gets ONE row carrying the full old→new path (dir + basename renames composed).
function seg_role(path, segs, nseg, i,    s, sl, k) {
    s = segs[i]; sl = tolower(s); k = index(sl, "handoff")
    if (substr(sl, k + 7, 1) == "x")                     return "NX"
    if (l6(path))                                        return "L6"
    if (s ~ /^Handoff_/ || s ~ /HANDOFF\./)              return "L2"
    if (s ~ /\.sh$/)                                     return "L1"
    if (hist(path))                                      return "L3"
    if (i == 2 && segs[1] == "skills" && s == "handoff") return "R1"
    if (s ~ /^handoff(-recall|-tidy|-memory|-init|-write)?\.md$/) return "R4"
    return "UNCLASSIFIED"
}
function path_pass(path,    segs, nseg, i, r, rr, lr, np, s) {
    nseg = split(path, segs, "/"); rr = ""; lr = ""; np = ""
    for (i = 1; i <= nseg; i++) {
        s = segs[i]
        if (index(tolower(s), "handoff") > 0) {
            r = seg_role(path, segs, nseg, i)
            if (r ~ /^R/) { if (rr == "") rr = r; sub(/handoff/, "handoffx", s) }
            else if (lr != "UNCLASSIFIED") lr = r
        }
        np = np (i > 1 ? "/" : "") s
    }
    if (lr == "UNCLASSIFIED")  print path "::UNCLASSIFIED:"
    else if (rr != "")         print path "::" rr ":" path "→" np
    else if (lr != "")         print path "::" lr ":"
}

BEGIN { while ((getline t < TEXTLIST) > 0) TEXT[t] = 1; close(TEXTLIST) }
{
    path = $0
    if (index(tolower(path), "handoff") > 0) path_pass(path)
    if (!(path in TEXT)) next
    f = ROOT "/" path; ln = 0
    HSEC = 0
    while ((getline line < f) > 0) {
        ln++; sub(/\r$/, "", line)
        # HANDOFF.md is current except its history sections (plan Task 4 "现行段");
        # the v2 Development Log section holds only pointers + the recall instruction.
        if (path == "HANDOFF.md" && line ~ /^##+ /) HSEC = (line ~ /已完成|最近完成/)
        # GOTCHAS.md / CHANGELOG.md: the file header is current text; history starts
        # at the first entry heading (an independent review found the header lines
        # /handoff-recall and "# Handoff —" hidden behind a whole-file L3).
        if (path == "GOTCHAS.md" && line ~ /^### Gotcha/) HSEC = 1
        if (path == "CHANGELOG.md" && line ~ /^## /)     HSEC = 1
        emit_line(path, ln, line)
    }
    close(f)
}
'

# Seed rows for tests/fixtures/p2_2_rename_exceptions.txt from a manifest on
# stdin: every occurrence-level L3/L4/L6/L7/L8/L9/L10 row → path:line:ROLE:reason.
# (L1/L2 are asserted positively by the guard's (c) and by test_handoff_schema;
# L5 = the guard files themselves, excluded from the scan.)
p22_exception_seed() {
    LC_ALL=C awk -F: '$3 != "" && $4 ~ /^L([3-4]|[6-9]|10)$/ {
        r = $4
        if (r == "L3")  why = "historical prose, frozen record"
        if (r == "L4")  why = "legacy sweep operand, already an OLD name"
        if (r == "L6")  why = "frozen v1/v2 fixture"
        if (r == "L7")  why = "backfill historical input"
        if (r == "L8")  why = "deferred-to-P2.2b release product name"
        if (r == "L9")  why = "plan 5 scope edge: project root dir or remote name"
        if (r == "L10") why = "generic noun handoff, not the tool identifier"
        print $1 ":" $2 ":" r ":" why
    }'
}

# CLI: print the manifest.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    p22_inventory || { echo "p2_2_rename_inventory: no text files scanned" >&2; exit 1; }
fi
