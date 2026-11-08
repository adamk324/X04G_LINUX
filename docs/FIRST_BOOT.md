# First Linux boot — RAM only (`fastboot boot`)

## Hardware results so far

| Date | Image | Result |
|---|---|---|
| 2026-11-08 | `x04g-diag-boot.img` (c38b74f) | `fastboot boot`: Sending OKAY, **Booting OKAY**. Screen kept LK's "USB Transmission OK" text, then after ~20 s the clock reset into stock Android. No kernel output on screen. → LK accepted and jumped; kernel hung early, or ran without screen and without feeding LK's watchdog. Undetermined without UART. |

## Timing tests (no UART needed)

Start a stopwatch when `fastboot` prints `Booting OKAY`, stop when the Mi logo appears.

| Image | cmdline extras | init |
|---|---|---|
| `x04g-T1-canary.img` | `panic=3` | sleep 8 s, `reboot -f` |
| `x04g-T2-canary-safe.img` | `panic=3 maxcpus=1 clk_ignore_unused pd_ignore_unused` | same |
| `x04g-T3-diag-safe.img` | `panic=3 clk_ignore_unused pd_ignore_unused` | diagnostic init + feeds `/dev/watchdog0` |

Reading: **~9–13 s** = userspace ran · **~3–6 s** = kernel panic · **~20 s** = early hang
(LK watchdog). QEMU reference for T1: userspace at 1.0 s, reboot at 9.0 s (emulated).


Nothing is written to the clock. The image lives in RAM; unplugging the clock returns it to
stock Android exactly as before.

## What the test image is

`x04g-diag-boot.img` = our kernel `7.3.0-x04g` (+ DTB with patch 0001) + the diagnostic
initramfs from `rootfs/test-initramfs/` (busybox 1.36.1). The initramfs **never mounts or
writes eMMC**. It:

* shows the kernel log on the panel (fbcon, rotated), then a status line every 10 s;
* collects a read-only hardware report in `/run/x04g-report.txt`;
* exposes **USB serial (CDC ACM)** with a root shell and **USB network (CDC NCM)**,
  clock = `172.16.42.1`, PC gets `172.16.42.2`, `telnet 172.16.42.1`.

Rebuild (WSL/CI):
```bash
scripts/linux/build-busybox.sh
rootfs/test-initramfs/build.sh build/busybox-out/busybox build/artifacts/modules-7.3.0-x04g.tar.gz build/initramfs.cpio.gz
scripts/linux/mkbootimg-from-stock.sh backups/<adb-session>/partitions/boot.bin build/artifacts/boot build/initramfs.cpio.gz build/x04g-diag-boot.img
```

## Procedure (PowerShell, platform-tools folder)

```powershell
cd F:\platform-tools-latest-windows\platform-tools
.\adb reboot bootloader            # clock shows "=> FASTBOOT mode..."
.\fastboot devices                 # must list the clock (driver: see below)
.\fastboot getvar unlocked
.\fastboot getvar max-download-size
.\fastboot boot D:\X04G_clock_linux\X04G_LINUX\build\x04g-diag-boot.img
```

If `fastboot devices` is empty: Device Manager → the unknown "Android"/MT65xx device →
update driver → *Android Bootloader Interface* (Google USB driver).

## What to report back

| Observation | Meaning |
|---|---|
| `fastboot boot` output (OKAY / FAILED + message) | whether LK accepts RAM boot |
| Screen: Mi logo only / orange-state text / scrolling text | LK jumped? kernel console alive? |
| Rotated text readable? | DSI panel + fbcon OK |
| New USB device "Mi Smart Clock (Linux)", COM port, network adapter | USB gadget OK |
| Touching the screen (in the serial shell: `cat /dev/input/event*` and tap) | touch |
| Contents of `/run/x04g-report.txt` | everything else (iomem, mmc, drm, thermal) |

Get the report: open the COM port in PuTTY (any baud), or `telnet 172.16.42.1`, then
`cat /run/x04g-report.txt`.

## Getting out

Unplug the clock, plug it back in: stock Android boots, unchanged. If the screen stays black,
wait 60 s and do the same. (The ramoops/pstore crash log only helps once Linux can warm-reboot
into Linux again; with RAM booting, Android boots in between and may overwrite that area.)
