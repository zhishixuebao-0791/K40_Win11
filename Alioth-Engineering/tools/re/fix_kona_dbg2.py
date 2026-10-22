# 用法：python fix_kona_dbg2.py <Kona/DBG2.aml> <Hana/DBG2.aml> <输出.aml>
# 修复 Silicium Kona DBG2 的 OEM 数据：Silicium 截取 OEM 区时把偏移取成了"表开头"，OEM 区里装的是表头前 0x94 字节，
# 2XIF 修补表因此错位、截断，kd_8003_5143 找不到签名，就不会强制 VBUS 有效（QSCRATCH HS_PHY_CTRL = 0x10100000），
# DWC3 不上拉，电脑端什么都枚举不到，KD 卡在 KdUsbFnWaitForConnection。
# SM8150(Hana) 与 SM8250(Kona) 的 USB 布局相同（DWC3 0xa600000、QSCRATCH 0xa6f8800、\_SB.URS0），
# 高通原版 Hana/Lahaina/Waipio/Kailua 的 OEM 数据完全一致，所以直接换成 Hana 的 OEM 数据，表的其他部分不动。
import struct, sys

def devices(d):
    off, num = struct.unpack_from('<II', d, 36)
    p = off
    for _ in range(num):
        rev, ln, ngar, nsl, nso, oeml, oemo, pt, pst, rsv, baro, aso = struct.unpack_from('<BHBHHHHHHHHH', d, p)
        gars = [struct.unpack_from('<Q', d, p + baro + g * 12 + 4)[0] for g in range(ngar)]
        yield dict(p=p, ln=ln, oeml=oeml, oemo=oemo, pt=pt, pst=pst, ns=d[p + nso:p + nso + nsl], gars=gars)
        p += ln

def usb_dev(d):
    for v in devices(d):
        if v['pt'] == 0x8003 and v['pst'] == 0x5143 and v['ns'] == b'\\_SB.URS0\x00' and v['gars'][0] == 0xa600000:
            return v
    raise SystemExit('找不到 \\_SB.URS0 / 0xa600000 的 0x8003/0x5143 设备')

kona = bytearray(open(sys.argv[1], 'rb').read())
hana = open(sys.argv[2], 'rb').read()
if sum(kona) % 256:
    raise SystemExit('Kona 输入表校验和不正确')
if sum(hana) % 256:
    print('提示：Hana 表本身校验和不正确（Silicium 的表常见），只取它的 OEM 数据，不影响结果')
k, h = usb_dev(kona), usb_dev(hana)
if k['oeml'] != h['oeml']:
    raise SystemExit(f"OEM 长度不同：Kona {k['oeml']:#x}，Hana {h['oeml']:#x}")
hana_oem = hana[h['p'] + h['oemo']:h['p'] + h['oemo'] + h['oeml']]
if hana_oem[4:8] != b'2XIF':
    raise SystemExit('Hana OEM 数据没有 2XIF 签名')
start = k['p'] + k['oemo']
old = bytes(kona[start:start + k['oeml']])
if old == hana_oem:
    print('Kona OEM 数据已经是修复后的内容')
kona[start:start + k['oeml']] = hana_oem
kona[9] = 0
kona[9] = (-sum(kona)) % 256
assert sum(kona) % 256 == 0
open(sys.argv[3], 'wb').write(bytes(kona))

cnt = struct.unpack_from('<I', hana_oem, 8)[0]
print(f'已写入 {sys.argv[3]}（{len(kona)} 字节，校验和字节 {kona[9]:#04x}）')
for j in range(cnt):
    t, ph, _, _, offs, andm, orv = struct.unpack_from('<BBBBIII', hana_oem, 12 + j * 16)
    print(f'  修补{j}: 类型={t:#x} 阶段={ph} 偏移={offs:#x} AND={andm:#010x} OR={orv:#010x}')
diff = [i for i in range(len(kona)) if i != 9 and not (start <= i < start + k['oeml']) and kona[i] != open(sys.argv[1], 'rb').read()[i]]
print('OEM 区与校验和以外改动的字节数：', len(diff))
