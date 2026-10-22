# Phase18a：为 Kona 提供最小 IORT，让 qcsmmu8280 跳过 PEP 接口（2026-10-22）

## 依据
- Phase17j kd 实测：qcsmmu8280 DriverEntry 中 `IoGetIommuInterface(1)` 返回 0xC00000BB，`!acpicache` 无 IORT → 驱动上下文"内核 IOMMU 可用"标志为 0 → AddDevice 必须向 PEP 查询 `{a0e1dd36}`，PEP0 无可用驱动 → Code 31。
- 标志为 1 时 AddDevice（0x3690）跳过 0x12370（详见 phase17h2-qcpep8280-kd-result-20261022.md 末节）。

## IORT 内容（`acpi/Kona-IORT-min.aml`，`tools/re/gen_kona_iort.py` 生成，SHA256 9af15bed…86f7）
| 节点 | 基址/范围 | 型号 | 全局中断(GSIV) | 上下文中断 | PMU |
| --- | --- | --- | --- | --- | --- |
| 应用 SMMU | 0x15000000 / 0x100000 | 3 (MMU-500) | 0x61 (SPI 65) | 96 个：SPI 97–118、181–192、315–345、395–409、412/418/419/421/423/424/425、690–697、707 | 0 |
| GPU SMMU | 0x03DA0000 / 0x10000 | 3 | 0x2C1 (SPI 673) | 8 个：SPI 678–685 | 0 |
- 参数来源：Linux v6.12 `sm8250.dtsi`（apps_smmu、adreno_smmu）；节点格式、上下文中断标志 1 沿用 Silicium `Hana/IORT.dsl`。
- 与 Hana 对比：应用 SMMU 前 80 个上下文中断相同，之后不同（Hana 128 个）；GPU SMMU 基址不同（Hana 0x2CA0000），上下文中断差 2。
- 第一版不含命名组件（无流 ID 映射），只验证内核 IOMMU 能否初始化。音频需要的 `\_SB.ADSP.SLM1.ADCM` 等映射之后再补。
- iasl 反汇编核对通过（长度 0x408，校验和正确）。

## 构建（Ubuntu）
`bash Alioth-Engineering/tools/build-acpi-hid-phase18a.sh`
- 放置临时 `Silicium-ACPI/SoCs/Qualcomm/Kona/IORT.aml`，打开 ACPI.inc 中被注释的 IORT 行，调用 `build-acpi-hid-phase17f.sh`（VARIANT=base，DBG2_FIX=1），检查 FVMAIN.Fv 含 IORT，结束后恢复。
- 产物：`UEFI-Images/Mu-alioth-1-acpi-hid-phase18a-iort-dbg2-<时间>.img`。
- 更正：之前笔记说"pep 变体 FVMAIN 100% 满，再加内容会失败"是误读。FvMain 是 `NumBlocks = 0`（自动大小），日志永远显示 100% Full；真正受限的是 FVMAIN_COMPACT（3MB，phase17h 时只用了 38%）。

## 验证（手机）
1. 手机注册表保持：qcsmmu Start=3（ImagePath qcsmmu8280），qcsubsys Start=4。
2. kd 先监听，再 `fastboot boot` phase18a 镜像（不要 flash）。
3. 断点同 Phase17j：`qcsmmu8280+0x2b1c`（IoGetIommuInterface 返回值）、`+0x2b70`（CreateDomain）、`+0x2bac`（标志置 1）；`!acpicache` 应出现 IORT。
4. 判读：
   - 能开机且返回 0、标志置 1 → 再看 MMU0/MMU1 状态、`{55beca03}` 是否需要；然后补流 ID 映射。
   - 仍返回 0xC00000BB → 内核没接受这张 IORT（看 `!acpicache` 是否有 IORT；内核可能还要求命名组件或其他条件）。
   - 开机卡死/蓝屏 → kd 现场定位（内核 SMMU 初始化访问硬件）。回退：fastboot boot phase17g-base。
