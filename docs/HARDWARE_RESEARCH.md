# Hardware research — Xiaomi Mi Smart Clock (X04G / LX04)

Status legend:
**[DEV]** confirmed on *your* unit (none yet — needs `backup-x04g.ps1 -Step identify` + Linux boot) ·
**[SRC]** confirmed from kernel source / device tree that someone booted ·
**[DOC]** stated by community research (teardown, wiki) · **[?]** unverified / conflicting.

## 1. Variants

| | X04G (global) | LX04 (China) |
|---|---|---|
| Stock OS | Android Things 10 (Android Go), Google Assistant | Android 8.1, Xiao AI |
| Build string | `Xiaomi/mico_x04g/micro_x04g 10/QP1A.190711.020/1.7.5` [DOC] | — |
| Hardware | same board per octathorp/x04g_tools [DOC] | same |

Different bootloader/LK builds and partition layouts are possible between variants and firmware
versions — **the layout below is from one X04G; yours must be read with `printgpt` before any write.** [?]

## 2. SoC and memory

| Item | Value | Status | Source |
|---|---|---|---|
| SoC | MediaTek **MT8167A** (pin-compatible sibling of MT8516) | [DOC]+[SRC] | Informatic teardown; `mt8167.dtsi` includes `mt8516.dtsi` |
| CPU | 4× Cortex-A35, single cluster | [SRC] | `mt8516.dtsi` |
| Max clock | 1.5 GHz @ 1.30 V OPP added for x04g | [SRC] | commit `9a57d7ad889` |
| RAM | 2× Samsung **K4B4G1646E-BYMA** (4 Gbit DDR3 each) = **1 GiB** | [DOC] | Informatic teardown |
| DT memory node | `reg = <0 0x40000000 0 0x20000000>` = **512 MiB** | [SRC] **[?]** | x04g DTS — conflicts with 1 GiB; MTK LK normally rewrites `/memory` at boot. Must check `/proc/meminfo` on first boot. |
| Reserved | ATF @ `0x54600000` (0x30000), CONSYS 2 MiB, OP-TEE node | [SRC] | DTS |
| eMMC | Kioxia **THGBMNG5D1LBAIL** 4 GB, 8-bit, HS200 | [DOC]+[SRC] | teardown; `&mmc0` |
| PMIC | MediaTek **MT6392** (via PWRAP) | [SRC] | DTS |

## 3. Peripherals

| Function | Part | Bus / pins | Linux driver | Status |
|---|---|---|---|---|
| Display | 4" 480×800 portrait MIPI-DSI panel, **Zhunyi Z40046**, controller **Fitipower JD9161Z**, mounted rotated 270° → 800×480 landscape | DSI0, reset GPIO66 | `DRM_PANEL_FITIPOWER_JD9161Z` (in tree) | [SRC] |
| Backlight | PWM (disp_pwm0) + enable GPIO43 | — | `pwm-backlight` | [SRC] |
| Touch | **Chipsemi CHSC6440** (stock: `tlsc6x_touch`) | I2C2 @0x2e, IRQ GPIO18, RST GPIO19 | `edt-ft5x06` (`focaltech,ft6236` compatible) | [SRC] coords swapped/inverted in DT |
| ALS/Prox | **Epticore EM30719** | I2C0 @0x24, IRQ GPIO10 | `EM3071X` (added by the x04g tree) | [SRC] |
| Mic ADC | **Everest ES7243**, 2-mic array, TDM | I2C1 @0x13, TDM RX on pins 100–103 | `SND_SOC_ES7243` + `mt8167s-es7243` card | [SRC] WIP init sequence from stock disassembly |
| Speaker | MT8167 internal codec → external amp, amp enable GPIO51 | — | `SND_SOC_MT8167_CODEC` | [SRC] |
| Wi-Fi / BT | MT8167 integrated **CONSYS** (WMT), 2.4 GHz Wi-Fi, BT | — | **out-of-tree** `lscorcia/linux-mt8167-consys` + firmware `WIFI_RAM_CODE_8167`, `ROMv2_lm_patch_1_*`, `WMT_SOC.cfg` | [SRC] WIP ("hacks to build as modules") |
| GPU | **Imagination PowerVR GE8300** (Rogue) | MFG | firmware `rgx.fw.22.40.54.30` exists; no in-tree driver enabled in the x04g config | [?] see KERNEL_DEVELOPMENT.md §GPU |
| USB | MUSB, micro-B, peripheral (ID pin GPIO41) | — | `USB_MUSB_MEDIATEK` | [SRC] USB networking reported working |
| Buttons | VOL+ = keypad KPCOL0; VOL− = PMIC "home" key; Mute | — | `KEYBOARD_MT6779`, `KEYBOARD_MTK_PMIC` | [SRC] mute not described in DT **[?]** |
| UART | UART0 @ `0x11005000`, **921600 8N1, 1.8 V**; **TP30 = TX, TP29 = RX** (back of board) | — | `8250_mt6577` | [DOC] |
| Board connectors | CON6212 LCD/touch · CON6213 ALS/PS · CON6214 buttons | — | — | [DOC] |

## 4. USB IDs seen on Windows

| Mode | VID:PID | How |
|---|---|---|
| BootROM | `0E8D:0003` | hold **VOL+** while plugging in USB (~5 s window) |
| Preloader | `0E8D:2000` | normal power-on, ~2 s |
| LK fastboot | `0E8D:201C` | recovery menu → "Reboot to bootloader" |
| fastbootd | `18D1:4EE0` | recovery menu → "Enter fastboot" |
| Android MTP | `0E8D:2008` | normal boot |

## 5. Partition table (one X04G, from postmarketOS/Nura wiki) [DOC]

`proinfo nvram persist seccfg lk lk2 boot recovery para logo dtbo expdb frp tee1 tee2 kb dkb md_udc metadata nvdata vbmeta vbmeta_system vbmeta_vendor super cache userdata`

Device-unique data: `proinfo`, `nvram`, `nvdata`, `persist` (serial, Wi-Fi/BT MAC, calibration).
Preloader lives in the eMMC **boot1** hardware partition, not in the GPT.

## 6. Physical device — to be confirmed by you

Run `scripts\windows\backup-x04g.ps1 -Step identify` and commit the (non-secret) parts:

- [ ] hw code / SoC reported by MTKClient (expect `0x8167` family)
- [ ] SBC / SLA / DAA flags (`gettargetconfig`) — decides whether BootROM exploit or stock DA is needed
- [ ] GPT names + sizes (compare with §5)
- [ ] Android build string (recovery screen) — X04G or LX04 firmware
- [ ] seccfg lock state
- [ ] RAM size seen by Linux (512 MiB vs 1 GiB question)
