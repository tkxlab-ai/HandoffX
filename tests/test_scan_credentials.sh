#!/bin/bash
source "$(dirname "$0")/common.sh"
SCAN="$SCRIPTS_DIR/scan-credentials.sh"

run_case() {
    local name="$1" fixture="$2" expected_exit="$3"
    local actual_exit=0
    "$SCAN" "$FIXTURES_DIR/$fixture" > /dev/null 2>&1 || actual_exit=$?
    assert_exit "$name" "$expected_exit" "$actual_exit"
}

# clean / whitelisted should exit 0
run_case "clean text"             clean.md         0
run_case "env var reference only" env_ref.md       0
run_case "vault reference only"   vault_ref.md     0
run_case "placeholder only"       placeholder.md   0

# real credential patterns should exit 1
run_case "OpenAI project key"     openai_key.md          1
run_case "Anthropic API key"      anthropic_key.md       1
run_case "GitHub personal token"  github_token.md        1
run_case "GitHub OAuth token"     github_oauth_token.md  1
run_case "GitHub server token"    github_server_token.md 1
run_case "AWS access key"         aws_key.md             1
run_case "private key header"     private_key.md         1
run_case "Slack bot token"        slack_token.md         1
run_case "Supabase service role"  supabase_key.md        1

# output labels are correct
out=$("$SCAN" "$FIXTURES_DIR/openai_key.md" 2>&1 || true)
assert_contains "reports OpenAI label"        "$out" "OpenAI"

out=$("$SCAN" "$FIXTURES_DIR/github_oauth_token.md" 2>&1 || true)
assert_contains "reports GitHub OAuth label"  "$out" "GitHub OAuth"

out=$("$SCAN" "$FIXTURES_DIR/github_server_token.md" 2>&1 || true)
assert_contains "reports GitHub server label" "$out" "GitHub server"

# stdin mode
out_stdin=$(cat "$FIXTURES_DIR/github_token.md" | "$SCAN" 2>&1 || true)
assert_contains "stdin mode works"            "$out_stdin" "GitHub"
# empty stdin (cron/CI: `scan-credentials.sh </dev/null`, or `cat missing | scan`)
# used to scan "" and exit 0 — never touching ./$HX_MAIN_FILE. Nothing scanned ≠ clean.
out=$("$SCAN" </dev/null 2>&1); ec=$?
assert_exit "empty stdin → exit 2 (nothing scanned is not clean)" 2 "$ec"
# the usage path also exits 2 when cwd has no $HX_MAIN_FILE — pin the branch
assert_contains "empty stdin names the empty-stdin verdict" "$out" "stdin is empty"

run_case "GitHub fine-grained PAT" github_fine_grained_pat.md 1
run_case "HuggingFace token"       huggingface_token.md       1

out=$("$SCAN" "$FIXTURES_DIR/github_fine_grained_pat.md" 2>&1 || true)
assert_contains "reports fine-grained PAT label" "$out" "GitHub fine-grained PAT"

out=$("$SCAN" "$FIXTURES_DIR/huggingface_token.md" 2>&1 || true)
assert_contains "reports HuggingFace label" "$out" "HuggingFace"

# ─── v2 directory mode (H1) ─────────────────────────────────────────────────
SANDBOX=$(mktemp -d)
cat > "$SANDBOX/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
clean main file
EOF
cat > "$SANDBOX/$HX_GOTCHAS_FILE" <<'EOF'
# Known Gotchas
clean
EOF
mkdir -p "$SANDBOX/$HX_LOGS_DIR" "$SANDBOX/$HX_DEC_DIR"
cat > "$SANDBOX/$HX_LOGS_DIR/0001-2026-04-18T2030-init.md" <<'EOF'
---
schema: 2
type: dev-log
---
clean entry
EOF

# Clean v2 project → exit 0
"$SCAN" "$SANDBOX" >/dev/null 2>&1
ec=$?
assert_exit "v2 dir clean → exit 0" 0 "$ec"

# Plant credential in $HX_LOGS_DIR/
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX/$HX_LOGS_DIR/0002-2026-04-19T1000-leaked.md"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in $HX_LOGS_DIR → exit 1" 1 "$ec"
assert_contains "v2 dir reports leak path" "$out" "$HX_LOGS_DIR/0002-"
assert_contains "v2 dir reports leak label" "$out" "OpenAI project key"

# Move leak to GOTCHAS.md
rm -f "$SANDBOX/$HX_LOGS_DIR/0002-2026-04-19T1000-leaked.md"
cat "$FIXTURES_DIR/anthropic_key.md" > "$SANDBOX/$HX_GOTCHAS_FILE"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in GOTCHAS → exit 1" 1 "$ec"
assert_contains "v2 dir reports GOTCHAS path" "$out" "$HX_GOTCHAS_FILE"

# Move leak to $HX_DEC_DIR/
cat > "$SANDBOX/$HX_GOTCHAS_FILE" <<'EOF'
# Known Gotchas
clean again
EOF
cat "$FIXTURES_DIR/github_token.md" > "$SANDBOX/$HX_DEC_DIR/0001-2026-04-19-leaked.md"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in $HX_DEC_DIR → exit 1" 1 "$ec"
assert_contains "v2 dir reports Decisions path" "$out" "$HX_DEC_DIR/0001-"

rm -rf "$SANDBOX"

# C-v2-archive-scan (Codex review #11): scan must walk $HX_LOGS_DIR.archive/<year>/
SANDBOX_AR=$(mktemp -d)
cat > "$SANDBOX_AR/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
clean
EOF
echo "clean" > "$SANDBOX_AR/$HX_GOTCHAS_FILE"
mkdir -p "$SANDBOX_AR/$HX_LOGS_DIR" "$SANDBOX_AR/$HX_DEC_DIR" "$SANDBOX_AR/$HX_LOGS_DIR.archive/2024"
# Plant a credential under the archive subdir
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX_AR/$HX_LOGS_DIR.archive/2024/0001-2024-01-15T1000-leak.md"
out=$("$SCAN" "$SANDBOX_AR" 2>&1)
ec=$?
assert_exit "v2 dir: leak in $HX_LOGS_DIR.archive/<year>/ → exit 1" 1 "$ec"
assert_contains "v2 dir: archive scan reports archive path" "$out" "$HX_LOGS_DIR.archive/2024"
rm -rf "$SANDBOX_AR"

# Non-existent path → usage error (exit 2)
"$SCAN" "/nonexistent/path/xyzzy" >/dev/null 2>&1
ec=$?
assert_exit "missing path → exit 2" 2 "$ec"

# ─── fail-closed on unreadable input (2026-10-29 twin of CRITICAL-B, Gotcha #24) ──
# Dir mode used `find … 2>/dev/null || true` and scan_file used a bare
# `grep -q` whose error exit (2) read as "no match": an unreadable dir or
# entry scanned nothing and still exited 0 — a credential gate posing as
# clean. Unreadable input must exit 2 (cannot scan), never 0.
SANDBOX_UR=$(mktemp -d)
cat > "$SANDBOX_UR/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
clean main file
EOF
printf '# Known Gotchas\nclean\n' > "$SANDBOX_UR/$HX_GOTCHAS_FILE"
mkdir -p "$SANDBOX_UR/$HX_LOGS_DIR" "$SANDBOX_UR/$HX_DEC_DIR"
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX_UR/$HX_LOGS_DIR/0001-2026-04-19T1000-leaked.md"
# baseline: the planted key IS caught, otherwise the controls below prove nothing
"$SCAN" "$SANDBOX_UR" >/dev/null 2>&1; ec=$?
assert_exit "unreadable-fixture baseline: planted key → exit 1" 1 "$ec"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unreadable dir/file controls SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$SANDBOX_UR/$HX_LOGS_DIR"
    out=$("$SCAN" "$SANDBOX_UR" 2>&1); ec=$?
    chmod 755 "$SANDBOX_UR/$HX_LOGS_DIR"
    assert_exit "unreadable $HX_LOGS_DIR/ → exit 2 (not silent clean)" 2 "$ec"
    assert_contains "unreadable dir names itself as unscannable" "$out" "cannot scan"
    chmod 000 "$SANDBOX_UR/$HX_LOGS_DIR/0001-2026-04-19T1000-leaked.md"
    "$SCAN" "$SANDBOX_UR" >/dev/null 2>&1; ec=$?
    assert_exit "unreadable entry inside readable dir → exit 2" 2 "$ec"
    "$SCAN" "$SANDBOX_UR/$HX_LOGS_DIR/0001-2026-04-19T1000-leaked.md" >/dev/null 2>&1; ec=$?
    assert_exit "single-file mode on unreadable file → exit 2" 2 "$ec"
    chmod 644 "$SANDBOX_UR/$HX_LOGS_DIR/0001-2026-04-19T1000-leaked.md"
fi
# Regular file squatting on the dir path (root-immune, no chmod involved).
# Drop the planted key first: a found credential (1) outranks unscannable (2),
# so the squat must be the only signal left.
rm -f "$SANDBOX_UR/$HX_LOGS_DIR/0001-2026-04-19T1000-leaked.md"
rm -rf "$SANDBOX_UR/$HX_DEC_DIR"; echo x > "$SANDBOX_UR/$HX_DEC_DIR"
"$SCAN" "$SANDBOX_UR" >/dev/null 2>&1; ec=$?
assert_exit "$HX_DEC_DIR is a regular file → exit 2" 2 "$ec"
rm -rf "$SANDBOX_UR"

# ─── walker coverage the first review round found missing ───────────────────
# (a) find's own non-zero exit must be captured: the top-level dir is fine but a
#     nested archive year is unreadable. This is the only case that exercises
#     the `if ! found=$(find …)` branch — chmod 000 on the top dir never reaches it.
# (b) a symlinked dir must be descended (find without trailing slash does not),
#     a symlinked entry must be followed (-type f alone drops it), a dangling
#     symlink is not "legitimately missing", and a directory named $HX_MAIN_FILE
#     must propagate scan_file's 2. All four are root-immune.
SANDBOX_SL=$(mktemp -d)
printf '<!-- HANDOFF v2 schema -->\nclean\n' > "$SANDBOX_SL/$HX_MAIN_FILE"
printf '# Known Gotchas\nclean\n' > "$SANDBOX_SL/$HX_GOTCHAS_FILE"
mkdir -p "$SANDBOX_SL/$HX_LOGS_DIR" "$SANDBOX_SL/$HX_DEC_DIR" "$SANDBOX_SL/$HX_LOGS_DIR.archive/2025"
printf -- '---\nschema: 2\ntype: dev-log\n---\nclean\n' > "$SANDBOX_SL/$HX_LOGS_DIR.archive/2025/0001-2025-01-01T0000-old.md"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "walker fixture baseline (clean, with archive year) → exit 0" 0 "$ec"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ unreadable archive-year control SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$SANDBOX_SL/$HX_LOGS_DIR.archive/2025"
    "$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
    chmod 755 "$SANDBOX_SL/$HX_LOGS_DIR.archive/2025"
    assert_exit "unreadable .archive/<year> under readable dir → exit 2 (find rc captured)" 2 "$ec"
fi
# directory named $HX_MAIN_FILE → scan_file returns 2 and dir mode must propagate it
mv "$SANDBOX_SL/$HX_MAIN_FILE" "$SANDBOX_SL/$HX_MAIN_FILE.real"; mkdir "$SANDBOX_SL/$HX_MAIN_FILE"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "$HX_MAIN_FILE is a directory → exit 2" 2 "$ec"
rmdir "$SANDBOX_SL/$HX_MAIN_FILE"; mv "$SANDBOX_SL/$HX_MAIN_FILE.real" "$SANDBOX_SL/$HX_MAIN_FILE"
# dangling symlink where GOTCHAS.md should be → not a legitimate skip
mv "$SANDBOX_SL/$HX_GOTCHAS_FILE" "$SANDBOX_SL/$HX_GOTCHAS_FILE.real"; ln -s /nonexistent/gotchas "$SANDBOX_SL/$HX_GOTCHAS_FILE"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "$HX_GOTCHAS_FILE is a dangling symlink → exit 2" 2 "$ec"
rm "$SANDBOX_SL/$HX_GOTCHAS_FILE"; mv "$SANDBOX_SL/$HX_GOTCHAS_FILE.real" "$SANDBOX_SL/$HX_GOTCHAS_FILE"
# same for a dir slot: the dir loop has its own `[ -L ]`, lock it separately
ln -s /nonexistent/decisions "$SANDBOX_SL/$HX_DEC_DIR.archive"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "$HX_DEC_DIR.archive is a dangling symlink → exit 2" 2 "$ec"
rm "$SANDBOX_SL/$HX_DEC_DIR.archive"
# $HX_LOGS_DIR is a symlink to a real dir that contains a key → must be descended
mv "$SANDBOX_SL/$HX_LOGS_DIR" "$SANDBOX_SL/real_logs"; ln -s real_logs "$SANDBOX_SL/$HX_LOGS_DIR"
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX_SL/real_logs/0002-2026-04-19T1000-leaked.md"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "$HX_LOGS_DIR symlink → real dir with key → exit 1 (descended)" 1 "$ec"
rm "$SANDBOX_SL/$HX_LOGS_DIR"; mv "$SANDBOX_SL/real_logs" "$SANDBOX_SL/$HX_LOGS_DIR"
rm -f "$SANDBOX_SL/$HX_LOGS_DIR/0002-2026-04-19T1000-leaked.md"
# entry is a symlink to a file with a key → must be followed, not dropped by -type f
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX_SL/outside-key.md"
ln -s ../outside-key.md "$SANDBOX_SL/$HX_LOGS_DIR/0003-2026-04-19T1100-link.md"
"$SCAN" "$SANDBOX_SL" >/dev/null 2>&1; ec=$?
assert_exit "entry symlink → file with key → exit 1 (followed)" 1 "$ec"
rm -rf "$SANDBOX_SL"

# ─── W1 (v4.1.1, report 5 HX-01): self-hosted forge token contexts ──────────
# An `Authorization: token <hex40>` header or a `GITEA_TOKEN=<hex40>` line
# pasted into a handoff exited 0: the list only knew vendor prefixes. A bare
# hex40 rule is not an option (every commit SHA would trip it), so the rules
# key on context. Samples are assembled at runtime: this file ships in the
# public tarball, the sanitizer's guard (5) feeds tests/*.sh to itself, and a
# literal hex40 there — or the forge's name, which its privacy gate matches
# case-insensitively in non-.md files — would block the next publish.
H10="0123456789"; HEX40="${H10}abcdef${H10}abcdef01234567"
FG="Git"; FG="${FG}ea"; FGU=$(printf '%s' "$FG" | tr 'a-z' 'A-Z')
W1_POS_HDR="curl -H \"Authorization: token $HEX40\" https://forge.example/api/v1/user"
W1_POS_VAR="${FGU}_TOKEN=$HEX40"
W1_POS_CTX="${FG} api token: \"$HEX40\""
W1_NEG="Authorization: token \$${FGU}_TOKEN
${FGU}_TOKEN=\${${FGU}_TOKEN}
Authorization: token vault://forge/${FG}/token
Authorization: token <your-token>
Authorization: token xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
commit $HEX40
$HEX40 fix: pin the forge release URL
Merge: 1a2b3c4 5d6e7f8"
assert_exit "W1 sample is 40 hex" 40 "${#HEX40}"

ec=0; out=$(printf '%s\n' "$W1_POS_HDR" | "$SCAN" 2>&1) || ec=$?
assert_exit "W1 stdin: Authorization: token <hex40> → exit 1" 1 "$ec"
assert_contains "W1 stdin: names the header rule" "$out" "Authorization header token"
ec=0; out=$(printf '%s\n' "$W1_POS_VAR" | "$SCAN" 2>&1) || ec=$?
assert_exit "W1 stdin: <FORGE>_TOKEN=<hex40> → exit 1" 1 "$ec"
assert_contains "W1 stdin: names the variable rule" "$out" "Forge token variable"
ec=0; out=$(printf '%s\n' "$W1_POS_CTX" | "$SCAN" 2>&1) || ec=$?
assert_exit "W1 stdin: forge-named line with token: \"<hex40>\" → exit 1" 1 "$ec"
assert_contains "W1 stdin: names the forge-line rule" "$out" "Forge-named token"
ec=0; out=$(printf 'Authorization: Bearer %s\n' "$HEX40" | "$SCAN" 2>&1) || ec=$?
assert_exit "W1 stdin: Authorization: Bearer <literal> → exit 1" 1 "$ec"
ec=0; out=$(printf '%s\n' "$W1_NEG" | "$SCAN" 2>&1) || ec=$?
assert_exit "W1 stdin: \$VAR / \${VAR} / vault:// / <placeholder> / xxx / commit SHA / git log → exit 0" 0 "$ec"
assert_not_contains "W1 stdin negatives print no finding" "$out" "detected"

W1_T=$(mktemp -d)
printf '%s\n' "$W1_POS_VAR" > "$W1_T/pos.md"
printf '%s\n' "$W1_NEG" > "$W1_T/neg.md"
ec=0; out=$("$SCAN" "$W1_T/pos.md" 2>&1) || ec=$?
assert_exit "W1 file: <FORGE>_TOKEN=<hex40> → exit 1" 1 "$ec"
assert_contains "W1 file: names rule and path" "$out" "Forge token variable (40-hex) detected in $W1_T/pos.md"
ec=0; "$SCAN" "$W1_T/neg.md" >/dev/null 2>&1 || ec=$?
assert_exit "W1 file: negatives → exit 0" 0 "$ec"

mkdir -p "$W1_T/proj/$HX_LOGS_DIR" "$W1_T/proj/$HX_DEC_DIR"
printf '<!-- HANDOFF v2 schema -->\n%s\n' "$W1_NEG" > "$W1_T/proj/$HX_MAIN_FILE"
printf '# Known Gotchas\nclean\n' > "$W1_T/proj/$HX_GOTCHAS_FILE"
ec=0; "$SCAN" "$W1_T/proj" >/dev/null 2>&1 || ec=$?
assert_exit "W1 dir: negatives in $HX_MAIN_FILE → exit 0" 0 "$ec"
printf '%s\n' "$W1_POS_HDR" > "$W1_T/proj/$HX_LOGS_DIR/0001-2026-11-03T1000-forge.md"
ec=0; out=$("$SCAN" "$W1_T/proj" 2>&1) || ec=$?
assert_exit "W1 dir: header token in $HX_LOGS_DIR → exit 1" 1 "$ec"
assert_contains "W1 dir: names rule and log path" "$out" "Authorization header token detected in $W1_T/proj/$HX_LOGS_DIR/0001-"
rm -rf "$W1_T"

out=$("$SCAN" --help 2>&1)
assert_contains "W1 --help states the coverage boundary" "$out" "只识别上面的模式与表头列；表格外的通用密码语义不检测"
assert_contains "fix1 --help names the table-header heuristic" "$out" "表头启发式"
assert_contains "W1 --help lists the header rule" "$out" "Authorization: token|Bearer"

# ─── fix1 I3 / Codex C9: an x-initial token and the JSON-key form ──────────
# The header rule took any value starting with x/X for an `xxxx` placeholder,
# so a real token that happens to start with x slipped; and the variable rules
# wanted `TOKEN` right before `:`/`=`, so `"…_TOKEN": "<hex40>"` (a settings
# json env block) slipped. Placeholder now = the WHOLE value is x/X . _ -.
XTOK="x${HEX40#?}"; XTOKU="X${HEX40#?}"
I3_POS="Authorization: Bearer $XTOK
authorization: bearer $XTOKU
Authorization: token $XTOKU
Authorization: Token $XTOK"
I3_JSON1="\"${FGU}_TOKEN\": \"$HEX40\""
I3_JSON2="{ \"${FG}\": { \"token\": \"$HEX40\" } }"
I3_NEG="Authorization: Bearer xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Authorization: token XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Authorization: Bearer xxxx-xxxx-xxxx-xxxx-xxxx-xxxx
Authorization: Bearer \${${FGU}_TOKEN}
\"${FGU}_TOKEN\": \"\$${FGU}_TOKEN\"
\"${FGU}_TOKEN\": \"vault://forge/token\"
see https://forge.example/${FG}/commit/$HEX40"
I3_T=$(mktemp -d)
while IFS= read -r l; do
    ec=0; printf '%s\n' "$l" | "$SCAN" >/dev/null 2>&1 || ec=$?
    assert_exit "I3 stdin: x/X-initial token is a hit: ${l%% [xX]*}" 1 "$ec"
done <<EOF
$I3_POS
EOF
ec=0; out=$(printf '%s\n' "$I3_JSON1" | "$SCAN" 2>&1) || ec=$?
assert_exit "I3 stdin: JSON \"<FORGE>_TOKEN\": \"<hex40>\" → exit 1" 1 "$ec"
assert_contains "I3 stdin: JSON form names the variable rule" "$out" "Forge token variable"
ec=0; printf '%s\n' "$I3_JSON2" | "$SCAN" >/dev/null 2>&1 || ec=$?
assert_exit "I3 stdin: forge-named JSON \"token\": \"<hex40>\" → exit 1" 1 "$ec"
printf '%s\n' "$I3_JSON1" > "$I3_T/pos.md"
ec=0; "$SCAN" "$I3_T/pos.md" >/dev/null 2>&1 || ec=$?
assert_exit "I3 file: JSON form → exit 1" 1 "$ec"
mkdir -p "$I3_T/proj/$HX_LOGS_DIR" "$I3_T/proj/$HX_DEC_DIR"
printf '<!-- HANDOFF v2 schema -->\nclean\n' > "$I3_T/proj/$HX_MAIN_FILE"
printf '# Known Gotchas\nclean\n' > "$I3_T/proj/$HX_GOTCHAS_FILE"
printf '%s\n' "$I3_POS" | sed -n 1p > "$I3_T/proj/$HX_LOGS_DIR/0001-2026-11-03T1000-x.md"
ec=0; "$SCAN" "$I3_T/proj" >/dev/null 2>&1 || ec=$?
assert_exit "I3 dir: x-initial header token in $HX_LOGS_DIR → exit 1" 1 "$ec"
ec=0; out=$(printf '%s\n' "$I3_NEG" | "$SCAN" 2>&1) || ec=$?
assert_exit "I3 stdin: whole-value placeholders / \$VAR / vault:// / SHA in a URL → exit 0" 0 "$ec"
assert_not_contains "I3 negatives print no finding" "$out" "detected"
rm -rf "$I3_T"

# ─── fix3 N3: directory mode walked its file list through a here-string; a
# here-string bash cannot write scanned nothing and exited 0. ulimit -f 0
# makes every regular-file write fail (bash 3.2 falls back to /tmp for an
# unusable TMPDIR, so the size cap is the deterministic lever); the
# unwritable-TMPDIR case covers bash versions that honour TMPDIR.
N3_T=$(mktemp -d)
mkdir -p "$N3_T/proj/$HX_LOGS_DIR"
printf '<!-- HANDOFF v2 schema -->\nclean\n' > "$N3_T/proj/$HX_MAIN_FILE"
printf '%s\n' "$W1_POS_HDR" > "$N3_T/proj/$HX_LOGS_DIR/0001-2026-11-03T1000-n3.md"
ec=0; out=$( (trap '' XFSZ; ulimit -f 0; exec bash "$SCAN" "$N3_T/proj") 2>&1) || ec=$?
assert_exit "fix3-N3 dir mode, no file writes possible → the planted log is still scanned (exit 1)" 1 "$ec"
assert_contains "fix3-N3 dir mode, no file writes possible → names the log" "$out" "detected in $N3_T/proj/$HX_LOGS_DIR/0001-"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ fix3-N3 unwritable TMPDIR dir scan SKIPPED (root writes into mode-555 dirs)"
else
    mkdir "$N3_T/ro"; chmod 555 "$N3_T/ro"
    ec=0; TMPDIR="$N3_T/ro" bash "$SCAN" "$N3_T/proj" >/dev/null 2>&1 || ec=$?
    chmod 755 "$N3_T/ro"
    assert_exit "fix3-N3 dir mode, unwritable TMPDIR → exit 1, never 0" 1 "$ec"
fi
rm -rf "$N3_T"

# ─── fix3 N4: the header rule asked for 20 chars AFTER the first
# non-placeholder char, so x+19 / _+19 slipped while a×20 hit. Now: the value
# as a whole is 20+ of [A-Za-z0-9._-], and only a value that is ENTIRELY
# placeholder-shaped is exempt. Values built at runtime.
rep() { local s="" i=0; while [ "$i" -lt "$2" ]; do s="$s$1"; i=$((i+1)); done; printf '%s' "$s"; }
A19=$(rep a 19)
for v in "x$A19" "_$A19" "$(rep a 20)" "$(rep x 21)$A19" "X$A19" ".$A19" "-$A19"; do
    ec=0; printf 'Authorization: Bearer %s\n' "$v" | "$SCAN" >/dev/null 2>&1 || ec=$?
    assert_exit "fix3-N4 header value ${v:0:1}…(${#v} chars) → hit" 1 "$ec"
done
for v in "$(rep x 40)" "$(rep _ 30)" "$(rep X 20)$(rep - 5)" "<token>" "<your-api-token-goes-here>" "\$TOKEN" "\${TOKEN}" "vault://forge/token" "$(rep a 19)"; do
    ec=0; printf 'Authorization: token %s\n' "$v" | "$SCAN" >/dev/null 2>&1 || ec=$?
    assert_exit "fix3-N4 header value '${v:0:12}'(${#v}) → not a hit" 0 "$ec"
done

# ─── fix4: the placeholder filter's sed ran under the caller's locale; BSD
# sed under UTF-8 dies on an invalid byte ("illegal byte sequence") → rc 2 →
# "cannot scan" → postflight refused any handoff with a Latin-1 byte. The
# locale is set explicitly so this reproduces on macOS (GNU sed never failed).
F4_T=$(mktemp -d)
printf 'caf\351 note\n' > "$F4_T/latin1.md"
ec=0; printf 'caf\351 note\n' | LC_ALL=en_US.UTF-8 "$SCAN" >/dev/null 2>&1 || ec=$?
assert_exit "fix4 stdin with a Latin-1 byte, no credential, UTF-8 locale → exit 0" 0 "$ec"
ec=0; LC_ALL=en_US.UTF-8 "$SCAN" "$F4_T/latin1.md" >/dev/null 2>&1 || ec=$?
assert_exit "fix4 file with a Latin-1 byte, no credential, UTF-8 locale → exit 0" 0 "$ec"
rm -rf "$F4_T"

# ─── fix5 R4: the "scanned == found" backstop, driven directly. The test-only
# hook HANDOFFX_TEST_SCAN_STOP_AFTER=<n> ends the per-file loop after n files,
# the shape of a reader that dies early; fewer statuses than files must refuse.
R4_T=$(mktemp -d)
mkdir -p "$R4_T/proj/$HX_LOGS_DIR"
printf '<!-- HANDOFF v2 schema -->\nclean\n' > "$R4_T/proj/$HX_MAIN_FILE"
printf 'clean\n' > "$R4_T/proj/$HX_LOGS_DIR/0001-2026-11-03T1000-a.md"
printf 'clean\n' > "$R4_T/proj/$HX_LOGS_DIR/0002-2026-11-03T1001-b.md"
ec=0; "$SCAN" "$R4_T/proj" >/dev/null 2>&1 || ec=$?
assert_exit "fix5-R4 control: clean dir → exit 0" 0 "$ec"
ec=0; out=$(HANDOFFX_TEST_SCAN_STOP_AFTER=1 "$SCAN" "$R4_T/proj" 2>&1) || ec=$?
assert_exit "fix5-R4 reader stops after 1 of 2 files → exit 2" 2 "$ec"
assert_contains "fix5-R4 names the shortfall" "$out" "scanned fewer files than found"
rm -rf "$R4_T"

# ─── v4.2.0 ④ table-header heuristic: a fleet table with a 密码 column walked
# past every regex. A cell under a password/token header that is not a
# placeholder, has no whitespace and is ≥6 chars is a finding. Fixture values
# are made-up words, not credential shapes.
T=$(mktemp -d) || { echo "❌ mktemp"; exit 1; }
tbl="$T/fleet.md"; printf '| host | user | 密码 |\n|---|---|---|\n| a | root | hunter2x |\n| b | ops | $VAULT_B |\n| c | ops | 见 1Password |\n| d | ops | — |\n| e | ops | <待填> |\n| f | ops | xxxxxx |\n| g | ops | short |\n| h | ops | vault://x |\n| i | ops | n/a |\n| j | ops | – |\n| k | ops | •••••• |\n| l | ops | *** |\n' > "$tbl"
ex=0; out=$("$SCAN" "$tbl" 2>&1) || ex=$?
assert_exit "table literal password is a finding" 1 "$ex"
assert_contains "table finding names the column and line" "$out" 'column "密码"'
assert_contains "table finding points at line 3" "$out" "(line 3)"
for l in 4 5 6 7 8 9 10 11 12 13 14; do assert_not_contains "table row $l is not a finding" "$out" "(line $l)"; done
# final C1: the same table with CRLF line ends must be judged identically —
# the separator regex used to reject the trailing \r, so no column was sensitive.
sed 's/$/\r/' "$tbl" > "$T/fleet-crlf.md"
assert_exit "C1 control: CRLF copy really ends lines in CR" 14 "$(LC_ALL=C grep -c "$(printf '\r')\$" "$T/fleet-crlf.md")"
lf_n=$(printf '%s\n' "$out" | grep -c 'table column' || true)
ex=0; outc=$("$SCAN" "$T/fleet-crlf.md" 2>&1) || ex=$?
assert_exit "C1 CRLF table literal password → exit 1" 1 "$ex"
assert_contains "C1 CRLF table finding points at line 3" "$outc" "(line 3)"
assert_exit "C1 CRLF table: same hit count as LF ($lf_n)" "$lf_n" "$(printf '%s\n' "$outc" | grep -c 'table column' || true)"
# fix1 I1: a placeholder-only row shaped like `| - | - |` is data, not a new
# separator — it must not turn the row above into a header and reset the columns.
printf '| host | 密码 |\n|---|---|\n| a | - |\n| - | - |\n| c | hunter2x |\n' > "$T/dash.md"
ex=0; out=$("$SCAN" "$T/dash.md" 2>&1) || ex=$?
assert_exit "fix1-I1 a | - | - | row does not reset the header → exit 1" 1 "$ex"
assert_contains "fix1-I1 the literal below it is reported at line 5" "$out" "(line 5)"
# fix1 I2: header keywords need a right boundary (bare `pass` both sides);
# no plural, so a count column like "tokens used" is not a credential column.
# (fix3: values carry a letter — a purely numeric cell is no longer a literal,
# so `123456` would make the positives vacuous and the negatives meaningless.)
for h in passport compass 'tokens used' bypass; do
    printf '| name | %s |\n|---|---|\n| svc | abc123def |\n' "$h" > "$T/neg.md"
    ex=0; "$SCAN" "$T/neg.md" >/dev/null 2>&1 || ex=$?
    assert_exit "fix1-I2 header '$h' is not a credential column → exit 0" 0 "$ex"
done
for h in db_password dbPassword 'SSH pwd'; do
    printf '| name | %s |\n|---|---|\n| svc | abc123def |\n' "$h" > "$T/pos.md"
    ex=0; "$SCAN" "$T/pos.md" >/dev/null 2>&1 || ex=$?
    assert_exit "fix1-I2 header '$h' is a credential column → exit 1" 1 "$ex"
done
# fix3: an LLM-usage table under a `token` header (this repo's own Decision
# 0019) was flagged. A literal must be all-ASCII and contain an ASCII letter.
printf '| 模型 | token |\n|---|---|\n| x | 0（命中才花修） |\n' > "$T/usage.md"
ex=0; "$SCAN" "$T/usage.md" >/dev/null 2>&1 || ex=$?
assert_exit "fix3 token column with a non-ASCII usage note → exit 0" 0 "$ex"
printf '| session | token |\n|---|---|\n| s1 | 1234567 |\n| s2 | 1,234,567 |\n| s3 | 12.5_000 |\n' > "$T/count.md"
ex=0; "$SCAN" "$T/count.md" >/dev/null 2>&1 || ex=$?
assert_exit "fix3 token column with purely numeric counts → exit 0" 0 "$ex"
printf '| k | api_key |\n|---|---|\n| a | 12345678901234567890 |\n' > "$T/num.md"
ex=0; "$SCAN" "$T/num.md" >/dev/null 2>&1 || ex=$?
assert_exit "fix3 api_key column with a purely numeric value → exit 0" 0 "$ex"
printf '| k | api_key |\n|---|---|\n| a | hunter2x |\n| b | abc123def |\n' > "$T/alnum.md"
ex=0; out=$("$SCAN" "$T/alnum.md" 2>&1) || ex=$?
assert_exit "fix3 api_key column with ASCII values containing a letter → exit 1" 1 "$ex"
assert_contains "fix3 abc123def is still reported (line 4)" "$out" "(line 4)"
# fix2 #1: a second table abutting the first (no blank line) must still get
# its own header; a strict `| --- |` row later in a block re-reads the row
# above, and sensitivity never decreases inside a table block.
printf '| host | note |\n|---|---|\n| a | b |\n| host | 密码 |\n|---|---|\n| c | hunter2x |\n' > "$T/adj.md"
ex=0; out=$("$SCAN" "$T/adj.md" 2>&1) || ex=$?
assert_exit "fix2 adjacent second table with a 密码 column → exit 1" 1 "$ex"
assert_contains "fix2 adjacent second table → reports line 6" "$out" "(line 6)"
printf '| host | 密码 |\n|---|---|\n| a | $PW_A |\n| host | note |\n|---|---|\n| c | abcdefgh |\n' > "$T/adj2.md"
ex=0; "$SCAN" "$T/adj2.md" >/dev/null 2>&1 || ex=$?
assert_exit "fix2 sensitivity never decreases inside a table block (adjacent table without a sensitive column, same index) → exit 1" 1 "$ex"
printf '| host | 密码 |\n|---|---|\n| a | $PW_A |\n| --- | --- |\n| c | hunter2x |\n' > "$T/ph.md"
ex=0; out=$("$SCAN" "$T/ph.md" 2>&1) || ex=$?
assert_exit "fix2 a | --- | --- | row inside a table keeps the header → exit 1" 1 "$ex"
assert_contains "fix2 a | --- | --- | row inside a table → reports line 5" "$out" "(line 5)"
# fix2 #2: passphrase is a credential column; passport still is not
printf '| user | passphrase |\n|---|---|\n| a | correcthorse |\n' > "$T/pp.md"
ex=0; "$SCAN" "$T/pp.md" >/dev/null 2>&1 || ex=$?
assert_exit "fix2 header 'passphrase' is a credential column → exit 1" 1 "$ex"
for h in token Password api_key; do
    printf '| name | %s |\n| --- | :---: |\n| svc | `plainvalue9` |\n' "$h" > "$T/en-$h.md"
    ex=0; out=$("$SCAN" "$T/en-$h.md" 2>&1) || ex=$?
    assert_exit "table header '$h' with a literal cell → exit 1" 1 "$ex"
    assert_contains "table header '$h' finding names the column" "$out" "column \"$h\""
done
printf '| host | note |\n|---|---|\n| a | plainvalue9longstring |\n' > "$T/note.md"
ex=0; out=$("$SCAN" "$T/note.md" 2>&1) || ex=$?
assert_exit "non-sensitive column with a long no-space value → exit 0" 0 "$ex"
assert_not_contains "non-sensitive column prints no table finding" "$out" "table column"
ex=0; out=$("$SCAN" < "$tbl" 2>&1) || ex=$?
assert_exit "table stdin mode → exit 1" 1 "$ex"
assert_contains "table stdin mode names the column" "$out" 'column "密码"'
mkdir -p "$T/proj/$HX_LOGS_DIR"
printf '<!-- HANDOFF v2 schema -->\nclean\n' > "$T/proj/$HX_MAIN_FILE"
cp "$tbl" "$T/proj/$HX_LOGS_DIR/0001-x.md"
ex=0; out=$("$SCAN" "$T/proj" 2>&1) || ex=$?
assert_exit "table directory mode → exit 1" 1 "$ex"
assert_contains "table directory mode names the log" "$out" "$HX_LOGS_DIR/0001-x.md (line 3)"
# failure matrix: none of these may read as clean
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    echo "  ➖ table unreadable-file control SKIPPED (root bypasses chmod 000; Gotcha #15 / B7-a 同范式)"
else
    chmod 000 "$tbl"
    ex=0; out=$("$SCAN" "$tbl" 2>&1) || ex=$?
    chmod 644 "$tbl"
    assert_exit "table file unreadable → exit 2" 2 "$ex"
    assert_contains "table file unreadable → cannot scan" "$out" "cannot scan"
fi
ex=0; out=$(TMPDIR=/nonexistent "$SCAN" < "$tbl" 2>&1) || ex=$?
assert_exit "stdin with unusable TMPDIR → exit 2" 2 "$ex"
assert_contains "stdin with unusable TMPDIR → names the temp-file failure" "$out" "cannot create a temp file"
assert_not_contains "stdin with unusable TMPDIR prints no ✅" "$out" "✅"
# an awk that fails must not read as "no table hits"
mkdir "$T/bin"; printf '#!/bin/sh\nexit 2\n' > "$T/bin/awk"; chmod 755 "$T/bin/awk"
ex=0; out=$(PATH="$T/bin:$PATH" "$SCAN" "$T/note.md" 2>&1) || ex=$?
assert_exit "table scan with a failing awk → exit 2" 2 "$ex"
assert_contains "table scan with a failing awk → names the table scan" "$out" "table scan failed — cannot scan"
rm -rf "$T"

summary
