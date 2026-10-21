import struct,sys
d=open(sys.argv[1],'rb').read(); tgt=int(sys.argv[2],16)
pe=struct.unpack_from('<I',d,0x3c)[0]
nsec=struct.unpack_from('<H',d,pe+6)[0]; opt=struct.unpack_from('<H',d,pe+20)[0]
for i in range(nsec):
    o=pe+24+opt+i*40; n=d[o:o+8].rstrip(b'\0').decode(); vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8)
    if n not in ('.text','PAGE','INIT'): continue
    for k in range(0,min(vs,rs),4):
        w=struct.unpack_from('<I',d,ro+k)[0]
        if (w&0xfc000000) in (0x94000000,0x14000000):
            imm=w&0x3ffffff
            if imm&(1<<25): imm-=1<<26
            if va+k+imm*4==tgt: print(n,hex(va+k),'bl' if w&0x80000000 else 'b')
