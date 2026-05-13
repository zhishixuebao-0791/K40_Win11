# Phase11 Validation and Phase12 Plan - 2026-05-13

## Inputs

- UEFI: `Mu-alioth-1-acpi-hid-phase11-20260513-141246.img`
- ACPI state: `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260513_125356`
- Dependency state: `D:\Code\REDMIK40_Win11\AudioDependencyState_20260513_130117`

## Result

Phase11 is effective.

The Phase11 `_DEP` reduction made all three previously missing DSP roots enumerate:

| Device | Instance | Driver | State |
| --- | --- | --- | --- |
| ADSP | `ACPI\QCOM061B\2&DABA3FF&0` | `qcsubsys`, `oem15.inf` | Code 31, `0xC0000034` |
| CDSP | `ACPI\QCOM06B0\2&DABA3FF&0` | `qcsubsys`, `oem15.inf` | Code 31, `0xC0000034` |
| SCSS | `ACPI\QCOM061F\2&DABA3FF&0` | `qcsubsys`, `oem15.inf` | Code 31, `0xC0000034` |
| SPSS | `ACPI\QCOM068D\2&DABA3FF&0` | `qcsubsys`, `oem15.inf` | Code 31, `0xC000003B` |

This confirms the Phase10 blocker was ACPI dependency gating, not driver matching or WDAC.

Working dependencies remain stable:

- `QCOM06E0` / `qcPILC`: OK
- `QCOM2533` / `QCRPEN`: OK
- `QCOM250B` / `qcscm`: OK
- `QCOM258D` / `qcGLINK`: OK
- `QCOM250E` / `QCIPC_ROUTER`: OK
- `QCOM257C` / `qcpdsr`: OK
- `QCOM258B` / `QcTftpKmdf`: OK
- `QCOM0620` / `qcsubsys`: OK

Remaining unresolved nodes:

- `QCOM0532` / `CDI_`: Code 28, no driver binding.
- `QCOM0520` / `QSM_`: Code 28, no driver binding.
- `FSA04480`: Code 51; not on the critical path for DSP-root enumeration.

## Interpretation

The current blocker is now `qcsubsys8280.sys` runtime start failure on the DSP-root child devices.

`0xC0000034` usually means the driver could not find a required object/resource/name during start. For these ACPI devices, the likely missing inputs are ACPI methods/resources/properties expected by Surface/8280 `qcsubsys`, not signature or INF matching.

Do not continue broad driver injection. The driver is already installed, trusted enough to load, and bound to the devices.

## Phase12 Direction

Phase12 should inspect and patch the ACPI shape/resources for `ADSP`, `CDSP`, `SCSS`, and `SPSS`.

Priority checks:

1. Compare working `SSDD/QCOM0620` and failing DSP roots in DSDT:
   - `_CRS`
   - `_DSD`
   - `_DSM`
   - `_DEP`
   - `_UID`
   - `_SUB`
   - any `Package()` property values consumed by `qcsubsys`

2. Compare Surface/8280 expected ACPI shape from `windows_qcom_platforms` or Surface driver INF assumptions:
   - IDs: `QCOM061B`, `QCOM06B0`, `QCOM061F`, `QCOM068D`
   - required compatible IDs: especially `ACPI\QCOMFFE6` on CDSP
   - subsystem name/property fields

3. Build a diagnostic script to dump offline/online ACPI registry property bags for these devices:
   - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM061B`
   - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM06B0`
   - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM061F`
   - `HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM068D`
   - compare against `QCOM0620`

4. Only after confirming missing ACPI properties, build Phase12 UEFI.

The next UEFI patch should be smaller than Phase11: keep the Phase11 `_DEP` success, then add only the minimum ACPI resources/properties required to move `qcsubsys` from Code 31 to started.
