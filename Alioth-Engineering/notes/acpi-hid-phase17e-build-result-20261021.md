# Phase17e UEFI 构建结果（2026-10-21）

## 镜像（两种桩方案一起构建，省一轮往返）

| 方案 | 镜像 | SHA256 |
| --- | --- | --- |
| `PEP_STUB=all`（清空全部 27 个设备配置方法） | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17e-all-20261021-153806.img` | `8b41220db9af0da802f325d0b285e1d42a4d8a5aaee78ecb5c8d41843d5dfdab` |
| `PEP_STUB=storage`（只清空 BPMD/SDMD） | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17e-storage-20261021-153855.img` | `e44c0da6c079747670e807bbc371b0b075622e2c095843c5e1b8ae44ae2244d5` |

- 日志：`logs/mu-alioth-phase17e-all-build-20261021-153717.log`、`logs/mu-alioth-phase17e-storage-build-20261021-153806.log`
- 两版 49 项检查全部 True（含 `phase17e_stub_count`）；UFS0 `_DEP` 与 PEPH 都识别为"已改，跳过"；AML 无 0519/0509 残留；iasl 9 个遗留错误不变（Remarks 增加只是改名后的方法没人引用）。
- storage 版的 `DSDT.asl` 相对 Phase17d 只有 BPMD、SDMD 两处变化（已 diff 确认）。Ubuntu 上 `DSDT.asl` 当前停留在 storage 状态，脚本每次运行都会先撤销旧桩，不影响下次构建。

## 静态核实：qcpep8250 怎样读取 PEP0 的配置方法

- DSDT 内部**没有任何地方**调用 APMD/GPMD/G0MD/BPMD/SDMD/CPMX/C0MD/BSMD/LPMD/MPMD 等方法，它们只可能由 qcpep 读取。
- qcpep8250.sys 中**找不到**这些名字：ASCII、UTF-16、mov/movk 拼接常量都没有；也没有以 `MD` 为后缀做比较的指令。
- 驱动中所有 ACPI 求值点（IOCTL 0x32C004，`AeiB`/`AeiC` 输入）求值的方法名只有：`PEPH`（0x3da80，ID 校验）、`SOCI`（0x57d08）、`THTZ`（0xc9a58）、`GEPT`（0x203304），其余 4 字符常量是内存池标记 `qpep/qpev/qpeH`。驱动中也没有 `IOCTL_ACPI_ENUM_CHILDREN`（0x32C020）。
- 推断：设备配置方法是通过 ACPI 接口函数表（不经 IOCTL 常量）枚举 PEP0 子对象读取的，具体机制静态上无法完全确认。
- **判读风险**：如果 qcpep 把空包 `Package(Zero){}` 当作非法配置并提前退出初始化（像 17c 的 PEPH 失败那样），all 版也会"能开机"，但这不能说明设备配置是卡死的原因。所以开机后**必须看 PEP0 自身的状态**。

## 手机端判读（fastboot boot，不要 flash；保持 qcsmmu、qcsubsys 的 Start=4 和 qcpep 参数不变）

先测 all：

| all 的结果 | PEP0 状态 | 结论 / 下一步 |
| --- | --- | --- |
| 能开机 | OK（已启动） | 卡死来自某个设备配置 → 测 storage；storage 能开机就继续在剩余方法里二分，storage 卡死就锁定 BPMD/SDMD |
| 能开机 | Code 10/31 等 | qcpep 因空包提前退出，**结论无效** → 改用"只改名不留桩"（删掉方法），或抓 qcpep WPP（`WppRecorder_TraceGuid={a77e292c-44cf-4821-907a-93ac09231a2d}`）看在哪一步退出 |
| 仍然卡死 | — | 卡死来自 PEP 核心（INTR/PPPM/CTPM/STND，PMIC/RPMh/AOP 初始化）→ 转向核心配置 |

需要记录：PEP0 的 ProblemCode/ProblemStatus、`Control\DeviceClasses\{55beca03-...}` 是否存在。
