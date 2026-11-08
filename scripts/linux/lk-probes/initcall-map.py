#!/usr/bin/env python3
"""Map initcall levels/indices to function names for checkpoint images (patch 0002).
Usage: initcall-map.py <build/out dir> [out.json]   (needs aarch64-linux-gnu-readelf)
Checkpoint N = 10000*level + index runs right before initcall <index> of <level>."""
import bisect, json, struct, subprocess, sys
out_dir = sys.argv[1]; dst = sys.argv[2] if len(sys.argv) > 2 else None
v = out_dir + '/vmlinux'
sec = subprocess.run(['aarch64-linux-gnu-readelf', '-SW', v], capture_output=True, text=True).stdout
for l in sec.splitlines():
    if ' .init.data ' in l:
        p = l.split(']')[1].split(); addr, off = int(p[2], 16), int(p[3], 16)
data = open(v, 'rb').read(); sm = {}; syms = []
for l in open(out_dir + '/System.map'):
    a, t, n = l.split()[:3]; a = int(a, 16); sm[n] = a
    if t in 'tTwW': syms.append((a, n))
syms.sort(); A = [a for a, _ in syms]
name = lambda a: syms[bisect.bisect_right(A, a) - 1][1]
bounds = [f'__initcall{i}_start' for i in range(8)] + ['__initcall_end']
T = {}
for lvl in range(8):
    s, e = sm[bounds[lvl]], sm[bounds[lvl + 1]]
    T[lvl] = [name(x + struct.unpack('<i', data[off + x - addr:off + x - addr + 4])[0]) for x in range(s, e, 4)]
if dst: json.dump(T, open(dst, 'w'), indent=0)
for lvl in T: print(f'level {lvl}: {len(T[lvl])} initcalls')
