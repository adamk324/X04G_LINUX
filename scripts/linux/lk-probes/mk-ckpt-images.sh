#!/usr/bin/env bash
# Build one RAM-boot image per kernel boot checkpoint (patches/kernel/0002).
# Each image is the same kernel with x04g_ckpt_cfg.reset_at = N patched into the Image;
# the board resets via PSCI as soon as checkpoint N is reached.
#
# Usage: scripts/linux/lk-probes/mk-ckpt-images.sh <artifacts/boot dir> <initramfs.cpio.gz> <out-dir> [N ...]
# Default checkpoints: 1..25 (see docs/USB_DEBUGGING.md for their meaning) and 99 (never fires).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
source "$ROOT/configs/bootimg-x04g.env"
BOOTDIR="$1"; RAMDISK="$2"; OUT="$3"; shift 3
LIST="${*:-1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 99}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
DTB="$(ls "$BOOTDIR"/*.dtb | head -n1)"
gzip -dc "$BOOTDIR/Image.gz" > "$W/Image"
if ! mkbootimg --help >/dev/null 2>&1; then
    mkdir -p "$W/py/gki"; : > "$W/py/gki/__init__.py"
    printf 'def generate_gki_certificate(*a, **k):\n    raise SystemExit("v4")\n' > "$W/py/gki/generate_gki_certificate.py"
    export PYTHONPATH="$W/py"
fi
for n in $LIST; do
    python3 - "$W/Image" "$W/Image.$n" "$n" <<'PY'
import sys
src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
b = bytearray(open(src, 'rb').read())
i = b.find(b'X04GCKPT')
if i < 0 or b.count(b'X04GCKPT') != 1:
    sys.exit('checkpoint config not found exactly once (is patch 0002 applied?)')
b[i + 8:i + 12] = n.to_bytes(4, 'little')
open(dst, 'wb').write(b)
PY
    gzip -9n -c "$W/Image.$n" > "$W/Image.$n.gz"
    cat "$W/Image.$n.gz" "$DTB" > "$W/k.$n"
    mkbootimg --header_version "$BOOTIMG_HEADER_VERSION" --pagesize "$BOOTIMG_PAGESIZE" \
        --base "$BOOTIMG_BASE" --kernel_offset "$NATIVE64_KERNEL_ADDR" \
        --ramdisk_offset "$BOOTIMG_RAMDISK_ADDR" --second_offset "$BOOTIMG_SECOND_ADDR" \
        --tags_offset "$BOOTIMG_TAGS_ADDR" --dtb_offset "$BOOTIMG_DTB_ADDR" \
        --os_version "$BOOTIMG_OS_VERSION" --os_patch_level "$BOOTIMG_OS_PATCH_LEVEL" --board "" \
        --kernel "$W/k.$n" --ramdisk "$RAMDISK" --dtb "$DTB" \
        --cmdline "$NATIVE64_BOOTOPT console=tty0 console=ttyGS0,115200 loglevel=7 panic=10 clk_ignore_unused pd_ignore_unused" \
        --output "$OUT/x04g-C$(printf %02d "$n").img"
done
ls "$OUT" | head -40
