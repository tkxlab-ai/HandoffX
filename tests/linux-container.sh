#!/bin/bash
# linux-container.sh — maintainer tool, not a test suite (run_all only picks up
# tests/test_*.sh). Replays the full regression in a Linux container (mawk, bash 5,
# no python3) so the "Linux mawk/POSIX-safe" claim is re-checked on demand instead
# of by a hand-typed docker session that drifts every time (Dev Log 0072).
#
# usage: bash tests/linux-container.sh [--root] [--image ubuntu:22.04]
#   default: tests run as a non-root user with the host's uid — root bypasses chmod,
#   so every chmod-based gate would be skipped (Gotcha #15 / B7-a) and prove nothing
#   --root: run as root (the chmod cases then report ➖ by design)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="ubuntu:22.04"
AS_ROOT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --root)  AS_ROOT=1; shift ;;
        --image) [ -n "${2:-}" ] || { echo "Usage: $0 [--root] [--image <image>]"; exit 1; }
                 IMAGE="$2"; shift 2 ;;
        *)       echo "Usage: $0 [--root] [--image <image>]"; exit 1 ;;
    esac
done

DOCKER=""
for d in "$(command -v docker 2>/dev/null || true)" "$HOME/.orbstack/bin/docker" /usr/local/bin/docker; do
    if [ -n "$d" ] && [ -x "$d" ]; then DOCKER="$d"; break; fi
done
if [ -z "$DOCKER" ]; then
    echo "❌ docker not found (\$PATH, \$HOME/.orbstack/bin/docker, /usr/local/bin/docker) — start OrbStack / Docker first" >&2
    exit 1
fi

# a staged copy, not the live tree: the container writes tests/.tmp and sandbox
# output, and Release/ holds real artifacts that must never be bind-mounted writable
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/linux-container.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
# /.git stays: the rename-guard bguard needs git inside the tree
rsync -a \
    --exclude='/Release' \
    --exclude='/tests/.tmp' \
    --exclude='/.github-publish-wt' \
    --exclude='/.cursor' \
    --exclude='/.superpowers' \
    --exclude='/.omc' \
    --exclude='/.claude' \
    --exclude='/memory' \
    "$ROOT/" "$STAGE/"

# suites that check the real release (doc freshness, integrity) read Release/latest
LATEST=$(readlink "$ROOT/Release/latest" 2>/dev/null || true)
if [ -z "$LATEST" ] || [ ! -d "$ROOT/Release/$LATEST" ]; then
    echo "❌ Release/latest is missing or dangling — cannot stage the current release" >&2
    exit 1
fi
mkdir "$STAGE/Release"
cp -R "$ROOT/Release/$LATEST" "$STAGE/Release/$LATEST"
cp "$ROOT/Release/CHANGELOG.md" "$STAGE/Release/CHANGELOG.md"
ln -s "$LATEST" "$STAGE/Release/latest"

# this network mangles apt's pipelined HTTP/1.1 (NOSPLIT): these four options are
# what made apt work in Dev Log 0072. zsh: test_handoff_v2_schema Z1 sources the
# shared lib under zsh -fc; without it the gate is a ➖ on Linux.
INNER='
set -e
APT_OPTS="-o Acquire::http::Pipeline-Depth=0 -o Acquire::http::No-Cache=true -o Acquire::http::User-Agent=Mozilla/5.0 -o Acquire::ForceIPv4=true"
export DEBIAN_FRONTEND=noninteractive
# output kept, not discarded: an apt failure here is usually the network, and a bare
# non-zero exit with no text sends the maintainer to debug the tests instead
APT_LOG=/tmp/apt.log
if ! { apt-get $APT_OPTS update -qq && apt-get $APT_OPTS install -y -qq shellcheck ruby unzip zip rsync locales git zsh; } > "$APT_LOG" 2>&1; then
    tail -n 15 "$APT_LOG"
    echo "❌ apt install failed (see the lines above)"
    exit 1
fi
git config --system --add safe.directory /work
export LANG=C.UTF-8 LC_ALL=C.UTF-8
LOG=/tmp/run_all.log
if [ "$AS_ROOT" = "1" ]; then
    set +e; bash tests/run_all.sh > "$LOG" 2>&1; rc=$?; set -e
    who="root"
else
    user=$(getent passwd "$HOST_UID" | cut -d: -f1)
    if [ -z "$user" ]; then useradd -m -u "$HOST_UID" -s /bin/bash lctest; user=lctest; fi
    set +e
    su -s /bin/bash "$user" -c "cd /work && LANG=C.UTF-8 LC_ALL=C.UTF-8 bash tests/run_all.sh" > "$LOG" 2>&1
    rc=$?; set -e
    who="$user (uid $HOST_UID)"
fi
grep -E "❌" "$LOG" | head -40 || true
suites=$(grep -c "^🧪 " "$LOG" || true)
passed=$(awk "/─── [0-9]+ passed, [0-9]+ failed/ { p += \$2 } END { print p + 0 }" "$LOG")
failed=$(awk "/─── [0-9]+ passed, [0-9]+ failed/ { f += \$4 } END { print f + 0 }" "$LOG")
skips=$(grep -c "➖" "$LOG" || true)
tail -n 1 "$LOG"
echo "linux-container: as $who — $suites suites / $passed passed / $failed failed / $skips ➖ (run_all exit $rc)"
exit "$rc"
'

echo "🐧 $IMAGE ← $STAGE ($([ "$AS_ROOT" = "1" ] && echo root || echo "uid $(id -u)"))"
set +e
"$DOCKER" run --rm -v "$STAGE":/work -w /work \
    -e AS_ROOT="$AS_ROOT" -e HOST_UID="$(id -u)" \
    "$IMAGE" bash -c "$INNER"
rc=$?
set -e
exit "$rc"
