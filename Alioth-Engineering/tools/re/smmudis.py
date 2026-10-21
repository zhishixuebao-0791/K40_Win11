import struct,sys,capstone
F=sys.argv[1]; want=int(sys.argv[2],16)
d=open(F,'rb').read()
pe=struct.unpack_from('<I',d,0x3c)[0]
nsec=struct.unpack_from('<H',d,pe+6)[0]; opt=struct.unpack_from('<H',d,pe+20)[0]
secs=[]
for i in range(nsec):
    o=pe+24+opt+i*40
    name=d[o:o+8].rstrip(b'\0').decode(); vs,va,rs,ro=struct.unpack_from('<IIII',d,o+8)
    secs.append((name,va,vs,ro,rs))
def r2o(r):
    for n,va,vs,ro,rs in secs:
        if va<=r<va+max(vs,rs): return ro+r-va
# imports
dd=pe+24+112
irva,isz=struct.unpack_from('<II',d,dd+8)
imp={}
o=r2o(irva)
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
# pdata
pd=[s for s in secs if s[0]=='.pdata'][0]
funcs=[]
for i in range(0,pd[2],8):
    b,x=struct.unpack_from('<II',d,pd[3]+i)
    if b==0: break
    if x&3: ln=((x>>2)&0x7ff)*4
    else:
        w=struct.unpack_from('<I',d,r2o(x))[0]; ln=(w&0x3ffff)*4
    funcs.append((b,b+ln))
f=[f for f in funcs if f[0]<=want<f[1]]
print('func',[hex(a) for a in f[0]])
s,e=f[0]
def rstr(r):
    o=r2o(r)
    if o is None: return ''
    b=d[o:o+120]
    if len(b)>2 and b[1]==0:
        t=b.decode('utf-16le','ignore').split('\0')[0]
    else: t=b.split(b'\0')[0].decode('latin1')
    return repr(t[:80]) if t and all(31<ord(c)<127 for c in t[:10]) else ''
md=capstone.Cs(capstone.CS_ARCH_ARM64,capstone.CS_MODE_ARM); md.detail=False
regs={}
for ins in md.disasm(d[r2o(s):r2o(e)],s):
    c=''
    if ins.mnemonic=='adrp':
        rd,imm=ins.op_str.split(', #'); regs[rd]=int(imm,16)
    elif ins.mnemonic in('add','ldr') :
        p=ins.op_str.replace('[','').replace(']','').split(', ')
        if ins.mnemonic=='add' and len(p)==3 and p[1] in regs and p[2].startswith('#'):
            t=regs[p[1]]+int(p[2][1:],16); c=hex(t)+' '+rstr(t)
        if ins.mnemonic=='ldr' and len(p)==3 and p[1] in regs and p[2].startswith('#'):
            t=regs[p[1]]+int(p[2][1:],16); c=imp.get(t,hex(t))
    elif ins.mnemonic=='bl':
        t=int(ins.op_str[1:],16); c='sub_'+hex(t)
    print(f'{ins.address:6x} {ins.mnemonic:6} {ins.op_str:36} {c}')
