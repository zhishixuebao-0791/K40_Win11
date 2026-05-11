# ACPI HID Phase9A Build Result - 2026-05-11

## Build Host

- Ubuntu project root: `/home/ucchip/K40_Win11`
- Build script: `/home/ucchip/K40_Win11/Alioth-Engineering/tools/build-acpi-hid-phase9a.sh`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase9a-build-20260511-174222.log`

## Phase9A Change

Phase9A keeps the Phase8 audio HID route and changes only the PILC subsystem identity:

- `PILC` remains exposed as `QCOM06E0`.
- `SSDD/qcsubsys` remains exposed as `QCOM0620`.
- `PILC._SUB` now returns `MTP08280`.

Target: let Windows naturally match the official Surface Pro 9 5G `qcpilEXT8280` package without relying on unsigned INF aliasing.

## Build Notes

The alioth base DSDT still has legacy ACPICA validation errors unrelated to this experiment. The script therefore compiles DSDT with forced AML output:

```bash
iasl -f -ve -p DSDT DSDT.asl
```

The compiled AML verification passed:

- `QCOM06E0`: present
- `QCOM0620`: present
- `MTP08280`: present
- stale `QCOM051B/QCOM251B/QCOM0522/QCOM2522`: absent

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase9a-20260511-174312.img`
- SHA256: `245d2b2dd515ae16df8954a246d551846df06b11f1d834fba69ce072edd25e34`

## Win10 Validation Steps

Copy the image back to:

```text
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase9a-20260511-174312.img
```

Flash or boot this UEFI, then boot Windows and run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcAcpiShape.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

Expected evidence:

- `QCOM06E0` hardware IDs should include `SUBSYS_MTP08280`.
- `QCOM06E0` compatible IDs should still include `ACPI\QCOM06E0`.
- `qcpilEXT8280` should bind naturally if the Surface candidate package is still installed.
- Main decision point: whether `QCOM06E0/qcPILC` changes from `ProblemCode=31` to `ProblemCode=0`, or fails with a new, more specific reason.
