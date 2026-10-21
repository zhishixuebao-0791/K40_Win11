# 用法：python guidref.py <sys> <guid>  找出引用该 GUID 的指令，并列出其后 12 条指令（含导入函数名）
import struct,sys,uuid,capstone
d=open(sys.argv[1],'rb').read(); g=uuid.UUID(sys.argv[2]).bytes_le
pe=struct.unpack_from('<I',d,0x3c)[0];nsec=struct.unpack_from('<H',d,pe+6)[0];opt=struct.unpack_from('<H',d,pe+20)[0]
secs=[]
for i in range(nsec):
    o=pe+24+opt+i*40;n=d[o:o+8].rstrip(b'\0').decode();vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8);secs.append((n,va,vs,ro,rs))
def o2r(off):
    for n,va,vs,ro,rs in secs:
        if ro<=off<ro+rs: return va+off-ro
def r2o(r):
    for n,va,vs,ro,rs in secs:
        if va<=r<va+max(vs,rs): return ro+r-va
tg=set(); i=d.find(g)
while i!=-1: tg.add(o2r(i)); i=d.find(g,i+1)
print('GUID rva',[hex(x) for x in tg])
imp={}
irva=struct.unpack_from('<I',d,pe+24+112+8)[0]; o=r2o(irva)
while True:
    ilt,_,_,nm,iat=struct.unpack_from('<IIIII',d,o)
    if nm==0: break
    k=0
    while True:
        e=struct.unpack_from('<Q',d,r2o(ilt)+k*8)[0]
        if e==0: break
        if not e>>63:
            no=r2o(e&0x7fffffff)+2; imp[iat+k*8]=d[no:d.index(b'\0',no)].decode()
        k+=1
    o+=20
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.skipdata=True
for n,va,vs,ro,rs in secs:
    if n not in('.text','PAGE','INIT'): continue
    ins=list(md.disasm(d[ro:ro+min(vs,rs)],va)); pg={}
    for k,x in enumerate(ins):
        if x.mnemonic=='adrp':
            try: r,imm=x.op_str.split(', #'); pg[r]=int(imm,16)
            except: pass
        elif x.mnemonic in('add','ldr'):
            p=x.op_str.replace('[','').replace(']','').split(', ')
            if x.mnemonic=='add' and len(p)==3 and p[1] in pg and p[2].startswith('#') and pg[p[1]]+int(p[2][1:],16) in tg:
                print('--- ref at',hex(x.address))
                for y in ins[k-3:k+14]:
                    c=''
                    if y.mnemonic=='ldr':
                        q=y.op_str.replace('[','').replace(']','').split(', ')
                        if len(q)==3 and q[1] in pg and q[2].startswith('#'): c=imp.get(pg[q[1]]+int(q[2][1:],16),'')
                    print('   ',hex(y.address),y.mnemonic,y.op_str,c)
