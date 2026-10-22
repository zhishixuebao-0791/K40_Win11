# Phase17h-2：qcpep8280 实测结果（2026-10-22）

## 前提
- 手机离线把 `Services\qcpep\ImagePath` 改为 `qcpep.wd8280.inf_arm64_bd3744d48a04c516\qcpep8280.sys`（`tools/Set-Qcpep8280ImagePath-Offline-Admin.ps1`）。
- `fastboot boot` `Mu-alioth-1-acpi-hid-phase17h-pep8280-dbg2-20261022-164416.img`（PEP0 = QCOM0617，17e-all DSDT，修复版 DBG2）。
- kd 日志：`logs/kd-phase17h2-20261022-173014/kd.log`。

## 结果
- kd 确认：**加载的是 qcpep8280**（`lm m qcpep*` → `qcpep8280`），首测加载错驱动的问题已排除。
- 开机能进用户态（IPC Router / QMI / DispBroker 输出与首测相同），之后约 2 分钟出现 **BugCheck 0x101 CLOCK_WATCHDOG_TIMEOUT**（0x18, 0, PRCB, **CPU6**），桶为 `CLOCK_WATCHDOG_TIMEOUT_INTERRUPTS_DISABLED`。
- 现场：
  - CPU0/2/4/5/7 都在 `KiIpiSendRequestToAwakeProcessors → KiIpiWaitForRequestBarrier`，等 CPU6 应答 IPI（TLB 刷新）。
  - CPU6：PnP 工作线程（`PnpDeviceActionWorker → PiRestartDevice → PnpCallAddDevice → Wdf01000!FxDriver::AddDevice`）正在执行 **qcpep8280 的 AddDevice**，期间长时间不响应中断。冻结 IPI 直到 `KeReleaseSpinLock → KfLowerIrql` 时才通过 `KiPlayInterrupt` 补处理。
  - CPU6 调用链（帧指针链，RVA 用 `.pdata` 定位到函数）：

| 层 | 函数起止 (RVA) | 返回地址 |
|---|---|---|
| AddDevice 主体 | `0x27afb0`–`0x2801b8` | `0x27f694` |
| | `0x239d20`–`0x23a36c` | `0x239d9c` |
| | `0x2b8bc0`–`0x2b9018` | `0x2b8efc` |
| | `0x140b18`–`0x140e0c` | `0x140d30` |
| | `0x23a08`–`0x23a6c` | `0x23a58` |
| | `0x338b0`–`0x33924`（WdfInterruptCreate 包装） | `0x33910` |
| | `Wdf01000!imp_WdfInterruptCreate → FxInterrupt::_CreateAndInit → FxObject::Commit → AssignParentObject → KeReleaseSpinLock` | |

- `!ppm`：Idle States (0)，"Perf/throttle states not registered"，PPM 尚未由 PEP 注册。
- 与首测（实际跑的是 qcpep8250）对比：首测也是 0x101，挂住的是 CPU5，栈形态相同（KiIpiServiceRoutine 后接池地址）。**两个版本的 qcpep 都在 PEP0 AddDevice 期间让某个核长时间屏蔽中断**。

## 尚未确定
- 冻结点只是 CPU6 第一次重新打开中断的位置，**长时间屏蔽中断的真实位置在它之前**（AddDevice `0x27afb0` 中 `0x27f690` 调用之前的某处，或这条调用链里先前已返回的兄弟调用）。不能凭这次现场下结论。

## 下一步（精确定位）
- 在 kd 中用延迟断点 `bu` 给 AddDevice 主体和链上各函数入口加带时间戳的日志断点（命中后自动 `g`），重新开机复现，按最后一个命中点和时间间隔来二分屏蔽中断的位置。

## 第二、三轮复现（17:49、17:57）
- 日志断点时间线：AddDevice 进入 → `0x239d20` → `0x2b8bc0` → `0x140b18` → 连续 4 次 `0x338b0`（中断创建包装，调用者 `0x140d18`），约 0.3 秒内完成，**第 4 次之后 CPU6 停止响应 → 0x101**。`AddDevice_after_239d20` 从未命中。两次结果一致。
- 4 次调用的 `x3`（输出句柄槽）分别是 `.data` 中的 `0x228280 / 0x228288 / 0x2283a8 / 0x2283b0`，即连续创建 4 个 WDFINTERRUPT，第 4 个创建过程中挂住。冻结点每次都在第 4 次 `WdfInterruptCreate → FxInterrupt::_CreateAndInit → FxObject::Commit → AssignParentObject → KeReleaseSpinLock → KfLowerIrql`。
- WDF IFR 日志（`!wdfkd.wdflogdump qcpep8280.sys`）只有 7 条 DMF 上下文记录，没有线索。
- kd 操作要点：`bu addr N` 是放过 N 次、第 N+1 次才停；**蓝屏后要等手机重启后再发 `g`**，否则 kd 会卡住无法重连，只能重启桥接。

## 第四轮（18:00，kd-phase17h4）：根因定位 —— qcpep8280 写死 SC8280XP 的 4 个 TSENS 控制器
- 计数断点在第 4 次 `0x338b0` 停下，`p` 越过 `WdfInterruptCreate` 正常返回（STATUS_SUCCESS），`gu` 回到 `0x140d18` 后再 `gu` → 0x101。卡在 `0x140b18` 的外层循环第 3 轮。
- `0x140b18`：外层遍历 TSENS 实例（全局 `[+0x2301c0]`=RVA 0x228170，每实例 0x128 字节，`+0x100/+0x108` 为映射后的 SROT/TM 基址），先用 `0x1326f8`(MMIO 读32)/`0x132710`(MMIO 写32) 配置中断掩码与阈值，再为每个实例创建 2 个 WDFINTERRUPT。
- 现场 `!vtop` 得到的 4 个实例物理地址：
  - 0：`0x0c222000 / 0x0c263000`；1：`0x0c223000 / 0x0c265000`（**SM8250 有**）
  - 2：`0x0c224000 / 0x0c251000`；3：`0x0c225000 / 0x0c252000`（**SM8250 没有**，SC8280XP 独有的 tsens2/3）
- 地址表写死在 `.rdata` RVA `0x1a6a70`（`{0x1000, PA}` × 8），配置结构 RVA `0x1a6b10` = `{&地址表, &传感器映射 0x1a6ab0, 控制器数 4, 0x2e, …}`，由 `0x2b8bc0`（`0x2b8d28`）无条件选用，没有多套配置。
- 唯一的跳过条件：`0x2b8c70` 读字节 `[RVA 0x230171]`，等于 1 时直接返回 0（这是"已初始化"标志，只有 `0x2b8f14` 写入），**没有注册表/ACPI 开关**。
- `.rdata/.data` 中没有其他 `{大小, 物理地址}` 形式的寄存器表。
- 结论：与 qcpep8250 写 SM8150 LMH 同类问题。qcpep8280 在 SM8250 上不改驱动无法通过 AddDevice。
- 可选修补点：① `0x2b8c78` 的 `b.ne` 改为 NOP，整个 TSENS 初始化跳过（0x230171 保持 0，其余 7 处读取者视为未初始化）；② RVA `0x1a6b20` 的控制器数 4→2，保留 tsens0/1（需先核对传感器映射表 0x1a6ab0 是否引用控制器 2/3）。

## 方案①未能实施 / 社区方案核查（2026-10-22 18:20）
- 用户选择方案①（跳过 TSENS 初始化），但由我准备驱动修补和重新签名的脚本时，回复被安全检查拦截（与之前修补 qcpep8250 时的情况相同）。在当前工具环境下，由我来修补驱动二进制这条路走不通。
- 社区核查：WOA-Project `windows_silicon_qcom_kona` 中的 `qcpep8250.sys` 与本地副本 git 哈希相同（63b9c3b8…），就是会写 SM8150 LMH 的版本；`qcpepextension8250.inf` 只为 `DEV_2519` 添加 PPM 软件组件（`VID_QCOM&PID_0519&SID_0001`），没有行为参数。Silicium Kona DSDT 的 PEP0 是 `QCOM0519`（不匹配任何 INF），推断社区 SM8250 方案本来就不加载 qcpep。
- 现有两个官方 qcpep（8250=实为 8180 版、8280）在 SM8250 上都会访问不存在的硬件，不改驱动都无法通过 AddDevice。

## 方向1：qcsmmu8280 如何使用 PEP 接口，以及 qcpep8280 的"桩 PEP"开关（2026-10-22 18:40，突破）
- qcsmmu8280 `sub_12370`：`sub_116a8` 通过 `{55beca03}` 找到 PEP 设备 → `0x3e9a8` 建立 WDFIOTARGET（打开已有设备）→ `0x3ec30` 用 **QueryInterface** 向 PEP 要接口 **`{a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}`**（大小 0x28，版本 1，即 INTERFACE 头 + 1 个函数），拷贝到设备上下文 `+0x2510`。另一个可选 GUID `{99f8bbdb-5b65-444b-adbe-5b87efedd76c}` 大小 0x38。
- qcpep8280 提供方（`0x46c68`）：`WdfDeviceAddQueryInterface`，接口 = {Size 0x28, Ver 1, Context NULL, Ref/Deref = 空函数 `0x451e0`, 功能函数 `0x20230`}。
- `0x20230(arg)`：IRQL>0 → 0xC0000022；**全局 `0x223f74` 非 0 → 直接返回 0**；否则 `0x2478d0(arg, &0x223ba8, 1,1,0,0)`（按名字找设备节点下发电源请求，含 "DEVICE" 字符串）。
- `0x223f74` = 注册表特性 0x58 = **`Services\qcpep\Parameters\EnableStubbedPepForPresilicon`**（REG_DWORD，默认 0），在 AddDevice `0x27cb20`（`0xfb790` 特性查询，缓存表 RVA 0x1c4cf0）读取，早于 `0x27f690` 调 `0x239d20`。
- **`0x239d20` 开头检查同一标志，非 0 时直接返回成功，跳过 `0x2b8bc0`（TSENS 初始化，即卡死点）**。共有 ~15 个函数读取该标志。
- qcpep8250 中没有这个值名，只有 8280 有。
- 下一步：离线写 `EnableStubbedPepForPresilicon=1`（`tools/Set-QcpepStubbedPresilicon-Offline-Admin.ps1`），ImagePath 保持 8280，kd 监听 + fastboot boot phase17h，观察 AddDevice 是否完成、PEP0 状态、`{55beca03}` 是否注册、MMU0/MMU1 状态。注意桩模式下 PEP 不做真实电源管理（qcsmmu/qcsubsys 目前 Start=4，验证 PEP 后再逐个恢复）。

## Phase17i 首测（18:25，kd-phase17i）：桩开关被 INF 覆盖
- 离线写入 `EnableStubbedPepForPresilicon=1` 后开机，`0x239d84` 读到 w8=0，TSENS 初始化照常执行 → 0x101。
- kd `!reg`：`ControlSet001\Services\qcpep\Parameters\EnableStubbedPepForPresilicon = 0`。原因：`qcpep.wd8280.inf` 第 195 行 `HKR,Parameters,EnableStubbedPepForPresilicon,0x00010001,0x0`，PEP0 每次（重新）安装都会执行这段 AddReg，把离线写的 1 覆盖为 0，然后才调用 AddDevice。
- 本次开机 PEP0（`ACPI\QCOM0617\2&daba3ff&0`）内存中已显示安装完成：ConfigFlags=0、Driver=`{4d36e97d-e325-11ce-bfc1-08002be10318}\0039`、Service=qcpep、oem21.inf。若这一状态已落盘，再次离线写 1 即可保留（安装完成后不再执行 AddReg）。
- 教训：通过注册表改驱动参数时，要先看 INF 的 AddReg 是否会在安装时覆盖同名值。

## Phase17i 第二次（18:34，kd-phase17i2）
- 磁盘上该值仍为 1，但 Enum\ACPI\QCOM0617 不存在（上次的安装记录因蓝屏未落盘），本次开机首次安装又把值覆盖为 0。
- 用 kd 在 0x27cb2c 把内存标志 0x223f74 置 1（仅本次开机）：0x239d84 读到 1，TSENS 初始化未执行，0x239d20 返回 0 → TSENS 卡死被绕过。
- PEP0 走过 AddDevice / PrepareHardware / D0Entry，在 SelfManagedIoInit（qcpep8280+0x2ab624 回调）中出现 BugCheck 0x10D WDF_VIOLATION（参数1=5，句柄为 NULL）：0x72550 使用全局自旋锁句柄 [0x2243a0]，该句柄为空。
- 本会话中对这一路径的进一步分析被安全检查中断，未继续。

## 方向1 结论：qcsmmu8280 对两个 PEP 接口的使用（2026-10-22 19:00）
- `{a0e1dd36}`：AddDevice（0x3690）在 0x3f74 同步调用 0x12370 查询，失败 → 消息 0x22 → AddDevice 返回 0xC0000001。
- `{99f8bbdb}`（大小 0x38，3 个函数）：0x3e600 用 IoRegisterPlugPlayNotification 监听 `{55beca03}` 接口到达，回调 0x3eed0 再打开 PEP 设备查询。异步路径，PEP 不出现时只是不触发。两个接口都只由 PEP 提供（qcpep8280 0x46c68 / 0x4682c、0x469f4）。
- **跳过条件**：0x12370 只在两个字节都为 0 时调用：① `[[0x61380]+0x7c]`（多实例只做一次的已完成标志，成功后由 0x2a200 置位）；② 驱动上下文偏移 0 的字节 = DriverEntry 中 0x2aa0 的结果：`IoGetIommuInterface` 成功且 CreateDomain/DeleteDomain 正常时为 1（"Windows 内核 IOMMU 可用"）。
- 即：**内核 IOMMU 可用时，qcsmmu8280 的 AddDevice 不向 PEP 要接口**。内核 IOMMU 依赖 ACPI IORT；alioth 的 ACPI.inc 注释掉了 Kona/IORT.aml，Silicium-ACPI 中没有 Kona 的 IORT（有 Hana/Kailua/Kodiak/Moorea/Napali/Rennell），网上也未找到现成的 Kona IORT。
- Phase16d 时把 IORT 怀疑"放下"的结论需要修正：IORT 不是当时失败点，但它决定了 SMMU 是否依赖 PEP。
- 本会话中准备解析 Hana IORT 结构时被安全检查中断，未继续。

## Phase17j（18:52，kd-phase17j）：kd 证实内核 IOMMU 不可用、ACPI 中没有 IORT
- 条件：phase17g-base 镜像（Phase16 + DBG2，PEP0=0519 不绑定），离线把 qcsmmu Start 4→3（tools/Set-ServiceStart-Offline-Admin.ps1）。
- qcsmmu8280 DriverEntry → 0x2aa0：`MmGetSystemRoutineAddress("IoGetIommuInterface")` = `nt!IoGetIommuInterface`（存在）；**`IoGetIommuInterface(1, &iface)` 返回 0xC00000BB（STATUS_NOT_SUPPORTED）**；CreateDomain 与标志置 1 的断点都未命中 → 驱动上下文"内核 IOMMU 可用"标志 = 0 → AddDevice 走向 PEP 要 {a0e1dd36} 的分支。
- `!acpicache`：XSDT、FACP、APIC、PPTT、GTDT、DBG2、SSDT、BGRT、DSDT（SDM8250）—— **没有 IORT**。
- 结论：要让 qcsmmu8280 不依赖 PEP，前提是提供一张正确的 Kona IORT，使内核 IOMMU 初始化成功（是否足够，还要看内核对 Qualcomm SMMU-500 的支持，以及 CreateDomain/DeleteDomain 能否成功）。
- 手机当前状态：qcsmmu Start=3、ImagePath=qcsmmu8280；qcpep ImagePath=qcpep8280，Parameters\EnableStubbedPepForPresilicon=1；qcsubsys Start=4。
