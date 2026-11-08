#!/usr/bin/env bash
# Build the X04G diagnostic initramfs (gzip cpio).
# Usage: rootfs/test-initramfs/build.sh <busybox-aarch64-static> <modules-*.tar.gz> <out.cpio.gz>
# Env:   INIT=<path>  init script to install as /init (default: ./init; ./canary-init = timing canary)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BB="$1"; MODTAR="$2"; OUT="$3"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
R="$WORK/root"
mkdir -p "$R"/{bin,sbin,usr/bin,usr/sbin,etc,dev,proc,sys,tmp,run,var/lib/misc,lib/modules}
install -m 0755 "$BB" "$R/bin/busybox"
# Busybox applet symlinks, without running the aarch64 binary on the build host
for a in sh ash mount umount mkdir ls cat echo sleep insmod rmmod lsmod dmesg uname head tail \
         wc awk sed grep cut tr ip ifconfig udhcpd telnetd getty setsid ps top free df \
         hexdump od xxd sha256sum md5sum dd ln cp mv rm touch chmod reboot poweroff halt \
         vi less more find stat date env sync kill killall true false test '[' '[[' printf \
         readlink basename dirname seq usleep watch netstat route ping hwclock i2cdetect \
         i2cget i2cdump devmem sysctl blockdev watchdog udhcpc timeout stty; do
    ln -sf busybox "$R/bin/$a"
done
# Modules useful for first hardware checks (built as =m in configs/x04g.config)
tar -xzf "$MODTAR" -C "$WORK"
# Loaded by /init in lexical order, hence the numeric prefixes.
# EXTRA_MODULES (space separated, in load order) is for emulator tests, e.g.
#   EXTRA_MODULES="dummy_hcd.ko mii.ko usbnet.ko cdc_ether.ko cdc_ncm.ko cdc-acm.ko"
n=10
for m in ${EXTRA_MODULES:-} edt-ft5x06.ko em3071x.ko; do
    f="$(find "$WORK/lib/modules" -name "$m" | head -n1)"
    [ -n "$f" ] && cp "$f" "$R/lib/modules/$n-$m"
    n=$((n + 1))
done
install -m 0755 "${INIT:-$HERE/init}" "$R/init"
mknod -m 600 "$R/dev/console" c 5 1 2>/dev/null || true
(cd "$R" && find . -print0 | LC_ALL=C sort -z | \
    cpio --null -o -H newc --owner=0:0 --reproducible --quiet) | gzip -9n > "$OUT"
echo "initramfs: $OUT ($(stat -c %s "$OUT") bytes)"
ls -la "$R/lib/modules"
