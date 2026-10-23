# PEP0 桩驱动：qcsmmu8280 / qcsubsys8280 对 PEP 接口的使用（2026-10-23，静态分析）

工具：tools/re/fulldis.py（整体反汇编，含导入名/全局地址注释）、disgrep.py（按正则带上下文检索，标注所在函数）、guidsite.py（GUID 存放 RVA）。

## qcsmmu8280（AddDevice 同步路径 sub_12370）
1. sub_116a8：`IoGetDeviceInterfaces({55beca03-ba2c-4fbc-9efc-ee8eca56f0c7})` → `IoGetDeviceObjectPointer`（第一个符号链接）。→ 桩驱动必须注册并启用该设备接口，且 IRP_MJ_CREATE 能成功（KMDF 功能驱动默认即成功）。
2. sub_3e9a8：基于该设备对象建 WDFIOTARGET。
3. sub_3ec30：QueryInterface `{a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}`，Size=0x28，Version=1（GUID 按值经 x1:x2 传入），拷到设备上下文 +0x2510。
4. sub_11898：从设备注册表 `Resources` 子键读 `SMMU` 字符串值（WdfDeviceOpenRegistryKey→WdfRegistryOpenKey→WdfRegistryQueryString）。INF：`HKR,Resources,"SMMU",REG_SZ,%13%\SMMC.bin`（Kona qcsmmu8250.inf 第 72 行同样有）。
5. sub_11ca8：`\DosDevices\` + 路径，ZwCreateFile/ZwReadFile 读入整个文件（AeoB 格式电源资源描述：\_SB.MMU0 的 COMPONENT/FSTATE/CLOCK），以**缓冲区指针为唯一参数**调用接口 +0x20 的函数，返回 NTSTATUS，<0 → WPP 0x1a → 整体失败。
- 结论：{a0e1dd36} = “把设备的 AeoB 电源资源交给 PEP 注册”。qcpep8280 的实现 0x20230 在桩模式（EnableStubbedPepForPresilicon）下直接返回 0。**桩驱动：返回 STATUS_SUCCESS 即可**（IRQL>0 时 qcpep 返回 0xC0000022，可照搬）。

## qcsmmu8280 的 {99f8bbdb-5b65-444b-adbe-5b87efedd76c}（异步、可选）
- IoRegisterPlugPlayNotification 等 {55beca03} 到达 → sub_3eed0 打开 PEP → QueryInterface Size=0x38 Version=1 → 设备上下文 +0x24a0（头 0x20 + 3 个函数指针）。
- 只用到第 3 个函数（+0x30）：sub_1d630 中 `f(1)` … `f(0)`，调用前判空（空 → WPP 0xa3 返回失败，不崩溃）。仅在引用计数 +0x23f0 非 0 且轮询超时的恢复路径中触发。
- 桩驱动可以不提供该接口，或提供且 3 个函数都返回 STATUS_SUCCESS。

## qcsubsys8280（ADSP，音频链下一环）
- sub_ea68：sub_e208 打开 PEP IoTarget → sub_e768 用 WdfIoTargetQueryForInterface（WDF 表 177）要 {a0e1dd36}，Size 0x28 → 拷到全局 0x6c460（函数指针 0x6c480）；失败 → WPP 0x2a 走错误路径。
- sub_d8f0：同样 ZwCreateFile/ZwReadFile 读资源文件（对应 Phase15A 的 Resources\BinaryPath / RADS.bin），调用接口函数，**不检查返回值**。
- 结论：桩驱动的同一个函数同时满足 SMMU 与 ADSP。

## 其他引用者（风险）
- Kona 包中引用 {55beca03}：qcdxkm8250（GPU，引用 {99f8bbdb}）、qcqdss8250（{a0e1dd36}）、qcsmmu8250/qcpep8250/qcsubsys8250。Kona 的 i2c/spi/uart 不引用。
- GPU 驱动在 {55beca03} 出现后会去查 {99f8bbdb}（Size 0x38），细节未分析（本会话分析中断）。若桩驱动**不提供** {99f8bbdb}，GPU 查询失败时的行为未知 → 首测建议：先不提供 {99f8bbdb}，用 kd 观察 GPU/显示是否受影响；如有问题再评估。

## 桩驱动规格（草案）
- 绑定 PEP0（ACPI\QCOM0519，Phase16 镜像中的原始 HID，不需改 UEFI），KMDF 1.15，非过滤功能驱动。
- EvtDeviceAdd：WdfDeviceCreate → WdfDeviceCreateDeviceInterface({55beca03}) → WdfDeviceAddQueryInterface({a0e1dd36}, Size 0x28, Ver 1, Ref/Deref 空函数, 函数：IRQL>PASSIVE 返回 STATUS_ACCESS_DENIED，否则 STATUS_SUCCESS)。
- 不做任何 MMIO，不注册 PoFx PEP（不是真正的电源引擎插件）。
- 手机前置：qcpep 服务需停用或改绑（避免两个驱动抢 PEP0）；qcsmmu Start=3；qcsubsys 首测保持 4，SMMU 通过后再开。
