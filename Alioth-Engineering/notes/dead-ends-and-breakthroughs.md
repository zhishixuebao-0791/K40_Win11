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

### 12. 只用 DISM /Add-Driver 注入 qcpep8280 就认为会加载 8280 驱动（Phase17h 首测，2026-10-22）
- 现象：Phase17h（PEP0→QCOM0617）能开到用户态（DispBroker、IPC Router 输出都有），开机约 2 分钟后出现 **BugCheck 0x101 CLOCK_WATCHDOG_TIMEOUT**（参数 0x18, 0, PRCB=CPU5, 5），CPU5 不响应时钟中断，栈无法解析。
- 关键证据：kd 中 `lm m qcpep*` **只加载了 qcpep8250**，qcpep8280 根本没有运行。
- 原因：8250 和 8280 的 INF 都 `AddService = qcpep`（BOOT_START）。离线 DISM 只把包放进 DriverStore，**不会改已存在的 `Services\qcpep\ImagePath`**（注入日志确认注入前后都指向 qcpep.wd8250…\qcpep8250.sys）。开机时引导加载器按旧 ImagePath 装入 8250；PnP 把 QCOM0617 绑到 qcpep 服务后，调用的仍是已加载的 8250 镜像 → 走 LMH 写入路径 → CPU 挂住 → 0x101。
- 结论：**Phase17h 首测不是 8280 的有效测试**，不能据此判断 8280 不行。同服务名替换驱动时，必须离线改 ImagePath（与 Phase16b 处理 qcsmmu 相同）。用 `tools/Set-Qcpep8280ImagePath-Offline-Admin.ps1`。
- 附带：kd 里 `sxe ld:` 连写两条只有最后一条生效；BOOT_START 驱动在 KD 连上之前就已加载，`sxe ld` 抓不到，要用 `lm` 确认。

### 13. 只补 ACPI IORT 让 qcsmmu8280 走"内核 IOMMU"分支（Phase18a，2026-10-23）
- 做法：phase18a 镜像加入 Kona 最小 IORT（应用 SMMU + GPU SMMU），`!acpicache` 确认 IORT 已加载。
- 结果：`IoGetIommuInterface` 仍返回 0xC00000BB。`nt!HalpGetIommuInterface` 只看 `nt!HalpHvIommu`（Hyper-V 提供的 IOMMU）；现场 HalpHvIommu=0、HalpIommuCount=0、HvlEnlightenments=0。
- 结论：ARM64 Windows 的这套 IOMMU 接口依赖 Hyper-V 接管 SMMU，K40 没有 Hyper-V，IORT 再正确也不会生效。不要再从 IORT 内容（中断、流 ID、触发方式）上找原因。

### 14. 在 K40 上让 Windows 跑在 Hyper-V（EL2）之上，以获得内核 IOMMU（2026-10-23，查证）
- 需求来源：死路 13，`HalpHvIommu` 只有 Hyper-V 接管 SMMU 时才为 1。
- 社区方案 slbounce（TravMurav）借助 Windows 的 Secure Launch（tcblaunch.exe）接管 QHEE 进入 EL2。其 README 明确写：**不能用于安卓设备**——QHEE 检查 devcfg 中允许 Secure Launch 的标志，只有出厂预装 Windows 的设备才设置。K40 是安卓机，EL2 被 QHEE 占用，无法启用 Hyper-V。
- qhypstub 只适用于 msm8916/615 等老平台。
- 结论：K40 上 qcsmmu8280 不可能走"内核 IOMMU 可用"分支，必须由 PEP（或替代者）提供 `{a0e1dd36}` 接口。
- 来源：https://github.com/TravMurav/slbounce 、https://github.com/TravMurav/Qcom-Secure-Launch

### 15. 在社区找 SM8250 现成的 PEP 替代/桩驱动或 Windows 音频方案（2026-10-23，查证）
- 查过：WOA-Project/windows_silicon_qcom_kona（本地副本与远端一致，最新 22221a0 2026-01-04；PowerManagement 只有高通原版 qcpep8250，无社区替代，docs 只有 NTDBG/RawPLATIDs）、edk2-porting/WOA-Drivers（只有 MSM8998/SDM845，PEP 为高通原版）、Project-Aloha（msmnile-Drivers 已归档，QC8250 子模块指向上面的 kona 仓库）、小米平板 6（pipa，同为 SM8250）Windows 移植（驱动仍在开发，未见音频可用报告）。
- 结论：网上没有开源的 qcpep 替代或桩驱动，也没有 SM8250 在 Windows 下音频（ADSP）跑通的公开报告。社区 Kona DSDT 让 PEP0 保持 QCOM0519 不绑定，等于默认放弃了 PEP→SMMU→ADSP 这条链。
- 剩余渠道：README 中的 Telegram 群 t.me/project_aloha_issues（需用户本人去问）。

### 16. 给 PEP0 设 ConfigFlags=0x20（CONFIGFLAG_REINSTALL）让 PnP 下次开机装 pep0stub（Phase19a，2026-10-23）
- 背景：DISM 离线注入 pep0stub 后服务会在开机阶段加载（kd 看到 DriverEntry），但 PEP0 实例早已存在（ConfigFlags=0、无 Driver），PnP 不会主动重新匹配。
- 设 0x20 后下一次开机 0x7B（参数 0xC0000034）。kd：PEP0 `ServiceName=pep0stub`，但停在 `DeviceNodeInitialized`，AddDevice 没被调用——带"重新安装"标志的设备在开机阶段不会启动，要等用户态安装；UFS0 等 `_DEP` 依赖 PEP0，系统盘起不来。
- 结论：PEP0 是开机关键依赖，不能把"安装"留给用户态。必须离线写好完整安装记录（Enum 的 Service/Driver/ClassGUID、Control\Class 驱动键，ConfigFlags=0），见 tools/Set-Pep0StubInstalled-Offline-Admin.ps1。
- 另：kd 桥接在目标机强制重启后不会自动重连，每次开机前要重启 kd_bridge。

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

### 10. KDNET over USB EEM 内核调试打通（Phase17g，2026-10-22）
- 三个前提缺一不可：① UEFI 中要有 DBG2（`ACPI.inc` 默认只在 DEBUG 构建中打包，用 `tools/build-acpi-hid-phase17f.sh` 强制打包）；② 用修复后的 `acpi/Kona-DBG2-oemfix.aml`（Silicium 原表 OEM 区错位，强制 VBUS 有效的修补不会执行，KD 会卡在等待连接）；③ BCD `busparams 0`，手机 USB 直连电脑。
- 结果：`phase17g-base` 镜像开机进桌面，电脑端出现 `Windows KDNET USB-EEM Network Adapter`（`USB\VID_045E&PID_064D`），WinDbg `Connected to target 169.254.213.22`。主机是 Win10 1909，也能用。
- 用法要点：kd.exe 要从 WinDbg 包（WindowsApps）复制出 `amd64` 目录才能运行；`tools/kd_bridge.py` 在后台运行 kd，通过 inbox.txt 发命令，`!!BREAK` 由一次性辅助进程发 Ctrl+Break。图形界面 WinDbg 被强制结束后，这一次开机里目标机不会再重连，所以要在**开机之前**就启动 kd（建议加 `-b`）。
- 意义：以后定位开机卡死、Code 31/10 等问题，可以直接下内核断点，不必再靠离线取证猜测。

### 11. 内核调试现场定位 qcpep 卡死根因：写 SM8150 的 LMH 寄存器（Phase17g-pep，2026-10-22）
- 方法：kd 先监听，再 `fastboot boot` phase17g-pep；卡死后 Break（目标仍能响应，不是整机总线挂死）。
- 现场：CPU0–6 在 `nt!MiDemoteSlabEntriesDpc`（KeGenericCallDpc 全核屏障）里等待；**CPU7 运行 `Phase1Initialization` 线程，不响应冻结 IPI**。线程栈：`IopInitializeBootDrivers → PiProcessAddBootDevices → PnpCallAddDevice → Wdf01000!FxDriver::AddDevice → qcpep8250+0x1df35c → +0x5c50 → +0x5b88 → +0x3398（dsb + 32 位写）`。
- `+0x5c50` 用 `MmMapIoSpaceEx(物理地址, 0x2c, 0x204)` 映射 **`0x18350800` / `0x18358800`**，存入全局变量 `+0x1c7100/+0x1c7108`，然后由 `+0x5b88` 写入 `0x3a`/`0`。
- 这两个地址是 **SM8150/SC8180X 的 LMH（lmh_cluster1/0）**（Linux sm8150.dtsi、sc8180x.dtsi）；**SM8250 上没有**（LMH 集成在 EPSS `0x18590000` 中）。写入得不到应答，CPU7 永远停住，其他核在下一次全核同步时等它，整机卡死。
- `+0x1df300` 一进来就无条件调用 `+0x5c50(1)`，**没有注册表开关可以跳过**（与 17d 改 EnableBCL 等参数仍然卡死一致）。
- 结论：这个 "qcpep8250.sys"（内部名 qcpep8180.sys）的 CPU 限流部分是按 8150/8180 硬件写死的，在 SM8250 上不能原样使用。
- 更正：死路第 10 条说"OSM 地址表不是根因"，结论下得太早。同一类按 8180 写死的 CPU 子系统地址确实是问题所在，只不过现场抓到的是 LMH。OSM（`0x18321000` 等）是否也会被访问还没核实，修补时要一并检查。

- 补充（2026-10-22）：qcpep8250 中专门访问 8180 写死地址的函数有 `+0x5520`、`+0x5b20`、`+0x5b88`（LMH 0x18350800/0x18358800）、`+0x6288`（LMH 0x18350bc0 的 bit0 开关）、`+0x6388`（读 OSM 调频域 0x18323704/0x18325f04 的 L 值）。另一处映射函数 `+0x1dd730` 还映射了 GIC `0x17a00108/0x17a00188`（SM8250 上存在）。`+0x137978` 引用了 OSM 地址表 `+0x177f90`，是否访问还没查完。
- 方向调整：对 qcpep8250.sys 做二进制修补这条路暂停（分析过程多次被中断）。改走"不改驱动"的路线：评估 qcpep8280.sys（WHQL，SC8280XP 同为 EPSS 架构）能否在 SM8250 上提供 `{55beca03}` 接口，或者用其他方式提供这个接口。

### 12. qcpep8280 在 SM8250 上卡死的根因：写死 SC8280XP 的 4 个 TSENS 控制器（Phase17h，2026-10-22）
- 修正 ImagePath 后 kd 确认加载的是 qcpep8280，系统能进用户态，但 PEP0 首次安装触发 AddDevice 时出现 0x101（CPU 不响应 IPI）。
- 用计数断点 + `p`/`gu` 逐层定位：AddDevice → `0x239d20` → `0x2b8bc0`（选用 `.rdata` 0x1a6b10 的 TSENS 配置，控制器数 4）→ `0x140b18` 循环逐个配置 TSENS 并创建中断；第 3 个控制器（`0x0c224000/0x0c251000`）在 SM8250 上不存在，MMIO 访问挂死。
- 没有注册表/ACPI 开关。修补点见 notes/phase17h2-qcpep8280-kd-result-20261022.md。
- 方法论：现场 `!vtop` 把驱动映射的虚拟地址换算成物理地址，再对照 Linux dtsi，是最快判断"驱动写死的硬件不存在"的手段。

### 13. 不改驱动绕过 qcpep8280 的 TSENS 卡死：注册表"桩 PEP"开关（2026-10-22，待实测）
- qcsmmu8280 向 PEP 要的只是 QueryInterface `{a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}`（1 个函数）。qcpep8280 中该函数在 `EnableStubbedPepForPresilicon != 0` 时直接返回成功。
- 同一个开关让 AddDevice 链上的 `0x239d20` 直接返回，跳过 TSENS 初始化（Phase17h 的卡死点）。
- 值位置：`HKLM\SYSTEM\<ControlSet>\Services\qcpep\Parameters\EnableStubbedPepForPresilicon`（REG_DWORD=1）。详见 notes/phase17h2-qcpep8280-kd-result-20261022.md。

### 4. 取得 alioth 自签名 DSP 固件（2026-10-16）
- 可靠流程：`fastboot boot` 临时启动 TWRP → 只读挂载当前槽的 `modem_x` → adb pull → 按 SHA256 清单校验 → `tools\pil_squasher.py` 合并。
- 结果在 `components\Devices\Alioth\firmware-squashed\`（adsp/cdsp/slpi 三个 mbn）。
- 注意：Mass Storage 模式只暴露 LUN0，看不到 modem 分区，不要再尝试从 Mass Storage 读固件。

### 14. pep0stub 0x7B 根因：自签测试证书未导入手机受信任根，winload 剔除该 boot 驱动（Phase19a，2026-10-23）
- 现象：boot3 完整安装记录（Start=0/Group=Base）开机 0x7B(0xC0000034)；kd 中 `lm m pep0stub` 空、`\Driver\pep0stub not found`、PEP0 停在 DeviceNodeInitialized，winload 的 BootDriverListHead 里有 qcpep/qcscm 等但**无 pep0stub**。
- 精确定位（只读核查，未改动）：
  1. 第1步 `pep0stub.sys/.inf/.cat` 确在 DriverStore（`…\pep0stub.inf_arm64_aae1034fcdb56eb3\`），排除文件缺失。
  2. `Get-AuthenticodeSignature pep0stub.sys`：自签名 `CN=K40 Alioth Test Driver Signing`（指纹 `7151DDBEB8836BE0D0733A53B1B5700C787E1FF7`），链单节、状态 **UntrustedRoot**。
  3. 离线挂手机 SOFTWARE hive 查证书库（`tools/Check-Pep0StubTrust-Offline-Admin.ps1`）：ROOT(26)/TrustedPublisher(14)/CA(3) 及两个组策略库**均无**该指纹。
- 根因：testsigning 已开（qcpep 的 Andromeda 签名能进引导列表即证），但 testsigning 只免 WHQL/微软交叉证书，**不免「签名证书的根必须在设备受信任根库」**。pep0stub 的自签根不在手机里 → winload boot CI 判 UntrustedRoot → 把它剔出引导驱动列表 → PEP0 无驱动 → UFS `_DEP(\_SB.PEP0)` 不满足 → 0x7B。与 qcpep（根已信任）形成对照。
- 对策（成熟方案，微软「Installing Test Certificates」口径）：把 K40 测试证书离线导入手机的 **Trusted Root** + **Trusted Publisher**（`SOFTWARE\Microsoft\SystemCertificates\ROOT|TrustedPublisher\Certificates\<指纹>\Blob`）。因 PEP0 是 boot 关键依赖、无法先进桌面再用 certmgr 导，必须走离线写 hive。见下一步 `tools/Import-K40TestCert-Offline-Admin.ps1`（待建）。
- 教训：本项目自己签的任何 **boot-start** 测试驱动，首次用前都要先把测试证书根装进设备受信任库，否则一律 winload 静默剔除 → 0x7B。
- 附：PowerShell 5.1 读无 BOM 的 .ps1 当 GBK，带中文的新脚本必须存成 UTF-8 **带 BOM**，否则解析乱码报错。

**更正（boot4 实测，2026-10-23 16:39）**：把 K40 测试证书导入手机 `SOFTWARE\...\SystemCertificates\ROOT`+`TrustedPublisher`（各 850 字节）后重启，**仍然 0x7B(0xC0000034)**；kd 复核 pep0stub 依旧不在 winload 的 BootDriverListHead、不在模块列表、PEP0 仍 DeviceNodeInitialized。即「导证书到注册表受信任根」对 winload 的 boot 驱动无效。
- 现场确认：`ci!g_CiOptions = 0x0100000e`（**bit 0x02 TESTSIGN 置位，testsigning 确实开**；HVCI 位 0x400+ 未置，HVCI 关）。引导列表里的 qcpep 是 **qcpep8280（WHQL，微软签名）**，天生过 winload，不能当"测试根有效"的证据。
- 根因修正（微软文档印证）：**boot-critical 驱动的签名由 winload 作为 Secure Boot 验证的一部分校验，这条信任链与 testsigning 分开**。testsigning 放行的是内核（Start≥1）加载的驱动；winload 对 boot 驱动走更严的链，注册表导入的测试根它读不到（winload 早期只挂 SYSTEM hive，证书库在 SOFTWARE hive）。
- 剩余可行路线：本机 Secure Boot 关（突破9），故 `nointegritychecks on`（+ testsigning on）可用——WoA 开发期跑自签 boot 驱动的成熟做法。ESP 与 WIN 在同一物理盘，Mass Storage 下用 `Get-Partition -DiskNumber <win盘>` 找到 ESP(GptType c12a7328…) 临时挂盘符即可改 BCD（见 Set-KdnetEem-Offline-Admin.ps1）。
- 待验证：设 nointegritychecks 后 pep0stub 能否进引导列表。若 nointegritychecks 也无效（新内核在某些条件下会忽略它），则放弃 boot-start 自签路线，改为给 pep0stub 寻求微软/WHQL 可信签名，或重构依赖避免 boot-start。

**boot5 实测（2026-10-23 16:54）**：ESP 的 BCD 设 `nointegritychecks on`+`testsigning on`（改前 testsigning 已是 Yes）后重启，**仍 0x7B(0xC0000034)**，pep0stub 仍不在引导列表/未加载/PEP0 仍 DeviceNodeInitialized。即 **nointegritychecks 也救不了自签 boot 驱动**（新内核多半已把它中性化）。结论：没有 BCD 开关能让 winload 放行自签 boot-critical 驱动。
- ESP 工具：`tools/Set-BootIntegrity-Offline-Admin.ps1`（手机磁盘1/ESP 分区36/954MB，临时挂盘符改 {default}，先备份）。

### 15. 关键重想：pep0stub 不必 boot-start，改 Start=1 由内核加载绕开 winload（Phase19b 计划，2026-10-23）
- 依据：phase17g-base 里 PEP0 本就是「无驱动」却能开机进桌面（突破10）→ UFS 的 `_DEP(\_SB.PEP0)` 并不要求 PEP0 有"已启动的驱动"。真正要 {55beca03} 的 qcsmmu 是 **Start=3（开机后内核加载）**。
- 0x7B 的真正触发：把 pep0stub 设 **Start=0 但 winload 加载不了其镜像**（0xC0000034），boot-start 服务加载失败才 0x7B——不是"PEP0 必须开机启动"。此前计划（Phase19a/死路16 附近）以为必须 Start=0 是误判。
- 新路线：pep0stub 设 **Start=1**。winload 不碰它（绕开 winload 签名墙）；内核 CI 认 testsigning+已导入的测试证书（qcsmmu8280 Start=3 即如此加载）；PEP0 在 winload 阶段同 phase16「无 boot 驱动」→ UFS 照常起；开机后内核加载 pep0stub→注册 {55beca03}→Start=3 的 qcsmmu 来查即命中。
- 风险/待验证：若 UFS 的 _DEP 在启动时真的等 PEP0「启动完成」，Start=1 可能仍死锁（但 phase16 无驱动能开机这条强烈反对该风险）。实测 boot6 验证。

**boot6 实测（2026-10-23 17:00）：Start=1 也 0x7B(0xC0000034)**，推翻突破15的乐观预期。修正对 0x7B 的理解：
- 因果链：0x7B 的 `0xC0000034` 指**引导设备 UFS 起不来**。UFS `_DEP` 依赖 `\_SB.PEP0`。**只要 PEP0 被分配了驱动(Service=pep0stub)但在引导设备就绪前没"启动完成"，UFS 就死等 → 0x7B**。Start=0 winload 不载自签→没启动；Start=1 内核阶段才载→比引导等待晚→也没启动。两者同死。
- phase16 能开机**仅因 PEP0 完全没分配驱动**（没有要等的东西）。所以 UFS 的 _DEP 对「PEP0 一旦有驱动就必须启动完成」是硬要求。
- 死结：pep0stub 必须引导阶段启动(Start=0+winload 加载)，而 winload 不放行自签 → 无解（在不改签名/不改 ACPI 的前提下）。

### 死路 17：给 PEP0 分配自签 pep0stub 驱动（无论 Start=0/1）都 0x7B（2026-10-23）
- 已穷尽：Start=0（winload 不载自签，boot3/4/5）、Start=1（内核加载太晚，boot6）；配合导证书到受信任根、ESP BCD testsigning on + nointegritychecks on——全部 0x7B(0xC0000034)。
- 根因：UFS `_DEP(\_SB.PEP0)` 要求「PEP0 一旦有驱动就必须在引导设备就绪前启动完成」；自签驱动无法在引导阶段被 winload 加载，Start=1 又太晚。
- 两条尚未排除的出路（下一步二选一/并行，需用户定方向）：
  1. **改 ACPI 去掉 UFS0 的 _DEP 中对 \_SB.PEP0 的依赖**（项目有重建 ACPI 能力，phase17g 等已做）。去掉后 PEP0 不必引导启动，pep0stub 可用 Start=1 由内核加载（内核 CI 认我们的测试证书），开机后再向 Start=3 的 qcsmmu 提供 {55beca03}。待核：UFS 是否真不需要 PEP0 的电源配合（phase16 无 PEP0 驱动能跑，强烈支持可去）。
  2. **先精确定位 winload 到底为何不载 pep0stub**：是签名被拒，还是 KMDF 的 Wdf01000 在引导阶段不可用（KMDF 驱动做 boot-start 需 Wdf01000 也 boot-start，非常规）。先离线查 `Services\Wdf01000\Start`；若非 boot-start，则 boot-start KMDF 本就起不来，需改写为纯 WDM 或仍走路线1。

### 16. Phase19：改 ACPI 去 UFS0→PEP0 依赖，pep0stub 走 Start=1（2026-10-23，用户选定路线1，工具已就绪待 Ubuntu 构建）
- 定位：UFS0 的 `_DEP` 只含 `\_SB_.PEP0`（alioth DSDT.asl 的 Device(UFS0) 内，源 55–58 行）。删它即可让引导设备不再等 PEP0。SDC2/ABD_ 也 _DEP PEP0 但非引导设备、不阻塞，保留不动。
- 工具（本机已验证）：
  - `tools/patch-dsdt-remove-ufs-pep-dep.py`：只删 Device(UFS0) 内引用 PEP0 的那个 _DEP，带安全校验（全文件 PEP0 引用必须恰好 -1）。用本机 `tools/acpica/iasl.exe` 对 alioth DSDT.asl 实测：删前/删后编译错误集逐条一致（9 条全是反编译残留，构建本就 `iasl -f` 容忍），零新增错误，AML 字节差 12。
  - `tools/build-acpi-hid-phase19.sh`：基于 17f-base（Phase16 DSDT + 修复版 Kona DBG2），编译前插入上面补丁，产出 `Mu-alioth-1-acpi-hid-phase19-noufsdep-dbg2-*.img`。**在 Ubuntu 构建机跑**。
- 手机侧前置（已就位）：pep0stub Start=1、PEP0 Enum 已分配 pep0stub、测试证书已导入受信任根、ESP BCD testsigning+nointegritychecks on。
- 待验证（boot7，新镜像）：UFS 能否越过 0x7B 进桌面；内核是否加载 pep0stub（lm m pep0stub）、PEP0 是否 Started、`pep0stub: RegisterResources`、MMU1 是否脱离 Code 31。
- 若仍失败的回退判断：若进桌面但 pep0stub 没加载→查内核 CI 是否认证书（事件 CodeIntegrity）；若 pep0stub 加载但 qcsmmu 仍 Code31→回到接口语义（Size/Version/RegisterResources 是否被调）。
