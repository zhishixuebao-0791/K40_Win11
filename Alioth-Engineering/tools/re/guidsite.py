# 找出 PE 中某个 GUID 的存放位置（RVA），供在 fulldis 输出中 grep "; 0x<rva>" 定位引用代码
# 用法：python guidsite.py <驱动.sys> <guid> [<guid>...]
import struct, sys, uuid
d = open(sys.argv[1], 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]; n = struct.unpack_from('<H', d, pe + 6)[0]; opt = struct.unpack_from('<H', d, pe + 20)[0]
secs = []
for i in range(n):
    o = pe + 24 + opt + i * 40; nm = d[o:o + 8].rstrip(b'\0').decode(); vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8); secs.append((nm, va, ro, rs))
for g in sys.argv[2:]:
    b = uuid.UUID(g).bytes_le; p = d.find(b)
    while p >= 0:
        for nm, va, ro, rs in secs:
            if ro <= p < ro + rs: print(g, nm, 'rva=0x%x' % (va + p - ro))
        p = d.find(b, p + 1)
