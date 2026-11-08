# Backup and recovery

**Rule: nothing on the device is written until a backup has been made AND verified by
`scripts/verify_backup.py` (exit code 0) AND copied to a second disk.**

## 1. One-time setup (Windows 11, PowerShell)

1. Install Python 3.10+ (python.org, "Add to PATH"), Git for Windows.
2. Install **UsbDk** 64-bit `.msi` from https://github.com/daynix/UsbDk/releases.
3. In the repo folder:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\scripts\windows\setup-mtkclient.ps1
   ```

## 2. Read-only backup (Windows, PowerShell)

Each step: start the command → unplug clock → **hold VOL+** → plug USB → release when MTKClient
shows the device. All commands use `--noreconnect`. Use the same `-Session` name for all steps.

```powershell
$s = "x04g-" + (Get-Date -Format yyyyMMdd)
.\scripts\windows\backup-x04g.ps1 -Step identify   -Session $s   # GPT + SBC/SLA/DAA
.\scripts\windows\backup-x04g.ps1 -Step boot       -Session $s   # boot1 (preloader) + boot2
.\scripts\windows\backup-x04g.ps1 -Step partitions -Session $s   # every GPT partition
.\scripts\windows\backup-x04g.ps1 -Step full       -Session $s   # whole user area (~3.7 GB)
.\scripts\windows\backup-x04g.ps1 -Step verify     -Session $s   # SHA-256 + GPT/partition cross-check
```

Equivalent raw commands (MTKClient @ 118a000):

```powershell
python mtk.py printgpt --noreconnect
python mtk.py gettargetconfig --noreconnect
python mtk.py r preloader emmc_boot1.bin --parttype boot1 --noreconnect
python mtk.py r preloader emmc_boot2.bin --parttype boot2 --noreconnect
python mtk.py rl partitions --noreconnect
python mtk.py rf emmc_user_full.bin --noreconnect
```

Backups contain device-unique IDs (serial, MACs) and proprietary firmware: **never commit or
publish them.** `backups/` is git-ignored.

## 3. Restore procedures (only from your own verified backup)

| Situation | Restore (BootROM mode, VOL+) |
|---|---|
| Linux boot image in `recovery` misbehaves | `python mtk.py w recovery partitions\recovery.bin --noreconnect` |
| `boot` overwritten | `python mtk.py w boot partitions\boot.bin --noreconnect` |
| Relock / restore seccfg | `python mtk.py w seccfg partitions\seccfg.bin --noreconnect` |
| Anything else in GPT | `python mtk.py w <name> partitions\<name>.bin --noreconnect` |
| Total eMMC user-area loss | `python mtk.py wf emmc_user_full.bin --noreconnect` |
| Preloader damaged (last resort) | `python mtk.py w preloader emmc_boot1.bin --parttype boot1 --noreconnect` |

Because the BootROM is mask ROM, VOL+ BootROM access survives any eMMC content change; this is why
a verified full backup makes the device practically unbrickable. **Untested on your unit** —
confirm BootROM access works during the identify step before relying on it.

## 4. Operations that need your explicit approval

| Operation | Effect | Reversible via |
|---|---|---|
| `mtk da seccfg unlock` | writes `seccfg`; Orange State | restore `seccfg.bin` |
| `mtk e metadata,userdata,md_udc` (in x04g_tools guide) | **erases user data** | restore partitions — not needed for Linux RAM boot, we skip it |
| writing `recovery` / `boot` | replaces Android boot images | restore `.bin` |
| any write to `preloader`, `lk`, `tee*`, GPT | can stop the device from reaching LK | BootROM + full backup only |

We will never touch preloader, lk, tee, GPT, nvram/nvdata/proinfo/persist.
