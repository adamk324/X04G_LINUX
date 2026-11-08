# Changelog

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
