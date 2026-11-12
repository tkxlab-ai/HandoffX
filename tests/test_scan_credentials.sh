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

summary
