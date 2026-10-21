import struct,sys,capstone
F=sys.argv[1]; targets=[int(x,16) for x in sys.argv[2:]]
d=open(F,'rb').read()
pe=struct.unpack_from('<I',d,0x3c)[0]
nsec=struct.unpack_from('<H',d,pe+6)[0]; opt=struct.unpack_from('<H',d,pe+20)[0]
base=struct.unpack_from('<Q',d,pe+24+24)[0]
secs=[]
for i in range(nsec):
    o=pe+24+opt+i*40
    name=d[o:o+8].rstrip(b'\0').decode(); vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8)
    secs.append((name,va,vs,ro,rs))
def off2rva(off):
    for n,va,vs,ro,rs in secs:
        if ro<=off<ro+rs: return va+off-ro
def rva2off(r):
    for n,va,vs,ro,rs in secs:
        if va<=r<va+max(vs,rs): return ro+r-va
trva=[off2rva(t) for t in targets]
print('sections',[(s[0],hex(s[1])) for s in secs]); print('target rvas',[hex(x) for x in trva])
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM)
for n,va,vs,ro,rs in secs:
    if n not in('.text','PAGE','INIT') and not n.startswith('.text') and not n.startswith('PAGE'): continue
    code=d[ro:ro+min(vs,rs)]
    # manual adrp/add scan
    for i in range(0,len(code)-8,4):
        w=struct.unpack_from('<I',code,i)[0]
        if (w&0x9f000000)==0x90000000:
            rd=w&31; immlo=(w>>29)&3; immhi=(w>>5)&0x7ffff; imm=((immhi<<2)|immlo)
            if imm&(1<<20): imm-=1<<21
            pc=va+i; page=(pc&~0xfff)+(imm<<12)
            for j in range(4,16,4):
                w2=struct.unpack_from('<I',code,i+j)[0]
                if (w2&0xffc00000)==0x91000000 and ((w2>>5)&31)==rd:
                    tgt=page+((w2>>10)&0xfff)
                    if tgt in trva: print(f'xref {hex(tgt)} at {n} rva {hex(pc)}')
                    break
