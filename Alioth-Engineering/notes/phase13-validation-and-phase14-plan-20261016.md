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

## 未决问题

- Phase13 写入的 `RPEC` 和 `PDName` 开机后被删除，删除者未知，可能是驱动自己清理不认识的值。这不影响 Phase14 的方向，但步骤C之后要再核对一次。
