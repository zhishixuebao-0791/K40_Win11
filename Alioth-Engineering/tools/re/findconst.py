# 用法：python findconst.py <sys> <imm>  找出 mov wN,#imm 的位置及所在函数（.pdata）
import struct,sys,capstone
d=open(sys.argv[1],'rb').read(); want=sys.argv[2]
pe=struct.unpack_from('<I',d,0x3c)[0];nsec=struct.unpack_from('<H',d,pe+6)[0];opt=struct.unpack_from('<H',d,pe+20)[0]
secs=[]
for i in range(nsec):
    o=pe+24+opt+i*40;n=d[o:o+8].rstrip(b'\0').decode();vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8);secs.append((n,va,vs,ro,rs))
def r2o(r):
    for n,va,vs,ro,rs in secs:
        if va<=r<va+max(vs,rs): return ro+r-va
pd=[s for s in secs if s[0]=='.pdata'][0]; funcs=[]
for i in range(0,pd[2],8):
    b,x=struct.unpack_from('<II',d,pd[3]+i)
    if b==0: break
    ln=((x>>2)&0x7ff)*4 if x&3 else (struct.unpack_from('<I',d,r2o(x))[0]&0x3ffff)*4
    funcs.append((b,b+ln))
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.skipdata=True
for n,va,vs,ro,rs in secs:
    if n not in('.text','PAGE','INIT'): continue
    for x in md.disasm(d[ro:ro+min(vs,rs)],va):
        if x.mnemonic=='mov' and x.op_str.endswith('#'+want):
            f=[a for a in funcs if a[0]<=x.address<a[1]]
            print(n,hex(x.address),x.op_str,'func',hex(f[0][0]) if f else '?')
