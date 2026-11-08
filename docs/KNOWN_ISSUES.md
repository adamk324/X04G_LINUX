# Known issues and open questions

| # | Issue | Impact | Status |
|---|---|---|---|
| 1 | DT `memory` node declares 512 MiB, hardware has 1 GiB (2× 4 Gbit DDR3) | half the RAM unused unless LK rewrites `/memory` | open — check `/proc/meminfo` on first boot |
| 2 | `cpu-idle-states` deleted in DTS: cores don't return from idle with stock ATF | higher idle power | upstream limitation, P3 |
| 3 | Wi-Fi/BT driver is out-of-tree and WIP | no wireless at first boot; use USB networking | Milestone 6 |
| 4 | ES7243 mic init sequence comes from stock disassembly (WIP commit) | capture may not work | untested |
| 5 | Mute button not described in DTS | button does nothing | needs GPIO from stock DTB |
| 6 | PowerVR GE8300 support in mainline/Mesa unknown | software rendering only | P3 research |
| 7 | Stock LK requires unlocked seccfg to boot unsigned images | unlock is a write to `seccfg` | needs your approval after backup |
| 8 | Boot image format expected by LK not yet measured | first boot image may be rejected | resolved by `mkbootimg-from-stock.sh` once `boot.bin` backup exists |
| 9 | UART is 1.8 V | 3.3 V adapters can damage the SoC | use 1.8 V adapter |
| 10 | GitHub write access not available from the cloud build session | commits must be pushed from your PC | see DEVELOPMENT_STATUS.md |
