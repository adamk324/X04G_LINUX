# X04G_LINUX

Mainline Linux port for the **Xiaomi Mi Smart Clock (X04G / LX04)**, MediaTek MT8167, 1 GiB RAM,
4" 800×480 touchscreen. The goal is a lightweight, maintainable Linux smart display.

This repo builds on community work. It does not fork it:
[lscorcia/linux](https://github.com/lscorcia/linux) (`x04g-7.3`, mainline v7.3 + X04G patches),
[lscorcia/linux-mt8167-consys](https://github.com/lscorcia/linux-mt8167-consys) (Wi-Fi/BT),
[octathorp/x04g_tools](https://github.com/octathorp/x04g_tools),
[Informatic/xiaomi-x04g-research](https://github.com/Informatic/xiaomi-x04g-research),
[bkerler/mtkclient](https://github.com/bkerler/mtkclient).

## Layout

```
.github/workflows/kernel-build.yml   CI: pinned kernel -> Image.gz, DTB, modules, logs (artifacts)
kernel/source.env                    pinned kernel / consys / firmware revisions
configs/x04g.config                  kernel config fragment (on top of arm64 defconfig)
patches/kernel/                      our patches on top of the pinned kernel (applied in order)
scripts/linux/                       fetch / build / boot-image scripts (WSL2 or CI)
scripts/windows/                     PowerShell: MTKClient setup, read-only backup
scripts/verify_backup.py             backup verifier (GPT CRC + byte compare), any OS
docs/                                research, boot chain, recovery, build guide, status
device-tree/ rootfs/ interface/      future milestones
```

## Quick start

* **Kernel build:** push to `main`, or run *Actions → kernel-build → Run workflow*, then download
  the artifact. Local build steps are in [docs/BUILD_GUIDE.md](docs/BUILD_GUIDE.md).
* **Device:** start with [docs/RECOVERY.md](docs/RECOVERY.md). Make and verify a full backup
  before anything is written to the clock.

## Status

See [docs/DEVELOPMENT_STATUS.md](docs/DEVELOPMENT_STATUS.md). Nothing has been tested on hardware yet.
