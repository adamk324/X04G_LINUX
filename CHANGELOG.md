# Changelog

## 2026-11-08 — T4 result, initcall-debug images

- T4 on hardware: no USB enumeration within 63 s, then reset (timeline from x04g-usb-monitor).
- T5/T6: `initcall_debug` on the panel via simpledrm (mtk_drm_init blacklisted); T5 also
  blacklists OP-TEE, eFuse, HW RNG, thermal, DEVAPC initcalls. QEMU: blacklist honoured, READY.
- LK cmdline buffer measured from lk.bin: 2048 bytes, panics on overflow.

## 2026-11-08 — fix: monitor script aborted on fastboot's stderr

- x04g-usb-monitor.ps1: Windows PowerShell 5.1 turned fastboot's stderr progress lines into a
  terminating error (ErrorActionPreference=Stop), aborting right after "Sending". fastboot now
  runs as a .NET process with both streams captured (tested with a stderr-writing stub).

## 2026-11-08 — USB-only debugging (no UART available)

- Kernel: built-in legacy g_serial + U_SERIAL_CONSOLE (`console=ttyGS0`): kernel log on a Windows
  COM port from the moment the MUSB controller probes; dummy_hcd as module for emulator tests.
- Diagnostic init rewritten: timestamped stages S01–S10 + heartbeat (kmsg/USB console, file,
  panel), unbinds g_serial and binds configfs ACM+NCM (falls back to g_serial), `getty -L`
  shell, DHCP + telnet on 172.16.42.1, NCM interface name from configfs, 8 s UDC wait.
- Emulated self-test (QEMU + dummy_hcd): g_serial bound at kernel stage, switch to composite,
  host-side DHCP lease 172.16.42.2, ACM shell round-trip. Added to CI.
- scripts/windows/x04g-usb-monitor.ps1: fastboot boot + timestamped USB/COM/network timeline,
  pulls stage log and report over serial.
- docs/USB_DEBUGGING.md: channels, expected Windows enumeration, failure reading table.
- New primary test image x04g-T4-usbdiag.img; T1/T2 rebuilt with the new kernel.

## 2026-11-08 — first hardware boot attempt

- `fastboot boot x04g-diag-boot.img`: LK accepted (Booting OKAY), no kernel output on screen,
  reset to Android after ~20 s.
- LK `cmd_boot` analysed: address checks pass, kernel inflated from the download buffer,
  dconfig overlay check is a stub that always succeeds.
- Timing canary initramfs (`canary-init`) and three RAM-boot test images (T1–T3) to locate the
  hang without UART; diagnostic init now feeds /dev/watchdog0.

## 2026-11-08 — first boot image (RAM boot), LK analysed

- backup-x04g-adb.ps1: the user's run showed every LF expanded to CRLF (su behind a tty). Script
  now undoes this when the raw hash mismatches and accepts only a device-hash match. The user's
  six images were repaired the same way; all match the device SHA-256.
- Static analysis of the stock LK: bootopt parsing, 512 KiB kernel alignment rule for 64-bit,
  gzip-only decompress, v2 DTB / appended DTB, `/memory` rewrite, fastboot `boot` command exists
  (BOOT_ARCHITECTURE.md).
- Stock boot.img measured: header v2, page 2048, ramdisk 0x55000000, tags/DTB 0x54000000.
- rootfs/test-initramfs: read-only diagnostic init (screen status, report, USB ACM shell + NCM
  network/telnet). scripts/linux/build-busybox.sh (busybox 1.36.1, static aarch64).
- CI: builds busybox + diagnostic initramfs and smoke-boots kernel + initramfs in QEMU virt.
- QEMU (emulated): init runs, modules load, report written, PID 1 stays alive.
- First image `x04g-diag-boot.img` built from the user's stock header; payloads verified.
- Fix: mkbootimg-from-stock.sh and verify_backup.py were committed without the executable bit.

## 2026-11-08 — facts from the user's unit (stock Android over ADB)

- Unit is already bootloader-unlocked (orange); stock kernel is 32-bit (`bootopt=64S3,32N2,32N2`).
- mkbootimg-from-stock.sh: force `bootopt=…,64N2`, load arm64 kernel at 0x40080000, default
  payload Image.gz-dtb, refuse ramdisk/DTB placement on firmware RAM.
- patches/kernel/0001: X04G DT declares 1 GiB, reserves persistent_ram (as ramoops) and the
  LK/framebuffer area 0x7f000000 +16 MiB. Built; DTB checked with fdtget. Not booted.
- configs: PSTORE / PSTORE_RAM / PSTORE_CONSOLE / PSTORE_PMSG.
- scripts/windows/backup-x04g-adb.ps1: read-only ADB backup with device-side SHA-256 check
  (syntax-checked with pwsh 7.4; binary capture tested with a fake adb).

## 2026-11-08 — first successful kernel build

- First green GitHub Actions run (#2, run id 42495456144); artifact uploaded.
- kernel-build.yml: concurrency group now includes the event, so a manual dispatch no longer cancels the push run.

- First kernel build `7.3.0-x04g` succeeded (cloud session, gcc 13.3.0). Built only, not booted.
- build-kernel.sh: fixed a silent exit (gzip SIGPIPE under pipefail) in the Image magic check;
  empty LOCALVERSION so the release has no `+`; stale module tarballs are removed.
- mkbootimg-from-stock.sh: stub for Ubuntu 24.04's missing `gki` module, keeps empty args
  (`--board ''`), preserves the MTK `bootopt=` token from the stock cmdline. Tested against a
  synthetic header-v2 image: payloads and offsets round-trip.

## 2026-11-08 — Milestone 1/2 bootstrap

- Repository structure, docs (hardware, boot chain, recovery, kernel, build, distro, status, issues).
- Pinned kernel: lscorcia/linux `x04g-7.3` @ `2fb2bc1fd01c` (mainline v7.3 + X04G patches).
- `configs/x04g.config`: device options from lscorcia's pmOS config; non-MediaTek platforms,
  PCI/ACPI/KVM/media etc. disabled to shorten builds.
- `scripts/linux/fetch-kernel.sh`, `build-kernel.sh` (fragment check + output verification + metadata),
  `mkbootimg-from-stock.sh` (clones the stock boot.img header).
- `scripts/windows/setup-mtkclient.ps1`, `backup-x04g.ps1` (read-only, `--noreconnect`),
  `scripts/verify_backup.py` (tested on a synthetic GPT image).
- GitHub Actions `kernel-build.yml` (ubuntu-24.04, ccache, artifacts).
