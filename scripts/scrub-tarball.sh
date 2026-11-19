#!/bin/bash
# scrub-tarball.sh — build the release source tarball from git-tracked content only.
#
# gitx-release contract (build_source_tarball): gitx uses this hook instead of
# its own rsync staging ONLY when this file is executable AND the project is a
# git work tree. It runs
#     bash scripts/scrub-tarball.sh <out.tar.gz> <prefix> <ref>
# then extracts the result, injects Release/CHANGELOG.md and re-packs.
# Why -x matters: without the mode bit gitx silently takes the rsync path,
# whose exclude list hard-codes the pre-v4 names, so the current project-state
# files would ship. Keep git mode 100755 (the release contract test asserts it).
# What stays out is decided by the root-anchored export-ignore lines in
# .gitattributes, not by a name list here: one list, read by git itself.
set -euo pipefail
# Why (report 5 HX-08): no `._*` AppleDouble members, whatever the caller's
# environment. git archive itself writes none; the setting also reaches any tar
# this process starts, and documents the contract next to the archive step.
export COPYFILE_DISABLE=1

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <out.tar.gz> <prefix> <ref>" >&2
    exit 2
fi
out="$1"; prefix="$2"; ref="$3"
# Empty operands: an empty <prefix> would archive at the tarball root and an
# empty <ref>/<out> only fails later with a vaguer git/gzip error.
if [ -z "$out" ] || [ -z "$prefix" ] || [ -z "$ref" ]; then
    echo "❌ scrub-tarball.sh: <out>, <prefix> and <ref> must all be non-empty" >&2
    exit 2
fi
# gitx passes absolute paths but does not promise the cwd: resolve <out> first,
# then archive the repository this script lives in, never whatever cwd holds.
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
cd "$(dirname "$0")/.."
here=$(pwd -P)
if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "❌ $here is not a git work tree — scrub-tarball.sh can only archive a git ref" >&2
    exit 2
fi
# An unpacked source tree placed inside another checkout is "inside a work
# tree" too, and git archive would then package the OUTER repository.
if [ "$top" != "$here" ]; then
    echo "❌ $here is not the top of its own git work tree (git resolves to $top) — refusing to archive another repository" >&2
    exit 2
fi

# Explicit failure branch, not `… && mv`: inside an && list errexit does not
# fire, and a successful cleanup there would launder the failure into exit 0.
if ! git archive --worktree-attributes --format=tar --prefix="$prefix/" "$ref" | gzip -n > "$out.tmp"; then
    rm -f "$out.tmp"
    echo "❌ git archive of '$ref' failed — no tarball written to $out" >&2
    exit 1
fi
mv "$out.tmp" "$out"
