#!/bin/bash
# DOC_DIR override seam — (B) 可测性前置；使后续 RED gate 能对 fixture 跑真实脚本。
source "$(dirname "$0")/common.sh"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tests"
printf 'x\n' > "$W/README.md"
out_repo=$( (unset DOC_DIR; bash "$(dirname "$0")/test_doc_freshness.sh") 2>&1 | tail -1)
out_fix=$(DOC_DIR="$W" bash "$(dirname "$0")/test_doc_freshness.sh" 2>&1 | tail -1)
assert_exit "DOC_DIR=fixture 改变真实脚本结果(认 env 覆盖)" 0 \
  "$([ "$out_repo" != "$out_fix" ] && echo 0 || echo 1)"
summary
