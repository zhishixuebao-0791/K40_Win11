# 用法：python wppmsg.py <sys> <guid_rva_hex> [...]  列出每个 WPP 调用点：消息 GUID、消息编号、所在地址
import struct,sys,capstone
d=open(sys.argv[1],'rb').read(); want={int(x,16) for x in sys.argv[2:]}
pe=struct.unpack_from('<I',d,0x3c)[0];nsec=struct.unpack_from('<H',d,pe+6)[0];opt=struct.unpack_from('<H',d,pe+20)[0]
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.skipdata=True
for i in range(nsec):
    o=pe+24+opt+i*40;n=d[o:o+8].rstrip(b'\0').decode();vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8)
    if n not in('.text','PAGE','INIT'): continue
    ins=list(md.disasm(d[ro:ro+min(vs,rs)],va))
    pg={}
    for k,x in enumerate(ins):
        if x.mnemonic=='adrp':
            r,imm=x.op_str.split(', #'); pg[r]=int(imm,16)
        elif x.mnemonic=='add':
            p=x.op_str.split(', ')
            if len(p)==3 and p[1] in pg and p[2].startswith('#'):
                t=pg[p[1]]+int(p[2][1:],16)
                if t in want:
                    num='?'
                    for y in ins[max(0,k-4):k+6]:
                        if y.mnemonic=='mov' and y.op_str.startswith('w3, #'): num=y.op_str[5:]
                    bl=[y.op_str for y in ins[k:k+8] if y.mnemonic=='bl']
                    print(hex(t),'msg',num,'at',hex(x.address),'->',bl[:1])
