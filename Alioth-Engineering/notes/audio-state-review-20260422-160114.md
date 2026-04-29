# Audio State Review - 20260422_160114

## 结论

当前 **不适合直接注入 Kona Audio 最小包**。

更准确地说：

- 不适合直接注入 `Kona\Drivers\Audio` 这条完整音频链
- 但已经出现了一个 **可单点试验的低风险候选**：
  - `FSA4480`

## 直接证据

采集目录：

- `C:\Code\REDMIK40_Win11\AudioState_20260422_160114`

### 1. 没有声音设备

`01_SoundDevices.txt` 为空。

这说明当前系统里没有任何被 `Win32_SoundDevice` 识别出来的声卡/音频设备。

### 2. 没有真正的 MEDIA 设备

`02_Pnp_MEDIA.txt` 里只有：

- `Microsoft 流服务代理`

没有真实的播放/录音音频设备。

### 3. 没有音频根设备

`03_Pnp_AudioCandidates.txt` 里只看到：

- `ACPI\QCOM24A5`
- `ACPI\QCOM050D`
- `ACPI\QCOM05A2`

没有出现我们后续注入 `Kona Audio` 前必须先看到的这些音频根设备：

- `ADCM\...`
- `AUDD\...`
- `ADSP\QCOM2510`
- `ACPI\QCOM2560`
- `ACPI\QCOM258A`
- `ACPI\QCOM25D2`

### 4. 音频相关已签名驱动为空

`05_SignedDrivers_AudioRelated.txt` 为空。

这说明当前系统里还没有任何真正挂上的音频相关候选驱动。

### 5. 音频端点注册表为空

`08_AudioRegistryEndpoints.txt` 里：

- `Render` 为空
- `Capture` 为空

### 6. Windows 音频服务本身是正常的

`10_UserFacingAudioState.txt` 里：

- `AudioSrv = Running`
- `AudioEndpointBuilder = Running`

说明不是系统服务没起来，而是下层设备没有枚举成功。

## 唯一低风险候选：FSA4480

`04_ProblemDevices.txt` 里出现了：

- `ACPI\FSA04480\...`

而本地刚好存在一个 **精确匹配** 的 INF：

- `源码\windows_xiaomi_platforms_full\components\ANYSOC\Hardware\HARDWARE.USB.FSA4480\fsa4480.inf`

这个 INF 的匹配项就是：

- `ACPI\FSA04480`

并且它不是启动级 SOC/PMIC/PCIe 驱动，风险显著低于此前出问题的 Kona 平台驱动。

## 为什么现在还不适合直接注入 Kona Audio

本地 `Kona Audio` 相关 INF 需要的关键根设备包括：

- `SLM1\QCOM2524`
- `ADCM\QCOM2525`
- `AUDD\QCOM2537`
- `ADSP\QCOM2510`
- `ACPI\QCOM2560`
- `ACPI\QCOM258A`
- `ACPI\QCOM25D2`

这次采集结果里，这些入口 **一个都没有出现**。

所以如果现在直接去注：

- `qcadcm8250.inf`
- `qcauddev8250.inf`
- `qcslimbus8250.inf`
- `qcadsprpc8250.inf`
- `qcadsprpcd8250.inf`
- `AudioService8250.inf`

大概率结果不会是“音频恢复”，而是：

- 驱动根本绑不上
- 或再次引入新的平台风险

## 当前最适合的判断

### 不适合直接注入

不适合直接注入：

- 整个 `Kona Audio` 最小包
- 任意 `ADCM/AUDD/ADSP/QCOM25xx` 音频链驱动

### 适合继续推进

适合推进的只有两条：

1. 继续追“为什么音频根设备没有枚举出来”
2. 如果你要做第一轮试验，只考虑 `FSA4480` 单点候选

## 下一步建议

下一步不再碰 `Kona Audio`。

先只做：

1. 把 `FSA4480` 整理成独立实验目录
2. 明确它的回退方式
3. 等你确认后，再决定要不要做第一轮单点注入测试

在没有新的 `ADCM/AUDD/ADSP/QCOM25xx` 证据之前，**不要碰 Kona Audio**。
