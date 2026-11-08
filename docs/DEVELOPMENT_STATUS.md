# Development status

Legend: **source** = checked by reading source code · **built** = compiled successfully ·
**emulated** = tested in an emulator · **hardware** = tested on the X04G.

| Milestone | State |
|---|---|
| 1 Research | done (source/docs level): see HARDWARE_RESEARCH, BOOT_ARCHITECTURE, KERNEL_DEVELOPMENT, DISTRO_SELECTION |
| 2 Dev environment | scripts + CI workflow written; local cloud build in progress; **GitHub Actions run not yet verified** |
| 3 Kernel compilation | see "Build results" |
| 4 Device preparation | **blocked on you:** run the read-only backup (RECOVERY.md) |
| 5–8 | not started |

## Build results

| Date | Where | Kernel | Result |
|---|---|---|---|
| 2026-11-08 | cloud session (Ubuntu 24.04, gcc 13.3 cross) | lscorcia x04g-7.3 @ 2fb2bc1 | in progress |

## Hardware tests

None yet.

## Next steps

1. Push repo → first GitHub Actions run → confirm artifacts.
2. You: `setup-mtkclient.ps1`, then `backup-x04g.ps1` identify/boot/partitions/full/verify.
3. Fill in HARDWARE_RESEARCH §6 from the identify output.
4. Build boot.img from your stock header (`mkbootimg-from-stock.sh`) and plan the first RAM boot.
   The seccfg unlock needs your approval first.
5. pmOS device package (`rootfs/pmaports/device-xiaomi-x04g`) using the netboot initramfs.
