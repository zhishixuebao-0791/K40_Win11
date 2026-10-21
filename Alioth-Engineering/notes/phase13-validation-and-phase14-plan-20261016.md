# Phase13 验证结果与 Phase14 计划 - 2026-10-16

## 输入

- `logs\AcpiPhase3State_20260513_201040`
- `logs\AudioDependencyState_20260513_201610`
- `logs\QcsubsysAcpiShape_20260513_202401`
- Phase13 apply 日志：`logs\apply-qcsubsys-phase13-adsp-registry-shape-20260513-185922.log`
- 注意：手机 Windows 的系统时钟停在 2026-05-13（没有 RTC 同步），所以日志目录名和事件时间戳不能当真实时间用。这三份日志确实是 Phase13 补丁之后开机采集的。区分是哪次开机，要看事件日志里每次开机的 CI 策略加载记录（这次开机显示为 05-13 20:03），不能看日期。

## Phase13 结果：失败（故障特征未变）

| 设备 | 结果 |
| --- | --- |
| QCOM0620 SSDD / QCOM06E0 PILC / QCOM2533 RPEN | 仍 OK |
| QCOM061B ADSP / QCOM06B0 CDSP / QCOM061F SCSS | 仍 Code 31，`0xC0000034` (STATUS_OBJECT_NAME_NOT_FOUND) |
| QCOM068D SPSS | 仍 Code 31，`0xC000003B` |
| QCOM0532 CDI / QCOM0520 QSM | 仍 Code 28 |

开机后 `Enum\ACPI\QCOM061B\2&daba3ff&0` 的状态：

- 保留：`Device Parameters\PDInfo\NumPDs=1`、`PDInfo\0\GUID`、`Device Parameters\0\ADSP\Interfaces`、`0\ADSP\Interfaces`
- 消失：`PDInfo\0\PDName`、两处 `RPEC`（未查明是谁删除，见“未决问题”）
- `DEVPKEY_Device_ConfigurationId = oem15.inf:ACPI\QCOM061B,SUBSYS_Device_ADSP.NT`，**没有任何扩展 INF**
- 设备栈只有 `\Driver\ACPI`

## 根因定位（本次关键结论）

1. **8280 驱动是“基础 INF + 扩展 INF”架构。** `qcsubsys8280.inf` 的 `[SUBSYSReg]` 是空的，ADSP 硬件键只写 `PDInfo\NumPDs=0`。每个子系统真正的运行参数来自扩展 INF：
   - ADSP：`surfacepro_ext_adsp8280.inf`（匹配 `ACPI\VEN_QCOM&DEV_061B&SUBSYS_MTP08280`，与手机 HardwareID **完全一致**），但从未安装到手机上。
   - CDSP：`qcsubsys_ext_cdsp18280.inf` / `surfaceproextcdsp8280`；SPSS：`qcsubsys_ext_spss8280.inf`。
2. **参数位置写错了。** 扩展 INF 中 `[SUBSYSReg]` 被 `SUBSYS_Device_ADSP_ext.NT`（不是 `.NT.HW`）引用，`HKR` 指向**驱动软件键** `Control\Class\{4d36e97d-e325-11ce-bfc1-08002be10318}\0036`：
   ```
   HKR,ADSP,"ImagePath",REG_SZ,"%13%\qcadsp8280.mbn"     <- 固件路径
   HKR,ADSP,"RPEC",REG_MULTI_SZ,{99CA9C16-4E1E-4970-B49E-2CA56753588B}
   HKR,ADSP,"Interfaces",REG_MULTI_SZ,PIL_TZ,FASTRPC,GLINK
   HKR,ADSP,"MANU",REG_DWORD,0x06be0baf
   HKR,ADSP,"IgnoreWdogEnabled"/"SubsysUefiLoadedImageAction"=2/"UefiLoadedImageTZProcID"=0x1F/...
   ```
   Phase12（ACPI `_DSD`）和 Phase13（Enum 硬件键）都没有写到这个位置。缺少 `ImagePath` 时驱动打开固件失败，正好对应 `0xC0000034 = STATUS_OBJECT_NAME_NOT_FOUND`。
3. **值名也写错了。** 用 `qcsubsys8280.sys` 的 UTF-16 字符串核对，驱动读取的是 `ImagePath`、`serviceName`、`RPEC`、`Interfaces`、`MANU`、`PDInfo`、`NumPDs`、`Desktop`、`DeviceObjectName`、`SubsysUefiLoadedImageAction`、`UefiLoadedImageTZProcID`、`UefiLoadedSubsysDetectionStatus`。**里面没有 `PDName`**。8280 的 PDInfo 应写成 `PDInfo\N\ServiceName`，`PDName` 是 8250 驱动的写法。
4. **固件不能直接用 Surface 或高通参考版本。** `qcadsp8280.mbn` 属于 SC8280XP（makena）；Kona 包里的 `qcadsp8250.mbn` 是高通 MTP 参考签名版本。alioth 是量产机，TZ 按小米 OEM 签名验签，必须用手机自己 modem 分区里的 `image\adsp.mdt` 加 `adsp.bXX`，经 pil-squasher 合并成单个 mbn。旁证：本地 `WOA-Drivers-main\components\SDM845\Device\<厂商>\` 每个厂商都单独带一份 `qcadsp850.mbn`。
5. 待确认：PILC 硬件键里的 `SubsystemLoad\ADSP\MemoryAlignment=0x100000` / `MemoryReservation`（8280 为 0x2000000，8250 为 0x1a00000）是否已经由 qcpilEXT8280 写入。

## Phase14 计划（每一步都先确认证据，再做下一步）

### 步骤A：只读取证（Mass Storage 模式，不修改手机）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Export-QcsubsysPhase14Evidence-Admin.ps1 -WindowsDrive E
```

- 导出 ADSP/CDSP/SCSS/SPSS/SSDD/PILC/PDSR 的 Enum 键和 Control\Class 软件键，摘要里直接列出 `ADSP\ImagePath` 是否缺失。
- 自动查找 modem 分区（FAT 格式），只读复制 `image\adsp.*`、`cdsp.*`、`slpi.*`，并记录 SHA256。

判定条件：只有确认软件键里 `ADSP\ImagePath` 缺失、且 modem 固件成功取出，才进入步骤B。

### 步骤B：合并固件

- 用 pil-squasher（linux-msm/pil-squasher，C 写的小工具，可以在 WSL/Ubuntu 里编译）把 `adsp.mdt` 加 `adsp.bXX` 合并成 `qcadsp_alioth.mbn`。需要先征得用户同意再下载。
- 校验：输出是 ELF，program header 数量与 mdt 一致，文件大小合理（约 10~20MB）。

### 步骤C：按 8280 格式离线写入软件键（只改 ADSP，要有备份和回滚）

- 把 `qcadsp_alioth.mbn` 复制到手机 Windows 的固定路径（例如 `\Windows\System32\DriverStore\alioth\ADSP\`）。
- 在 `Control\Class\{4d36e97d...}\<ADSP 的 Driver 序号>\ADSP` 下写入 `ImagePath`、`RPEC`、`Interfaces`、`MANU`、`IgnoreWdogEnabled`、`SubsysUefiLoadedImageAction`、`UefiLoadedImageTZProcID`、`UefiLoadedSubsysDetectionStatus`、`SpuAriFuseWorkAroundEnabled`。软件键根下写 `WaitForVolStartupAppComplete=1` 和 `Mappings\PathMappingKeyName=Default`。
- 硬件键的 PDInfo 改成 8280 格式（`ServiceName` 代替 `PDName`），`NumPDs` 先设为 1（只放 audio_pd）。
- 第一轮**不加** `Desktop` 子设备（Slimbus/ADCM），也不加 FastRPC 的 so 文件映射。
- 开机后跑三个诊断脚本，看 `0xC0000034` 有没有变化。

### 分支判定

- 状态码变成其他值（例如 TZ 验签失败或 PIL 报错）：说明 `ImagePath` 方向正确，继续排查固件或 PIL 内存配置。
- ADSP 启动成功：按同样方法处理 CDSP（`qccdsp`）和 SCSS（`slpi`），然后测试 `Desktop` 子设备。
- 仍是 `0xC0000034`：用 Procmon 开机日志或 WPP 查看驱动实际打开的注册表路径和文件路径，不再猜测。

## 步骤A 实测结果（`logs\QcsubsysPhase14Evidence_20261016-190042`）

Mass Storage 模式下手机 WIN 分区这次被分到 D:。盘符每次可能不同，运行前要先确认。

1. **已确认：驱动软件键缺少全部 8280 扩展参数。** `Class\{4d36e97d...}\0036`（ADSP）只有 INF 安装时写的基本值（DriverDesc/InfPath=oem15.inf/InfSection=SUBSYS_Device_ADSP.NT/MatchingDeviceId），**没有 `ADSP` 子键，没有 `ImagePath`、`RPEC`、`Interfaces`、`MANU`，也没有 `Mappings`、`WaitForVolStartupAppComplete`**。0035（CDSP）、0034（SCSS）、0033（SPSS）同样缺失。
2. **新发现：PILC 也没有为 ADSP 预留内存。** `Enum\ACPI\QCOM06E0\...\Device Parameters\SubsystemLoad` 下只有 `GFXSUC` 和 `VENUS`，**没有 `SubsystemLoad\ADSP`**。扩展 INF 的 `PIL_Device_Ext` 本应写入 `MemoryAlignment=0x100000`、`MemoryReservation=0x2000000`（8280）或 `0x1a00000`（8250）。步骤C 要一起补上。
3. qcsubsys 服务的 `Parameters` 正常（`ADSPRestartEnabled=1` 等）。
4. modem 分区：Mass Storage 只暴露 UFS LUN0（37 个分区），LUN0 上没有 modem 分区。固件改为用 TWRP 加 adb 提取。
5. 脚本缺陷（已修复）：变量持有离线 hive 键对象，导致 `reg unload` 报“拒绝访问”，hive 残留加载。修复方法：卸载前 `Remove-Variable`；日志统一写 UTF-8。

## 步骤B 结果：alioth 自签名固件已提取并合并（2026-10-16）

- 提取方法：`fastboot boot` 临时启动 TWRP 12（不刷写）→ 当前槽位 `_b` → `modem_b` = `/dev/block/sde30`，在 TWRP 中只读挂载 vfat → `adb pull image\{adsp,cdsp,slpi}.*`，完成后卸载。
- 原始文件：`components\Devices\Alioth\firmware-raw\modem_b\`，共 58 个，大小和 SHA256 与手机逐个一致（清单见 `firmware-raw\remote_manifest.txt`）。
- 合并工具：`tools\pil_squasher.py`（linux-msm/pil-squasher commit 3c9f8b8 的 Python 移植；本机没有 WSL 和 C 编译器；段文件缺失时直接报错）。
- 合并结果：`components\Devices\Alioth\firmware-squashed\`（SHA256 见 `SHA256SUMS.txt`）
  - `qcadsp_alioth.mbn` 21,094,524 字节，ELF32，20 段；19 个非空段与 `.bXX` 逐字节一致，hash 段取自 mdt（mdt = b00+b01）。
  - `qccdsp_alioth.mbn` 5,818,132 字节；`qcslpi_alioth.mbn` 7,869,796 字节。
- ADSP 镜像末段结束于 0x141e07c（约 20.1MB），小于 PIL 预留 0x2000000。
- alioth 的 `adspua.jsn`/`adspr.jsn` 只有 `root_pd` 和 `audio_pd`，**没有 Surface 的 `charger_pd`**，所以 PDInfo 只写 audio_pd（NumPDs=1）。
- 操作坑：Git Bash 会把以 `/` 开头的 adb 远端路径转成 Windows 路径，需要设置 `MSYS_NO_PATHCONV=1`；本地目标路径用正斜杠 `C:/...`。TWRP 下 USB 中途复位过一次（transport_id 变化），所以拉取完必须按清单做哈希校验。

## 步骤C 已准备（待执行）

- `tools\Apply-QcsubsysPhase14AdspSoftwareKey-Admin.ps1 -WindowsDrive <手机WIN盘符>`
- `tools\Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1 -WindowsDrive <盘符> -BackupDir <备份目录>`
- 写入内容：固件复制到手机 `\Windows\System32\Drivers\Alioth\ADSP\qcadsp_alioth.mbn`；软件键 `ADSP\ImagePath/RPEC/Interfaces/MANU/IgnoreWdogEnabled/SubsysUefiLoadedImageAction=2/UefiLoadedImageTZProcID=0x1F/UefiLoadedSubsysDetectionStatus=0/SpuAriFuseWorkAroundEnabled=1`；硬件键 `PDInfo`（ServiceName 形态，1 项）和 `Mappings\PathMappingKeyName`；PILC 的 `SubsystemLoad\ADSP` 写 Alignment=0x100000、Reservation=0x2000000；同时清理 Phase13 残留。
- 第一轮刻意不写：`Desktop` 子设备、FastRPC so 映射、`WaitForVolStartupAppComplete`（可能等待一个不存在的启动程序）、`Resources\BinaryPath`（RADS.bin 属于 8280 资源描述）。
- 8280 专有、需要重点怀疑的值：`SubsysUefiLoadedImageAction`、`UefiLoadedImageTZProcID`、`SpuAriFuseWorkAroundEnabled`。如果故障特征变成 TZ/SCM 相关错误，先调整这三个值。

## 步骤C 执行记录（2026-10-16 19:30，手机 WIN=D:）

- 固件复制和全部注册表值写入成功。hive 卸载前已直接读回核对：ADSP 软件键 9 个值、PDInfo（ServiceName 形态）、Mappings、PILC 两处 SubsystemLoad\ADSP 都正确；Phase13 的 `0\ADSP\Interfaces` 已删除（剩下空键）。
- 脚本缺陷：PS 5.1 对含 pscustomobject 的 `List[object]` 执行 `@()` 时会抛“参数类型不匹配”，导致 manifest 没写出、hive 没卸载。已修复（改用 `ToArray()`；清单写入失败也一定卸载 hive）。
- 本次的 `manifest.json` 是根据写入前的离线取证（`QcsubsysPhase14Evidence_20261016-190042`）和 apply 日志重建的，回滚脚本可以正常使用。

## Phase14 验证结果（开机日志 `*_20261016_194051/194656/195422`）：重大进展

| 设备 | Phase13 | Phase14 |
| --- | --- | --- |
| ADSP QCOM061B | `0xC0000034` | **`0xC000003B` STATUS_OBJECT_PATH_SYNTAX_BAD** |
| CDSP / SCSS（未改动，对照） | `0xC0000034` | `0xC0000034` |
| SPSS（未改动） | `0xC000003B` | `0xC000003B` |

- 只有被修改的 ADSP 状态码变了，补软件键的方向得到证实。开机后写入的 PDInfo（ServiceName 形态）和 Mappings 全部保留，没有被驱动删除。
- 新故障点分析：SPSS 的 8280 扩展 INF 根本没有 `ImagePath`，却和 ADSP 报同一个 `0xC000003B`；两者的共同缺项是 `.NT.HW` 下的 `Resources\BinaryPath`（ADSP 对应 RADS.bin，SPSS 对应 RSPU.bin）。`qcsubsys8280.sys` 里 `\DosDevices\`、`BinaryPath`、`Resources` 三个 UTF-16 字符串相邻（0x52388~0x523c0），附近还有一个 `INVALID PATH` 占位串；内核打开不以 `\` 开头的路径时，返回的正是 `STATUS_OBJECT_PATH_SYNTAX_BAD`。
- RADS.bin 是 **AeoB 格式的 PEP 电源资源描述**（`DEVICE \_SB.ADSP` → COMPONENT/FSTATE/PSTATE → NPARESOURCE `/arc/client/rail_cx|mx|xo|lpicx|lpimx` 加总线 `ICBID_MASTER_LPASS_PROC/ICBID_SLAVE_EBI1/ICBID_SLAVE_CLK_CTL`）。qcsubsys 要先向 PEP 投票给 DSP 上电，才会去加载固件。
- 8250 对照：Kona 包为 CDSP 提供 `RCDS.bin`、为 SCSS 提供 `RSCS.bin`，但 Audio 扩展里没有 RADS.bin；`qcsubsys8250.sys` 中的 `AeoB` 只是解析代码里的常量，没有内嵌资源。alioth 的 DSDT 里也没有 `\_SB.ADSP` 根节点的 PEP 资源包。
- `qcpep8250.sys` 能找到 `/arc/client/rail_cx|mx|xo|mmcx` 和这三个 ICBID，**但找不到 `rail_lpicx/rail_lpimx` 字符串**（只有 `lcx.lvl`/`lmx.lvl`，外加一个动态拼接用的 `/arc/client/` 前缀）。所以 Surface 的 RADS.bin 在 8250 上很可能卡在 LPI 电源轨上。

## Phase15A 计划：区分实验

- 脚本：`tools\Apply-QcsubsysPhase15aAdspResources-Admin.ps1 -WindowsDrive <盘符>`（回滚复用 Phase14 的通用回滚脚本，指定本次的 BackupDir）。
- 内容：只给 ADSP 写 `Device Parameters\Resources\BinaryPath = C:\Windows\System32\Drivers\Alioth\ADSP\RADS.bin`，先原样使用 Surface 的 RADS.bin。
- 判定：
  - 不再是 `0xC000003B` → 证实是 BinaryPath 缺失；新错误码就是下一个卡点（预计是 LPI 电源轨），然后参照 8250 的 RCDS.bin 结构为 alioth 改一份 RADS.bin（去掉或替换 lpicx/lpimx）。
  - 仍是 `0xC000003B` → 排除 BinaryPath，转查 `ImagePath` 路径格式（试 `\SystemRoot\...` 或 `\??\C:\...`）。

## Phase15A 验证结果（2026-10-17，日志 `*_20261017_095834/100424/101125`）：状态码未变

- 写入日志 `apply-qcsubsys-phase15a-adsp-resources-20261017-095239.log` 成功（manifest 正常、hive 第 1 次就卸载成功）。`...095127.log` 是第一次尝试，在加载 hive 之前就中止了，没有写入任何值。
- 开机后 `Device Parameters\Resources\BinaryPath` 保留；手机上 `\Windows\System32\Drivers\Alioth\ADSP\` 中有 `RADS.bin`（1976 字节）和 `qcadsp_alioth.mbn`。
- ADSP 仍是 `0xC000003B`，SPSS 仍是 `0xC000003B`，CDSP/SCSS 仍是 `0xC0000034`。
- 结论：**单独补 BinaryPath 不能消除 0xC000003B**，所以“缺 BinaryPath 是唯一原因”被排除（BinaryPath 现在保留不动）。
- 静态扫描 `qcsubsys8280.sys`：没有 MOVZ/MOVK 构造 0xC000003B，也没有该字面常量；`0xC0000034` 有 12 处字面常量。说明 **0xC000003B 不是驱动自己生成的，而是某个内核 API（打开文件/注册表/符号链接等）收到格式不对的路径后返回的**，驱动只是透传。
- 驱动里同时内置了 `C:\Windows\System32\qcdsp1v2.MBN`（DOS 形式）和 `\SystemRoot\system32\qccdsp.mbn` 两种默认路径，说明它能处理 DOS 路径，所以 ImagePath 写成 `C:\...` 的嫌疑降低。
- 下一步不能再逐项猜测，需要精确定位是哪个 API 拿到了哪条路径：
  1. 静态：用 capstone 反汇编 qcsubsys8280.sys，找到 ZwCreateFile/ZwOpenFile/ZwOpenKey/IoCreateSymbolicLink/RtlInitUnicodeString 等导入调用点，以及喂给它们的字符串/注册表值来源（PC 上就能做，不用折腾手机）。
  2. 动态：在手机上用 Sysinternals Procmon（ARM64）开启开机日志，记录 qcsubsys 启动 ADSP 时实际查询的注册表值和打开的文件，以及每一步的结果。

## Phase15B：Procmon 开机日志（动态取证，2026-10-17 准备）

- 工具：Sysinternals Process Monitor 4.12（`Procmon64a.exe`，ARM64，Microsoft 签名有效），已复制到手机 `C:\Code\REDMIK40_Win11\`。
- 手机端脚本：`tools\Collect-ProcmonBootLog-OnPhone.ps1`（`-Mode Enable` 开启开机日志 → 重启 → `-Mode Collect` 保存 boot.pml 和本次 ADSP 状态）。
- 电脑端：用 Procmon64.exe 打开 PML，按 Path 含 `QCOM061B`、`0036`、`Alioth\ADSP`、`qcsubsys` 筛选，查看注册表查询结果（NAME NOT FOUND）以及失败前最后的操作。
- 局限：如果路径在进入文件系统之前就被对象管理器判定为语法错误，Procmon 看不到那次打开文件的操作；但能看到驱动查询了哪些注册表值、哪些值不存在。

## Phase15B 结果：Procmon 开机日志精确定位到根因（2026-10-17）

日志：`logs\ProcmonBoot_20261017_103821\`（boot.pml 1.58GB → `/NoFilter` 导出 boot_all.csv 共 337 万条 → `tools\filter_procmon_csv.py` 筛选到 `filtered\`）。注意：Procmon 默认过滤规则会排除 System 进程，导出时必须加 `/NoFilter`。

qcsubsys 处理 ADSP 的实际顺序（System 进程，10:34:36.47xx）：
1. 读硬件键 PDInfo（NumPDs/GUID/serviceName/FileNameWildCard/RootDirectory/CountFile）→ 全部 SUCCESS
2. 读软件键 `0036\ADSP\ImagePath` → SUCCESS
3. 读 SpuAriFuseWorkAroundEnabled/IgnoreWdogEnabled/SubsysUefiLoadedImageAction/UefiLoadedImageTZProcID/UefiLoadedSubsysDetectionStatus → SUCCESS；WaitForVolStartupAppComplete、IsBugCheckEnabled、SubsysErrorHandlingPolicy、`Services\qcsubsys\Parameters\AdspLicensePath` → NAME NOT FOUND（取默认值，继续执行）
4. **以 Read Attributes 打开 `C:\Windows\System32\drivers\Alioth\ADSP\qcadsp_alioth.mbn` → SUCCESS**（证明 ImagePath 的 `C:\` 写法正确）
5. **`RegOpenKey Control\DeviceClasses\{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}` → NAME NOT FOUND**（驱动查询一个设备接口类，系统里没有任何设备注册过它）
6. 约 5ms 后 PnP 开始清理 QCOM061B（创建 Control 键、删除 AllocConfig），启动失败

RPEC/Interfaces/MANU/Mappings/Resources\BinaryPath **都没被读到**，说明失败发生在这些值之前。这解释了 Phase15A 为什么没有效果。`0xC000003B` 的合理解释是：接口列表为空，驱动用空的符号链接名去打开接口设备，内核返回 OBJECT_PATH_SYNTAX_BAD。

接口 `{55beca03-...}` 的提供者：该 GUID 的二进制形式出现在 qcsmmu8250/8280、qcpep、qcdxkm、camera、i2c/spi/uart、qcsubsys 等驱动中（这些都是 SMMU 的使用者）；qciommu8250 中没有。PEP0 已经是 OK 状态，但 DeviceClasses 中没有这个键，所以提供者不是 PEP。**结论：这是 SMMU（qcsmmu）提供的接口。**

手机上的 SMMU 状态（之前的诊断脚本按 `ACPI\QCOM0509` 查找，所以一直显示 not present，属于误判）：
- MMU1 实际已枚举，实例路径是 `ACPI\VEN_QCOM&DEV_0509&SUBSYS_MTP08250&REV_0002\1`，但**没有 Service（没有绑定驱动）**
- MMU0 通过 `_DEP` 依赖 MMU1，MMU1 不启动，所以 MMU0 不出现
- IMM0/IMM1（QCOM059B，对应 qciommu8250 的 QCOM259B）已枚举、没有驱动，与本问题无关
- qcsmmu 服务已安装（qcsmmu8250.inf），但处于 Stopped
- 原因：`qcsmmu8250.inf` 只匹配 `ACPI\VEN_QCOM&DEV_2509&REV_0001/0002`，而 DSDT 给的是原生 `QCOM0509`

## Phase16 计划：在 ACPI 中把 SMMU HID 改为 Kona 的 QCOM2509

- 构建脚本：`tools\build-acpi-hid-phase16.sh`（= Phase12 + `("QCOM0509","QCOM2509")`，并增加 ASL/AML 校验：2509 出现 2 处、0509 不残留）。在 Ubuntu 上运行，方式同 Phase12。
- 依据：SCM0/GLNK/IPC0/RPEN/PDSR/TFTP 都是通过 ACPI 改 HID 成功绑定 Kona 驱动的；Phase2a 用离线注册表 CompatibleIDs 做别名已证实无效（会被重建）。MMU1 的实例 ID 已带 `REV_0002`，改 HID 后正好命中 `SMMU_Device_8250v2`。
- 预期：qcsmmu 绑定 MMU1 → MMU0 出现并绑定 → 注册 `{55beca03-...}` → ADSP 越过第 5 步，开始读 RPEC/Interfaces/BinaryPath，并加载固件。
- 风险：SMMU 驱动接管后，如果某些 DMA 流（UFS/显示）的映射配置不对，可能导致开机异常。回退方法：fastboot 重新刷/启动 Phase12 镜像（Mass Storage 不受影响）。
- 验证：开机后看 MMU0/MMU1 是否绑定 qcsmmu 且状态 OK、`Control\DeviceClasses\{55beca03-...}` 是否存在、ADSP 状态码是否变化。可再做一次 Procmon 开机日志看 ADSP 走到哪一步。
- 诊断脚本需要修正：MMU 的实例路径是 `ACPI\VEN_QCOM&DEV_0509&...` 形式，不能只按 `ACPI\QCOM0509` 查找。

## Phase16 验证结果（2026-10-17，镜像 `Mu-alioth-1-acpi-hid-phase16-20261017-113041.img`，日志 `*_20261017_104223/104743/105509`）

- HID 改动生效：MMU1 = `ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1`，匹配 `oem9.inf`（qcsmmu8250.inf）`SMMU_Device_8250v2`，Service=qcsmmu，Driver=`{4d36e97d...}\0037`。
- 但 **Code 52**：CI 事件 3004 显示“无法验证 qcsmmu8250.sys 的映像完整性，因为在系统上找不到文件哈希”。与 2026-05 qcsubsys8250 的情况相同：Kona 包由 `Windows On Andromeda KMCI Codesigning` 签名，不被 Microsoft Windows Driver Policy 信任（信任该证书的 WDAC/SSDE 路线已证实是死路）。
- 所以 SMMU 接口仍未注册，MMU0 仍未出现，ADSP 仍是 `0xC000003B`（符合预期）。

## Phase16b 计划：WHQL 签名的 qcsmmu8280.sys + 保留 8250v2 配置（不需要重新编译 UEFI）

- 对比：Surface `qcsmmu8280.cat` 为 Microsoft WHQL 签名（有效）；两个 SMMC.bin **SHA256 相同**；Parameters\0/1 的 GUID、OFFI 等结构一致；只有 Dynamic 段的 CTXI/S2CB 流映射表完全不同（0 行相同，8280 的是 SC8280XP 的流 ID）。
- 因此**不走**“把 HID 改成 QCOM0609、让 8280 INF 安装”这条路：首次开机会按 8280 的流 ID 表编程 SMMU，8250 的 UFS/显示 DMA 很可能发生故障。
- 改为：MMU1 已由 oem9.inf 安装，软件键 `Class\...\0037` 里已经有 8250v2 的 ChipSetVersion/CTXI/S2CB/Resources\SMMU；只需
  1. `dism /Add-Driver` 离线注入 Surface qcsmmu8280 包（注册 WHQL catalog，让 CI 能找到哈希）；
  2. 把 `Services\qcsmmu\ImagePath` 指向 DriverStore 中的 `qcsmmu8280.sys`。
- 脚本：`tools\Apply-QcsmmuPhase16b8280Binary-Admin.ps1 -WindowsDrive <盘符>`（先校验 8250v2 配置是否完整，不完整就中止；ImagePath 有备份，可用通用回滚脚本恢复）。
- 验证：MMU1 状态 OK、MMU0 出现并启动、`Control\DeviceClasses\{55beca03-...}` 存在、ADSP 状态码变化；以及开机是否正常（SMMU 接管后的稳定性）。
- 风险与回退：8280 驱动程序能否正确使用 8250 的表需要实测；如果开机异常，进 Mass Storage 运行回滚脚本恢复 ImagePath 即可（qcsmmu8250 会重新被 CI 拒绝，等于回到 Phase16 的状态）。
- 附带修复：通用回滚脚本加了防护，FirmwareOnPhone 为空时不会去删除任何文件。

## Phase16b 验证结果（2026-10-17，日志 `*_20261017_121152/121706/141905`，写入日志 `logs\apply-qcsmmu-phase16b-8280-binary-20261017-120621.log`）

- 写入成功：DISM 注入 `qcsmmu8280.inf_arm64_1d80adabc6ef3b6d`，`Services\qcsmmu\ImagePath` 已指向 `qcsmmu8280.sys`。手机正常开机，没有出现存储/显示异常。
- **签名问题已解决**：本次开机没有新的 CI 3004，也没有新的 Kernel-PnP 219（驱动加载失败）事件，说明 `qcsmmu8280.sys` 已被 CI 接受并成功加载（DriverEntry 通过）。
- MMU1 从 **Code 52 变为 Code 31**，ProblemStatus = `0xC0000001`（STATUS_UNSUCCESSFUL）。设备栈只有 `\Driver\ACPI`。Code 31 = CM_PROB_FAILED_ADD，即失败发生在 **AddDevice（EvtDriverDeviceAdd）阶段**，此时还没有开始操作硬件，最可能是读取或校验配置时失败。
- 静态对比两版驱动程序中的宽字符串（注册表值名）：
  - 共有：ChipSetVersion、ErrataApplicableClients、Resources\SMMU、Guid、`\OFFI`/`\CTXI`/`\S2CB`/`\HYPD`/`\ARMV`/`\CLCK`/`\SCLCK`/`\MMUV`/`\MMU_ERRATA`/`\PREFETCHDETAILS`/`\DynamicCBAssignment`、EnablePtCaching、EnableGuardPages、EnableTestInterface。
  - 仅 8280 有：`EnableIOCoherentPTW`、`\EnableSMMUStallOnFault`（值 `Disabled`）、`Control\LKMDTel`（TimesRun/MaxReportSizeInMB/BranchTrackEnabled，遥测用）。
  - 两个 INF 的配置差异：8280 多写 `Parameters\EnableIOCoherentPTW=1` 与 `Parameters\<N>\EnableSMMUStallOnFault\Disabled=0`；`Parameters\1\OFFI` 不同（8250：`00 01 FF 03 FF 06 08`，8280：`00 01 02 03 FF 06 10`）；`ErrataApplicableClients` 不同（8250v2：`FF`，8280：`00 01 04`）；8280 INF 不写 ChipSetVersion，但驱动程序仍会读取。
- 候选原因有好几个，按规则 2 不盲改，下一步用 Procmon 开机日志精确定位 qcsmmu8280 在 AddDevice 中最后读取了什么、哪一项 NAME NOT FOUND。

## Phase16c 计划：Procmon 开机日志定位 qcsmmu8280 的 AddDevice 失败点

- 手机上：`Collect-ProcmonBootLog-OnPhone.ps1 -Mode Enable` → 重启 → `-Mode Collect`（脚本已更新，会额外记录 `smmu_status.txt`）。
- 电脑上：`Procmon64.exe /NoFilter /OpenLog boot.pml /SaveAs boot_all.csv`，然后 `python tools\filter_procmon_csv.py boot_all.csv <输出目录> smmu`。
  - smmu 模式的关键词：qcsmmu、`\0037`、dev_2509、smmc.bin、lkmdtel、55beca03；
  - 另外输出 `context_after_load.csv`：`qcsmmu8280.sys` Load Image 之后 System 进程的前 3000 条事件（不限路径），用来看 AddDevice 期间的全部访问。
- 判定：看 qcsmmu 在失败前读取的最后几项注册表值/文件及其结果，再决定补值（如 EnableIOCoherentPTW、EnableSMMUStallOnFault）还是修改 OFFI/ChipSetVersion 等。

## Phase16c 结果：Procmon 开机日志（`logs\ProcmonBoot_20261017_142448`，`smmu\` 为筛选结果）

- 本次开机：ADSP 仍为 0xC000003B；MMU1 为 CM_PROB_FAILED_ADD / 0xC0000001。
- qcsmmu8280 的时间线（System 进程）：Load Image → DriverEntry（WPP/WDF 相关注册表，正常）→ PnP 读取 DmaRemappingCompatible → **AddDevice**：读取 `WUDF\CompanionConfigurations`（WdfDeviceCreate 的一部分）→ 打开 `DeviceClasses\{55beca03-...}`，结果 NAME NOT FOUND，之后没有创建 → 约 0.6ms 后 PnP 收尾（失败）。
- **AddDevice 期间驱动完全没有读取自己的配置**（`Class\...\0037` 中的 CTXI/S2CB/ChipSetVersion、`Resources\SMMU`、Services\qcsmmu\Parameters\0/1 一项都没碰）。所以失败与 8250/8280 配置差异无关，是在读配置之前就失败了。这样一来，上一轮列出的注册表候选（EnableIOCoherentPTW/OFFI 等）**都不是 AddDevice 失败的原因**。
- 静态线索（qcsmmu8280.sys）：
  - 导入了 `ZwQuerySystemInformation`，文字池中有 `'DSDT'`、`'ACPI'`、`STATUS_BUFFER_TOO_SMALL` 三个常量，说明驱动会自己读取整张 DSDT（firmware table 接口，Procmon 看不到）。
  - 使用 Microsoft DMF（DeviceInterfaceTarget、CrashDump、LiveKernelDump 等模块）；8250 版没有 DMF，并且内置一张芯片名称表（MSM/SDM…）。
  - 导入了 `DbgPrintEx`；诊断字符串形如 `SmmuInitHardware() : SmmuError : ...`，所以可以用 DebugView 抓取。
- 关于 `{55beca03-...}`：在 Surface/Kona 包中，qcpep/qcscm/i2c/spi/uart/相机/GPU/qcsubsys/qcsmmu 都引用了它，而且都是查询或订阅方（`IoGetDeviceInterfaces`/`IoRegisterPlugPlayNotification`）。手机系统分区中没有其他驱动包含它。WDF 驱动通过 WdfDeviceCreateDeviceInterface 注册接口，不会出现导入名，所以提供者仍然很可能是 qcsmmu 本身（和最初的判断一致），但还没有直接证据。
- 附带发现：**PEP0（`ACPI\QCOM0519`）没有任何驱动**：没有 Service，设备栈只有 ACPI。Kona 的 qcpep.wd8250.inf 只认 `QCOM2519`，8280 版只认 `QCOM0617`。启动日志中 `qcpep` 出现 0 次。MMU1 的 `_DEP` 指向 PEP0；SMMC.bin、RADS.bin 这类 AeoB 资源都是 PEP 框架的电源资源。这是一个独立的大问题，以后要处理（qcpep 是 boot-start 驱动，而且与 SoC 强相关，不能直接套用 8280 版）。

## Phase16d 计划：DebugView 抓取 qcsmmu8280 的 DbgPrintEx 输出

- 工具：Sysinternals DebugView 命令行 ARM64 版 `dbgviewcli64a.exe`（已下载，微软签名有效），已复制到手机 `C:\Code\REDMIK40_Win11\`。
- 脚本：`tools\Capture-QcsmmuDebugOutput-OnPhone.ps1`
  - `-Mode Live`（默认）：打开 Debug Print Filter（DEFAULT/IHVDRIVER/IHVBUS=0xFFFFFFFF）→ 开始抓取内核输出 → `pnputil /restart-device` 重启 MMU1（失败就改用禁用再启用）→ 保存 `dbgview.log`、`smmu_lines.txt`、`mmu1_status.txt`。不需要重启手机。
  - 如果 Live 没有抓到输出，改用 `-Mode BootEnable`，重启手机后运行 `-Mode BootCollect`。
- 判定：根据 SmmuError 行和状态码确定 AddDevice 失败在哪一步（DSDT 解析 / DMF 模块 / 接口 / 其他）。

## Phase16d 结果与 Phase16e 计划（2026-10-20）

- DebugView 没有抓到 qcsmmu 的任何输出，已记入死路第 9 条。
- 反汇编 qcsmmu8280.sys（工具在 tools\re\：xref.py / smmudis.py / blscan.py，基于 capstone，脚本不要命名为 dis.py，否则会和标准库冲突）：
  - DriverEntry（0x2da0）调用 0x2aa0：先用 `MmGetSystemRoutineAddress("IoGetIommuInterface")`，再调用 `IoGetIommuInterface(1, &iface)`，然后执行 iface->CreateDomain / DeleteDomain，成功时把驱动上下文中的标志字节置 1，表示"Windows 内核 IOMMU（DMA 重映射）可用"。
  - AddDevice（EvtDriverDeviceAdd = 0x3690）读取这个标志：为 0 走 0x37ec（DMF 初始化），为 1 走 0x3944。返回 0xC0000001 的分支及其 WPP 消息编号为：0x19（取驱动上下文失败）、0x1a（0x65a28 DMF 配置分配失败）、0x3ccc 附近的分支、0x22（0x3f74 → sub_12370，仅在标志为 0 且 sub_2a1e0 返回 0 时执行）。
- 新线索：alioth 的 `aliothPkg/Include/ACPI.inc` 中 `Kona/IORT.aml` 被注释掉了，而且 Silicium-ACPI 里根本没有 Kona 的 IORT。Windows 内核的 IOMMU 是依靠 IORT 才知道 SMMU 存在的，所以在 alioth 上内核 IOMMU 很可能不可用，8280 驱动只能走"标志为 0"的分支。哪一步失败，等 WPP 消息编号来确认。
- Phase16e：手机运行 `tools\Capture-QcsmmuWpp-OnPhone.ps1`（logman ETW 会话 + 重启 MMU1），电脑端解析 ETL 中的消息编号。

## Phase16e 结果（2026-10-20）：根因是 PEP

- ETW 抓到 qcsmmu8280 的 WPP 消息依次为 `{750ad4a7} 0xc` → `{750ad4a7} 0x20` → `{6062ceb3} 0x22`，然后是 DMF 清理消息。日志在 `logs\QcsmmuWpp_Live_20261020_183347`（ETL + tracerpt 生成的 wpp.xml）。
- 含义：SMMU 自己就要打开 {55beca03} 接口，打不开就让 AddDevice 失败。这个接口由 qcpep 的 `WdfDeviceCreateDeviceInterface` 注册，而 PEP0 没有驱动，所以接口不存在。（IORT/内核 IOMMU 的怀疑可以先放下：失败点并不在那个分支。）
- 详见 dead-ends-and-breakthroughs.md 突破第 8 条。

## Phase17 计划：给 PEP0 装上驱动

- 现状：DSDT 中 PEP0 的 `_HID` 是 QCOM0519，没有任何 INF 匹配。qcpep.wd8250.inf 匹配 `ACPI\QCOM2519`（服务名 qcpep，并带 PEP 资源注册表和 PPMSettings-8250Profiles.wd.ppkg 配置包），但 qcpep8250.sys 是 Andromeda 签名。qcpep8280.sys 虽然是 WHQL 签名，但内部是 SC8280XP 的电源逻辑，用在 SM8250 上开机蓝屏的风险很高（PEP 是开机加载驱动）。
- 笔记中从未尝试过测试签名（`bcdedit testsigning`）。WOA 社区常用这个办法加载高通参考签名驱动；Andromeda 签名的驱动在测试签名模式下有可能被接受，需要实测。前提是 UEFI 安全启动关闭。
- 首选路线 A：先只读检查安全启动和 BCD 状态 → 开启测试签名 → 验证 Andromeda 签名驱动能否加载（可以用当前已经匹配的 qcsmmu8250 来验证：把 ImagePath 改回 8250）→ UEFI 中把 PEP0 的 HID 改成 QCOM2519，用原生 qcpep8250。
- 备选路线 B：UEFI 中把 PEP0 改为 2519，并按 Phase16b 的办法把 ImagePath 指向 qcpep8280.sys。必须先离线备份，并准备好回滚。

## Phase17a 实测（2026-10-21）：开机卡在 Silicium 启动画面

- 改动：`bcdedit testsigning on`，同时把 `Services\qcsmmu\ImagePath` 改回 qcsmmu8250.sys（Andromeda 签名）。
- 现象：重启后停在 Project Silicium logo + 转圈，进不了 Windows。
- 推断（待验证）：测试签名很可能已经放行了 qcsmmu8250.sys，它是开机加载驱动，在初始化时卡住（例如一直等待 PEP 接口，或对 SMMU 硬件的编程不当）。另一种可能是 testsigning 本身导致卡死（可能性低）。
- 隔离办法：只离线恢复 ImagePath（`tools\Restore-Qcsmmu8280ImagePath-Offline-Admin.ps1`），保留 testsigning。如果之后能正常开机，就说明测试签名有效，卡死的是 8250 驱动。
- 结果：恢复 ImagePath 后正常开机，桌面出现"测试模式"水印（Build 22621）。结论：testsigning 本身没有问题。卡死与 qcsmmu8250.sys 有关，说明它在测试签名下很可能已经被加载（Andromeda 签名被放行，下一阶段用 CI 事件直接确认）。目前 qcsmmu 仍然使用 8280。

## Phase17b 计划：UEFI 中把 PEP0 的 HID 改为 QCOM2519，用原生 qcpep8250

- 构建脚本：`tools/build-acpi-hid-phase17.sh`，即 Phase16 加一项 `("QCOM0519", "QCOM2519")`，并增加 ASL/AML 校验。在 Ubuntu 上运行，用法和 Phase16 一样。
- 验证时用 `fastboot boot` 启动 Phase17 镜像，不要 flash。如果出问题，重启后改用 Phase16 镜像就能回退（HID 变回 0519，qcpep 不会再被匹配）。
- 预期：PEP0 绑定 qcpep（qcpep.wd8250.inf，Andromeda 签名，靠测试签名放行）→ 出现 `DeviceClasses\{55beca03}` → MMU1（qcsmmu8280）的 AddDevice 不再报 0x22 → 再看 ADSP。
- 风险：qcpep 是 PoFx 的 PEP 插件，又是开机加载驱动，可能导致开机卡死或蓝屏。回退方法同上。
- 前置发现（2026-10-21）：手机驱动库中根本没有 qcpep 包，Services\qcpep 也不存在。原因是当初 `apply-alioth-offline-fixes-admin.ps1` 把 Kona 的 `Drivers\SOC` 整个排除在注入范围之外。需要先在 Mass Storage 下运行 `tools\Apply-Phase17QcpepInject-Admin.ps1`（DISM 离线注入 qcpep.wd8250.inf）。注入后只要 HID 还是 0519，就不会匹配任何设备，开机行为不变。

## Phase17b 实测（2026-10-21）：INACCESSIBLE_BOOT_DEVICE（0x7B）蓝屏

- 条件：fastboot boot Phase17 镜像（PEP0 → QCOM2519），testsigning 开启，qcpep.wd8250 已离线注入，qcsmmu 为 8280。
- 关键事实：DSDT 中 `UFS0`（QCOM24A5）的 `_DEP` 是 `\_SB_.PEP0`。HID 为 0519 时 PEP0 没有驱动，作为空设备启动，依赖得到满足；改为 2519 后 PEP0 必须由 qcpep 启动，UFS 才能启动。
- 待区分：A）qcpep8250 在开机时被加载但初始化失败；B）qcpep 没有装到 PEP0 上，设备停在待安装状态。回退到 Phase16 镜像后，查 `Services\qcpep`、`Enum\ACPI\QCOM2519` 的 Service 值和 setupapi.dev.log 来判断。
- 回退后的证据（Phase16 镜像下开机）：
  - `Services\qcpep` 存在（Start=0，ImagePath 指向 DriverStore 中的 qcpep8250.sys），这个键是 DISM 离线注入开机关键驱动时创建的。
  - qcpep 作为开机启动驱动处于 **Running/OK**，说明 Andromeda 签名的开机驱动在测试签名下已被 winload 加载，签名这一关过了。
  - `Enum\ACPI\QCOM2519` 不存在，setupapi.dev.log 中也没有 QCOM2519：Phase17 那次开机时，PEP0 作为新设备没有完成安装（或者安装结果因蓝屏没有保存到注册表），UFS 一直在等 PEP0，所以出现 0x7B。更接近 B。
- Phase17c：`tools/build-acpi-hid-phase17c.sh` = Phase17 + 删除 UFS0 的 `_DEP`（只删这一处，`_DEP` 总数从 73 变为 72，已在电脑上单独测试过删除函数）。目的是让系统先从 UFS 正常开机，再由用户态 PnP 按 INF 完整安装 qcpep（包括 `.HW` 中的 PEP 资源配置）。安装完成后可能需要再重启一次，qcpep 才会真正接管 PEP0。回退方法仍是 Phase16 镜像。

## Phase17c 实测与 Phase17d（2026-10-21）

- Phase17c 可以正常开机。PEP0 = `ACPI\QCOM2519\2&DABA3FF&0`，Service=qcpep，`Device Parameters\Resources\ResourceList`（VRDL…SRDL）已按 INF 完整写入；但 PEP0 为 **Code 31 / 0xC000000E**，重启后不变。MMU1、ADSP 因 `_DEP` 指向 PEP0 而没有被枚举。
- 反汇编 qcpep8250.sys（tools\re\findconst.py、addrref.py）：
  - 0xC000000E 来自 PAGE:0x20f488（初始化大函数 0x20dd20）。
  - sub_3e170 通过 IOCTL_ACPI_EVAL_METHOD（0x32C004）执行 PEP0 的 **`PEPH`** 方法，输入为 `AeiB`+`PEPH`，输出 `AeoB` 中的第一个字符串，存入全局 0x1c8ea0。
  - sub_50cd8 = WDF 函数表第 126 项，以参数 1/2 读取 PEP0 的 HardwareID / CompatibleIDs，再用 sub_154568 与 PEPH 字符串比较；两个都不匹配时，记录 WPP 消息 0x52 并返回 0xC000000E。
- alioth DSDT 的 `Scope(\_SB_.PEP0)` 中 PEPH 返回 `"ACPI\\VEN_QCOM&DEV_0519"`（全文只此一处），而 `_HID` 已改成 2519，所以比对失败。
- Phase17d：`tools/build-acpi-hid-phase17d.sh` = Phase17c + PEPH 中的 `DEV_0519` 改为 `DEV_2519`，并增加检查 `phase17d_peph_2519`、`phase17d_DEV_0519_absent`，AML 中不得出现 `DEV_0519`。
- 教训：改高通设备的 HID 时，要同时搜索 `VEN_QCOM&DEV_xxxx` 形式的硬编码字符串（例如 PEPH）。

## 未决问题

- Phase13 写入的 `RPEC` 和 `PDName` 开机后被删除，删除者未知，可能是驱动自己清理不认识的值。这不影响 Phase14 的方向，但步骤C之后要再核对一次。
