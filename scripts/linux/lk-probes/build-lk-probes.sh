#!/usr/bin/env bash
# Build LK probe boot images (P1..P3) and, if a stock boot.img is given, P0 (stock, unchanged)
# and P2 (probe with the stock DT).
# Usage: scripts/linux/lk-probes/build-lk-probes.sh <artifacts/boot dir> <initramfs.cpio.gz> <out-dir> [stock boot.img]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../../.." && pwd)"
source "$ROOT/configs/bootimg-x04g.env"
BOOTDIR="$1"; RAMDISK="$2"; OUT="$3"; STOCK="${4:-}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$OUT"
DTB="$(ls "$BOOTDIR"/*.dtb | head -n1)"

aarch64-linux-gnu-as "$HERE/probe64-entry.S" -o "$W/e64.o"
aarch64-linux-gnu-objcopy -O binary "$W/e64.o" "$W/probe64-entry.bin"
asm32() {  # asm32 <src> <out-name> [--defsym ...]
    local src="$1" out="$2"; shift 2
    (cd "$W" && arm-linux-gnueabihf-as -I "$W" "$@" "$HERE/$src.S" -o "$out.o")
    arm-linux-gnueabihf-objcopy -O binary "$W/$out.o" "$W/$out.bin"
}
asm32 probe32-reset  probe32-reset
asm32 probe64-switch probe64-switch                                      # P3: smc 0x82000200 (zimage64)
asm32 probe64-switch probe64-lk115 --defsym SIP_ID_LO=0x0115 --defsym SET_R3_ZERO=1   # P4: LK's call
asm32 probe64-switch probe64-lk115-r3 --defsym SIP_ID_LO=0x0115          # P4b: r3 garbage
aarch64-linux-gnu-as "$HERE/probe64-native.S" -o "$W/n.o"
aarch64-linux-gnu-objcopy -O binary "$W/n.o" "$W/probe64-native.bin"
gzip -9n -c "$W/probe64-native.bin" > "$W/probe64-native.bin.gz"

if ! mkbootimg --help >/dev/null 2>&1; then
    mkdir -p "$W/py/gki"; : > "$W/py/gki/__init__.py"
    printf 'def generate_gki_certificate(*a, **k):\n    raise SystemExit("v4")\n' > "$W/py/gki/generate_gki_certificate.py"
    export PYTHONPATH="$W/py"
fi
CMD="$ZIMAGE64_BOOTOPT console=tty0 loglevel=7"
mk() {  # mk <kernel> <dtb-section> <out> [kernel-addr] [bootopt]
    mkbootimg --header_version "$BOOTIMG_HEADER_VERSION" --pagesize "$BOOTIMG_PAGESIZE" \
        --base "$BOOTIMG_BASE" --kernel_offset "${4:-$ZIMAGE64_KERNEL_ADDR}" \
        --ramdisk_offset "$BOOTIMG_RAMDISK_ADDR" --second_offset "$BOOTIMG_SECOND_ADDR" \
        --tags_offset "$BOOTIMG_TAGS_ADDR" --dtb_offset "$BOOTIMG_DTB_ADDR" \
        --os_version "$BOOTIMG_OS_VERSION" --os_patch_level "$BOOTIMG_OS_PATCH_LEVEL" --board "" \
        --kernel "$1" --ramdisk "$RAMDISK" --dtb "$2" --cmdline "${5:-$ZIMAGE64_BOOTOPT} console=tty0 loglevel=7" --output "$3"
    echo "built $(basename "$3") ($(stat -c %s "$3") bytes)"
}
cat "$W/probe32-reset.bin"  "$DTB" > "$W/k1"
cat "$W/probe64-switch.bin" "$DTB" > "$W/k3"
mk "$W/k1" "$DTB" "$OUT/x04g-P1-lk-jump32.img"
mk "$W/k3" "$DTB" "$OUT/x04g-P3-aarch64-switch.img"
cat "$W/probe64-lk115.bin"    "$DTB" > "$W/k4";  mk "$W/k4"  "$DTB" "$OUT/x04g-P4-aarch64-switch-lk115.img"
cat "$W/probe64-lk115-r3.bin" "$DTB" > "$W/k4b"; mk "$W/k4b" "$DTB" "$OUT/x04g-P4b-aarch64-switch-lk115-r3.img"
cat "$W/probe64-native.bin.gz" "$DTB" > "$W/k5"; mk "$W/k5" "$DTB" "$OUT/x04g-P5-native64-stub.img" "$NATIVE64_KERNEL_ADDR" "$NATIVE64_BOOTOPT"
if [ -n "$STOCK" ]; then
    cp "$STOCK" "$OUT/x04g-P0-stock-control.img"
    unpack_bootimg --boot_img "$STOCK" --out "$W/stock" >/dev/null
    SDTB="$W/stock/dtb"                                   # v2 DTB section exactly as stock
    python3 - "$SDTB" "$W/stock.dtb" <<'PY'
import sys; b=open(sys.argv[1],'rb').read(); i=b.find(b'\xd0\x0d\xfe\xed'); open(sys.argv[2],'wb').write(b[i:])
PY
    cat "$W/probe32-reset.bin" "$W/stock.dtb" > "$W/k2"
    mk "$W/k2" "$SDTB" "$OUT/x04g-P2-lk-jump32-stockdt.img"
fi
