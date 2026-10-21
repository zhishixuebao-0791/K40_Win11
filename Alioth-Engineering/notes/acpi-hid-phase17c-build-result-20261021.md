# Phase17c UEFI 构建结果（2026-10-21）

## 改动

Phase17c = Phase17（Phase16 + PEP0 QCOM0519→QCOM2519）+ 删除 UFS0（QCOM24A5）的 `_DEP`（原本只有 `\_SB_.PEP0` 一项）。

## 构建

- 脚本：`Alioth-Engineering/tools/build-acpi-hid-phase17c.sh`
- 日志：`Alioth-Engineering/logs/mu-alioth-phase17c-build-20261021-111832.log`
- 镜像：`UEFI-Images/Mu-alioth-1-acpi-hid-phase17c-20261021-111925.img`
- SHA256：`740be78c41aca4a59125ce8292a0f12b6091684f6d74d0e5e471760cd45d387b`
- 校验：`phase17c_ufs0_no_dep: True` 等 ASL 检查全部通过；AML 含 QCOM2519/QCOM2509，无 0519/0509 残留；iasl 优化数 1176→1175（少了一个 _DEP Package）；iasl 9 个遗留错误不变；FVMAIN 剩余 552 字节。

## 构建前核实（Ubuntu 端，基于 Phase17 DSDT）

- DSDT 中共有 31 个设备 `_DEP` 依赖 PEP0：UFS0、SDC2、ABD、UARD、UR14/18/20、I2C5/8、IC10、SPI4、SCSS、ADSP、QWLN、PDSR、CDSP、SPSS、LLC、MMU1、GPU0、PCI0/1、IPA、GSI、QWPP、QDSS、CAMP、VFE0、URS1、UCP0、BTH0。
- **UFS0 只直接依赖 PEP0，没有经过其他设备间接依赖**（GIO0/SPMI/SCM0 都不依赖 PEP0）。所以只删 UFS0 的 `_DEP`，就足以保证开机不再因 UFS 等待 PEP0 而出现 0x7B。
- qcpep.wd8250.inf：PEP0 的实例 ID 预计是 `ACPI\VEN_QCOM&DEV_2519&SUBSYS_MTP08250...`，它不匹配 MTPC/HAZD 专用节，会落到通用的 `ACPI\QCOM2519` → `Pep_Device`。PEP 资源（`Resources\VRDL/NSTC/DSGP/DMPP/GBDL/CCGP/HLCB/SRDL`、`SystemLibResources\LVDD/LPDC/LPCU/LDCV`，AeoB 格式）由 `.NT.HW` 的 AddReg 写入设备硬件键，**必须经过一次完整的 INF 安装才会存在**。服务是 BOOT_START，LoadOrderGroup=Base。
- 证据说明：回退到 Phase16 后 `Enum\ACPI\QCOM2519` 不存在，这**不能**单独证明假设 B。Phase17 开机时如果 PEP0 已在内存中的 SYSTEM hive 里建立，蓝屏前 hive 没来得及写回磁盘，键同样会丢失。A/B 要靠 Phase17c 来区分。

## 手机端判定（fastboot boot，不要 flash；回退用 Phase16 镜像）

| 现象 | 结论 | 下一步 |
| --- | --- | --- |
| 正常开机，PEP0 = `ACPI\VEN_QCOM&DEV_2519...` 已安装 qcpep，但 Code 10/31 等 | A：qcpep8250 能加载，但启动失败 | 抓 qcpep 的 WPP/ETW 和 CI 事件，查失败点 |
| 正常开机，PEP0 已装 qcpep，状态 OK（可能需要再重启一次） | B 成立，PEP 链路打通 | 查 `DeviceClasses\{55beca03}`、MMU1/MMU0、ADSP |
| 正常开机，PEP0 安装后再重启出现蓝屏 | qcpep 初始化导致崩溃 | 记下蓝屏代码，回退 Phase16，分析 dump |
| 依旧 0x7B | UFS 还有别的依赖链（与静态分析不符） | 回退，取 dump |

需要导出的证据：PEP0 实例的 Service/ProblemCode/ProblemStatus、`Device Parameters\Resources` 是否有 VRDL 等值、setupapi.dev.log 中的 QCOM2519 段、`Control\DeviceClasses\{55beca03-...}`、MMU1/ADSP 状态。
