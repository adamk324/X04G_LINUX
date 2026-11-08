# Boot architecture

## Boot chain

```
BootROM (mask ROM, 0E8D:0003 if VOL+ held)
  └─ Preloader         eMMC boot1 HW partition          (0E8D:2000 for ~2 s)
      └─ ATF BL31 + OP-TEE   GPT: tee1 / tee2 (A/B copies)  [DOC/SRC: optee node + ATF reserved mem]
          └─ LK (Little Kernel)   GPT: lk / lk2              (fastboot 0E8D:201C)
              ├─ checks seccfg (lock state) + AVB (vbmeta, vbmeta_system, vbmeta_vendor)
              └─ Android boot image   GPT: boot (normal) | recovery (key combo)
                     kernel + ramdisk (+ dtb)  → Linux
```

Facts (community, unverified on your unit):

- **VOL+ during plug-in** forces BootROM download mode → MTKClient has full eMMC read/write
  regardless of lock state. This is the universal recovery path. [DOC: Informatic, Nura wiki]
- Stock LK fastboot and fastbootd **do not accept unsigned payloads while locked**. [DOC: Informatic]
- `mtk da seccfg unlock` unlocks the bootloader → "Orange State" warning at boot. [DOC]
- After unlock, boot images repacked with magiskboot (stock header) boot fine **without touching
  vbmeta**; images built with a generic Android layout reportedly did not boot. [DOC: Informatic]
  → our `mkbootimg-from-stock.sh` clones every header field from *your* stock `boot.img`.
- The x04g DTS keeps `console=tty0` + 921600 UART and a simple-framebuffer at `0x7f1c0000`
  (LK leaves the panel initialised, 480×800 a8r8g8b8). [SRC]
- lscorcia reports running postmarketOS with the **netboot** initramfs hook (rootfs over USB) on
  the x04g (pmaports MR !8525/!8526). [DOC] — this is the recommended first-boot method: no rootfs
  on eMMC needed.

## Measured on your unit (2026-11-08)

- Bootloader is **already unlocked** (`device_state=unlocked`, orange state). The seccfg unlock
  step in RECOVERY.md is not needed.
- LK hands the kernel `bootopt=64S3,32N2,32N2`: ATF runs AArch64, LK and the stock kernel run
  AArch32. MTK LK reads this token from the boot image cmdline and switches mode before jumping
  to the kernel, so **our image must say `bootopt=64S3,32N2,64N2`** — `mkbootimg-from-stock.sh`
  now forces the last field to `64N2`.
- Stock kernel sits at `0x40008000` (zImage convention). For arm64 the script places the kernel
  at `0x40080000` (`ARM64_KERNEL_ADDR` to override) and refuses to build an image whose ramdisk or
  DTB would land on firmware RAM (persistent_ram, ATF, LK/framebuffer).
- Kernel payload defaults to `Image.gz` + appended DTB (also put in the v2 DTB section if the
  header is v2), because the stock 32-bit kernel's format does not tell us what the 64-bit LK path
  wants. `KERNEL_FORMAT=gzip|raw` overrides it if a boot test shows otherwise.

## Stock LK analysis (your `lk.bin`, sha256 7915041207940…, build `mico_x04g-451d69f-20210619014509-20211214131701`)

Static analysis of the 32-bit Thumb-2 LK (MTK header `0x58881688`, load address `0x56000000`,
`app/mt_boot/mt_boot.c`). Addresses are LK virtual addresses.

| Finding | Evidence |
|---|---|
| `bootopt=` is searched in the first 490 chars of the **boot image cmdline**; the kernel field is compared at offset 18: `"64"` → 64-bit flag, `"32"` → 32-bit | parser at `0x560310b0`; strings `"64"`/`"32"` at `0x56055c08`/`0x56052cfc`; flag at `0x56066cc4`; "Warning! No bootopt info!" otherwise |
| 64-bit path requires `kernel_addr & 0x7FFFF == 0` (512 KiB aligned), else panic "64 bit kernel can't boot at 0x%08x" | `ubfx r3, r8, #0, #0x13` at `0x56019ea0` |
| 64-bit path always calls `decompress_kernel(src, kernel_addr, size, 0xC800000)` → **gzip** (checks deflate method 8 + gzip flags; "gzip header is not correct") with a 200 MB output limit | `0x5601a04a`, `0x5601c528`, `0x5601c4a8` |
| Header v2: DTB taken from the v2 DTB section ("mkdtimg format" or "fdt format only"); otherwise LK scans backwards from the kernel end for an appended FDT | `bldr_load_dtb` around `0x5601e700` |
| LK rewrites `/memory` from its mblock table ("PASS memory DTS node") and copies the DTB to the tags address | `0x56019fb4`… |
| LK applies dtbo / "dconfig" overlays; failure path prints "dconfig DT overlay failed, system not bootable" | `0x5601a06a` — mainline DTB has no `__symbols__`; lscorcia boots mainline with this LK family, so assumed non-fatal **[?]** |
| Fastboot commands: `getvar download flash erase continue reboot* boot flashing (un)lock oem …` — **`boot` (RAM boot) exists** | registration list in `fastboot_init` (`0x5601cd64`–`0x5601cfe0`) |

Stock boot.img (sha256 cadd9bc1…): header **v2**, page 2048, kernel `0x40008000` (32-bit zImage
with appended DTB), ramdisk `0x55000000`, tags/DTB `0x54000000`, cmdline
`bootopt=64S3,32N2,32N2 buildvariant=user`, v2 DTB section = 64-byte table + one FDT.

Our image keeps those offsets except kernel → `0x40080000`, and sets `bootopt=64S3,32N2,64N2`.
Unresolved: where LK stages the compressed kernel before inflating (if it overlapped the
destination, inflating would fail with "decompress kernel image fail!!!").

## Boot mode decision (2026-11-08)

LK's native 64-bit path (`bootopt=…,64N2`, Image.gz-dtb at 0x40080000) was tried three times:
LK always reported `Booting OKAY`, but no kernel activity was ever observed (no USB, no screen
output even with simpledrm + initcall_debug), and the board reset ~63 s later regardless of
kernel options. Switched to the **zimage64** route used by pmaports for 32-bit-firmware MTK
devices: keep `bootopt=64S3,32N2,32N2` and the stock kernel address `0x40008000`; the shim's
AArch32 entry issues `smc 0x82000200` with r1 = AArch64 entry, r2 = DT, r4 = 1 (KERNEL_64),
then inflates the kernel (uzlib) and jumps with x0 = DT. See configs/bootimg-x04g.env.

## Unknown — must be measured from your backup

| Question | How we answer it |
|---|---|
| boot.img header version (0/1/2), base, offsets, page size | `unpack_bootimg --boot_img boot.bin` in WSL |
| Kernel format the 64-bit LK path expects (Image.gz + appended DTB is the default guess) | first boot test; `KERNEL_FORMAT` override |
| Does LK use the DTB from boot.img or from `dtbo`/its own? | inspect stock image + UART log |
| Does unlocked LK support `fastboot boot` (RAM boot, no flash)? | test (step 1 below) |
| Does LK rewrite `/memory`? (our DT now declares 1 GiB anyway) | `/proc/iomem` after first boot |
| Exact header offsets (ramdisk address vs 0x54400000 firmware RAM) | `unpack_bootimg` on `boot.bin`; script checks overlap |
| Exact seccfg/AVB behaviour of your firmware version | identify step + UART log |

## Boot strategy, least destructive first

1. **RAM boot via LK fastboot** — `fastboot boot x04g-linux-boot.img`. Writes nothing.
   seccfg is already unlocked on your unit; whether this LK honours `fastboot boot` is untested.
2. **Flash to `recovery` only**, keep `boot` = stock Android. Linux is started with the recovery
   key combo, Android still boots normally. Restorable from backup in one MTKClient command.
3. Flash to `boot` (Linux default) — only after 1 or 2 works.

The kernel's rootfs comes first from the pmOS netboot hook (USB), later from an eMMC partition
(candidates: `cache` or `userdata` — repurposing either requires your approval).

## UART

TP30 = TX, TP29 = RX, **1.8 V logic** (a 3.3 V adapter can damage the SoC — use a 1.8 V-capable
adapter or a level shifter), 921600 8N1. Strongly recommended before the first Linux boot: it is
the only way to see LK and early kernel messages if the screen stays black.
