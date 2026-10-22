# 用法：python gen_kona_iort.py <输出 .aml>
# Phase18a：生成 Kona（SM8250）最小 IORT，只含两个 SMMUv1/v2 节点（应用 SMMU + GPU SMMU），不含命名组件。
# 目的：让 Windows 内核 IOMMU 初始化，使 qcsmmu8280 的 IoGetIommuInterface 成功，从而跳过向 PEP 要接口的分支。
# 参数来源：Linux v6.12 arch/arm64/boot/dts/qcom/sm8250.dtsi（apps_smmu@15000000、adreno_smmu@3da0000），
#           节点格式与中断标志写法沿用 Silicium Hana/IORT.dsl（IORT 修订版 0，型号 3 = ARM MMU-500）。
# GSIV = GIC SPI 号 + 32。PMU 中断 Linux 未给出，填 0 个。
import struct, sys


def spi(*ranges):
    out = []
    for r in ranges:
        out += list(range(r[0], r[1] + 1)) if isinstance(r, tuple) else [r]
    return [x + 32 for x in out]


APPS = dict(base=0x15000000, span=0x100000, nsg=65 + 32,
            ctx=spi((97, 118), (181, 192), (315, 345), (395, 409),
                    412, 418, 419, 421, 423, 424, 425, (690, 697), 707))
GPU = dict(base=0x03DA0000, span=0x10000, nsg=673 + 32, ctx=spi((678, 685)))
CTX_FLAGS = 1  # 与 Hana 一致


def smmu_node(n):
    ctx = b''.join(struct.pack('<II', g, CTX_FLAGS) for g in n['ctx'])
    glob = struct.pack('<IIII', n['nsg'], 0, 0, 0)          # NSgIrpt, 标志, NSgCfgIrpt, 标志
    hdr_len = 0x3C
    length = hdr_len + len(glob) + len(ctx)
    body = struct.pack('<BHBIII', 3, length, 0, 0, 0, 0)     # 类型 3、长度、修订 0、保留、映射数 0、映射偏移 0
    body += struct.pack('<QQII', n['base'], n['span'], 3, 0)  # 基址、范围、型号 3、标志 0
    body += struct.pack('<IIIII', hdr_len, len(n['ctx']), hdr_len + len(glob), 0, 0)
    assert len(body) == hdr_len
    return body + glob + ctx


nodes = [smmu_node(APPS), smmu_node(GPU)]
payload = struct.pack('<III', len(nodes), 0x30, 0) + b''.join(nodes)
length = 36 + len(payload)
hdr = struct.pack('<4sIBB6s8sI4sI', b'IORT', length, 0, 0, b'QCOM  ', b'QCOMEDK2', 0x8250, b'INTL', 0x20230628)
tbl = bytearray(hdr + payload)
tbl[9] = (-sum(tbl)) & 0xff
open(sys.argv[1], 'wb').write(tbl)
print(f"已生成 {sys.argv[1]}：长度 {length:#x}，节点 {len(nodes)} 个；"
      f"应用 SMMU 上下文中断 {len(APPS['ctx'])} 个，GPU SMMU 上下文中断 {len(GPU['ctx'])} 个；校验和 {tbl[9]:#04x}")
