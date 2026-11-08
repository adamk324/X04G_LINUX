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
echo "stock kernel format: $KFMT (informational)"

# The stock X04G kernel is 32-bit ARM (bootopt=...,32N2), so its format says nothing about
# what LK wants for an AArch64 kernel. Measured on the user's unit (2026-11-08):
#   bootopt=64S3,32N2,32N2  ->  ATF 64-bit, LK 32-bit, kernel 32-bit.
# For our arm64 kernel the default is Image.gz with appended DTB (MTK LK 64-bit path
# decompresses gzip and looks for an appended FDT); header-v2 images get the DTB section too.
# Override with KERNEL_FORMAT=gzip|raw|gzip-dtb if a boot test shows LK needs another layout.
KFMT="${KERNEL_FORMAT:-gzip-dtb}"
echo "using kernel format: $KFMT"

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
def setarg(name, val):
    if name in res: res[res.index(name)+1] = val
    else: res.extend([name, val])
def getint(name):
    return int(res[res.index(name)+1], 0) if name in res else 0
base = getint('--base')
# Stock kernel address is 0x40008000 (32-bit zImage convention). arm64 Images are loaded at
# a 2 MiB-aligned base + 0x80000 by convention; use 0x40080000 unless overridden.
kaddr = int(os.environ.get('ARM64_KERNEL_ADDR', '0x40080000'), 0)
print('stock kernel load address: 0x%x -> 0x%x' % (base + getint('--kernel_offset'), kaddr))
setarg('--kernel_offset', '0x%08x' % (kaddr - base))
# Firmware-owned RAM measured on the user's unit (/proc/iomem, stock Android):
#   0x54400000-0x544fffff persistent_ram (ramoops), 0x54600000-0x5462ffff ATF,
#   0x7f000000-0x7fffffff LK/framebuffer holes. Payloads must not be loaded there.
fw = [(0x54400000, 0x54500000, 'persistent_ram'), (0x54600000, 0x54630000, 'ATF'),
      (0x7f000000, 0x80000000, 'LK/framebuffer')]
rsize = os.path.getsize(ramdisk) if ramdisk != 'none' else 0
for nm, start, size in (('ramdisk', base + getint('--ramdisk_offset'), rsize),
                        ('dtb', base + getint('--dtb_offset'), 64 * 1024)):
    for a, b, owner in fw:
        if start < b and start + size > a:
            sys.exit('ERROR: %s at 0x%x (+0x%x) overlaps %s 0x%x-0x%x; set offsets manually'
                     % (nm, start, size, owner, a, b))
cmd = ['mkbootimg'] + res + ['--kernel', kernel, '--output', out]
if ramdisk != 'none':
    cmd += ['--ramdisk', ramdisk]
else:
    empty = os.path.join(work,'empty.cpio'); open(empty,'wb').close(); cmd += ['--ramdisk', empty]
# Header v2 carries a separate DTB section: provide ours there too
if '--header_version' in res and int(res[res.index('--header_version')+1]) == 2:
    dtbs = [f for f in os.listdir(bootdir) if f.endswith('.dtb')]
    cmd += ['--dtb', os.path.join(bootdir, dtbs[0])]
# MTK LK reads `bootopt=<ATF>,<LK>,<kernel>` from the image cmdline and switches the CPU
# into that mode before jumping to the kernel. Stock X04G uses 64S3,32N2,32N2 (32-bit kernel);
# an arm64 kernel needs the last field to be 64N2. Keep the stock ATF/LK fields, force 64N2.
bootopt = 'bootopt=64S3,32N2,64N2'
for t in stock_cmdline.split():
    if t.startswith('bootopt='):
        f = t[len('bootopt='):].split(',')
        if len(f) == 3:
            bootopt = 'bootopt=%s,%s,64N2' % (f[0], f[1])
print('stock cmdline bootopt:', [t for t in stock_cmdline.split() if t.startswith('bootopt=')], '->', bootopt)
cmdline = ' '.join([bootopt, 'console=ttyS0,921600n1 console=tty0 earlycon fbcon=rotate:3 loglevel=7', extra])
cmd += ['--cmdline', cmdline.strip()]
print('+', ' '.join(cmd))
subprocess.check_call(cmd)
PY
ls -la "$OUTIMG"
unpack_bootimg --boot_img "$OUTIMG" --out "$WORK/verify" | head -20
