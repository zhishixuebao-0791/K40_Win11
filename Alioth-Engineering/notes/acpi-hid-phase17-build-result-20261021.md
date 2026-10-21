# Phase17 UEFI 构建结果（2026-10-21）

## 改动

Phase17 = Phase16（SMMU QCOM0509→QCOM2509）+ PEP0 `QCOM0519` → `QCOM2519`，让已离线注入的 `qcpep.wd8250.inf`（`ACPI\QCOM2519`）绑定 PEP0，注册 `{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}`。依据：Phase16e 的 WPP 根因链（PEP0 无驱动 → 没有 {55beca03} → SMMU Code 31 → ADSP 0xC000003B）。

## 构建

- 脚本：`Alioth-Engineering/tools/build-acpi-hid-phase17.sh`（Ubuntu）
- 日志：`Alioth-Engineering/logs/mu-alioth-phase17-build-20261021-103314.log`
- 镜像：`UEFI-Images/Mu-alioth-1-acpi-hid-phase17-20261021-103410.img`
- SHA256：`f828e53ceb6bfcd6ea9eeeb9e811e64aa41331c60973a90dbc6d0c880d45f6f4`

## 校验

- ASL：`phase17_pep_hid_x1: True`、`phase17_QCOM0519_absent: True`，其余 19 项（含 Phase16 SMMU）全部 True。
- AML：含 QCOM2519、QCOM2509；无残留 QCOM0519/QCOM0509。
- iasl 9 个上游遗留错误、FVMAIN 99%，均与 Phase12/16 相同。
- 构建前核对：qcpep.wd8250.inf 第 33 行 `Pep_Device, ACPI\QCOM2519`；alioth DSDT 的 PEP0 带完整的高通参考 PEP 配置方法（G0MD~G9MD、PGCT、PMCF、THTZ 等），与 qcpep8250 预期的 ACPI 形态一致。
- 未改动：TSENS 设备（INF 中的 QCOM253B~2543）不在本轮范围内。

## 手机端验证（前提：testsigning 已开启，qcpep 已注入，qcsmmu ImagePath 仍为 8280）

1. `fastboot boot` Phase17 镜像（不要 flash）。卡在 logo 或蓝屏 → 重启改用 Phase16 镜像回退（HID 回到 0519，qcpep 不再匹配）。
2. PEP0：实例路径应变为 `ACPI\QCOM2519\...`，Service=qcpep，状态 OK；如果是 Code 52，查 CI 3004 事件（判断 testsigning 是否放行 Andromeda 签名）。
3. `Control\DeviceClasses\{55beca03-...}` 是否存在。
4. MMU1（qcsmmu8280）是否从 Code 31 变为 OK，MMU0 是否出现；必要时重跑 `Capture-QcsmmuWpp-OnPhone.ps1` 看是否还有 0x22 消息。
5. ADSP（QCOM061B）状态码是否不再是 0xC000003B；有变化就再抓一次 Procmon 开机日志，看是否开始读取 RPEC/Interfaces/BinaryPath。
