#!/bin/bash
# test_recommended_consistency.sh — meta-test: the RECOMMENDED section list must be
# consistent across validate-handoff.sh, tidy-handoff.sh, and HANDOFF.template.md.
source "$(dirname "$0")/common.sh"

# Extract RECOMMENDED items from a bash script.
# Outputs one item per line, sorted.
extract_recommended() {
    local file="$1"
    # Grab everything between RECOMMENDED=( and the closing )
    # Extract quoted strings (preserving internal spaces), remove quotes
    sed -n '/RECOMMENDED=(/,/)/p' "$file" \
        | grep -oE '"[^"]*"' \
        | sed 's/^"//;s/"$//' \
        | sort
}

# Check template has a section
template_has() {
    grep -qE "^## [^A-Za-z]*$1([[:space:]]*$|[[:space:]]+[^A-Za-z])" "$TEMPLATES_DIR/HANDOFF.template.md"
}

validate_list=$(extract_recommended "$SCRIPTS_DIR/validate-handoff.sh")
tidy_list=$(extract_recommended "$SCRIPTS_DIR/tidy-handoff.sh")

# Test 1: validate 和 tidy 的 RECOMMENDED 列表必须一致
if [ "$validate_list" = "$tidy_list" ]; then
    echo "  ✅ validate RECOMMENDED == tidy RECOMMENDED ($(echo "$validate_list" | wc -l | tr -d ' ') items)"
    PASS=$((PASS+1))
else
    echo "  ❌ validate RECOMMENDED != tidy RECOMMENDED"
    echo "    validate: [$(echo "$validate_list" | tr '\n' ', ')]"
    echo "    tidy:     [$(echo "$tidy_list" | tr '\n' ', ')]"
    # Show diff
    diff <(echo "$validate_list") <(echo "$tidy_list") | sed 's/^/      /'
    FAIL=$((FAIL+1))
fi

# Test 2: 每个 RECOMMENDED 章节必须在 template 中存在
while IFS= read -r section; do
    [ -z "$section" ] && continue
    if template_has "$section"; then
        echo "  ✅ template has: $section"
        PASS=$((PASS+1))
    else
        echo "  ❌ template missing: $section"
        FAIL=$((FAIL+1))
    fi
done <<< "$validate_list"

# Test 3: bundle 副本也必须一致
if diff -q "$SCRIPTS_DIR/validate-handoff.sh" "$ROOT_DIR/skills/handoff/scripts/validate-handoff.sh" >/dev/null 2>&1; then
    echo "  ✅ validate dev == bundle"
    PASS=$((PASS+1))
else
    echo "  ❌ validate dev != bundle"
    FAIL=$((FAIL+1))
fi

if diff -q "$SCRIPTS_DIR/tidy-handoff.sh" "$ROOT_DIR/skills/handoff/scripts/tidy-handoff.sh" >/dev/null 2>&1; then
    echo "  ✅ tidy dev == bundle"
    PASS=$((PASS+1))
else
    echo "  ❌ tidy dev != bundle"
    FAIL=$((FAIL+1))
fi

summary
