# Phase18a 构建结果（Ubuntu，2026-10-23）

## 镜像
| 镜像 | 内容 | SHA256 |
| --- | --- | --- |
| `UEFI-Images/Mu-alioth-1-acpi-hid-phase18a-iort-dbg2-20261023-095921.img` | Phase16 DSDT（PEP0=QCOM0519）+ 修复版 DBG2 + Kona 最小 IORT | `2f1bbb5fc305fb7edb98aa10cfd6d5812052472aa7d6abafac21e30abb315bfd` |

- 日志：`logs/mu-alioth-phase18a-build-20261023-095921.log`（外层），`logs/mu-alioth-phase17g-base-build-20261023-095921.log`（内层 17f/base）。退出码 0。
- FVMAIN.Fv 中同时含 `Kona-IORT-min.aml`（整表）与修复版 DBG2。
- FV 空间：FVMAIN `0x7c6000` 总量（比 17g-base 的 `0x7c5000` 多一个块）、空闲 0xd10；FVMAIN_COMPACT 38%。印证了 Windows 侧的更正：FVMAIN 是自动大小，"100% Full"不代表放不下，真正上限是 FVMAIN_COMPACT 的 3MB。
- 构建后：ACPI.inc（IORT 行重新注释、DBG2 回到 DEBUG 条件）、Kona/DBG2.aml（原表 3d6c2673…）、DSDT.asl（17e-all，27 个桩）均已恢复；临时 Kona/IORT.aml 已删除；/tmp 无残留。

## 构建前对 IORT 的独立核对
- SHA256 与脚本一致（9af15bed…86f7）；iasl 反汇编正常：长度 0x408、2 个类型 3 节点、节点头 0x3C、全局中断数组 16 字节、上下文中断 8 字节/个，结构与 Silicium `Hana/IORT.dsl` 逐字段同构（IORT 修订 0、型号 3=MMU-500、标志 0、无映射）。
- 下载 Linux v6.12 `arch/arm64/boot/dts/qcom/sm8250.dtsi` 逐个比对：
  - apps_smmu：reg `0x15000000/0x100000`，`#global-interrupts = <2>`（SPI 64、65），其后 96 个上下文中断与 IORT 中 96 个（减 32）**完全一致**。
  - adreno_smmu：reg `0x03da0000/0x10000`，`#global-interrupts = <2>`（SPI 672、673），其后 8 个上下文中断 SPI 678–685 与 IORT **一致**。
  - 全局中断取两者中的第 2 个（SPI 65 → 0x61、SPI 673 → 0x2C1），与 Hana 表的取法相同。
- 留意点（不阻塞测试）：上下文中断标志沿用 Hana 的 1（边沿触发），而 Linux dtsi 写的是 `IRQ_TYPE_LEVEL_HIGH`。如果内核 IOMMU 初始化成功但出现中断风暴或上下文故障收不到，可以把 `CTX_FLAGS` 改成 0 再试。

## 手机端（同 `notes/acpi-hid-phase18a-iort-plan-20261022.md`）
1. 保持 qcsmmu Start=3（ImagePath qcsmmu8280）、qcsubsys Start=4。
2. kd 先监听，再 `fastboot boot` 本镜像（不要 flash）。
3. 断点：`qcsmmu8280+0x2b1c`（IoGetIommuInterface 返回值）、`+0x2b70`、`+0x2bac`；`!acpicache` 应出现 IORT。
