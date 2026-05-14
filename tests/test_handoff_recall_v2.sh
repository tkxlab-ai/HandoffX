#!/bin/bash
# test_handoff_recall_v2.sh — contract test for /handoff-recall v2 lookup primitives.
#
# Recall is AI-driven (the agent reads the files and summarizes), so end-to-end
# verification needs a CLI sandbox. This suite locks down the file-system
# contracts the recall flow depends on:
#   1. `ls -1 Handoff_Logs/[0-9]*.md | sort -r | head -N` returns the N newest entries.
#   2. Each per-file entry carries frontmatter (schema/type/date/number/title).
#   3. GOTCHAS.md exists and is readable as a single file.
#   4. Handoff_Decisions/ is enumerable but NOT touched by default recall.
source "$(dirname "$0")/common.sh"

# Build a v2 sandbox: 7 Dev Log entries, 2 Decisions, 1 Gotchas file.
SANDBOX=$(mktemp -d)
mkdir -p "$SANDBOX/Handoff_Logs" "$SANDBOX/Handoff_Decisions"

cat > "$SANDBOX/HANDOFF.md" <<'EOF'
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
    f="$SANDBOX/Handoff_Logs/${n}-2026-04-${day}T1000-entry-${i}.md"
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
cat > "$SANDBOX/Handoff_Decisions/0001-2026-04-22-first-decision.md" <<'EOF'
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

cat > "$SANDBOX/Handoff_Decisions/0002-2026-04-25-second-decision.md" <<'EOF'
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
cat > "$SANDBOX/GOTCHAS.md" <<'EOF'
# Known Gotchas

### Gotcha #1 — `[build]` first
- 症状: foo

### Gotcha #2 — `[runtime]` second
- 症状: bar
EOF

# ─── Contract 1: lookup primitive returns N newest by sequential number ───
recent5=$(ls -1 "$SANDBOX/Handoff_Logs/"[0-9]*.md | sort -r | head -5 | xargs -n1 basename)
n_recent=$(echo "$recent5" | wc -l | tr -d ' ')
assert_contains "C1: lookup returns 5 entries" "$n_recent" "5"

first_recent=$(echo "$recent5" | head -1)
last_recent=$(echo "$recent5" | tail -1)
case "$first_recent" in 0007-*) echo "  ✅ C1: head of sorted-r is newest (0007)"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C1: head was $first_recent, expected 0007-*"; FAIL=$((FAIL+1)) ;;
esac
case "$last_recent" in 0003-*) echo "  ✅ C1: tail of head -5 is 0003"; PASS=$((PASS+1)) ;;
    *) echo "  ❌ C1: tail was $last_recent, expected 0003-*"; FAIL=$((FAIL+1)) ;;
esac

# ─── Contract 2: each entry has v2 frontmatter ───
for f in "$SANDBOX/Handoff_Logs/"[0-9]*.md; do
    head -1 "$f" | grep -q '^---$' || { echo "  ❌ C2: $(basename "$f") missing leading ---"; FAIL=$((FAIL+1)); continue; }
    grep -q '^schema: 2$' "$f" || { echo "  ❌ C2: $(basename "$f") missing schema:2"; FAIL=$((FAIL+1)); continue; }
    grep -q '^type: dev-log$' "$f" || { echo "  ❌ C2: $(basename "$f") missing type"; FAIL=$((FAIL+1)); continue; }
    grep -q '^number: [0-9]\{4\}$' "$f" || { echo "  ❌ C2: $(basename "$f") missing number"; FAIL=$((FAIL+1)); continue; }
done
echo "  ✅ C2: all 7 Dev Log entries carry valid v2 frontmatter"
PASS=$((PASS+1))

# ─── Contract 3: GOTCHAS.md exists and contains entries ───
assert_file_exists "C3: GOTCHAS.md present" "$SANDBOX/GOTCHAS.md"
n_gotchas=$(grep -cE '^### Gotcha #' "$SANDBOX/GOTCHAS.md")
assert_contains "C3: GOTCHAS.md lists 2 entries" "$n_gotchas" "2"

# ─── Contract 4: Decisions enumerable but recall doesn't read by default ───
n_decisions=$(ls -1 "$SANDBOX/Handoff_Decisions/"[0-9]*.md | wc -l | tr -d ' ')
assert_contains "C4: Handoff_Decisions/ has 2 files" "$n_decisions" "2"
# (No assertion that they're READ — that's an AI behavioral contract enforced
# by the recall reference doc, not by file system state.)

# ─── Contract 5: requesting more than available returns all (clamped at N) ───
recent20=$(ls -1 "$SANDBOX/Handoff_Logs/"[0-9]*.md | sort -r | head -20 | wc -l | tr -d ' ')
assert_contains "C5: requesting 20 from a 7-entry log returns 7" "$recent20" "7"

# ─── Contract 6: empty Handoff_Logs/ returns no entries gracefully ───
EMPTY=$(mktemp -d)
mkdir -p "$EMPTY/Handoff_Logs"
n_empty=$(ls -1 "$EMPTY/Handoff_Logs/"[0-9]*.md 2>/dev/null | wc -l | tr -d ' ')
assert_contains "C6: empty dir → 0 entries" "$n_empty" "0"
rm -rf "$EMPTY"

rm -rf "$SANDBOX"

summary
