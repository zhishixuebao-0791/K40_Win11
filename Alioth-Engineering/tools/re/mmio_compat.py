# 用法：python mmio_compat.py <驱动.sys> <源SoC.dtsi> <目标SoC.dtsi>
# 列出驱动二进制中落在"源 SoC"设备树寄存器块里的 32 位地址常量，并标注目标 SoC 在同一地址是否也有硬件块，
# 用来评估一个高通驱动换到另一颗 SoC 上时，会不会访问到目标 SoC 上不存在的硬件（Phase17h：qcpep8280 → SM8250）。
import re, struct, sys, bisect

def blocks(path):
    text = open(path, encoding='utf-8', errors='replace').read()
    out = []
    # 节点名 + 紧随的 reg（只取第一组 <0 addr 0 size>）
    for m in re.finditer(r'([\w,.-]+)@([0-9a-f]+)\s*\{(.*?)\n\t\t\}', text, re.S):
        name, body = m.group(1), m.group(3)
        if name == 'soc':
            continue  # 总线容器节点，地址范围覆盖整个 SoC，会把所有地址都"匹配上"
        for r in re.finditer(r'<\s*0x?0*\s+(0x[0-9a-f]+)\s+0x?0*\s+(0x[0-9a-f]+)\s*>', body):
            a, s = int(r.group(1), 16), int(r.group(2), 16)
            if 0x100000 <= a < 0x20000000 and 0 < s <= 0x4000000:
                out.append((a, a + s, f'{name}@{m.group(2)}'))
    out.sort()
    return out

def find(bl, v):
    hits = [b for b in bl if b[0] <= v < b[1]]
    return min(hits, key=lambda b: b[1] - b[0]) if hits else None

drv = open(sys.argv[1], 'rb').read()
src, dst = blocks(sys.argv[2]), blocks(sys.argv[3])
print(f'源 SoC 寄存器块 {len(src)} 个，目标 SoC 寄存器块 {len(dst)} 个')
show_all = '--all' in sys.argv
seen = {}
# 只看按 8 字节对齐、高 32 位为 0 的 64 位常量：ARM64 代码文字池里存放物理地址的典型形式，误报远少于逐 4 字节扫描
for i in range(0, len(drv) - 7, 8):
    v, hi = struct.unpack_from('<II', drv, i)
    if hi == 0 and 0x100000 <= v < 0x20000000 and v & 0x3 == 0:
        b = find(src, v)
        if b:
            seen.setdefault(v, [0, b])[0] += 1
bad = []
for v in sorted(seen):
    n, b = seen[v]
    t = find(dst, v)
    if not t:
        bad.append(v)
    if show_all or not t:
        print(f'{v:#012x}  {n:>3}次  源：{b[2]:<40} 目标：{t[2] if t else "【不存在】"}')
blk = sorted({seen[v][1][2] for v in seen})
print(f'共 {len(seen)} 个地址（涉及源 SoC 硬件块 {len(blk)} 个），目标 SoC 上没有对应硬件块的 {len(bad)} 个')
print('涉及的源 SoC 硬件块：', ', '.join(blk))
