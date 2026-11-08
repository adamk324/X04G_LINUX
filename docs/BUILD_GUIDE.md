# Build guide

## Environment decision

| Option | Use for | Why |
|---|---|---|
| **GitHub Actions** (`ubuntu-24.04`) | all kernel/DTB/module builds | reproducible, cached, no local CPU time; artifacts downloadable |
| **WSL2 Ubuntu 24.04** | local kernel builds when iterating fast, `mkbootimg`, `pmbootstrap` | same toolchain as CI; pmbootstrap needs Linux |
| **Native Windows (PowerShell)** | MTKClient, `fastboot`, `adb`, serial console | USB access is simplest on the host; USB passthrough into WSL (usbipd) is fragile with the 5 s BootROM window |
| Linux VM | not needed | WSL2 covers it |

Rule of thumb: **anything touching USB → PowerShell. Anything building → Actions or WSL.**

## GitHub Actions

Workflow: `.github/workflows/kernel-build.yml`. Triggers on pushes to `main` / `dev/**` touching
kernel inputs, on PRs, and manually (Actions → kernel-build → Run workflow; choose a config fragment).

Steps: checkout → read pinned SHA → apt cross toolchain → ccache restore → fetch exact kernel
commit (`--depth 1`) + patches → build `Image.gz`, modules, DTBs → verify outputs → upload.

Artifact `x04g-kernel-<release>-<fragment>-<sha8>` contains:

```
boot/Image.gz              compressed arm64 kernel
boot/mt8167-xiaomi-x04g.dtb
boot/Image.gz-dtb          Image.gz with appended DTB (MTK LK style)
boot/mt8167-xiaomi-x04g.dts  decompiled DTB for review
boot/config-<release>      full .config
boot/System.map-<release>
modules-<release>.tar.gz   /lib/modules tree (stripped)
build-info.txt             kernel/project commits, toolchain, fragment, patches
build.log                  full log incl. fragment check
SHA256SUMS
```

Download with the GitHub CLI (PowerShell or WSL):

```powershell
gh run list -R adamk324/X04G_LINUX -w kernel-build -L 5
gh run download <run-id> -R adamk324/X04G_LINUX -D artifacts
```

## Local build (WSL2 Ubuntu 24.04 shell)

```bash
sudo apt-get install -y gcc-aarch64-linux-gnu flex bison bc libssl-dev libelf-dev \
    device-tree-compiler cpio kmod ccache mkbootimg
git clone https://github.com/adamk324/X04G_LINUX && cd X04G_LINUX
scripts/linux/fetch-kernel.sh          # -> build/linux at pinned SHA
scripts/linux/build-kernel.sh          # -> build/artifacts
# faster rebuilds:
CROSS_COMPILE="ccache aarch64-linux-gnu-" scripts/linux/build-kernel.sh
```

Keep the clone inside the WSL filesystem (`~/`), not under `/mnt/c` — builds on the Windows
filesystem are many times slower.

## Boot image (after backup — WSL shell)

```bash
scripts/linux/mkbootimg-from-stock.sh /mnt/d/<backup>/partitions/boot.bin \
    build/artifacts/boot  <initramfs.cpio.gz|none>  build/x04g-linux-boot.img
```

The script copies every header field from your stock image and matches its kernel format.
