# ACPI HID Phase10 Build Result - 2026-05-12

## Build host

- Ubuntu project root: `/home/ucchip/K40_Win11`
- Build script: `/home/ucchip/K40_Win11/Alioth-Engineering/tools/build-acpi-hid-phase10.sh`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase10-build-20260512-131331.log`

## Phase10 change

Phase10 keeps the working Phase9A pieces unchanged:

- `PILC` remains `QCOM06E0`.
- `PILC._SUB` remains `MTP08280`.
- `SSDD` remains `QCOM0620`.
- `QSM` remains native `QCOM0520`.
- `CDI` remains native `QCOM0532`.

Phase10 exposes the remaining DSP roots through Surface 8280-compatible HIDs:

- `ADSP`: `QCOM051D` -> `QCOM061B`
- `CDSP`: `QCOM0523` -> `QCOM06B0`
- `SPSS`: `QCOM0599` -> `QCOM068D`
- `SCSS`: `QCOM0521` -> `QCOM061F`

The target DSP root devices also return `_SUB = "MTP08280"` so the Surface 8280 extension INF packages can match by `SUBSYS_MTP08280` if Windows reaches that stage.

## AML verification

Compiled AML checks passed:

- `QCOM06E0`: present
- `QCOM0620`: present
- `QCOM061B`: present
- `QCOM06B0`: present
- `QCOM068D`: present
- `QCOM061F`: present
- `QCOM0520`: present
- `QCOM0532`: present
- stale `QCOM051D/QCOM0523/QCOM0599/QCOM0521`: absent
- `MTP08280` count: 5

`iasl` still reports the upstream legacy ACPICA errors already seen in previous phases, so the build continues with forced AML output.

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase10-20260512-131428.img`
- SHA256: `ea83ab834abe8da7329e201b6cf355604e9f6090a84db17bd96d0b4f92b1056d`

## Win10 validation steps

Copy the image back to:

```text
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase10-20260512-131428.img
```

Boot or flash it, then in phone Windows run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

Decision points:

- `PILC/QCOM06E0` must remain `Status=OK`.
- `SSDD/QCOM0620` must remain `Status=OK`.
- Check whether `ADSP/QCOM061B`, `CDSP/QCOM06B0`, `SPSS/QCOM068D`, and `SCSS/QCOM061F` appear.
- If the new 8280 DSP roots appear but are Code 28, install only the matching Surface extension packages next.
- If they do not appear, inspect ACPI runtime shape before touching driver injection.
- If `QSM/QCOM0520` remains Code 28 but the 8280 DSP roots now appear, keep QSM isolated for a later experiment.
