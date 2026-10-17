# Phase16 UEFI 构建结果（2026-10-17）

## 改动

Phase16 = Phase12 + SMMU HID `QCOM0509` → `QCOM2509`，目的是让 `qcsmmu8250.inf`（`ACPI\VEN_QCOM&DEV_2509&REV_0002`）绑定 MMU0/MMU1，注册 qcsubsys 需要的 SMMU 接口 `{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}`。依据见 `phase13-validation-and-phase14-plan-20261016.md` 的 Phase15B 一节。

## 构建

- 脚本：`Alioth-Engineering/tools/build-acpi-hid-phase16.sh`（Ubuntu）
- 日志：`Alioth-Engineering/logs/mu-alioth-phase16-build-20261017-112845.log`
- 镜像：`UEFI-Images/Mu-alioth-1-acpi-hid-phase16-20261017-113041.img`
- SHA256：`ab660c0476c5190e128ed913e4b1d027e3bd1ee3edfa640767623549f75b5616`

## 校验

- ASL：`phase16_smmu_hid_x2: True`（2 处 QCOM2509），`phase16_QCOM0509_absent: True`；Phase12 的 DSP 根节点 `_DEP`/`_DSD` 检查全部 True。
- AML：含 QCOM2509，不含残留 QCOM0509；其余 HID 与 Phase12 一致。
- iasl `-f` 仍报 9 个上游遗留错误（与 Phase12 相同），AML 正常生成。
- FVMAIN 占用 99%（与 Phase12 相同，剩余 544 字节，以后再加 DXE 需注意）。

## 手机端验证要点

1. `fastboot boot` 该镜像（先 boot 不要 flash；出问题直接重启回 Phase12）。
2. 检查 MMU0/MMU1（实例路径 `ACPI\VEN_QCOM&DEV_2509&...`）是否绑定 qcsmmu，状态是否 OK。
3. 检查 `HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}` 是否存在。
4. 看 ADSP(QCOM061B) 状态码是否不再是 `0xC000003B`；必要时再做一次 Procmon 开机日志，看 ADSP 是否开始读取 RPEC/Interfaces/BinaryPath。
5. 风险：SMMU 接管后，UFS/显示等 DMA 流映射如果不对，可能导致开机异常或黑屏，回退方法是用 Phase12 镜像。
