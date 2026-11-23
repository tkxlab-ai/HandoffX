#!/bin/bash
# handoff-lint.sh — check $HX_MAIN_FILE recall-readiness invariants
# usage: handoff-lint.sh [file]   (default: ./$HX_MAIN_FILE)
# exit: 0 clean, 1 findings, 2 file not found / usage error

# Four-piece path constants — derived from the single schema source
# (P2.0 coupling-c, Decision 0020 / Gotcha #25 mother-theme).
. "$(dirname "$0")/lib/handoff-schema.sh"

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file]   (default: ./$HX_MAIN_FILE)"
        echo "Exit: 0 clean / 1 findings / 2 file not found"
        exit 0
        ;;
esac

FILE="${1:-$HX_MAIN_FILE}"
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    exit 2
fi

# v2 layouts: skip the v1 inline-Dev-Log awk and instead validate the per-file
# entries in $HX_LOGS_DIR/ + $HX_DEC_DIR/. Each entry is checked for:
#   - canonical filename pattern for its directory (rejects malformed names)
#   - leading `---` frontmatter delimiter
#   - presence of schema/type/date/number/title frontmatter fields
#   - schema exactly `2`
#   - type matches directory (dev-log for Logs, decision for Decisions)
#   - number is 4 digits and matches the filename prefix
#   - date format matches type (YYYY-MM-DDTHH:MM for dev-log; YYYY-MM-DD for decision)
#   - title non-empty
#   - Dev Log entries also require body fields **触发**/**改动**/**验证**/**关联**
# (Codex review #3 + #5 fixes.)
if grep -qF -- '<!-- HANDOFF v2 schema -->' "$FILE"; then
    ROOT_DIR_LINT="$(cd "$(dirname "$FILE")" && pwd)"
    findings=0

    # Codex review #7: v2 marker without sibling artifacts is a broken layout,
    # not a "skip the check" condition. Require all three.
    for required in "$HX_LOGS_DIR" "$HX_DEC_DIR" "$HX_GOTCHAS_FILE"; do
        if [ ! -e "$ROOT_DIR_LINT/$required" ]; then
            echo "❌ v2 layout missing required sibling: $required"
            findings=1
        fi
    done

    if [ -e "$ROOT_DIR_LINT/$HX_GOTCHAS_FILE" ] && { [ ! -f "$ROOT_DIR_LINT/$HX_GOTCHAS_FILE" ] || [ ! -r "$ROOT_DIR_LINT/$HX_GOTCHAS_FILE" ]; }; then
        echo "❌ $HX_GOTCHAS_FILE: not a readable regular file — cannot lint"
        findings=1
    fi

    DEV_LOG_FILENAME_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9][0-9][0-9]-.+\.md$'
    DECISION_FILENAME_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-.+\.md$'
    DEV_LOG_DATE_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]$'
    DECISION_DATE_RE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$'

    # 每个条目仅一次 awk：元数据只来自第一对 ---，正文不能补字段。
    # CRLF 仅在解析视图中去掉行末 CR，原文件不改写。
    lint_v2_entry() {
        local f="$1" expected_type="$2" require_body_fields="$3" expected_date_re="$4"
        local base="${1##*/}"
        if [ ! -r "$f" ]; then
            echo "❌ $base: 文件不可读 — cannot lint"
            return 1
        fi
        awk -v base="$base" -v expected_type="$expected_type" \
            -v body_required="$require_body_fields" -v date_re="$expected_date_re" '
            function fail(message) { print "❌ " base ": " message; bad = 1 }
            BEGIN {
                quote = sprintf("%c", 39)
                nk = split("schema type date number title", keys, " ")
                for (i = 1; i <= nk; i++) required[keys[i]] = 1
            }
            { sub(/\r$/, "") }
            NR == 1 {
                if ($0 != "---") { fail("missing frontmatter (line 1 is not " quote "---" quote ")"); exit 1 }
                opened = 1; next
            }
            !closed {
                if ($0 == "---") { closed = 1; next }
                key = $0; sub(/:.*/, "", key)
                if (index($0, ":") && key in required) {
                    count[key]++
                    value = substr($0, index($0, ":") + 1)
                    sub(/^[ \t]*/, "", value); sub(/[ \t]*$/, "", value)
                    values[key] = value
                }
                next
            }
            body_required {
                if (/\*\*触发\*\*/ || /\*\*Trigger\*\*/) trigger = 1
                if (/\*\*改动\*\*/ || /\*\*Changes\*\*/) changes = 1
                if (/\*\*验证\*\*/ || /\*\*Verification\*\*/) verification = 1
                if (/\*\*关联\*\*/ || /\*\*Related\*\*/) related = 1
            }
            END {
                if (!opened) { if (!bad) fail("missing frontmatter (empty file)"); exit 1 }
                if (!closed) { fail("frontmatter 未闭合 (unclosed ---)"); exit 1 }
                for (i = 1; i <= nk; i++) {
                    key = keys[i]
                    if (!count[key]) fail("frontmatter missing field: " key)
                    else if (count[key] > 1) fail("frontmatter 重复必填键 (duplicate field): " key)
                }
                if (count["schema"] == 1 && values["schema"] != "2") fail("frontmatter schema must be 2")
                if (count["type"] == 1 && values["type"] != expected_type) fail("frontmatter type must be " expected_type)
                number = values["number"]
                if (count["number"] == 1) {
                    if (number !~ /^[0-9][0-9][0-9][0-9]$/) fail("frontmatter number must be 4 digits (got: " quote number quote ")")
                    else if (number != substr(base, 1, 4)) fail("frontmatter number (" number ") ≠ filename prefix (" substr(base, 1, 4) ")")
                }
                date = values["date"]
                if (count["date"] == 1) {
                    if (date == "") fail("frontmatter date is empty")
                    else if (date !~ date_re) fail("date format invalid for " expected_type " (got: " quote date quote ")")
                    else {
                        filename_date = substr(base, 6, 10)
                        if (expected_type == "dev-log") filename_date = filename_date "T" substr(base, 17, 2) ":" substr(base, 19, 2)
                        if (date != filename_date) fail("filename date (" filename_date ") ≠ frontmatter date (" date ")")
                    }
                }
                if (count["title"] == 1 && values["title"] == "") fail("frontmatter title is empty")
                if (body_required) {
                    if (!trigger) fail("missing body field: **触发** (or **Trigger**)")
                    if (!changes) fail("missing body field: **改动** (or **Changes**)")
                    if (!verification) fail("missing body field: **验证** (or **Verification**)")
                    if (!related) fail("missing body field: **关联** (or **Related**)")
                }
                exit bad
            }
        ' "$f"
    }

    lint_v2_dir() {
        local dir="$1" expected_type="$2" require_body_fields="$3" filename_re="$4" date_re="$5"
        if [ ! -d "$dir" ]; then
            # A missing dir is already flagged by the sibling check above; what
            # reaches here is a non-directory squatting on the canonical path.
            [ -e "$dir" ] || return 0
            echo "❌ $(basename "$dir"): exists but is not a directory — cannot lint, refusing to report clean"
            findings=1
            return 0
        fi
        # A dir we cannot list/traverse must not fall through to the loop below:
        # the glob stays empty, nothing is checked, and findings would still be 0
        # (fail-open, Gotcha #24).
        if [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
            echo "❌ $(basename "$dir")/: directory not readable/traversable (needs r+x) — cannot lint, refusing to report clean"
            findings=1
            return 0
        fi
        local f base
        # Walk *.md (not just NNNN-*.md) so malformed filenames are caught,
        # not silently skipped.
        for f in "$dir"/*.md; do
            base=$(basename "$f")
            # a dangling symlink or a directory named *.md is not "nothing
            # here" — it is a broken entry that recall would also trip on
            if [ -L "$f" ] && [ ! -e "$f" ]; then
                echo "❌ $base: dangling symlink (target missing) — cannot lint"
                findings=1
                continue
            fi
            if [ ! -f "$f" ]; then
                # an empty dir leaves the literal glob — only flag real entries
                [ -e "$f" ] || continue
                echo "❌ $base: not a regular file (directory?) — cannot lint"
                findings=1
                continue
            fi
            # INDEX.md is generated: the decision index (B③, Decision 0019 ③)
            # and the Dev Log index (regenerate_log_index, v4.4.2). In the logs
            # dir only the generated one is exempt — its first line is the
            # generator's header; a hand-made INDEX.md is still malformed.
            case "$base" in
                INDEX.md)
                    [ "$expected_type" = "decision" ] && continue
                    if [ "$expected_type" = "dev-log" ] && [ "$(sed -n 1p "$f" 2>/dev/null)" = "# Dev Log Index" ]; then continue; fi ;;
            esac
            if ! printf '%s' "$base" | grep -qE "$filename_re"; then
                echo "❌ $base: non-canonical filename for $expected_type (must match $filename_re)"
                findings=1
                continue
            fi
            lint_v2_entry "$f" "$expected_type" "$require_body_fields" "$date_re" || findings=1
        done
    }

    lint_v2_dir "$ROOT_DIR_LINT/$HX_LOGS_DIR" "dev-log"  "1" "$DEV_LOG_FILENAME_RE"  "$DEV_LOG_DATE_RE"
    lint_v2_dir "$ROOT_DIR_LINT/$HX_DEC_DIR"  "decision" "0" "$DECISION_FILENAME_RE" "$DECISION_DATE_RE"

    exit $findings
fi

awk '
function flush_entry() {
    if (cur == "") return
    missing = ""
    if (!seen_trigger) missing = missing " 触发"
    if (!seen_change) missing = missing " 改动"
    if (!seen_verify) missing = missing " 验证"
    if (!seen_link) missing = missing " 关联"
    if (missing != "") {
        print "❌ Dev Log entry missing fields:" missing " — " cur
        findings = 1
    }
    cur = ""
    seen_trigger = seen_change = seen_verify = seen_link = 0
}

	/^## [^A-Za-z]*Development Log/ {
	    flush_entry()
	    in_log = 1
	    section = "Development Log"
	    log_sections++
	    next
	}

	/^## / && in_log {
	    flush_entry()
	    in_log = 0
	}

	/^## / {
	    section = $0
	}

	!in_log && /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
	    if (section ~ /Decision Log/) next
	    print "❌ Dev Log entry outside Development Log section — " $0
	    findings = 1
	    next
	}

	/🚨 AI 注意/ {
    if (in_log) {
        anchor_in_log++
    } else {
        anchor_outside++
    }
}

in_log && /^### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ {
    flush_entry()
    cur = $0
    date = $2
    time = ($3 ~ /^[0-9][0-9]:[0-9][0-9]$/) ? $3 : "00:00"
    gsub(/-/, "", date)
    gsub(/:/, "", time)
    ts = date time
    if (prev_ts != "" && ts > prev_ts) {
        print "❌ Dev Log entries must be reverse chronological — " cur
        findings = 1
    }
    prev_ts = ts
    next
}

in_log && cur != "" {
    # v2.1.0: synonym tolerance — accept Chinese canonical OR English alternate
    if (/\*\*触发\*\*:/ || /\*\*Trigger\*\*:/) seen_trigger = 1
    if (/\*\*改动\*\*:/ || /\*\*Changes\*\*:/) seen_change = 1
    if (/\*\*验证\*\*:/ || /\*\*Verification\*\*:/) seen_verify = 1
    if (/\*\*关联\*\*:/ || /\*\*Related\*\*:/) seen_link = 1
}

END {
    flush_entry()
    if (log_sections != 1) {
        print "❌ expected exactly one Development Log section, found " (log_sections+0)
        findings = 1
    }
    if (anchor_in_log != 1 || anchor_outside > 0) {
        print "❌ anchor must be inside Development Log exactly once"
        findings = 1
    }
    exit findings
}
' "$FILE"
