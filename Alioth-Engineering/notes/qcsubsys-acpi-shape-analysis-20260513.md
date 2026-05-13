# Qcsubsys ACPI Shape Analysis - 2026-05-13

## Inputs

- UEFI: `Mu-alioth-1-acpi-hid-phase11-20260513-141246.img`
- Trace: `D:\Code\REDMIK40_Win11\QcsubsysAcpiShape_20260513_143537`

## Key Findings

The trace summary incorrectly reported every target as `<not present>` because the script only trusted `Get-PnpDevice`. The registry fallback shows the devices do exist under:

- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM0620`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM061B`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM06B0`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM061F`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM068D`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM06E0`
- `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM2533`

Driver binding is correct:

| Device | Driver | Notes |
| --- | --- | --- |
| `QCOM0620` | `qcsubsys`, `oem15.inf` | Known working SSDD/dependency node |
| `QCOM061B` | `qcsubsys`, `oem15.inf` | ADSP root, start failure |
| `QCOM06B0` | `qcsubsys`, `oem15.inf` | CDSP root, start failure |
| `QCOM061F` | `qcsubsys`, `oem15.inf` | SCSS root, start failure |
| `QCOM068D` | `qcsubsys`, `oem15.inf` | SPSS root, start failure |
| `QCOM06E0` | `qcPILC`, `oem16.inf` | Working PIL dependency |
| `QCOM2533` | `QCRPEN`, `oem7.inf` | Working reset/power dependency |

The active `qcsubsys` binary is from the Surface Pro 9 5G candidate:

- `C:\Windows\System32\DriverStore\FileRepository\qcsubsys8280.inf_arm64_aa16b5350e005f78\qcsubsys8280.sys`
- Version: `1.0.0.17556`
- Signature: Microsoft Windows Hardware Compatibility Publisher, valid catalog signature

SetupAPI confirms driver selection is successful and start is the failing stage:

- `QCOM061B`: `CM_PROB_FAILED_ADD`, `0xc0000034`
- `QCOM06B0`: `CM_PROB_FAILED_ADD`, `0xc0000034`
- `QCOM061F`: `CM_PROB_FAILED_ADD`, `0xc0000034`
- `QCOM068D`: `CM_PROB_FAILED_ADD`, `0xc000003b`

The new suspicious data point is:

- `QCOM061B\...\Device Parameters\PDInfo\NumPDs = 0`

This suggests the driver can bind to the ACPI node but cannot discover the expected protection-domain/subsystem metadata at runtime.

## Script Fix

`Trace-QcsubsysAcpiShape.ps1` has been fixed to use both:

- PnP API: `Get-PnpDevice` / `Win32_PnPEntity`
- Registry fallback: `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\<ID>`

This avoids false `<not present>` results when the device exists in Enum registry but is not returned by the PnP cmdlet.

## Next Direction

Do not change WDAC or broad driver packages now.

Phase12 should compare and patch ACPI property/resource shape for `ADSP/CDSP/SCSS/SPSS`, with priority on fields that may populate `PDInfo`:

1. Compare working `QCOM0620` against failing `QCOM061B/QCOM06B0/QCOM061F/QCOM068D`.
2. Inspect DSDT for `_DSD`, `_DSM`, `_CRS`, `_DEP`, `_UID`, `_SUB`, and subsystem/protection-domain property packages.
3. Compare against `windows_qcom_platforms` Surface 8280 ACPI expectations.
4. Build a very small Phase12 UEFI only after identifying the missing ACPI metadata.

## Phase12 Build Update

Phase12 UEFI has been built on Ubuntu.

- Build script: `/home/ucchip/K40_Win11/Alioth-Engineering/tools/build-acpi-hid-phase12.sh`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase12-build-20260513-195237.log`
- Output image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase12-20260513-195332.img`
- SHA256: `63b32591f672fbb95a63eb1162da8e8a98f28f1785628e86ef9a49b5a4922750`

Phase12 keeps the Phase11 `_DEP` reduction and adds standard `_DSD` metadata to the four qcsubsys roots:

- RPEC GUIDs for `ADSP`, `CDSP`, `SCSS`, and `SPSS`
- Interface GUID lists for PIL TZ, FastRPC, and GLINK where appropriate
- ADSP audio PD metadata: `PDInfo.NumPDs = 1`, `PDInfo.0.PDName = msm/adsp/audio_pd`, `PDInfo.0.GUID = {0A35A787-A69F-4A90-8B78-0710BA7BB82C}`

Validation remains required on the phone. If Code 31 remains unchanged, the next branch should treat these values as registry-backed qcsubsys inputs rather than ACPI `_DSD` inputs.
