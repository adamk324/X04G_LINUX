#!/usr/bin/env bash
# Build an X04G boot.img from the measured stock parameters (configs/bootimg-x04g.env).
# Needs no stock boot.img, so it also runs in CI.
#
# Usage: scripts/linux/mkbootimg-x04g.sh <mode> <artifacts/boot dir> <initramfs.cpio.gz> <out.img> [extra cmdline]
#   mode: zimage64  - 32-bit zImage path + zimage64 shim (default choice)
#         native64  - LK's own 64-bit path (Image.gz-dtb, 64N2)
# Env:   MKZIMAGE64=<path to mkzimage64>  (default build/zimage64/mkzimage64)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../configs/bootimg-x04g.env
source "$ROOT/configs/bootimg-x04g.env"
MODE="$1"; BOOTDIR="$2"; RAMDISK="$3"; OUTIMG="$4"; EXTRA="${5:-}"
MKZ="${MKZIMAGE64:-$ROOT/build/zimage64/mkzimage64}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

DTB="$(ls "$BOOTDIR"/*.dtb | head -n1)"
case "$MODE" in
    zimage64)
        [ -x "$MKZ" ] || { echo "mkzimage64 not found ($MKZ); run scripts/linux/build-zimage64.sh" >&2; exit 1; }
        gzip -dc "$BOOTDIR/Image.gz" > "$WORK/Image"
        # shim + compressed kernel, DTB appended after the compressed data
        "$MKZ" "$WORK/Image" "$WORK/zImage64" "$DTB"
        KERNEL="$WORK/zImage64"; KADDR="$ZIMAGE64_KERNEL_ADDR"; BOOTOPT="$ZIMAGE64_BOOTOPT" ;;
    native64)
        KERNEL="$BOOTDIR/Image.gz-dtb"; KADDR="$NATIVE64_KERNEL_ADDR"; BOOTOPT="$NATIVE64_BOOTOPT" ;;
    *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac

# Ubuntu 24.04's mkbootimg lacks its `gki` helper module (only needed for header v4)
if ! mkbootimg --help >/dev/null 2>&1; then
    mkdir -p "$WORK/pystub/gki"; : > "$WORK/pystub/gki/__init__.py"
    printf 'def generate_gki_certificate(*a, **k):\n    raise SystemExit("header v4 unsupported")\n' \
        > "$WORK/pystub/gki/generate_gki_certificate.py"
    export PYTHONPATH="$WORK/pystub${PYTHONPATH:+:$PYTHONPATH}"
fi

# Payload placement must avoid firmware RAM measured on the device
python3 - "$RAMDISK" "$BOOTIMG_RAMDISK_ADDR" "$DTB" "$BOOTIMG_DTB_ADDR" <<'PY'
import os, sys
rd, rda, dtb, dta = sys.argv[1], int(sys.argv[2], 0), sys.argv[3], int(sys.argv[4], 0)
fw = [(0x54400000, 0x54500000, 'persistent_ram'), (0x54600000, 0x54630000, 'ATF'), (0x7f000000, 0x80000000, 'LK/fb')]
for n, a, s in (('ramdisk', rda, os.path.getsize(rd)), ('dtb', dta, 64 * 1024)):
    for lo, hi, o in fw:
        if a < hi and a + s > lo:
            sys.exit('ERROR: %s 0x%x+0x%x overlaps %s' % (n, a, s, o))
PY

CMDLINE="$BOOTOPT console=tty0 fbcon=rotate:3 loglevel=7 $EXTRA"
mkbootimg --header_version "$BOOTIMG_HEADER_VERSION" --pagesize "$BOOTIMG_PAGESIZE" \
    --base "$BOOTIMG_BASE" --kernel_offset "$KADDR" --ramdisk_offset "$BOOTIMG_RAMDISK_ADDR" \
    --second_offset "$BOOTIMG_SECOND_ADDR" --tags_offset "$BOOTIMG_TAGS_ADDR" \
    --dtb_offset "$BOOTIMG_DTB_ADDR" --os_version "$BOOTIMG_OS_VERSION" \
    --os_patch_level "$BOOTIMG_OS_PATCH_LEVEL" --board "" \
    --kernel "$KERNEL" --ramdisk "$RAMDISK" --dtb "$DTB" \
    --cmdline "$(echo $CMDLINE)" --output "$OUTIMG"
[ "${#CMDLINE}" -lt 900 ] || echo "WARN: cmdline ${#CMDLINE} chars; LK adds ~770 to a 2048-byte buffer" >&2
echo "built $OUTIMG ($MODE, kernel @ $KADDR, $(stat -c %s "$OUTIMG") bytes)"
