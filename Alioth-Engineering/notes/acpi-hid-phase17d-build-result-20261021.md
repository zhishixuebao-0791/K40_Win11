# Phase17d UEFI 构建结果（2026-10-21）

## 改动

Phase17d = Phase17c + PEP0 的 `PEPH` 方法返回值 `"ACPI\\VEN_QCOM&DEV_0519"` → `"ACPI\\VEN_QCOM&DEV_2519"`。依据：Phase17c 中 PEP0 为 Code 31 / 0xC000000E，反汇编确认 qcpep8250 会拿 PEPH 返回的字符串与设备的 HardwareID/CompatibleIDs 比对（见 phase13 笔记 Phase17c 一节）。

## 构建

- 脚本：`Alioth-Engineering/tools/build-acpi-hid-phase17d.sh`
- 日志：`Alioth-Engineering/logs/mu-alioth-phase17d-build-20261021-114655.log`
- 镜像：`UEFI-Images/Mu-alioth-1-acpi-hid-phase17d-20261021-114746.img`
- SHA256：`1e713e6f76e0a07fad8d9378582646b0a8655557d5f3a27cff33a61b9aa63a13`
- 校验：`phase17d_peph_2519`、`phase17d_DEV_0519_absent`、`phase17c_ufs0_no_dep` 等 48 项全部 True；AML 含 `VEN_QCOM&DEV_2519`，无 `DEV_0519`/`QCOM0519`/`QCOM0509` 残留；iasl 9 个遗留错误不变；FVMAIN 剩余 552 字节。
- 最终 `DSDT.asl` 与 `DSDT.asl.pre-phase17c-*.bak` 的 diff **只有两处**：UFS0 的 `_DEP` 被删除，PEPH 改为 DEV_2519。

## 构建前核实

- 对照 Silicium-ACPI 中所有带 PEPH 的平台：a52q 0819/0819、a52sxq 0A17/0A17、surya 1419/1419、venus/lemonade 1A17/1A17、miatoll 0819/0819、lisa 0A17/0A17、Kailua 0C17/0C17、vayu/nabu/pipa/cepheus 0519/0519 —— **PEPH 中的 DEV 号一律等于 PEP0 的 `_HID`**，只有 alioth（HID 2519、PEPH 0519）不一致。修复方向正确。
- alioth DSDT 中 `VEN_QCOM&DEV_` 形式的硬编码只有 PEPH 这一处（另一处是 `VEN_QCOM&DEV__AVSTREAM`，与 HID 无关），没有别的随 HID 改动而失配的字符串。

## 构建脚本问题（已修复）

- 第一次构建失败：`Cannot locate top-level _DEP before _HID in Device(UFS0)`。
- 原因：构建脚本直接在 `sound_code/.../alioth/DSDT.asl` 上**叠加修改**，Phase17c 已经删掉 UFS0 的 `_DEP`，Phase17d 再次删除时就找不到目标。HID 替换天然可以重复执行，删除 `_DEP` 则不行。
- 修复：`replace_top_level_dep` 在 providers 为空且 `_DEP` 已不存在时打印 skip 并跳过。以后写新阶段脚本时，**每一步补丁都必须能重复执行**（或者先从固定基线恢复 DSDT.asl）。

## 手机端验证（fastboot boot，不要 flash；回退用 Phase17c 或 Phase16）

1. PEP0（`ACPI\QCOM2519\...`）是否从 Code 31 / 0xC000000E 变为 OK。如果仍失败，看新状态码，再抓 qcpep WPP（检查是否仍有消息 0x52）。
2. PEP0 启动后，`_DEP` 指向 PEP0 的 30 个设备（MMU1、ADSP、GPU0、PCI0/1、I2C/SPI/UART 等）会一起开始枚举 —— 注意开机稳定性和新出现的问题设备。
3. `Control\DeviceClasses\{55beca03-...}` 是否出现；MMU1/MMU0（qcsmmu8280）是否 OK；ADSP 状态码是否变化。
4. 风险：PEP 开始接管电源后，可能出现蓝屏或开机卡死（例如 PoFx 对某些设备做 F-state 切换）。记下蓝屏代码后回退。
