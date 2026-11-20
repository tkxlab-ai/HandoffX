#!/bin/bash
# emit-sbom.sh — CycloneDX 1.5 SBOM generator (extracted from release.sh §2.7)
# Produces a minimal SBOM listing distributable artifacts with SHA-256 hashes.
# Deterministic: timestamp anchored to SOURCE_DATE_EPOCH or 2000-01-01;
# serial derived from artifact hashes; components sorted alphabetically.
#
# Usage: emit-sbom.sh <release_dir> <project_name> <version> <skill_name> [source_date_epoch]
# Exit:  0 success, 1 failure

set -euo pipefail

RELEASE_DIR="${1:?Usage: emit-sbom.sh <release_dir> <project_name> <version> <skill_name> [source_date_epoch]}"
PROJECT_NAME="${2:?Missing project_name}"
VERSION="${3:?Missing version}"
SKILL_NAME="${4:?Missing skill_name}"
SOURCE_DATE_EPOCH="${5:-${SOURCE_DATE_EPOCH:-}}"

SBOM_OUT="$RELEASE_DIR/sbom.cyclonedx.json"

# JSON-escape a string for safe interpolation into JSON values.
# Backslash MUST be substituted first; control chars covered:
# \" \\ \b \f \n \r \t. (Inputs here are filenames + version strings;
# defensive against any future caller passing surprising characters.)
json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\b'/\\b}
    s=${s//$'\f'/\\f}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# Resolve SHA command
if command -v shasum >/dev/null 2>&1; then
    SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD="sha256sum"
else
    echo "❌ neither shasum nor sha256sum available" >&2
    exit 1
fi

# Deterministic timestamp
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    SBOM_TS=$(date -u -r "$SOURCE_DATE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
              || date -u -d "@$SOURCE_DATE_EPOCH" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
              || echo "2000-01-01T00:00:00Z")
else
    SBOM_TS="2000-01-01T00:00:00Z"
fi

# Collect distributable artifacts (sorted = deterministic)
SBOM_ARTS=()
[ -f "$RELEASE_DIR/${PROJECT_NAME}-${VERSION}.skill"          ] && SBOM_ARTS+=("${PROJECT_NAME}-${VERSION}.skill")
[ -f "$RELEASE_DIR/${PROJECT_NAME}-${VERSION}-source.tar.gz" ] && SBOM_ARTS+=("${PROJECT_NAME}-${VERSION}-source.tar.gz")
[ -f "$RELEASE_DIR/install.sh"                                ] && SBOM_ARTS+=("install.sh")

SERIAL_INPUT=""
COMPONENTS_JSON=""
COMPONENT_SEP=""
for art in "${SBOM_ARTS[@]}"; do
    h=$($SHA_CMD "$RELEASE_DIR/$art" | awk '{print $1}')
    SERIAL_INPUT="${SERIAL_INPUT}${h}"
    COMPONENTS_JSON+="${COMPONENT_SEP}"
    art_esc=$(json_escape "$art")
    version_esc=$(json_escape "$VERSION")
    COMPONENTS_JSON+=$(printf '    {"type": "file", "name": "%s", "version": "%s", "hashes": [{"alg": "SHA-256", "content": "%s"}]}' \
                               "$art_esc" "$version_esc" "$h")
    COMPONENT_SEP=$',\n'
done

SERIAL=$(printf '%s' "$SERIAL_INPUT" | $SHA_CMD - | awk '{print $1}')

SKILL_NAME_ESC=$(json_escape "$SKILL_NAME")
VERSION_ESC=$(json_escape "$VERSION")

cat > "$SBOM_OUT" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "serialNumber": "urn:sha256:${SERIAL}",
  "version": 1,
  "metadata": {
    "timestamp": "${SBOM_TS}",
    "component": {
      "type": "application",
      "name": "${SKILL_NAME_ESC}",
      "version": "${VERSION_ESC}"
    }
  },
  "components": [
${COMPONENTS_JSON}
  ]
}
EOF

echo "   → $SBOM_OUT"
