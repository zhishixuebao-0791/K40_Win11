# Phase17h 构建结果（Ubuntu，2026-10-22）

## 镜像
| 镜像 | 内容 | SHA256 |
| --- | --- | --- |
| `UEFI-Images/Mu-alioth-1-acpi-hid-phase17h-pep8280-dbg2-20261022-164416.img` | 17e-all DSDT，PEP0 `_HID`/PEPH 改为 QCOM0617；打包修复版 DBG2 | `617ed5c918c78bc2c67930f0f15ea938e75949864ab04884e6395a2448779c76` |

- 构建日志：`logs/mu-alioth-phase17h-build-20261022-164416.log`，`build_uefi.sh` 退出码 0。
- FVMAIN：100% 满（0 字节空闲，与 17g-pep 相同；0617 与 2519 等长，DSDT 大小不变）。以后若再往 pep 变体里加内容，需要先腾空间。

## 构建前提与校验（脚本输出，全部 True）
- 前提：PEP0 `_HID`=QCOM2519（1 处）、PEPH=`VEN_QCOM&DEV_2519`（1 处）、17e-stub 27 个、尚无 0617、SMMU=QCOM2509（2 处）。
- 修改后：`_HID`=QCOM0617、PEPH=`DEV_0617`，无 2519 残留；AML 中同样核对通过。
- FVMAIN.Fv 中同时含修复版 DBG2（SHA256 b49338c2…b200）和本次 DSDT.aml。
- 构建后 DSDT.asl、ACPI.inc、Kona/DBG2.aml 与 `.pre-phase17h-20261022-164416.bak` 逐字节一致，Ubuntu 侧仍是 17e-all 状态。

## 未能在 Ubuntu 侧核实的部分
- qcpep8280.sys / qcpep.wd8280.inf 不在 Ubuntu 工作区（`sound_code/driver_candidates` 不存在），所以"8280 驱动不含 SM8150 LMH/OSM 地址""INF 认 ACPI\QCOM0617"两点没有在这边复核，沿用 Windows 侧的结论。

## 手机端步骤（同计划文档）
1. Mass Storage：`tools\Apply-Phase17hQcpep8280Inject-Admin.ps1 -WindowsDrive D`（先备份 Services\qcpep，再 DISM 注入）。
2. 电脑端先启动 kd 桥接（`-b`），再 `fastboot boot` 本镜像（不要 flash）。
3. 判读：正常进桌面且 `{55beca03}` 出现 → 逐步恢复 qcsmmu/qcsubsys Start=3；卡死 → kd Break 看 CPU 停在哪个驱动/地址；Code 31/10 → 查 PEPH 比对或 8280 平台资源配置。
