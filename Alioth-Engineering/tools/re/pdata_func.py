# 用 ARM64 .pdata 把 RVA 映射到所属函数起止（不依赖 pefile）
import struct, sys
data = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', data, 0x3c)[0]
nsec = struct.unpack_from('<H', data, pe + 6)[0]
optsz = struct.unpack_from('<H', data, pe + 20)[0]
opt = pe + 24
exc_rva, exc_sz = struct.unpack_from('<II', data, opt + 112 + 3 * 8)
secs = []
for i in range(nsec):
    o = opt + optsz + i * 40
    name = data[o:o+8].rstrip(b'\0').decode()
    vs, va, rs, ro = struct.unpack_from('<IIII', data, o + 8)
    secs.append((name, va, max(vs, rs), ro))
def off(rva):
    for n, va, sz, ro in secs:
        if va <= rva < va + sz: return ro + rva - va
funcs = []
for i in range(exc_sz // 8):
    begin, info = struct.unpack_from('<II', data, off(exc_rva) + i * 8)
    if info & 3:  # 压缩格式：FunctionLength 位 2..12，单位 4 字节
        length = ((info >> 2) & 0x7ff) * 4
    else:
        x = struct.unpack_from('<I', data, off(info))[0]
        length = (x & 0x3ffff) * 4
    funcs.append((begin, begin + length))
funcs.sort()
for a in sys.argv[2:]:
    r = int(a, 16)
    hit = [f for f in funcs if f[0] <= r < f[1]]
    print(f"{r:#x} -> " + (", ".join(f"函数 {b:#x}-{e:#x}（返回点偏移 +{r-b:#x}）" for b, e in hit) if hit else "未找到"))
