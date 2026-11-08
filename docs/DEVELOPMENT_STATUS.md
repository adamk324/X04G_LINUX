# Development status

Legend: **source** = checked by reading source code · **built** = compiled successfully ·
**emulated** = tested in an emulator · **hardware** = tested on the X04G.

| Milestone | State |
|---|---|
| 1 Research | done (source/docs level): see HARDWARE_RESEARCH, BOOT_ARCHITECTURE, KERNEL_DEVELOPMENT, DISTRO_SELECTION |
| 2 Dev environment | scripts + CI workflow written; repo pushed to GitHub; local cloud build OK; GitHub Actions verified (run #2 green, artifact uploaded) |
| 3 Kernel compilation | done: reproducible build locally and in CI (built, not booted) |
| 4 Device preparation | **blocked on you:** run the read-only backup (RECOVERY.md) |
| 5–8 | not started |

## Build results

| Date | Where | Kernel | Result |
|---|---|---|---|
| 2026-11-08 | cloud session (Ubuntu 24.04, gcc 13.3.0 cross, binutils 2.42) | lscorcia x04g-7.3 @ 2fb2bc1 | **built**: release `7.3.0-x04g`; Image.gz 10.3 MB (sha256 e994aec9d1120225…), DTB 31 KB (sha256 b43bd2d0843f6f61…, compatible `xiaomi,x04g`), 801 modules incl. edt-ft5x06, em3071x, es7243, mt8167 AFE; all fragment options applied. Not booted. |
| 2026-11-08 | GitHub Actions run [#2](https://github.com/adamk324/X04G_LINUX/actions/runs/42495456144) (ubuntu-24.04, workflow_dispatch @ 19c55b9) | same | **success**: build step 26m53s (cold ccache), artifact `x04g-kernel-7.3.0-x04g-x04g-19c55b9e` (31.3 MB). Run #1 (push) was cancelled by the concurrency group, fixed since. |

## Hardware tests

None yet.

## Next steps

1. Compare CI vs local SHA256SUMS (reproducibility check).
2. You: `setup-mtkclient.ps1`, then `backup-x04g.ps1` identify/boot/partitions/full/verify.
3. Fill in HARDWARE_RESEARCH §6 from the identify output.
4. Build boot.img from your stock header (`mkbootimg-from-stock.sh`) and plan the first RAM boot.
   The seccfg unlock needs your approval first.
5. pmOS device package (`rootfs/pmaports/device-xiaomi-x04g`) using the netboot initramfs.
