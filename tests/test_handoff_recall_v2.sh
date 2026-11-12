#!/bin/bash
# test_handoff_recall_v2.sh — contract test for /handoffx-recall v2 lookup primitives.
#
# Recall is AI-driven (the agent reads the files and summarizes), so end-to-end
# verification needs a CLI sandbox. This suite locks down the file-system
# contracts the recall flow depends on:
#   1. `ls -1 $HX_LOGS_DIR/[0-9]*.md | sort -r | head -N` returns the N newest entries.
#   2. Each per-file entry carries frontmatter (schema/type/date/number/title).
#   3. GOTCHAS.md exists and is readable as a single file.
#   4. $HX_DEC_DIR/ is enumerable but NOT touched by default recall.
source "$(dirname "$0")/common.sh"

# Build a v2 sandbox: 7 Dev Log entries, 2 Decisions, 1 Gotchas file.
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/$HX_LOGS_DIR" "$SANDBOX/$HX_DEC_DIR"

cat > "$SANDBOX/$HX_MAIN_FILE" <<'EOF'
<!-- HANDOFF v2 schema -->
# Demo

## 📦 Project Overview
test
## 🎯 Current State
test
## 📜 Development Log

最近一条：(none)
最早一条：(none)
共 0 条
EOF

# 7 Dev Log entries with sequential timestamps (ascending number = ascending time)
for i in 1 2 3 4 5 6 7; do
    n=$(printf '%04d' "$i")
    day=$(printf '%02d' "$((20 + i))")
    f="$SANDBOX/$HX_LOGS_DIR/${n}-2026-04-${day}T1000-entry-${i}.md"
    cat > "$f" <<EOF
---
schema: 2
type: dev-log
date: 2026-04-${day}T10:00
number: ${n}
title: entry ${i}
---

### 2026-04-${day} 10:00 — entry ${i}

**触发**: test ${i}

**改动**:
- file${i}.md

**验证**: ok

**关联**: 无
EOF
done

# 2 Decisions
cat > "$SANDBOX/$HX_DEC_DIR/0001-2026-04-22-first-decision.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-04-22
number: 0001
title: first decision
---

### 2026-04-22 — first decision
- **背景**: test
EOF

cat > "$SANDBOX/$HX_DEC_DIR/0002-2026-04-25-second-decision.md" <<'EOF'
---
schema: 2
type: decision
date: 2026-04-25
number: 0002
title: second decision
---

### 2026-04-25 — second decision
- **背景**: test
EOF

# 1 Gotchas file
cat > "$SANDBOX/$HX_GOTCHAS_FILE" <<'EOF'
# Known Gotchas

### Gotcha #1 — `[build]` first
- 症状: foo

### Gotcha #2 — `[runtime]` second
- 症状: bar
EOF

# ─── Contract 1: lookup primitive returns N newest by sequential number ───
recent6=$(ls -1 "$SANDBOX/$HX_LOGS_DIR/"[0-9]*.md | sort -r | head -6 | xargs -n1 basename)
n_recent=$(echo "$recent6" | wc -l | tr -d ' ')
assert_contains "C1: lookup returns 6 entries (recall default)" "$n_recent" "6"

first_recent=$(echo "$recent6" | head -1)
last_recent=$(echo "$recent6" | tail -1)
case "$first_recent" in 0007-*) echo "  ✅ C1: head of sorted-r is newest (0007)"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C1: head was $first_recent, expected 0007-*"; FAIL=$((FAIL+1)) ;;
esac
case "$last_recent" in 0002-*) echo "  ✅ C1: tail of head -6 is 0002"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C1: tail was $last_recent, expected 0002-*"; FAIL=$((FAIL+1)) ;;
esac

# ─── Contract 2: each entry has v2 frontmatter ───
for f in "$SANDBOX/$HX_LOGS_DIR/"[0-9]*.md; do
    head -1 "$f" | grep -q '^---$' || { echo "  ❌ C2: $(basename "$f") missing leading ---"; FAIL=$((FAIL+1)); continue; }
    grep -q '^schema: 2$' "$f" || { echo "  ❌ C2: $(basename "$f") missing schema:2"; FAIL=$((FAIL+1)); continue; }
    grep -q '^type: dev-log$' "$f" || { echo "  ❌ C2: $(basename "$f") missing type"; FAIL=$((FAIL+1)); continue; }
    grep -q '^number: [0-9]\{4\}$' "$f" || { echo "  ❌ C2: $(basename "$f") missing number"; FAIL=$((FAIL+1)); continue; }
done
echo "  ✅ C2: all 7 Dev Log entries carry valid v2 frontmatter"
PASS=$((PASS+1))

# ─── Contract 3: GOTCHAS.md exists and contains entries ───
assert_file_exists "C3: $HX_GOTCHAS_FILE present" "$SANDBOX/$HX_GOTCHAS_FILE"
n_gotchas=$(grep -cE '^### Gotcha #' "$SANDBOX/$HX_GOTCHAS_FILE")
assert_contains "C3: $HX_GOTCHAS_FILE lists 2 entries" "$n_gotchas" "2"

# ─── Contract 4: Decisions enumerable but recall doesn't read by default ───
n_decisions=$(ls -1 "$SANDBOX/$HX_DEC_DIR/"[0-9]*.md | wc -l | tr -d ' ')
assert_contains "C4: $HX_DEC_DIR/ has 2 files" "$n_decisions" "2"
# (No assertion that they're READ — that's an AI behavioral contract enforced
# by the recall reference doc, not by file system state.)

# ─── Contract 5: requesting more than available returns all (clamped at N) ───
recent20=$(ls -1 "$SANDBOX/$HX_LOGS_DIR/"[0-9]*.md | sort -r | head -20 | wc -l | tr -d ' ')
assert_contains "C5: requesting 20 from a 7-entry log returns 7" "$recent20" "7"

# ─── Contract 6: empty $HX_LOGS_DIR/ returns no entries gracefully ───
EMPTY=$(mktemp -d)
mkdir -p "$EMPTY/$HX_LOGS_DIR"
n_empty=$(ls -1 "$EMPTY/$HX_LOGS_DIR/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "C6: empty dir → 0 entries" "$n_empty" "0"
rm -rf "$EMPTY"

rm -rf "$SANDBOX"

# L3 (v4.1.1): the recall shim told readers to skip a single-file archive that
# the v2 layout never writes; yearly archives live in a sibling directory.
RSHIM="$ROOT_DIR/skills/handoffx/command-shims/handoffx-recall.md"
assert_not_contains "L3: recall shim names no single-file archive" "$(cat "$RSHIM")" "${HX_MAIN_FILE%.md}.archive.md"
assert_contains "L3: recall shim names the yearly archive dir" "$(cat "$RSHIM")" "${HX_LOGS_DIR}.archive/<年>/"

# v4.2.0: the reference table still advertised 5 as the default after v4.1.1 moved it to 6.
RREF="$ROOT_DIR/skills/handoffx/references/handoffx-recall.md"
n=$(grep -c '^| `/handoffx-recall` | \*\*6\*\*（默认） |' "$RREF" || true)
assert_exit "recall reference table default row says 6" 1 "$n"
n=$(grep -c '^| `/handoffx-recall` | \*\*5\*\*' "$RREF" || true)
assert_exit "recall reference table has no stale 5" 0 "$n"

summary
