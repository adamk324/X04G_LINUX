# USB-only debugging (no UART)

The user's setup has no UART adapter. All Linux debugging goes through the clock's single
micro-USB cable to the Windows PC. UART (TP29/TP30, 1.8 V) is optional, never required.

## Channels, earliest first

| Phase | Mechanism | What Windows sees |
|---|---|---|
| Kernel stage | built-in legacy **g_serial** (CONFIG_USB_G_SERIAL=y) + `console=ttyGS0,115200` (CONFIG_U_SERIAL_CONSOLE) — binds as soon as the MUSB controller probes, before any userspace | `0525:A4A7` → **USB Serial Device (COMx)**; kernel log streams on it |
| Init stage | init unbinds g_serial and binds a configfs composite gadget: **CDC ACM** (root shell + log) + **CDC NCM** (network) | `1D6B:0104` "Mi Smart Clock (Linux)" → **USB Composite Device** with **USB Serial Device (COMy)** and **UsbNcm Host Device** (network adapter, built into Windows 11) |
| Network | clock `172.16.42.1/24`, DHCP gives the PC `172.16.42.2`; `telnetd` root shell | ping / telnet 172.16.42.1 |
| Fallback | stage lines printed on the panel (`/dev/tty0`) | — |

If the composite bind fails, init re-binds legacy g_serial so the serial shell still works
(networking then absent). The serial shell ignores modem-control lines (`getty -L`), so a
terminal can be closed and reopened at any time.

## Expected Windows enumeration, in order

| # | VID:PID | Name in Device Manager | Meaning |
|---|---|---|---|
| 1 | `0E8D:201C` | Android Bootloader Interface | LK fastboot (before `fastboot boot`) |
| 2 | — | (fastboot device disappears) | LK jumped to the kernel |
| 3 | `0525:A4A7` | Gadget Serial → USB Serial Device (COMx) | **kernel is running and the USB controller works** |
| 4 | `1D6B:0104` | Mi Smart Clock (Linux): USB Serial Device (COMy) + UsbNcm Host Device | **init (userspace) is running** |
| — | `0E8D:2000` | MediaTek PreLoader USB VCOM | the clock reset (watchdog / panic / reboot) |
| — | `0E8D:2008`, `18D1:*` | Android MTP / ADB | stock Android is back |

The COM numbers are assigned by Windows and can differ between steps 3 and 4.

## Stage log

Every init step is timestamped with kernel uptime and sent to the kernel log (and therefore the
USB console), `/run/x04g-stages.txt` and the panel:

```
[T+    1.02s] S01 init started (kernel 7.3.0-x04g)
[T+    1.10s] S02 pseudo filesystems mounted
[T+    1.13s] S03 watchdog: /dev/watchdog0        <- or "none" (then LK's ~20 s watchdog will reset us)
[T+    1.20s] S04 module loaded: …
[T+    1.70s] S05 UDC 11100000.usb present, bound function: g_serial, state: …
[T+    1.80s] S06 legacy g_serial unbound … / configfs ACM+NCM bound …
[T+    2.40s] S07 root shell on /dev/ttyGS0 (composite)
[T+    2.60s] S08 network: usb0 172.16.42.1 (telnet)
[T+    3.00s] S09 report written
[T+    3.00s] S10 READY
[T+   13.00s] HB alive, …                           <- heartbeat every 10 s
```

## Windows tool

```powershell
.\scripts\windows\x04g-usb-monitor.ps1 -Image .\build\x04g-T4-usbdiag.img
```

Runs `fastboot boot`, then logs (relative to "Booting OKAY"): device arrivals/removals, every line
from the clock's COM port, ping results for 172.16.42.1. When the composite gadget is up it
pulls `/run/x04g-stages.txt` and `/run/x04g-report.txt` over the serial shell. Output:
`logs\usbdiag-<time>.log` and `logs\x04g-report-<time>.txt`.

Manual access: PuTTY → Serial → COMy (any baud), or `telnet 172.16.42.1` (enable the Windows
"Telnet Client" optional feature, or use PuTTY in Telnet mode).

## Reading a failed run

| Last thing seen | Where it stops |
|---|---|
| Nothing after fastboot device disappears, reset ~20 s | kernel dies before the USB controller probes (early boot, DT, clocks, memory) |
| 0525:A4A7 COM port appears, kernel log on it, then stops | the last kernel log line shows the culprit |
| Composite appears, stages stop at Sxx | that init step |
| HB lines keep coming but screen dark | display path only (DRM/panel), everything else fine |

## Verified so far

| Check | Where | Result |
|---|---|---|
| legacy g_serial binds at kernel stage, unbind → configfs ACM+NCM | QEMU + dummy_hcd (emulated) | OK: S05 g_serial bound 1.7 s, S06 composite 2.4 s |
| host-side DHCP over NCM (gets 172.16.42.2), carrier both ends | QEMU + dummy_hcd (emulated) | OK |
| serial shell round-trip over ACM | QEMU + dummy_hcd (emulated) | OK (`SELFTEST_42`) |
| no-UDC path ends in READY | QEMU (emulated) | OK |
| Windows enumeration, MUSB on the real SoC | hardware | **not yet tested** |
