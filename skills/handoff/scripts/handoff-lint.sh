#!/bin/bash
# handoff-lint.sh — check HANDOFF.md recall-readiness invariants
# usage: handoff-lint.sh [file]   (default: ./HANDOFF.md)
# exit: 0 clean, 1 findings, 2 file not found / usage error

case "${1:-}" in
    -h|--help)
        echo "Usage: $0 [file]   (default: ./HANDOFF.md)"
        echo "Exit: 0 clean / 1 findings / 2 file not found"
        exit 0
        ;;
esac

FILE="${1:-HANDOFF.md}"
if [ ! -f "$FILE" ]; then
    echo "❌ file not found: $FILE" >&2
    exit 2
fi

# v2 layouts: skip the v1 inline-Dev-Log awk and instead validate the per-file
# entries in Handoff_Logs/ + Handoff_Decisions/. Each entry is checked for:
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
    for required in Handoff_Logs Handoff_Decisions GOTCHAS.md; do
        if [ ! -e "$ROOT_DIR_LINT/$required" ]; then
            echo "❌ v2 layout missing required sibling: $required"
            findings=1
        fi
    done

    DEV_LOG_FILENAME_RE='^[0-9]{4}-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}-.+\.md$'
    DECISION_FILENAME_RE='^[0-9]{4}-[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$'
    DEV_LOG_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$'
    DECISION_DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

    # Codex review #10: extract the date portion encoded in the filename so
    # we can cross-check it against the frontmatter `date:` value. The two
    # are independent inputs (migrate-to-v2 derives both from the original
    # entry header; a hand-edited file can drift them apart). Mismatched
    # dates break invariants assumed by /handoff write flow:
    #   - `ls Handoff_Logs/ | sort -r | head -1` orders by filename date
    #   - duplicate detection reads frontmatter `date:` for delta-time
    # If they disagree, recall and dup detection give different answers.
    extract_filename_date_dev_log() {
        # 0030-2026-05-07T0930-slug.md → 2026-05-07T09:30
        local base="$1" raw
        raw=$(printf '%s' "$base" | sed -nE 's/^[0-9]{4}-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2})-.*/\1T\2:\3/p')
        printf '%s' "$raw"
    }
    extract_filename_date_decision() {
        # 0011-2026-05-07-slug.md → 2026-05-07
        local base="$1" raw
        raw=$(printf '%s' "$base" | sed -nE 's/^[0-9]{4}-([0-9]{4}-[0-9]{2}-[0-9]{2})-.*/\1/p')
        printf '%s' "$raw"
    }

    # v2.1.0: synonym tolerance — Dev Log body fields accept Chinese canonical
    # or English alternates. At least one of each synonym set must appear.
    has_any_body_field() {
        local f="$1"; shift
        local syn
        for syn in "$@"; do
            if grep -qF -- "**${syn}**" "$f"; then
                return 0
            fi
        done
        return 1
    }

    lint_v2_entry() {
        local f="$1" expected_type="$2" require_body_fields="$3" expected_date_re="$4"
        local base; base=$(basename "$f")
        local n_prefix; n_prefix=$(printf '%s' "$base" | grep -oE '^[0-9]{4}' || true)
        local local_findings=0

        if [ "$(head -1 "$f" 2>/dev/null)" != "---" ]; then
            echo "❌ $base: missing frontmatter (line 1 is not '---')"
            return 1
        fi

        local field
        for field in schema type date number title; do
            grep -qE "^${field}:" "$f" || { echo "❌ $base: frontmatter missing field: ${field}"; local_findings=1; }
        done

        grep -qE '^schema: 2$' "$f" || { echo "❌ $base: frontmatter schema must be 2"; local_findings=1; }
        grep -qE "^type: ${expected_type}$" "$f" || { echo "❌ $base: frontmatter type must be ${expected_type}"; local_findings=1; }

        local fm_number
        fm_number=$(grep -E '^number:' "$f" | head -1 | sed -E 's/^number:[[:space:]]*//')
        if ! printf '%s' "$fm_number" | grep -qE '^[0-9]{4}$'; then
            echo "❌ $base: frontmatter number must be 4 digits (got: '$fm_number')"
            local_findings=1
        elif [ "$fm_number" != "$n_prefix" ]; then
            echo "❌ $base: frontmatter number ($fm_number) ≠ filename prefix ($n_prefix)"
            local_findings=1
        fi

        local fm_date
        fm_date=$(grep -E '^date:' "$f" | head -1 | sed -E 's/^date:[[:space:]]*//')
        # Codex review #9: empty `date:` value bypassed the format check
        # because the regex test was guarded behind `[ -n "$fm_date" ]`.
        # An empty date is itself a finding — entries without timestamp
        # metadata break filename/pointer ordering.
        if [ -z "$fm_date" ]; then
            echo "❌ $base: frontmatter date is empty"
            local_findings=1
        elif ! printf '%s' "$fm_date" | grep -qE "$expected_date_re"; then
            echo "❌ $base: date format invalid for $expected_type (got: '$fm_date')"
            local_findings=1
        else
            # Codex review #10: filename date and frontmatter date must agree.
            local fname_date=""
            if [ "$expected_type" = "dev-log" ]; then
                fname_date=$(extract_filename_date_dev_log "$base")
            else
                fname_date=$(extract_filename_date_decision "$base")
            fi
            if [ -n "$fname_date" ] && [ "$fname_date" != "$fm_date" ]; then
                echo "❌ $base: filename date ($fname_date) ≠ frontmatter date ($fm_date)"
                local_findings=1
            fi
        fi

        local fm_title
        fm_title=$(grep -E '^title:' "$f" | head -1 | sed -E 's/^title:[[:space:]]*//')
        if [ -z "$fm_title" ]; then
            echo "❌ $base: frontmatter title is empty"
            local_findings=1
        fi

        if [ "$require_body_fields" = "1" ]; then
            # v2.1.0: each semantic field accepts Chinese canonical OR English
            # alternate. Error message lists both so users see which alternates
            # are recognised without grepping the source.
            has_any_body_field "$f" "触发" "Trigger" \
                || { echo "❌ $base: missing body field: **触发** (or **Trigger**)"; local_findings=1; }
            has_any_body_field "$f" "改动" "Changes" \
                || { echo "❌ $base: missing body field: **改动** (or **Changes**)"; local_findings=1; }
            has_any_body_field "$f" "验证" "Verification" \
                || { echo "❌ $base: missing body field: **验证** (or **Verification**)"; local_findings=1; }
            has_any_body_field "$f" "关联" "Related" \
                || { echo "❌ $base: missing body field: **关联** (or **Related**)"; local_findings=1; }
        fi

        return $local_findings
    }

    lint_v2_dir() {
        local dir="$1" expected_type="$2" require_body_fields="$3" filename_re="$4" date_re="$5"
        [ -d "$dir" ] || return 0
        local f base
        # Walk *.md (not just NNNN-*.md) so malformed filenames are caught,
        # not silently skipped.
        for f in "$dir"/*.md; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            if ! printf '%s' "$base" | grep -qE "$filename_re"; then
                echo "❌ $base: non-canonical filename for $expected_type (must match $filename_re)"
                findings=1
                continue
            fi
            lint_v2_entry "$f" "$expected_type" "$require_body_fields" "$date_re" || findings=1
        done
    }

    lint_v2_dir "$ROOT_DIR_LINT/Handoff_Logs"      "dev-log"  "1" "$DEV_LOG_FILENAME_RE"  "$DEV_LOG_DATE_RE"
    lint_v2_dir "$ROOT_DIR_LINT/Handoff_Decisions" "decision" "0" "$DECISION_FILENAME_RE" "$DECISION_DATE_RE"

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

	!in_log && /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
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

in_log && /^### [0-9]{4}-[0-9]{2}-[0-9]{2}/ {
    flush_entry()
    cur = $0
    date = $2
    time = ($3 ~ /^[0-9]{2}:[0-9]{2}$/) ? $3 : "00:00"
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
