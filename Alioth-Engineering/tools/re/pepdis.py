# 用法：python pepdis.py <sys> <函数RVA_hex>... 反汇编整个函数（按 .pdata 边界），标注 adrp+add/ldr 指向的全局变量与字符串、
#       movz/movk 拼出的常量、文字池 ldr 读出的 64 位值。
#       python pepdis.py <sys> --callers <RVA_hex>  列出 bl 到该 RVA 的调用点（及所在函数）
#       python pepdis.py <sys> --refs <RVA_hex>...  列出通过 adrp+add/ldr/str 引用这些全局地址的指令
import struct, sys, re, capstone

d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(nsec):
    o = pe + 24 + opt + i * 40
    nm = d[o:o + 8].rstrip(b'\0').decode()
    vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    secs.append((nm, va, vs, ro, rs))

def r2o(r):
    for nm, va, vs, ro, rs in secs:
        if va <= r < va + rs:
            return ro + r - va

def s_at(r):
    o = r2o(r)
    if o is None:
        return ''
    m = re.match(rb'(?:[\x20-\x7e]\x00){4,}', d[o:o + 200])
    if m:
        return 'L"' + m.group(0).decode('utf-16le')[:70] + '"'
    m = re.match(rb'[\x20-\x7e]{4,}', d[o:o + 120])
    if m:
        return '"' + m.group(0).decode()[:70] + '"'
    return ''

pd = [s for s in secs if s[0] == '.pdata'][0]
funcs = []
for k in range(0, pd[2], 8):
    b, x = struct.unpack_from('<II', d, pd[3] + k)
    if b == 0:
        break
    funcs.append(b)
funcs = sorted(set(funcs))

def func_of(a):
    c = [f for f in funcs if f <= a]
    return c[-1] if c else None

def func_end(f):
    n = [g for g in funcs if g > f]
    return n[0] if n else f + 0x400

md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
md.detail = True
md.skipdata = True

_all = None
def all_ins():
    global _all
    if _all is None:
        _all = []
        for nm, va, vs, ro, rs in secs:
            if nm in ('.text', 'PAGE', 'INIT'):
                _all.extend(md.disasm(d[ro:ro + min(vs, rs)], va))
    return _all

def annotate(ins_list):
    regs = {}
    out = []
    for x in ins_list:
        note = ''
        try:
            ops = x.operands
        except capstone.CsError:
            out.append(f'  {x.address:#x}: {x.mnemonic} {x.op_str}')
            continue
        try:
            if x.mnemonic == 'adrp':
                regs[x.reg_name(ops[0].reg)[1:]] = ops[1].imm
            elif x.mnemonic in ('mov', 'movz', 'movk') and len(ops) == 2 and ops[1].type == capstone.arm64.ARM64_OP_IMM:
                r = x.reg_name(ops[0].reg)[1:]
                sh = ops[1].shift.value if ops[1].shift.type else 0
                if x.mnemonic == 'movk':
                    v = (regs.get(r, 0) & ~(0xffff << sh)) | ((ops[1].imm & 0xffff) << sh)
                else:
                    v = ops[1].imm << sh
                regs[r] = v & 0xffffffffffffffff
                if regs[r] > 0xffff:
                    note = f'  ; {regs[r]:#x}'
            elif x.mnemonic == 'add' and len(ops) == 3 and ops[2].type == capstone.arm64.ARM64_OP_IMM:
                b = regs.get(x.reg_name(ops[1].reg)[1:])
                if b is not None and b > 0x10000:
                    t = b + ops[2].imm
                    note = f'  ; -> +{t:#x} {s_at(t)}'
            elif x.mnemonic.startswith(('ldr', 'str')) and len(ops) >= 2:
                if ops[1].type == capstone.arm64.ARM64_OP_MEM:
                    b = regs.get(x.reg_name(ops[1].mem.base)[1:])
                    if b is not None and b > 0x10000:
                        note = f'  ; [+{b + ops[1].mem.disp:#x}]'
                elif ops[1].type == capstone.arm64.ARM64_OP_IMM and x.mnemonic == 'ldr':
                    o = r2o(ops[1].imm)
                    if o is not None:
                        note = f'  ; 文字池 = {struct.unpack_from("<Q", d, o)[0]:#x}'
        except Exception:
            pass
        out.append(f'  {x.address:#x}: {x.mnemonic} {x.op_str}{note}')
    return out

args = sys.argv[2:]
if args and args[0] == '--callers':
    t = int(args[1], 16)
    for x in all_ins():
        if x.mnemonic == 'bl' and x.op_str == f'#{t:#x}':
            print(f'{x.address:#x}  函数 +{func_of(x.address):#x}')
elif args and args[0] == '--refs':
    want = {int(a, 16) for a in args[1:]}
    ins = all_ins()
    for j, x in enumerate(ins):
        if x.mnemonic == 'adrp' and x.operands:
            page = x.operands[1].imm
            r = x.reg_name(x.operands[0].reg)
            for y in ins[j + 1:j + 10]:
                if r not in y.op_str:
                    continue
                m = re.search(r'#(0x[0-9a-f]+|\d+)\]?$', y.op_str)
                if m and page + int(m.group(1), 0) in want:
                    print(f'{y.address:#x}  函数 +{func_of(y.address):#x}  {y.mnemonic} {y.op_str}  -> +{page + int(m.group(1), 0):#x}')
                    break
else:
    for a in args:
        f = func_of(int(a, 16))
        e = func_end(f)
        print(f'==== 函数 +{f:#x} ~ +{e:#x}')
        o = r2o(f)
        print('\n'.join(annotate(list(md.disasm(d[o:o + (e - f)], f)))))
