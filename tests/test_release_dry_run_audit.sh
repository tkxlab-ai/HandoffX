#!/bin/bash
# test_release_dry_run_audit.sh — release staging must not leak private project state
source "$(dirname "$0")/common.sh"

RELEASE="$ROOT_DIR/release.sh"
VERSION="v999.999.999"

# 新旧两种布局都要清：canonical 目录是 Release/handoffx-<ver>，旧的是 Release/<ver>
rm -rf "$ROOT_DIR/Release/$VERSION" "$ROOT_DIR/Release/handoffx-$VERSION"

output=$(bash "$RELEASE" --dry-run-audit "$VERSION" 2>&1)
ec=$?
assert_exit "dry-run audit exits 0" 0 "$ec"
assert_contains "dry-run reports safe staging" "$output" "release dry-run audit passed"
assert_contains "dry-run checks forbidden files" "$output" "forbidden paths absent"
assert_contains "dry-run checks command shims" "$output" "required command shims present"
assert_contains "dry-run prints manifest preview" "$output" "release manifest preview"
assert_contains "manifest has generated timestamp" "$output" "generated_at:"
assert_contains "manifest lists forbidden paths" "$output" "forbidden_paths:"
assert_contains "manifest includes checksums" "$output" "sha256:"

audit_body=$(awk '
    /^audit_staged_source\(\)/ { in_fn = 1; depth = 0 }
    in_fn {
        print
        n = gsub(/\{/, "{")
        depth += n
        n = gsub(/\}/, "}")
        depth -= n
        if (depth == 0 && /\}/) exit
    }
' "$RELEASE")
assert_contains "release audit requires handoffx-init shim" \
    "$audit_body" \
    "handoffx-init.md"

for rel in "Release/$VERSION" "Release/handoffx-$VERSION"; do
    if [ -e "$ROOT_DIR/$rel" ]; then
        echo "  ❌ dry-run created $rel"
        FAIL=$((FAIL+1))
    else
        echo "  ✅ dry-run created no $rel"
        PASS=$((PASS+1))
    fi
done

# FORCE=1 must not bypass sanitizer findings. This is a static safety gate to
# avoid recursively invoking release.sh, which itself runs tests/run_all.sh.
release_body=$(cat "$RELEASE")
assert_not_contains "release sanitizer has no FORCE bypass" "$release_body" '${FORCE:-0}'
assert_not_contains "release output must not continue after sanitizer finding" "$release_body" "仍继续发布"

summary
