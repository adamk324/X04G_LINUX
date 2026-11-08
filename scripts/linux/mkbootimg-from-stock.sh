#!/usr/bin/env bash
# Build a Linux boot.img for the X04G by reusing the *stock* boot.img header
# parameters (header version, base, offsets, page size, OS version/patch level)
# and swapping in our kernel (+ DTB) and ramdisk.
#
# We deliberately do NOT hard-code load addresses: they are taken from the
# user's own stock boot.img backup, which is what the stock LK accepts.
#
# Usage:
#   scripts/linux/mkbootimg-from-stock.sh <stock-boot.img> <artifacts/boot dir> <initramfs.cpio.gz|none> <out.img> [extra cmdline]
#
# Requires: unpack_bootimg + mkbootimg (Ubuntu/Debian package "mkbootimg").
set -euo pipefail

STOCK="$1"; BOOTDIR="$2"; RAMDISK="$3"; OUTIMG="$4"; EXTRA="${5:-}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# Ubuntu 24.04's "mkbootimg" package ships without its `gki` helper module
# (only needed for boot header v4 GKI certificates). Provide a stub so v0-v3 work.
if ! python3 -c 'import gki.generate_gki_certificate' 2>/dev/null && \
   ! mkbootimg --help >/dev/null 2>&1; then
    mkdir -p "$WORK/pystub/gki"
    : > "$WORK/pystub/gki/__init__.py"
    printf 'def generate_gki_certificate(*a, **k):\n    raise SystemExit("GKI certificates (header v4) unsupported")\n' \
        > "$WORK/pystub/gki/generate_gki_certificate.py"
    export PYTHONPATH="$WORK/pystub${PYTHONPATH:+:$PYTHONPATH}"
fi

unpack_bootimg --boot_img "$STOCK" --out "$WORK/stock" > "$WORK/info.txt"
cat "$WORK/info.txt"

HDR=$(awk -F': ' '/^boot image header version/{print $2}' "$WORK/info.txt")
echo "stock header version: $HDR"

# Inspect stock kernel layout to pick the same kernel format
KFMT=raw
if [ "$(od -An -tx1 -N2 "$WORK/stock/kernel" | tr -d ' ')" = "1f8b" ]; then
    KFMT=gzip
    # Appended DTB? search for FDT magic after the gzip stream
    if python3 - "$WORK/stock/kernel" <<'PY'
import sys,zlib
b=open(sys.argv[1],'rb').read()
d=zlib.decompressobj(16+zlib.MAX_WBITS); d.decompress(b)
sys.exit(0 if d.unused_data[:4]==b'\xd0\x0d\xfe\xed' else 1)
PY
    then KFMT=gzip-dtb; fi
fi
echo "stock kernel format: $KFMT"

case "$KFMT" in
    gzip-dtb) KERNEL="$BOOTDIR/Image.gz-dtb" ;;
    gzip)     KERNEL="$BOOTDIR/Image.gz" ;;
    raw)      gzip -dc "$BOOTDIR/Image.gz" > "$WORK/Image"; KERNEL="$WORK/Image" ;;
esac

# Re-use the exact mkbootimg arguments of the stock image, then override payloads.
ARGS_FILE="$WORK/args"
unpack_bootimg --boot_img "$STOCK" --out "$WORK/stock2" --format=mkbootimg -0 > "$ARGS_FILE"

python3 - "$ARGS_FILE" "$KERNEL" "$RAMDISK" "$OUTIMG" "$EXTRA" "$WORK" "$BOOTDIR" <<'PY'
import sys, subprocess, os
argsf, kernel, ramdisk, out, extra, work, bootdir = sys.argv[1:]
a = open(argsf,'rb').read().split(b'\0')
a = [x.decode() for x in a]
if a and a[-1] == '': a.pop()   # keep empty values such as --board ''
res = []; i = 0; stock_cmdline = ''
drop_val = {'--kernel','--ramdisk','--dtb','--output','--out','--cmdline'}
while i < len(a):
    if a[i] == '--cmdline': stock_cmdline = a[i+1]
    if a[i] in drop_val: i += 2; continue
    res.append(a[i]); i += 1
cmd = ['mkbootimg'] + res + ['--kernel', kernel, '--output', out]
if ramdisk != 'none':
    cmd += ['--ramdisk', ramdisk]
else:
    empty = os.path.join(work,'empty.cpio'); open(empty,'wb').close(); cmd += ['--ramdisk', empty]
# Header v2 carries a separate DTB section: provide ours there too
if '--header_version' in res and int(res[res.index('--header_version')+1]) == 2:
    dtbs = [f for f in os.listdir(bootdir) if f.endswith('.dtb')]
    cmd += ['--dtb', os.path.join(bootdir, dtbs[0])]
# MTK LK reads `bootopt=` from the image cmdline to pick the CPU mode (e.g. 64S3,32N2,64N2
# = boot the kernel in AArch64). Keep any stock bootopt token verbatim.
keep = [t for t in stock_cmdline.split() if t.startswith('bootopt=')]
cmdline = ' '.join(keep + ['console=ttyS0,921600n1 console=tty0 earlycon fbcon=rotate:3 loglevel=7', extra])
cmd += ['--cmdline', cmdline.strip()]
print('+', ' '.join(cmd))
subprocess.check_call(cmd)
PY
ls -la "$OUTIMG"
unpack_bootimg --boot_img "$OUTIMG" --out "$WORK/verify" | head -20
