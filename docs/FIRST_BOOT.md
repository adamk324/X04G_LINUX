# First Linux boot — RAM only (`fastboot boot`)

## Hardware results so far

| Date | Image | Result |
|---|---|---|
| 2026-11-08 | `x04g-diag-boot.img` (c38b74f) | `fastboot boot`: Sending OKAY, **Booting OKAY**. Screen kept LK's "USB Transmission OK" text, then after ~20 s the clock reset into stock Android. No kernel output on screen. → LK accepted and jumped; kernel hung early, or ran without screen and without feeding LK's watchdog. Undetermined: that image had no USB channel at kernel stage (now added, see T4). |
| 2026-11-08 | `x04g-T6-initcalls.img` / T5 (adce887) | Screen keeps LK's "USB Transmission OK" (photo), no kernel text even with simpledrm + initcall_debug; no USB; preloader at 62.9 s, LK fastboot at 83.7 s. Reset time identical to T4 regardless of cmdline/drivers → the kernel most likely never executes in LK's native 64-bit path. |
| 2026-11-08 | `x04g-T4-usbdiag.img` (3ca372f) via `x04g-usb-monitor.ps1` | Booting OKAY at t=0; **no USB device at all** (kernel-stage g_serial 0525:A4A7 never enumerated); preloader at 63.2 s (reset); LK fastboot at 82.7 s, later continued to Android. → kernel did not get the MUSB controller up; suspected early hang. Suspect: CONFIG_OPTEE=y (not in lscorcia's config) and other drivers that touch secure-world resources on stock firmware. |

## Next: zimage64 boot path (T7/T8, built by CI)

pmaports boots mainline arm64 on 32-bit-firmware MediaTek devices (e.g. Doogee X5 Pro, MT6735P)
with `bootopt=64S3,32N2,32N2`, kernel at `0x40008000` and the **zimage64** shim
(gitlab.com/sleirsgoevy/zimage64; lscorcia tested commit 5668afde on MT8167, pmaports !9830).
LK starts it as a normal 32-bit zImage; the shim calls ATF `smc 0x82000200` (KERNEL_64) to
enter AArch64, inflates the real kernel to a 2 MiB-aligned address and jumps to it.

| Image (CI artifact `bootimg/`) | Purpose |
|---|---|
| `x04g-T7-zimage64-usbdiag.img` | zimage64 + USB diagnostic init (primary) |
| `x04g-T8-zimage64-canary.img` | zimage64 + timing canary (reboot 8 s after userspace) |

Built by `scripts/linux/build-zimage64.sh` + `scripts/linux/mkbootimg-x04g.sh` from the measured
parameters in `configs/bootimg-x04g.env` (no stock image needed).

## Timing tests (no UART needed)

Start a stopwatch when `fastboot` prints `Booting OKAY`, stop when the Mi logo appears.

| Image | cmdline extras | init |
|---|---|---|
| **`x04g-T5-noSecureDrivers.img`** | T4 + `initcall_debug loglevel=8 printk.time=1 initcall_blacklist=mtk_drm_init,optee_core_init,mtk_efuse_init,mtk_rng_driver_init,mtk_thermal_driver_init,mtk_devapc_driver_init` | USB diag init; screen shows every initcall (simpledrm on LK's framebuffer) |
| **`x04g-T6-initcalls.img`** | T4 + `initcall_debug loglevel=8 printk.time=1 initcall_blacklist=mtk_drm_init` | same, suspects enabled: last line on screen = hanging initcall |
| `x04g-T4-usbdiag.img` | `panic=10 console=ttyGS0,115200 console=tty0 clk_ignore_unused pd_ignore_unused` | USB-first diagnostic init — use with `x04g-usb-monitor.ps1`, see USB_DEBUGGING.md |
| `x04g-T1-canary.img` | `panic=3 console=ttyGS0,115200 console=tty0` | sleep 8 s, `reboot -f` |
| `x04g-T2-canary-safe.img` | T1 + `maxcpus=1 clk_ignore_unused pd_ignore_unused` | same |

LK's cmdline buffer is 2048 bytes (overflow → LK panic); our longest cmdline + LK's ~770 added chars ≈ 1.1 KB.
All images contain the kernel with built-in g_serial, so even the canaries show a COM port
(0525:A4A7) if the kernel gets as far as the USB controller.

Reading: **~9–13 s** = userspace ran · **~3–6 s** = kernel panic · **~20 s** = early hang
(LK watchdog). QEMU reference for T1: userspace at 1.0 s, reboot at 9.0 s (emulated).


Nothing is written to the clock. The image lives in RAM; unplugging the clock returns it to
stock Android exactly as before.

## What the test image is

`x04g-T4-usbdiag.img` = our kernel `7.3.0-x04g` (+ DTB with patch 0001) + the diagnostic
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
scripts/linux/mkbootimg-from-stock.sh backups/<adb-session>/partitions/boot.bin build/artifacts/boot build/initramfs.cpio.gz build/x04g-T4-usbdiag.img "panic=10 console=ttyGS0,115200 console=tty0 clk_ignore_unused pd_ignore_unused"
```

## Procedure (PowerShell, platform-tools folder)

```powershell
cd F:\platform-tools-latest-windows\platform-tools
.\adb reboot bootloader            # clock shows "=> FASTBOOT mode..."
.\fastboot devices                 # must list the clock (driver: see below)
.\fastboot getvar unlocked
.\fastboot getvar max-download-size
# preferred: one command that boots and records the USB timeline + report
cd D:\X04G_clock_linux\X04G_LINUX
.\scripts\windows\x04g-usb-monitor.ps1 -Image .\build\x04g-T4-usbdiag.img
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
