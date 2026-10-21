# 用法：python dumprva.py <sys> <rva_hex> [前字节数] [后字节数]  按 RVA 以 32 位字形式转储，并标注可见字符串
import struct, sys, re
d = open(sys.argv[1], 'rb').read()
rva = int(sys.argv[2], 16)
before = int(sys.argv[3]) if len(sys.argv) > 3 else 64
after = int(sys.argv[4]) if len(sys.argv) > 4 else 128
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
opt = struct.unpack_from('<H', d, pe + 20)[0]
base = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    n = d[o:o + 8].rstrip(b'\0').decode()
    vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    secs.append((n, va, vs, ro, rs))
def r2o(r):
    for n, va, vs, ro, rs in secs:
        if va <= r < va + rs:
            return ro + r - va
def strat(r):
    o = r2o(r)
    if o is None:
        return ''
    m = re.match(rb'[\x20-\x7e]{3,}', d[o:o + 80])
    if m:
        return '"' + m.group(0).decode() + '"'
    m = re.match(rb'(?:[\x20-\x7e]\x00){3,}', d[o:o + 160])
    if m:
        return 'L"' + m.group(0).decode('utf-16le') + '"'
    return ''
start = rva - before
for r in range(start, rva + after, 8):
    o = r2o(r)
    q = struct.unpack_from('<Q', d, o)[0]
    lo, hi = q & 0xffffffff, q >> 32
    note = ''
    if base <= q < base + 0x1000000:
        note = 'ptr rva=' + hex(q - base) + ' ' + strat(q - base)
    mark = '<==' if r <= rva < r + 8 else ''
    print(f'{r:08x}: {lo:08x} {hi:08x}  {note} {mark}')
