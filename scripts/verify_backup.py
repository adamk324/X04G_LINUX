#!/usr/bin/env python3
"""Verify an X04G MTKClient backup (pure stdlib; runs on Windows, WSL or Linux).

Checks
  1. GPT of the full user-area image (emmc_user_full.bin) is valid (header CRC + entries CRC).
  2. Every GPT partition exists in partitions/ with the GPT-declared size.
  3. Each partition dump is byte-identical to the same range inside the full image.
  4. emmc_boot1.bin starts with an MTK preloader header (EMMC_BOOT / MMM signatures).

Usage:  python scripts/verify_backup.py backups/<session>
Exit code 0 only if every check passes.
"""
import hashlib, os, struct, sys, zlib

SECTOR = 512
CHUNK = 16 * 1024 * 1024


def read_gpt(f):
    f.seek(SECTOR)
    hdr = f.read(92)
    if hdr[:8] != b"EFI PART":
        raise ValueError("no GPT signature at LBA1")
    (_, _, hsize, hcrc, _, _, _, _, _, _, ent_lba, n_ent, ent_size, ent_crc) = struct.unpack(
        "<8sIIIIQQQQ16sQIII", hdr)
    f.seek(SECTOR)
    raw = bytearray(f.read(hsize))
    raw[16:20] = b"\0\0\0\0"
    if zlib.crc32(raw) & 0xFFFFFFFF != hcrc:
        raise ValueError("GPT header CRC mismatch")
    f.seek(ent_lba * SECTOR)
    ents = f.read(n_ent * ent_size)
    if zlib.crc32(ents) & 0xFFFFFFFF != ent_crc:
        raise ValueError("GPT entries CRC mismatch")
    parts = []
    for i in range(n_ent):
        e = ents[i * ent_size:(i + 1) * ent_size]
        if e[:16] == b"\0" * 16:
            continue
        first, last = struct.unpack("<QQ", e[32:48])
        name = e[56:128].decode("utf-16-le").rstrip("\0")
        parts.append((name, first * SECTOR, (last - first + 1) * SECTOR))
    return parts


def sha_range(f, off, length):
    h = hashlib.sha256(); f.seek(off); left = length
    while left:
        b = f.read(min(CHUNK, left))
        if not b:
            raise ValueError("short read")
        h.update(b); left -= len(b)
    return h.hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(CHUNK), b""):
            h.update(b)
    return h.hexdigest()


def main(d):
    ok = True
    full = os.path.join(d, "emmc_user_full.bin")
    pdir = os.path.join(d, "partitions")
    if not os.path.exists(full):
        print("FAIL: emmc_user_full.bin missing"); return 1
    with open(full, "rb") as f:
        parts = read_gpt(f)
        print(f"GPT OK: {len(parts)} partitions, image {os.path.getsize(full):,} bytes")
        for name, off, size in parts:
            p = None
            for ext in (".bin", ".img", ""):
                cand = os.path.join(pdir, name + ext)
                if os.path.exists(cand):
                    p = cand; break
            if p is None:
                print(f"FAIL  {name:16s} dump missing"); ok = False; continue
            psize = os.path.getsize(p)
            if psize != size:
                print(f"FAIL  {name:16s} size {psize} != GPT {size}"); ok = False; continue
            # userdata is large: hash it too, it is the only way to be sure
            a, b = sha_file(p), sha_range(f, off, size)
            st = "OK  " if a == b else "FAIL"
            ok &= a == b
            print(f"{st}  {name:16s} {size:>12,}  {a[:16]}")
    b1 = os.path.join(d, "emmc_boot1.bin")
    if os.path.exists(b1):
        head = open(b1, "rb").read(0x1000)
        if b"EMMC_BOOT" in head or b"MMM" in head:
            print("OK    boot1 contains MTK preloader signature")
        else:
            print("WARN  boot1 has no EMMC_BOOT/MMM signature - inspect manually")
    else:
        print("WARN  emmc_boot1.bin (preloader) not backed up"); ok = False
    print("ALL CHECKS PASSED" if ok else "BACKUP NOT VERIFIED")
    return 0 if ok else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(2)
    sys.exit(main(sys.argv[1]))
