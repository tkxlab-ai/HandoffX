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

run_case "GitHub fine-grained PAT" github_fine_grained_pat.md 1
run_case "HuggingFace token"       huggingface_token.md       1

out=$("$SCAN" "$FIXTURES_DIR/github_fine_grained_pat.md" 2>&1 || true)
assert_contains "reports fine-grained PAT label" "$out" "GitHub fine-grained PAT"

out=$("$SCAN" "$FIXTURES_DIR/huggingface_token.md" 2>&1 || true)
assert_contains "reports HuggingFace label" "$out" "HuggingFace"

# ─── v2 directory mode (H1) ─────────────────────────────────────────────────
SANDBOX=$(mktemp -d)
cat > "$SANDBOX/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
clean main file
EOF
cat > "$SANDBOX/GOTCHAS.md" <<'EOF'
# Known Gotchas
clean
EOF
mkdir -p "$SANDBOX/Handoff_Logs" "$SANDBOX/Handoff_Decisions"
cat > "$SANDBOX/Handoff_Logs/0001-2026-04-18T2030-init.md" <<'EOF'
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

# Plant credential in Handoff_Logs/
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX/Handoff_Logs/0002-2026-04-19T1000-leaked.md"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in Handoff_Logs → exit 1" 1 "$ec"
assert_contains "v2 dir reports leak path" "$out" "Handoff_Logs/0002-"
assert_contains "v2 dir reports leak label" "$out" "OpenAI project key"

# Move leak to GOTCHAS.md
rm -f "$SANDBOX/Handoff_Logs/0002-2026-04-19T1000-leaked.md"
cat "$FIXTURES_DIR/anthropic_key.md" > "$SANDBOX/GOTCHAS.md"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in GOTCHAS → exit 1" 1 "$ec"
assert_contains "v2 dir reports GOTCHAS path" "$out" "GOTCHAS.md"

# Move leak to Handoff_Decisions/
cat > "$SANDBOX/GOTCHAS.md" <<'EOF'
# Known Gotchas
clean again
EOF
cat "$FIXTURES_DIR/github_token.md" > "$SANDBOX/Handoff_Decisions/0001-2026-04-19-leaked.md"
out=$("$SCAN" "$SANDBOX" 2>&1)
ec=$?
assert_exit "v2 dir leak in Handoff_Decisions → exit 1" 1 "$ec"
assert_contains "v2 dir reports Decisions path" "$out" "Handoff_Decisions/0001-"

rm -rf "$SANDBOX"

# C-v2-archive-scan (Codex review #11): scan must walk Handoff_Logs.archive/<year>/
SANDBOX_AR=$(mktemp -d)
cat > "$SANDBOX_AR/HANDOFF.md" <<'EOF'
<!-- HANDOFF v2 schema -->
clean
EOF
echo "clean" > "$SANDBOX_AR/GOTCHAS.md"
mkdir -p "$SANDBOX_AR/Handoff_Logs" "$SANDBOX_AR/Handoff_Decisions" "$SANDBOX_AR/Handoff_Logs.archive/2024"
# Plant a credential under the archive subdir
cat "$FIXTURES_DIR/openai_key.md" > "$SANDBOX_AR/Handoff_Logs.archive/2024/0001-2024-01-15T1000-leak.md"
out=$("$SCAN" "$SANDBOX_AR" 2>&1)
ec=$?
assert_exit "v2 dir: leak in Handoff_Logs.archive/<year>/ → exit 1" 1 "$ec"
assert_contains "v2 dir: archive scan reports archive path" "$out" "Handoff_Logs.archive/2024"
rm -rf "$SANDBOX_AR"

# Non-existent path → usage error (exit 2)
"$SCAN" "/nonexistent/path/xyzzy" >/dev/null 2>&1
ec=$?
assert_exit "missing path → exit 2" 2 "$ec"

summary
