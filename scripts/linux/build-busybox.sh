#!/usr/bin/env bash
# Build a static aarch64 busybox for the diagnostic initramfs.
# Usage: scripts/linux/build-busybox.sh [out-dir]   -> <out-dir>/busybox
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/busybox-out}"
BUSYBOX_REPO="https://github.com/mirror/busybox.git"
BUSYBOX_TAG="1_36_1"
BUSYBOX_COMMIT="1a64f6a20aaf6ea4dbba68bbfa8cc1ab7e5c57c4"
SRC="$ROOT/build/busybox-src"
CC_PREFIX="${CROSS_COMPILE:-aarch64-linux-gnu-}"

if [ ! -d "$SRC/.git" ]; then
    git clone -q --depth 1 -b "$BUSYBOX_TAG" "$BUSYBOX_REPO" "$SRC"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$BUSYBOX_COMMIT" ] || { echo "busybox commit mismatch" >&2; exit 1; }

make -s -C "$SRC" ARCH=arm64 CROSS_COMPILE="$CC_PREFIX" defconfig >/dev/null
# static; tc does not build against current kernel headers
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' "$SRC/.config"
yes "" | make -s -C "$SRC" ARCH=arm64 CROSS_COMPILE="$CC_PREFIX" oldconfig >/dev/null 2>&1 || true
make -s -C "$SRC" ARCH=arm64 CROSS_COMPILE="$CC_PREFIX" -j"$(nproc)" busybox 2>&1 | grep -vE "warning:|note:" || true
mkdir -p "$OUT"
install -m 0755 "$SRC/busybox" "$OUT/busybox"
file "$OUT/busybox" | grep -q "ARM aarch64.*statically linked" || { echo "busybox is not a static aarch64 binary" >&2; exit 1; }
echo "busybox: $OUT/busybox ($BUSYBOX_TAG @ ${BUSYBOX_COMMIT:0:12})"
