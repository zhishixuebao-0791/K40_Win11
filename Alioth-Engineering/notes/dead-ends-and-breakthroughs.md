# 死路与突破记录（持续更新）

用来避免重复尝试已证实无效的路径。每条写明：日期、路径、证据、结论。

## 死路（不要再试）

### 1. 用 ACPI `_DSD` 给 qcsubsys8280 传 PDInfo/RPEC/Interfaces（Phase12，2026-05-13）
- 证据：AML 里有对应值，但开机后 Enum 注册表中 `NumPDs` 仍为 0，Code 31 `0xC0000034` 不变。
- 结论：`_DSD` 不会被转换成 qcsubsys 读取的注册表结构。

### 2. 把 qcsubsys 的 RPEC/Interfaces/PDName 写进 Enum 硬件键（Phase13，2026-05-13）
- 证据：写入后开机，状态码不变；`PDName` 和 `RPEC` 被删除；`DEVPKEY_Device_ConfigurationId` 中没有扩展 INF。
- 结论：位置和值名都错了。8280 驱动从**驱动软件键** `Control\Class\...\ADSP` 读取 `ImagePath`、`RPEC` 等；PDInfo 用的值名是 `ServiceName`，不是 `PDName`。详见 `phase13-validation-and-phase14-plan-20261016.md`。

### 3. 直接使用 Surface 的 `qcadsp8280.mbn` 或高通参考版 `qcadsp8250.mbn` 作为 alioth 的 ADSP 固件（推断，未实测）
- 依据：前者属于 SC8280XP；后者是 MTP 参考签名。量产机 TZ 按 OEM 签名验签。
- 结论：必须从手机 modem 分区提取并合并 alioth 自己的 `adsp.mdt/.bXX`。如果以后实测推翻这一条，在这里更正。

### 4. WDAC / Code Integrity 方向（2026-05-06 ~ 05-08）
- 结论：Phase7 改走 Surface 8280 签名包后，CI 阻断已经消除。qcsubsys 的问题不在签名。之后不要再改 WDAC 策略。

### 5. 走老的 8250 驱动路线（QCOM2522 / qcsubsys8250 等）
- 结论：会碰到签名和 WDAC 风险（Code 52）。当前稳定路线是 Surface 8280 风格的 HID。

### 6. 以为 qcsubsys8250.sys 内嵌了 8250 版 ADSP 的 AeoB 资源（2026-10-16）
- 实测：驱动里的 3 处 `AeoB` 都是解析代码中的常量，长度字段不合理，不是资源块。不要再从 8250 驱动里找 RADS。
- 网上也没有找到现成的 8250 RADS.bin 或相关方案（截至 2026-10-16 的搜索）。

### 7. 只补 ADSP 的 Resources\BinaryPath（Surface 原版 RADS.bin）来消除 0xC000003B（Phase15A，2026-10-17）
- 实测：BinaryPath 和 RADS.bin 都在位，状态码仍是 0xC000003B。单独补这一项不够。
- 静态扫描显示 0xC000003B 来自内核 API 透传，而不是驱动自己构造的。下一步改为用反汇编或 Procmon 精确定位，不要再逐项猜注册表值。

### 8. 使用 Kona 包里由 Andromeda 证书签名的驱动（qcsmmu8250 等）（2026-10-17 再次确认）
- Phase16 中 qcsmmu8250 虽已匹配成功，但 CI 3004 / Code 52 拒绝加载。凡是由 `Windows On Andromeda KMCI Codesigning` 签名的 Kona 驱动都会遇到这个问题。
- 对策：改用 Surface 8280 包中 WHQL 签名的同类驱动程序本体，并沿用 8250 的配置（注册表和资源文件）。
- 不要直接用 8280 INF 安装 SMMU：它的流映射表是 SC8280XP 的。

### 9. 用 DebugView 抓 qcsmmu8280 的 DbgPrintEx 来定位 AddDevice 失败（Phase16d，2026-10-20）
- 实测：Live 模式（重启 MMU1）三次、开机模式一次，DebugView 都能抓到其他驱动的内核打印（CcFlushCachePriv、IPC_Router、QMI），但 qcsmmu 一行都没有。
- 原因（反汇编确认）：`SmmuError` 这类字符串只出现在 PrepareHardware/SmmuInitHardware 路径，AddDevice 走不到那里。驱动唯一的 DbgPrintEx 是 WDF 存根里的 "DriverEntry failed"。AddDevice 的诊断全部通过 WPP 输出（sub_2368/sub_24d0），DebugView 看不到。
- 对策：改用 ETW 抓 WPP。控制 GUID `{cf6bfd48-e161-4949-96d5-8647cfc488c8}`，AddDevice 所在源文件的消息 GUID `{6062ceb3-6692-336b-146c-b3eb83582bc2}`。不需要 TMF，用消息编号对照反汇编即可。

### 10. 在 DSDT 中清空 PEP0 的设备电源配置方法来解决 qcpep 卡死（Phase17e，2026-10-21）
- 做法：把 27 个设备电源配置方法（APMD/GPMD/BPMD/SDMD/…）都改成返回空包。
- 结果：仍然在转圈约 2 秒后整机卡死。卡死与设备电源配置无关，在 qcpep 核心初始化里。
- 另外：qcpep8250.sys 中的 OSM 地址表（`0x18321000/0x18323000/0x18325800`，SC8180X 布局）**不是根因**，因为能正常工作的 qcpep8280.sys 里有一模一样的表。不要再顺着这条线追。

### 11. 在默认 RELEASE 镜像上改 BCD 的 busparams 来打通 KDNET USB EEM（Phase17f，2026-10-21）
- 现象：busparams 1 和 0 都试过，电脑端什么都枚举不到，手机上也没有 `Services\kdnet`。
- 原因：`ACPI.inc` 中 DBG2 只在 `TARGET == DEBUG` 时打包，RELEASE 镜像里根本没有 DBG2。只改 BCD 没有用，必须用 `tools/build-acpi-hid-phase17f.sh` 构建带 DBG2 的镜像。
- 附带结论：Kona DBG2 只有一个设备，busparams 应为 0。
- **更正（2026-10-22）**：之前写"DBG2 OEM 数据签名不对只会跳过寄存器修补、不会导致 KD 失败"，这是错的。修补里有强制 VBUS 有效（QSCRATCH `0xf8810 = 0x10100000`）这一条，不执行它 DWC3 就不上拉，KD 会一直卡在等待连接，把开机挡住（Phase17f-base 停在 Silicium 画面）。Silicium 原版 Kona/DBG2.aml 不能直接用于 KDNET，要用 `acpi/Kona-DBG2-oemfix.aml`（phase17g）。

## 突破

### 1. PILC 启动：安装扩展 INF 解决（2026-05-11/12）
- 安装 `qcpilEXT8280.inf` 扩展后，`QCOM06E0` 从 Code 31 变为 OK，重启后仍然保持。
- 启示：8280 驱动的运行参数依赖扩展 INF。qcsubsys 的 ADSP/CDSP/SPSS 也是同样的结构。

### 2. SSDD 走 Surface 8280 路线后正常工作（Phase7，2026-05-08）
- `QCOM0620` 绑定 `qcsubsys8280.sys`，状态 OK，没有 CI 阻断。

### 3. 定位到 qcsubsys DSP 根节点 `0xC0000034` 的根因（2026-10-16，待 Phase14 实测验证）
- 缺少扩展 INF 写在驱动软件键里的 `ADSP\ImagePath` 等参数，以及 alioth 自签名的固件 mbn。
- 离线取证已确认：`Class\...\0036` 中没有 `ADSP` 子键；PILC 的 `SubsystemLoad` 中也没有 `ADSP` 内存预留。

### 5. Phase14：ADSP 故障码从 0xC0000034 变为 0xC000003B（2026-10-16）
- 写入 8280 软件键（ImagePath/RPEC/Interfaces/MANU 等）、PDInfo（ServiceName 形态）和 PILC 的 SubsystemLoad\ADSP 之后，只有 ADSP 的状态码变了，CDSP/SCSS 作为对照没变。
- 下一个卡点推断是缺少 `Resources\BinaryPath`（AeoB 电源资源 RADS.bin），由 Phase15A 验证。

### 6. Procmon 开机日志定位 ADSP 0xC000003B 的根因（2026-10-17）
- 方法：手机上 `Procmon64a.exe /EnableBootLogging` → 重启 → `/ConvertBootLog`；电脑上 `Procmon64.exe /NoFilter /OpenLog x.pml /SaveAs x.csv`，再用 `tools\filter_procmon_csv.py` 筛选。这是定位驱动 Code 31 的通用高效方法，以后优先使用。
- 结论：qcsubsys 在确认固件存在之后，去查询设备接口类 `{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}`（SMMU 接口），找不到就失败。根因是 SMMU（MMU0/MMU1，HID QCOM0509）没有绑定 qcsmmu8250（INF 只认 DEV_2509）。
- 以前诊断脚本把 MMU 判为 not present 是误判：实例路径是 `ACPI\VEN_QCOM&DEV_0509&SUBSYS_MTP08250&REV_0002\1`。

### 7. SMMU 绕过 Andromeda 签名：WHQL qcsmmu8280.sys + 8250v2 配置（Phase16b，2026-10-17）
- 做法：DISM 离线注入 Surface qcsmmu8280 包，把 `Services\qcsmmu\ImagePath` 指向 qcsmmu8280.sys，设备仍由 qcsmmu8250.inf（8250v2 节）安装，保留 8250 的流映射表。
- 结果：没有 CI 3004，驱动成功加载，开机正常；MMU1 从 Code 52 变为 Code 31（0xC0000001，AddDevice 失败）。
- 启示：“8250 INF 装配置 + 8280 WHQL 驱动程序本体”这种组合能够绕过签名问题，其他 Kona 驱动（如 qciommu）也可以借鉴。剩下的是配置兼容性问题。

### 8. 根因链定位：{55beca03} 是 PEP 提供的接口，PEP0 没有驱动导致 SMMU 和 ADSP 连锁失败（Phase16e，2026-10-20）
- 方法：用 logman 建 ETW 会话，抓 qcsmmu8280 的 WPP 跟踪（控制 GUID cf6bfd48-…），然后重启 MMU1，tracerpt 输出事件，按"消息 GUID + 编号"对照反汇编（tools\re\wppmsg.py、guidref.py）。不需要 TMF。这是定位 WDF 驱动 Code 31 的通用方法。
- 结果：AddDevice 依次打出消息 0xc、0x20、0x22。sub_116a8 用 `IoGetDeviceInterfaces({55beca03})` 得到空列表，`IoGetDeviceObjectPointer` 失败，sub_12370 失败，AddDevice 返回 0xC0000001。
- 反汇编 qcpep8280.sys 和 qcpep8250.sys：两者都用 {55beca03} 调用 WDF 函数表第 77 项 `WdfDeviceCreateDeviceInterface`，所以**提供者是 PEP**。其余高通驱动（smmu、subsys、gpu、i2c/spi/uart、相机、scm…）都是使用方。
- 依赖链：PEP0（QCOM0519）没有驱动 → 没有 {55beca03} → SMMU Code 31 → ADSP 0xC000003B。修好 PEP 是整条音频链路的前提。

### 9. 测试签名可用（Phase17a，2026-10-21）
- 设备没有启用安全启动（`Confirm-SecureBootUEFI` 报变量未定义 0xC0000100），`bcdedit /set {current} testsigning on` 之后可以正常开机，出现"测试模式"水印。
- 同时把 qcsmmu 换回 Andromeda 签名的 qcsmmu8250.sys 后，开机卡在 Silicium logo。离线恢复 8280 的 ImagePath 后恢复正常。说明 8250 驱动在测试签名下很可能已被加载（不再被 CI 拒绝），这为原生 Kona 驱动（qcpep8250 等）打开了路。
- 注意：单独换 qcsmmu8250 会导致开机卡死，在 PEP 修好之前不要再这样做。

### 4. 取得 alioth 自签名 DSP 固件（2026-10-16）
- 可靠流程：`fastboot boot` 临时启动 TWRP → 只读挂载当前槽的 `modem_x` → adb pull → 按 SHA256 清单校验 → `tools\pil_squasher.py` 合并。
- 结果在 `components\Devices\Alioth\firmware-squashed\`（adsp/cdsp/slpi 三个 mbn）。
- 注意：Mass Storage 模式只暴露 LUN0，看不到 modem 分区，不要再尝试从 Mass Storage 读固件。
