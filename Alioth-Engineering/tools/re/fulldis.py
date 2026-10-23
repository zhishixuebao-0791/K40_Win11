# 把 ARM64 PE 驱动的可执行节整体反汇编成文本：标注函数起点（.pdata）、导入函数名、adrp+add/ldr 目标地址
# 用法：python fulldis.py <驱动.sys> <输出.txt>
import struct, sys, capstone
F, OUT = sys.argv[1], sys.argv[2]
d = open(F, 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    name = d[o:o + 8].rstrip(b'\0').decode(); vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    ch = struct.unpack_from('<I', d, o + 36)[0]
    secs.append((name, va, vs, ro, rs, ch))
def r2o(r):
    for n, va, vs, ro, rs, ch in secs:
        if va <= r < va + max(vs, rs): return ro + r - va
dd = pe + 24 + 112
irva = struct.unpack_from('<I', d, dd + 8)[0]
imp = {}
o = r2o(irva)
while True:
    ilt, _, _, nm, iat = struct.unpack_from('<IIIII', d, o)
    if nm == 0: break
    k = 0
    while True:
        e = struct.unpack_from('<Q', d, r2o(ilt) + k * 8)[0]
        if e == 0: break
        if not e >> 63:
            no = r2o(e & 0x7fffffff) + 2; imp[iat + k * 8] = d[no:d.index(b'\0', no)].decode()
        k += 1
    o += 20
funcs = set()
for s in secs:
    if s[0] == '.pdata':
        for i in range(0, s[2], 8):
            b = struct.unpack_from('<I', d, s[3] + i)[0]
            if b: funcs.add(b)
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM); md.skipdata = True
out = open(OUT, 'w', encoding='utf-8')
for n, va, vs, ro, rs, ch in secs:
    if not ch & 0x20000000: continue
    code = d[ro:ro + min(vs, rs)]
    page = {}
    for ins in md.disasm(code, va):
        a = ins.address
        if a in funcs: out.write('\nsub_%x:\n' % a)
        note = ''
        if ins.mnemonic == 'adrp':
            r = ins.op_str.split(',')[0]; page[r] = int(ins.op_str.split('#')[1], 16)
        elif ins.mnemonic in ('add', 'ldr', 'str', 'ldrb', 'strb', 'ldrsw') and '#' in ins.op_str:
            ops = [x.strip() for x in ins.op_str.replace('[', '').replace(']', '').split(',')]
            base = ops[1] if ins.mnemonic == 'add' else ops[1]
            if base in page:
                try:
                    tgt = page[base] + int(ops[-1].lstrip('#'), 16)
                    note = '; 0x%x' % tgt + (' ' + imp[tgt] if tgt in imp else '')
                except ValueError: pass
        elif ins.mnemonic == 'bl':
            note = '; sub_%x' % int(ins.op_str.lstrip('#'), 16)
        # 目的寄存器被改写（非 adrp、非存储指令）时，作废之前记录的页地址，避免误标
        if ins.mnemonic != 'adrp' and not ins.mnemonic.startswith('st') and ins.op_str:
            page.pop(ins.op_str.split(',')[0].strip(), None)
        if ins.mnemonic in ('bl', 'blr'):
            for r in list(page):
                if r.lstrip('xw').isdigit() and int(r.lstrip('xw')) < 19: page.pop(r)
        out.write('%6x  %-8s %s %s\n' % (a, ins.mnemonic, ins.op_str, note))
print('完成', OUT)
