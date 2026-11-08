# Linux distribution selection

Constraints: ~1 GiB RAM (512 MiB if the DT memory question resolves badly), 4× A35,
4 GB eMMC shared with Android partitions, 800×480 single-purpose touch UI.

| | postmarketOS (Alpine) | Alpine (plain) | Debian arm64 | Buildroot |
|---|---|---|---|---|
| Idle RAM, console only (rough estimate, not measured on X04G) | ~40–60 MB | ~30–50 MB | ~80–120 MB (systemd) | ~10–25 MB |
| Boot time | fast (OpenRC; systemd optional) | fast | slower | fastest |
| Existing X04G work | **lscorcia boots pmOS on x04g** (netboot hook, MRs !8525/!8526) | none | none | none |
| Android boot.img / initramfs tooling | built in (`pmbootstrap`, mkinitfs, `deviceinfo`) | manual | manual | manual |
| USB-network debug shell, netboot | built in | manual | manual | manual |
| Packages | Alpine repos (musl) | same | largest | build yourself |
| Updates | `apk upgrade` | `apk upgrade` | `apt` | reflash image |
| Maintenance cost | low: one device package + our kernel | medium | medium | high |
| Dev complexity on Windows | pmbootstrap in WSL2 | WSL2 | WSL2 debootstrap | WSL2, long builds |

**Decision: postmarketOS** as the primary target (device package `device-xiaomi-x04g` +
`linux-x04g` kernel package, kept in `rootfs/pmaports/` of this repo and built with
`pmbootstrap` in WSL2 or CI). Use the console/"none" UI + our own lightweight interface rather than
a phone shell (Phosh/Plasma Mobile are too heavy for this RAM).

Buildroot stays a fallback for a single-purpose appliance image if pmOS RAM use turns out too high.
Debian is rejected for the default image (systemd + glibc overhead, no device tooling).
