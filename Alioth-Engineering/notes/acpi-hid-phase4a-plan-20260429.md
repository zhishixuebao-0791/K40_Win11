# ACPI HID Phase4a Plan

## Goal

Continue the ACPI-side HID remap approach proven by Phase3, but keep the next test narrow and reversible.

## Inputs

- Phase3 result note: `Alioth-Engineering/notes/acpi-phase3-state-analysis-20260429.md`
- Mu-Silicium alioth DSDT: `sound_code/Mu-Silicium/Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.asl`
- Expected output image pattern: `UEFI-Images/Mu-alioth-1-acpi-hid-phase4a-*.img`

## Scope

Patch only dependency devices that were already present in the Phase3 Windows runtime but still had no bound driver:

| Device | Current ACPI HID | Kona driver HID | Driver |
| --- | --- | --- | --- |
| `SCM0` | `QCOM050B` | `QCOM250B` | `qcscm8250.inf` |
| `GLNK` | `QCOM058D` | `QCOM258D` | `qcglink8250.inf` |

Phase4a also preserves the Phase3 remaps:

- `PILC`: `QCOM051B -> QCOM251B`
- `RPEN`: `QCOM0533 -> QCOM2533`

## Explicit Non-Goals

Do not change these in Phase4a:

- `IPC0`: `QCOM050E -> QCOM250E`
- `ADSP`: `QCOM051D -> QCOM251D`
- `QSM`: `QCOM0520 -> QCOM2520`
- `SSDD`: `QCOM0522 -> QCOM2522`
- `ARPC`: `QCOM0560 -> QCOM2560`
- `ARPD`: `QCOM058A -> QCOM258A`
- `PDSR`: `QCOM057C -> QCOM257C`
- `TFTP`: `QCOM058B -> QCOM258B`
- `SMMU`: `QCOM0509 -> ACPI\VEN_QCOM&DEV_2509&REV_0001/0002`

Reason: changing only `SCM0` and `GLNK` lets us isolate whether the next dependency layer improves `qcPILC` and downstream audio enumeration.

## Build Command

On this Ubuntu machine, PowerShell is not installed, so use the native Bash wrapper:

```bash
/home/ucchip/K40_Win11/tools/build-acpi-hid-phase4a.sh
```

If PowerShell Core is installed later, this command is also valid:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "/home/ucchip/K40_Win11/tools/build-acpi-hid-phase4a-wsl.ps1" -Clean
```

If build dependencies need to be installed again:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "/home/ucchip/K40_Win11/tools/build-acpi-hid-phase4a-wsl.ps1" -Clean -SetupApt
```

## Validation

First boot with `fastboot boot`, not permanent flash. After Windows starts, rerun:

- `D:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRoots.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRootCauses.ps1`

Expected useful signs:

- `ACPI\QCOM250B` exists and binds to `qcscm`.
- `ACPI\QCOM258D` exists and binds to `qcglink`.
- `QCOM050B/QCOM058D` are stale or absent as active devices.
- `QCOM251B/qcPILC` changes from Code 31 or starts.
- More downstream audio-related ACPI nodes may appear.
