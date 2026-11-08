# Kernel development

## Source selection

| Candidate | Base | X04G DTS | Display | Audio | Wi-Fi/BT | Verdict |
|---|---|---|---|---|---|---|
| **lscorcia/linux `x04g-7.3`** @ `2fb2bc1fd01c` (2026-09-21) | mainline **v7.3** + ~100 patches | yes | DSI + JD9161Z panel | MT8167 AFE + ES7243 (WIP) | no (separate module) | **chosen** — newest stable-tagged base, actively maintained, author boots pmOS on x04g |
| lscorcia/linux `x04g-7.4-rc1`, `x04g-linux-next` | 7.4-rc / next | yes | | | | track as `configs/experimental` later |
| lscorcia/linux `x04g-7.1-rc6-btwifi` | 7.1-rc6 | yes | | | in-tree attempt | superseded by out-of-tree module |
| lscorcia/linux `psclassic-consys` | — | PS Classic (MT8167) | | | CONSYS port | reference for Wi-Fi; same SoC block |
| lscorcia/linux-mt8167-consys @ `9e75325` | out-of-tree module | — | — | — | MT8167 CONSYS Wi-Fi + BT, WIP | Milestone 6 |
| Mainline v7.3 alone | — | **no** | no MT8167 DSI routes / panel | no | no | not usable alone |

Key x04g commits in the chosen tree (authors: Val Packett, Jens Reidel, Luca Leonardo Scorcia):
`5e0fded` add DTS · `831a42e` fix framebuffer · `ba4c3e6` Z40046 panel · `393c88b` USB network ·
`b70c84d` touch · `df47459` ALS/PS · `b28a09b` audio out · `dd41a08`/`37dcd91` ES7243 mic ·
`9a57d7a` 1.5 GHz OPP · `1eca128` DSI pipeline · `0c50241` touch coordinate swap ·
`12f175c` pwrap init fix · `8114571` IOMMU 4GB mode.

Pinning lives in `kernel/source.env`. Changing it = new CHANGELOG entry + CI build.

## Configuration

`arm64 defconfig` + `configs/x04g.config` (merged with `merge_config.sh`), then `olddefconfig`.
Device options were taken from lscorcia's postmarketOS config (gist `58c575a5…`, 7.3.0-rc5);
all non-MediaTek `ARCH_*` platforms are disabled. The build script fails loudly (WARN lines) if any
fragment option does not survive Kconfig dependency resolution.

Modules vs built-in: touchscreen, ALS, sound are modules (as in the reference config); everything
needed to reach a shell (MMC, pinctrl, PMIC, DRM/DSI, USB gadget) is built in.

## Patches

`patches/kernel/*.patch` are applied in order with `git apply` on top of the pinned commit.
Currently empty — the reference tree already contains everything for Priority 1.

## Planned work

| Priority | Item | Notes |
|---|---|---|
| P1 | verify boot, eMMC, DSI panel, touch, USB gadget on hardware | needs first boot |
| P1 | resolve DT memory 512 MiB vs 1 GiB | check if LK patches `/memory`; else patch DTS to `0x40000000` |
| P2 | build `linux-mt8167-consys` against our kernel in CI | firmware from `lscorcia/firmware-xiaomi-x04g` |
| P2 | audio: test MT8167 codec + amp GPIO51, ES7243 capture | `alsa-ucm` profile needed |
| P2 | mute button | not described in DTS — identify GPIO from stock DTB (`dtbo`/boot backup) |
| P3 | GPU | see below |
| P3 | cpuidle | DTS deletes `cpu-idle-states` (cores don't return with stock ATF) |
| P3 | suspend | depends on ATF/PSCI behaviour |

### GPU (PowerVR GE8300)

The firmware file `rgx.fw.22.40.54.30` (BVNC 22.40.54.30) is available. Mainline `drm/imagination`
(`DRM_POWERVR`) + Mesa's PowerVR Vulkan driver officially target other Rogue cores first; whether
22.40.54.30 is supported needs checking against the kernel's and Mesa's supported-BVNC lists at
the time of work. Until then rendering is **software (llvmpipe/pixman) on the DRM dumb buffer**,
which is adequate for an 800×480 UI.
