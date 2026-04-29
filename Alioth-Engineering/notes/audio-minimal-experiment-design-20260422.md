# Redmi K40 内置音频最小实验包设计

## 目标

这份方案的目标不是立刻把内置扬声器修好，而是先把后续音频实验收敛成一条低风险、可回退、可验证的路径。

当前阶段只做两件事：

1. 保住现在已经可用的系统基线
2. 为后续“最小音频实验包”准备输入信息和包边界

## 当前基线

当前已经确认可用的部分：

- Windows 可启动
- `jcyang` 可正常登录
- 供电 Hub 下 USB 键盘鼠标可用
- USB 网卡可用
- 横屏可以手动调整

当前仍缺失或不稳定的部分：

- 内置扬声器
- 内置麦克风
- 触摸
- 一大批 Qualcomm ACPI 设备仍未装驱动

## 关键判断

### 1. 现在不能再做宽范围驱动注入

此前已经验证过，整包注入 `windows_silicon_qcom_kona` 会把启动链打坏，触发多轮 `0xc0000428`。

所以后续任何音频实验都必须遵守：

- 只碰音频相关目录
- 不碰 `Drivers\SOC`
- 不碰 `Drivers\USBFn`
- 不碰 PMIC / PCIe / 平台启动级驱动

### 2. 内置音频不是“缺一个通用 INF”

目前的诊断信息说明：

- 系统里没有出现公开 Kona 音频栈通常依赖的关键根设备，例如：
  - `ADCM\...`
  - `AUDD\...`
  - `ADSP\QCOM2510`
  - `ACPI\QCOM2560`
  - `ACPI\QCOM258A`
  - `ACPI\QCOM25D2`
- `Mu-Silicium` 对 `alioth` 当前也仍然标记：
  - `Speakers = ❌`
  - `Microphone = ❌`

所以更可能的真实问题是：

- `alioth` 缺少板级音频适配
- 或 ACPI / 设备枚举链还没有把音频根设备正确暴露出来
- 或还缺 `alioth` 专用音频扩展 / 校准 / ACDB 组合

## 最小实验包的范围

第一轮只允许从以下目录中挑选候选内容：

- `源码\windows_silicon_qcom_kona\Drivers\Audio\ADCM`
- `源码\windows_silicon_qcom_kona\Drivers\Audio\Device`
- `源码\windows_silicon_qcom_kona\Drivers\Audio\AudMiniport`
- `源码\windows_silicon_qcom_kona\Drivers\Audio\Slimbus`
- `源码\windows_silicon_qcom_kona\Drivers\Audio\RPC\ADSPRPC`
- `源码\windows_silicon_qcom_kona\Drivers\Audio\RPC\ADSPRPCD`
- `源码\windows_silicon_qcom_kona\Extensions\Audio\ACDB\MTP`
- `源码\windows_silicon_qcom_kona\Extensions\Audio\AudMiniport\MTP`
- `源码\windows_silicon_qcom_kona\Extensions\Audio\Device`

## 明确排除项

第一轮必须排除：

- `源码\windows_silicon_qcom_kona\Drivers\SOC`
- `源码\windows_silicon_qcom_kona\Drivers\USBFn`
- 任何 PMIC / PCIe / USBFn / 平台总线 / 启动级核心驱动
- 任何来源不明的整包导入

## 第一轮实验前必须先拿到的信息

在正式设计音频实验包之前，先从当前手机 Win11 系统里采集以下状态：

1. 当前 `PnP` 里与音频相关的设备枚举情况
2. 当前 `MEDIA` 类设备是否为空
3. 当前已签名驱动中是否已经出现 `qcaud` / `qcslim` / `adsp` 相关驱动
4. 当前注册表里是否出现：
   - `ADCM`
   - `AUDD`
   - `ADSP`
   - `ACPI\QCOM2560`
   - `ACPI\QCOM258A`
   - `ACPI\QCOM25D2`
   - `ACPI\VEN_FSA0&DEV_4480`
5. 当前 `setupapi.dev.log` 里最近是否出现音频相关驱动匹配痕迹

## 成功标准

第一轮音频实验的成功标准不是“马上有声音”。

第一轮只看以下 4 件事：

1. Windows 仍能正常启动
2. 没有新的 `0xc0000428`
3. 至少出现一个新的音频根设备，例如：
   - `ADCM\...`
   - `AUDD\...`
   - `ADSP\QCOM2510`
   - `ACPI\QCOM2560`
   - `ACPI\QCOM258A`
   - `ACPI\QCOM25D2`
4. `MEDIA` 类设备开始出现

如果这 4 条一条都没满足，就说明实验范围仍然不对，必须停止扩大注入面。

## 失败标准

出现以下任意情况，就视为本轮实验失败：

- 进入恢复 / 蓝屏 / `0xc0000428`
- 系统比当前基线更不稳定
- USB 输入、网络等当前已工作的能力被破坏
- 没有新增音频相关根设备，只有新的未知设备或新的启动级错误

## 推荐执行顺序

### 阶段 1：只采集信息

先在手机 Win11 内运行：

- `C:\Code\REDMIK40_Win11\Collect-AliothAudioState.ps1`

输出结果保存在：

- `C:\Code\REDMIK40_Win11\AudioState_时间戳\`

### 阶段 2：根据采集结果做设备匹配表

下一步基于采集结果做一个表：

- 当前已出现的候选音频相关硬件 ID
- 本地 Kona 音频 INF 中可匹配的设备 ID
- 完全对不上、必须放弃的子包

### 阶段 3：只设计，不注入

只有完成上一步后，才开始输出“音频最小实验包候选清单”。

这一步仍然不注入，只做：

- 候选 INF 清单
- 候选依赖顺序
- 回退顺序
- 风险等级

## 当前最适合你的做法

现在最适合你的不是继续注入任何音频驱动，而是：

1. 保住当前能用的基线
2. 在手机 Win11 内运行音频状态采集脚本
3. 把采集结果回传
4. 再由这些结果反推第一轮音频最小实验包

## 额外说明

如果你只是临时需要声音，当前最稳的仍然是：

- 外置 USB 音频设备
- 或带标准 USB Audio 输出的扩展坞

这条路线与后续内置音频实验并不冲突。
