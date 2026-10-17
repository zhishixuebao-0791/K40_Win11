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

### 4. 取得 alioth 自签名 DSP 固件（2026-10-16）
- 可靠流程：`fastboot boot` 临时启动 TWRP → 只读挂载当前槽的 `modem_x` → adb pull → 按 SHA256 清单校验 → `tools\pil_squasher.py` 合并。
- 结果在 `components\Devices\Alioth\firmware-squashed\`（adsp/cdsp/slpi 三个 mbn）。
- 注意：Mass Storage 模式只暴露 LUN0，看不到 modem 分区，不要再尝试从 Mass Storage 读固件。
