# Phase17f UEFI 构建结果（2026-10-22）：带 DBG2，用于 KDNET over USB EEM

## 镜像

| 变体 | 内容 | 镜像 | SHA256 | FVMAIN 剩余 |
| --- | --- | --- | --- | --- |
| `VARIANT=pep` | 17e-all（PEP0=2519、PEPH=2519、UFS0 无 _DEP、27 个设备配置方法清空）+ DBG2 | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17f-pep-dbg2-20261022-145918.img` | `b421b66ab5eb17e7f0f2247f416adc9505e12ebbfc2d708b3b51b62b9a66bc78` | **0 字节（100%）** |
| `VARIANT=base` | Phase16 + DBG2（PEP0 仍为 0519，能正常开机） | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17f-base-dbg2-20261022-150011.img` | `874e5d437bd50f4d6a044f5ceab2b3788098a42d099715595b15171fcacfa580` | 280 字节 |

日志：`logs/mu-alioth-phase17f-pep-build-20261022-145918.log`（内含调用的 `mu-alioth-phase17e-all-build-20261022-145918.log`）、`logs/mu-alioth-phase17f-base-build-20261022-150011.log`。

## 校验

- ACPI.inc 中 DBG2 的 `!if $(TARGET) == DEBUG` 已在构建期间去掉，构建结束后 ACPI.inc 恢复，与构建前备份**逐字节一致**。
- 两个变体都在 `Build/.../FV/FVMAIN.Fv` 和对应的 FFS（`7E374E25-…`，ACPI 表文件）中找到了 Kona DBG2 的 256 字节原始数据。最终 .img 中的 FV 是 LZMA 压缩的，所以在 img 中直接搜索原始字节搜不到，这是正常的。
- base 变体的 DSDT 备份检查全部通过（SMMU=2509、PEP0=0519、PEPH=0519、无 17e 桩、PILC 含 MTP08280），构建后 DSDT.asl 已恢复为叠加状态（17e-all）。
- pep 变体沿用 17e 检查（49 项 True）。

## 需要注意

- **pep 变体的 FVMAIN 已经 100% 满**（DBG2 约 260 字节，加上 17e 桩，把剩下的 552 字节用完了）。以后在这个基础上再往 FVMAIN 加任何东西（DXE、ACPI 表、DSDT 变大）都会构建失败。到时要么删掉不用的 DXE，要么把 17e 桩换成更短的写法。
- USB 前提：alioth 的 `APRIORI.inc` 每次开机都会加载 `UsbPwrCtrlDxe`/`UsbfnDwc3Dxe`/`UsbConfigDxe`/`UsbInitDxe`，所以进入 Windows 前 USB 控制器和 PHY 已由 UEFI 初始化，满足 kd_8003_5143 不自己初始化 PHY 的前提。如果 base 变体下电脑仍然完全枚举不到设备，再查 UsbConfigDxe 在 ExitBootServices 时是否把控制器复位或断电。

## 手机端测试顺序（fastboot boot，不要 flash）

1. **先用 base 变体验证 KD 通道**（能正常开机，排除 qcpep 干扰）：
   - BCD 已设 `debug on`、`net`、`hostip 169.254.255.255`、`port 50005`、`key 1.2.3.4`、`dhcp no`、`busparams 0`。
   - 手机直连电脑（不要接扩展坞），电脑端看是否出现 KDNET USB EEM 网卡，WinDbg `windbg -k net:port=50005,key=1.2.3.4` 是否连上。
   - 连不上：Mass Storage 下用 `Export-KdnetState-Offline-Admin.ps1` 看是否出现 `Services\kdnet` 及 `KdInitStatus`/`KdInitResultString`。
2. **通道通了再用 pep 变体**：`sxe ld:qcpep8250.sys`，断下后对 DriverEntry、EvtDriverDeviceAdd、PrepareHardware/D0Entry 以及 PPP、GLINK（xport_qmp）初始化函数下断点，看卡死前最后命中的是哪一个；卡死后尝试 Break（Ctrl+Break），用 `!running -it`、`~*k` 看各 CPU 的调用栈。
3. 如果 Break 也没反应（总线挂死），就靠断点二分缩小到具体函数，再对照反汇编看它访问了哪个物理地址。
