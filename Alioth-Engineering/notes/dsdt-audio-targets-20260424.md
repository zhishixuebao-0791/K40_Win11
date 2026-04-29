# Alioth DSDT 音频节点定位结论

## 本次输入

- Raw ACPI: `D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309`
- DSDT 二进制: `D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309\DSDT\QCOMM_\SDM8250_\00000003\00000000.bin`
- 反编译输出: `C:\yjc_code\K40_Win11\Alioth-Engineering\analysis\dsdt-audio-current\DSDT.dsl`
- 自动报告: `C:\yjc_code\K40_Win11\Alioth-Engineering\analysis\dsdt-audio-current\audio-dsdt-target-report.md`

## 关键结论

Mu-alioth 当前 DSDT 不是完全没暴露音频拓扑。它已经暴露了 `AUDS`、`ADSP`、`SLM1`、`ADCM`、`AUDD`、`ARPC`、`ARPD`、`CFSA/FSA4480` 等节点。

当前主要问题不是 `_STA` 把音频设备整体屏蔽，而是 DSDT 暴露的 Qualcomm 音频 ID 是 `05xx` 系列，而本地 Kona Windows 音频驱动大多匹配 `25xx` 系列。

## 定位表

| 节点 | DSDT 暴露 | _STA 状态 | _DEP / 依赖 | 当前判断 |
| --- | --- | --- | --- | --- |
| `AUDS` | `_HID QCOM05D2` | 没有本地 `_STA`，默认随父节点有效 | 无 `_DEP` | 对应 Kona `ACPI\QCOM25D2`，适合做 alias |
| `ADSP` | `_HID QCOM051D` | `_STA` 返回 `0x0F` | `PEP0/PILC/GLNK/IPC0/RPEN/SSDD/ARPC` | 没被屏蔽，是音频链核心前置 |
| `SLM1` | `Device(SLM1)` | 没有本地 `_STA` | 有 `_CRS`，无 `_DEP` | 没看到显式 `SLM1\QCOM0524`，不能凭空 alias |
| `ADCM` | `CHLD -> ADCM\QCOM0525` | 没有本地 `_STA` | `MMU0/IMM0` | 对应 Kona `ADCM\QCOM2525`，第二阶段 alias |
| `AUDD` | `CHLD -> AUDD\QCOM0537` 和 `AUDD\QCOM052C` | 没有本地 `_STA` | 有 SPI4 `_CRS` | 对应 Kona `AUDD\QCOM2537/QCOM252C`，第二阶段 alias |
| `ARPC` | `_HID QCOM0560` | 没有本地 `_STA` | `MMU0/GLNK/SCM0` | 对应 Kona `ACPI\QCOM2560`，适合第一阶段 alias |
| `ARPD` | `_HID QCOM058A` | 没有本地 `_STA` | `ADSP/ARPC` | 对应 Kona `ACPI\QCOM258A`，适合第一阶段 alias |
| `CFSA` | `_HID FSA04480` | 没有本地 `_STA` | `_CRS` 指向 `I2C5` | ID 已匹配，问题在 I2C/依赖，不是 alias |

## 下一步方向

第一阶段不改 Mu-Silicium，不动 DSDT，不广泛注入 Kona 包。

先做极窄 INF alias 实验，只处理：

- `ACPI\QCOM05D2 -> ACPI\QCOM25D2`
- `ACPI\QCOM0560 -> ACPI\QCOM2560`
- `ACPI\QCOM058A -> ACPI\QCOM258A`

只有第一阶段稳定启动，并且能让更多音频子设备出现后，才进入第二阶段：

- `ADCM\QCOM0525 -> ADCM\QCOM2525`
- `AUDD\QCOM052C -> AUDD\QCOM252C`
- `AUDD\QCOM0537 -> AUDD\QCOM2537`

如果 alias 后驱动仍因为 `_DEP` 依赖不满足、资源不可用、或者设备无法启动，再转向 `Mu-Silicium -> aliothPkg/ACPI` 修改方向。

## 禁止项

- 不注入 `Drivers\SOC`
- 不注入 `Drivers\USBFn`
- 不注入 PMIC、PCIe、存储、平台总线类驱动
- 不整包导入 `windows_silicon_qcom_kona`
- 不直接修改原始 INF，只在实验包里复制并添加 alias
