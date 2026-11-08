#!/usr/bin/env bash
# Build the zimage64 boot shim (mkzimage64 host tool + embedded aarch64 payload).
# Usage: scripts/linux/build-zimage64.sh [out-dir]
# Env:   ZIMAGE64_SRC=<dir>  use an existing checkout (e.g. cloned on the Windows PC) instead
#                            of cloning; commits are still verified when it is a git checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../configs/bootimg-x04g.env
source "$ROOT/configs/bootimg-x04g.env"
OUT="${1:-$ROOT/build/zimage64}"
SRC="${ZIMAGE64_SRC:-$ROOT/build/zimage64-src}"
CROSS="${ZIMAGE64_CROSS:-aarch64-linux-gnu-}"

if [ ! -e "$SRC/Makefile" ]; then
    git clone -q "$ZIMAGE64_REPO" "$SRC"
    git -C "$SRC" -c advice.detachedHead=false checkout -q "$ZIMAGE64_COMMIT"
    git -C "$SRC" submodule update --init -q udt
    # uzlib comes from GitHub; pin it explicitly
    rm -rf "$SRC/uzlib"
    git clone -q "$ZIMAGE64_UZLIB_REPO" "$SRC/uzlib"
    git -C "$SRC/uzlib" -c advice.detachedHead=false checkout -q "$ZIMAGE64_UZLIB_COMMIT"
fi
check() {  # verify a checkout is at the pinned commit (skipped for plain source copies)
    if git -C "$1" rev-parse HEAD >/dev/null 2>&1; then
        [ "$(git -C "$1" rev-parse HEAD)" = "$2" ] || { echo "ERROR: $1 is not at $2" >&2; exit 1; }
    else
        echo "WARN: $1 is not a git checkout, commit not verified" >&2
    fi
}
check "$SRC" "$ZIMAGE64_COMMIT"
check "$SRC/udt" "$ZIMAGE64_UDT_COMMIT"
check "$SRC/uzlib" "$ZIMAGE64_UZLIB_COMMIT"

make -s -C "$SRC" clean >/dev/null 2>&1 || true
make -s -C "$SRC" CC="${CROSS}gcc" READELF="${CROSS}readelf" OBJCOPY="${CROSS}objcopy" mkzimage64
mkdir -p "$OUT"
install -m 0755 "$SRC/mkzimage64" "$OUT/mkzimage64"
install -m 0644 "$SRC/payload.bin" "$OUT/payload.bin"
echo "zimage64: $OUT/mkzimage64 (payload $(stat -c %s "$OUT/payload.bin") bytes, src ${ZIMAGE64_COMMIT:0:12})"
