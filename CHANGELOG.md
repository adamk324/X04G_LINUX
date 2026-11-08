# Changelog

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
