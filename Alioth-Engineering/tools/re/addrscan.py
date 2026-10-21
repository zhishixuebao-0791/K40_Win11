# 用法：python addrscan.py <sys> <hex地址>...  查找代码中 movz/movk 拼出的常量与数据段中的 LE 常量
import struct, sys, capstone
d = open(sys.argv[1], 'rb').read()
wants = {int(x, 16) for x in sys.argv[2:]}
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    n = d[o:o + 8].rstrip(b'\0').decode()
    vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    secs.append((n, va, vs, ro, rs))
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
md.skipdata = True
md.detail = True
hits = []
for n, va, vs, ro, rs in secs:
    size = min(vs, rs)
    if n in ('.text', 'PAGE', 'INIT'):
        regs = {}
        for x in md.disasm(d[ro:ro + size], va):
            m = x.mnemonic
            if m in ('mov', 'movz', 'movk', 'orr') and x.operands and len(x.operands) >= 2:
                r = x.reg_name(x.operands[0].reg)
                key = r[1:] if r[0] in 'wx' else r
                op = x.operands[1]
                if op.type == capstone.arm64.ARM64_OP_IMM:
                    sh = op.shift.value if op.shift.type else 0
                    imm = op.imm
                    if m == 'movk':
                        v = regs.get(key)
                        if v is None:
                            continue
                        v = (v & ~(0xffff << sh)) | ((imm & 0xffff) << sh)
                    else:
                        v = imm << sh if m == 'movz' else imm
                    v &= 0xffffffffffffffff
                    regs[key] = v
                    if v in wants:
                        hits.append((n, hex(x.address), hex(v), x.mnemonic + ' ' + x.op_str))
                continue
            if m in ('b', 'br', 'ret', 'bl', 'blr') or m.startswith('b.'):
                regs.clear()
    else:
        blob = d[ro:ro + size]
        for w in wants:
            for fmt in ('<I', '<Q'):
                pat = struct.pack(fmt, w)
                i = blob.find(pat)
                while i >= 0:
                    if fmt == '<I' and i % 4 == 0 or fmt == '<Q' and i % 8 == 0:
                        hits.append((n, hex(va + i), hex(w), 'data' + fmt))
                    i = blob.find(pat, i + 1)
for h in sorted(set(hits)):
    print(*h)
print('共', len(set(hits)), '处')
