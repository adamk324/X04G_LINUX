#!/usr/bin/env bash
# Fetch the pinned kernel source into build/linux and apply patches/kernel/*.patch.
# Usage: scripts/linux/fetch-kernel.sh [dest-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../kernel/source.env
source "$ROOT/kernel/source.env"
DEST="${1:-$ROOT/build/linux}"

if [ ! -d "$DEST/.git" ]; then
    mkdir -p "$DEST"
    git -C "$DEST" init -q
    git -C "$DEST" remote add origin "$KERNEL_REPO"
fi

# Shallow fetch of exactly the pinned commit (GitHub allows fetching by SHA).
git -C "$DEST" fetch -q --depth 1 origin "$KERNEL_COMMIT"
git -C "$DEST" -c advice.detachedHead=false checkout -q -f FETCH_HEAD
git -C "$DEST" clean -qfdx -e '/out*'

HEAD_SHA="$(git -C "$DEST" rev-parse HEAD)"
if [ "$HEAD_SHA" != "$KERNEL_COMMIT" ]; then
    echo "ERROR: checked out $HEAD_SHA, expected $KERNEL_COMMIT" >&2
    exit 1
fi
echo "kernel source: $KERNEL_REPO @ $HEAD_SHA ($KERNEL_BRANCH)"

shopt -s nullglob
for p in "$ROOT"/patches/kernel/*.patch; do
    echo "applying $(basename "$p")"
    git -C "$DEST" apply --index --whitespace=nowarn "$p"
done
