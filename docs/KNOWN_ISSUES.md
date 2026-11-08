# Known issues and open questions

| # | Issue | Impact | Status |
|---|---|---|---|
| 1 | Upstream DT `memory` node declares 512 MiB; stock firmware shows 1 GiB | half the RAM unused | **patched** (0001: 1 GiB + firmware reservations, measured from your `/proc/iomem`); confirm on first boot |
| 2 | `cpu-idle-states` deleted in DTS: cores don't return from idle with stock ATF | higher idle power | upstream limitation, P3 |
| 3 | Wi-Fi/BT driver is out-of-tree and WIP | no wireless at first boot; use USB networking | Milestone 6 |
| 4 | ES7243 mic init sequence comes from stock disassembly (WIP commit) | capture may not work | untested |
| 5 | Mute button not described in DTS | button does nothing | needs GPIO from stock DTB |
| 6 | PowerVR GE8300 support in mainline/Mesa unknown | software rendering only | P3 research |
| 7 | Stock LK requires unlocked seccfg to boot unsigned images | — | **resolved**: your unit is already unlocked (orange state) |
| 8 | Boot image format expected by LK not yet measured | first boot image may be rejected | resolved by `mkbootimg-from-stock.sh` once `boot.bin` backup exists |
| 9 | No UART available on the user's setup (and it would be 1.8 V) | early kernel hangs before USB probes stay invisible | USB-only debugging, see USB_DEBUGGING.md; UART optional |
| 10 | GitHub write access not available from the cloud build session | commits must be pushed from your PC | see DEVELOPMENT_STATUS.md |
| 11 | Stock runs a 32-bit kernel (`bootopt=…,32N2`); LK's native 64N2 path never started our kernel (T4–T6) | no boot | switched to zimage64 shim on the 32N2 path (T7/T8, pending test) |
| 12 | `mt8516.dtsi` reserves `secmon@43000000` / `optee@43200000`, but stock shows that range as normal RAM | a few MiB lost; harmless | upstream, leave as is |
