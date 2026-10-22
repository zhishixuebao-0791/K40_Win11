# Phase17g UEFI 构建结果（2026-10-22）：修复 Kona DBG2 的 OEM 数据（KDNET USB EEM）

## 镜像

| 变体 | 内容 | 镜像 | SHA256 | FVMAIN 剩余 |
| --- | --- | --- | --- | --- |
| base | Phase16 + 修复后的 DBG2（能正常开机，用来验证 KD 通道） | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17g-base-dbg2-20261022-151745.img` | `bf5de848f4483526ab141eb2014511c83ee004d0f49493d2e771002811e74f52` | 280 字节 |
| pep | 17e-all + 修复后的 DBG2（调试 qcpep 卡死） | `UEFI-Images/Mu-alioth-1-acpi-hid-phase17g-pep-dbg2-20261022-151836.img` | `8036e1c6d0046f5c5a5be9347060a332d5654625ecacce395e7ecd971fc51934` | 0 字节（100%） |

日志：`logs/mu-alioth-phase17g-base-build-20261022-151745.log`、`logs/mu-alioth-phase17g-pep-build-20261022-151836.log`（内含 `mu-alioth-phase17e-all-build-20261022-151836.log`）。

## 构建前独立核实修复表 `acpi/Kona-DBG2-oemfix.aml`

- SHA256 与脚本内置值一致；长度 256，校验和 0；除 OEM 区和校验和字节外，与 Silicium 原 Kona 表**0 字节差异**。
- 原 Kona 表的 OEM 区以 `DBG2 00010000 01 39 QCOM...` 开头，确实是一份 DBG2 表头（不是 OEM 修补数据），`+4` 处没有 `2XIF`。
- Silicium 中 Hana/Lahaina/Waipio/Kailua/Kodiak/Moorea 的 DBG2 都带有 `\_SB.URS0`（基址 0xa600000，0x8003/0x5143）的 USB 调试设备，OEM 长度都是 0x94、签名 `2XIF`。其中**第一个 URS0 条目的 OEM 数据与修复表逐字节一致**（6 个 SoC 全部一致）。
- 这些表里每个 SoC 都有**两个** URS0 条目，修补内容不同：
  - 条目 A（修复表采用）：`0xc700 &= ~7`（DCFG 速度为 High Speed）、阶段 2 `0xf8810 = 0x10100000`（强制 VBUS/会话有效）、`0xf88b4 = 0xdeb`。在原表中是 1 号设备，对应微软文档对高通机型默认的 busparams 1。
  - 条目 B（备选）：`0xc704 &= 0xffffe1ff`（清 DCTL bit 9–12）、**阶段 1** 就强制 VBUS 有效、`0xf88b4 = 0xdeb`。
  - 两者都强制 VBUS 有效，所以修复 Phase17f 卡住问题的关键在两边都有。如果条目 A 下电脑端能枚举但连接不稳，或者完全枚举不到，可以再做一份条目 B 的表试一下（只换 OEM 区）。

## 构建校验

- 两个变体：构建前检查 DBG2 校验和为 0、设备数 1、0x8003/0x5143、OEM+4 = `2XIF`，都通过。
- pep 构建完成后直接检查 `FVMAIN.Fv`：**包含修复后的表，不包含原表**。base 构建由脚本在同样状态下检查 FV。
- 构建结束后 `Kona/DBG2.aml` 恢复为原表、`ACPI.inc` 恢复原样（均已用 cmp 与备份逐字节比对）；DSDT.asl 停在 17e-all 叠加状态。
- 已清理脚本 mktemp 留在 /tmp 的临时目录。

## 手机端测试

- phase17f-base/pep 两个镜像会卡在 KD 等待连接，**不要再用**。
- 先 `fastboot boot` phase17g-base（手机直连电脑，BCD busparams 0）：
  - 看电脑端是否出现 KDNET USB EEM 设备，WinDbg `-k net:port=50005,key=1.2.3.4` 是否连上；连上后 `g` 继续，看能否正常进入桌面。
  - 仍然停在 Silicium 画面、电脑什么都看不到：长按电源键 + 音量下强制重启，Mass Storage 下取证（`Export-KdnetState-Offline-Admin.ps1`），再考虑条目 B，或查 UEFI ExitBootServices 时 USB 是否被断电。
- 通道通了再用 phase17g-pep，按 17f 笔记的步骤调试 qcpep（`sxe ld:qcpep8250.sys`、断点二分、卡死后 Break 看各 CPU 调用栈）。
