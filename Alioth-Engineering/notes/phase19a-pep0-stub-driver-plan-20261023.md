# Phase19a：PEP0 桩驱动 pep0stub（2026-10-23）

## 目的
qcpep8250 / qcpep8280 在 SM8250 上都会访问不存在的硬件而卡死（突破 11、12），桩开关路线又出现 0x10D（突破 13 之后），IORT 路线是死路（死路 13、14）。
qcsmmu8280 / qcsubsys8280 对 PEP 的需求已经静态分析清楚（notes/pep-stub-interface-analysis-20261023.md），所以自己写一个只提供这两个接口的桩驱动来代替 qcpep。

## 驱动
- 源码：`drivers/pep0_stub/pep0stub.c`；INF：`pep0stub.inf`；打包：`build-pkg.sh` → `pkg/`（sys 与 cat 均用 CN=K40 Alioth Test Driver Signing 测试签名）。
- 绑定 `ACPI\QCOM0519`（Phase16 / phase17g-base 镜像中 PEP0 的原始 HID，不用改 UEFI；qcpep 的两个 INF 分别认 2519、0617，不会抢）。
- KMDF 1.15，服务名 `pep0stub`，StartType=0（开机启动，Base 组）。原因：UFS0 等大量设备的 `_DEP` 依赖 `\_SB.PEP0`，必须在开机阶段就成功启动（Phase17b 教训）。
- 提供的内容：
  - 设备接口 `{55beca03-ba2c-4fbc-9efc-ee8eca56f0c7}`（KMDF 功能驱动默认放行 IRP_MJ_CREATE）；
  - QueryInterface `{a0e1dd36-dfb9-4c0e-bbaa-78f0746be181}`：Size 0x28、Version 1，+0x20 函数 `NTSTATUS f(PVOID 资源缓冲区)`，IRQL>PASSIVE 返回 STATUS_ACCESS_DENIED，否则 STATUS_SUCCESS；
  - 不提供 `{99f8bbdb}`（首测观察 GPU / 显示是否受影响）。
- 不访问任何 MMIO，不调用 PoFxRegisterPlugin。
- 调试输出（kd 中可见，前缀 `pep0stub: `）：DriverEntry、AddDevice 完成、每次 RegisterResources 调用（含缓冲区地址）。

## 测试步骤
1. 手机进 Mass Storage（盘符最近是 D:），电脑端管理员 PowerShell：
   `powershell -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Apply-Pep0Stub-Offline-Admin.ps1" -WindowsDrive D`
2. 电脑端先启动 kd 桥接（tools/kd_bridge.py），再 `fastboot boot` phase17g-base 镜像（`UEFI-Images\Mu-alioth-1-acpi-hid-phase17g-base-dbg2-20261022-151745.img`）。
3. 第一次开机：PEP0 在用户态由 PnP 安装 pep0stub 并启动。qcsmmu 的 AddDevice 早在开机阶段就失败了，不会自动重试，所以要**再重启一次**（第二次开机 pep0stub 作为开机驱动先启动）。
4. 第二次开机后检查：
   - PEP0：没有问题码，Service=pep0stub；
   - `DeviceClasses\{55beca03-...}` 存在；
   - MMU1（qcsmmu8280）：Code 31 是否消失；kd 中能看到 `pep0stub: RegisterResources #n`（SMC 资源文件 SMMC.bin）；
   - 显示 / GPU / 触摸是否正常。
5. SMMU 通过后，下一步（Phase19b）把 qcsubsys 的 Start 改回 3，观察 ADSP 是否离开 0xC000003B。

## 判读
| 现象 | 含义 / 下一步 |
|---|---|
| 第二次开机 0x7B | pep0stub 开机阶段没启动成功 → 用 `tools\Disable-Pep0Stub-Offline-Admin.ps1` 回滚，kd 看 DriverEntry / AddDevice 输出 |
| PEP0 正常，MMU1 仍 Code 31 | kd 看是否出现 RegisterResources 调用；没有调用 → QueryInterface 被拒（核对 Size/Version）；有调用 → SMMU 在后续步骤失败，抓 WPP |
| MMU1 正常 | 突破，进入 Phase19b |
| 显示 / GPU 异常 | 评估补 {99f8bbdb}（3 个函数返回 SUCCESS） |

## 回滚
`powershell -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Disable-Pep0Stub-Offline-Admin.ps1" -WindowsDrive D`
（Start=4，并删除 Enum\ACPI\QCOM0519 实例的 Service/Driver 值，让 PEP0 回到 Phase16 的"无驱动"状态。）
