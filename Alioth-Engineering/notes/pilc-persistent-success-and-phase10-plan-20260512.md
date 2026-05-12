# PILC persistent success and Phase10 plan - 2026-05-12

## Inputs

- `D:\Code\REDMIK40_Win11\PilcStartFailureDeep_20260512_094526`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260512_100543`

## Current result

`qcPILC` is no longer the active blocker.

- `ACPI\QCOM06E0\2&DABA3FF&0` is present and `Status=OK`.
- Service is `qcPILC`.
- Stack is `\Driver\qcPILFC;\Driver\qcPILC;\Driver\ACPI`.
- The device exposes `SUBSYS_MTP08280`, and the Surface 8280 extension entries are present.

`SSDD` is also stable on the Surface 8280 path.

- `ACPI\QCOM0620\2&DABA3FF&0` is present and `Status=OK`.
- Service is `qcsubsys`.
- Providers are `QCOM258D`, `QCOM257C`, and `QCOM258B`, all already working in the current trace.

## New blocker

`QSM` is now visible but has no driver binding.

- Instance: `ACPI\QCOM0520\2&DABA3FF&0`
- Role: Subsystem service manager
- Status: Error
- ProblemCode: 28
- Service: empty
- Driver: empty
- Hardware IDs include `ACPI\VEN_QCOM&DEV_0520&SUBSYS_MTP08250`, `ACPI\QCOM0520`, `*QCOM0520`.

The current Surface Pro 9 5G 8280 candidate does not provide a usable `QCOM0520` or `QCOM2520` match. `qcsubsys8280.inf` only names the service-manager description string, but its install section supports the following relevant HIDs:

- `ACPI\QCOM061B` for ADSP
- `ACPI\QCOM0620` for SSDD
- `ACPI\QCOM06B0` for CDSP
- `ACPI\QCOM068D` for SPSS
- `ACPI\QCOM061F` for SCSS

## Direction

Do not continue with WDAC experiments or broad 8250 driver injection at this point. The stable path is now Surface 8280-style ACPI exposure.

Phase10 should keep the working pieces unchanged:

- Keep `PILC` as `QCOM06E0`.
- Keep `SSDD` as `QCOM0620`.
- Keep the working dependency aliases for `RPEN`, `SCM0`, `GLNK`, `IPC0`, `PDSR`, and `TFTP`.

Phase10 should focus on exposing the remaining DSP roots through Surface 8280-compatible HIDs:

- `ADSP`: native `QCOM051D` -> Surface 8280 `QCOM061B`
- `CDSP`: native `QCOM0523` -> Surface 8280 `QCOM06B0`
- `SPSS`: native `QCOM0599` -> Surface 8280 `QCOM068D`
- `SCSS`: native `QCOM0521` -> Surface 8280 `QCOM061F`

Defer `QSM QCOM0520 -> QCOM2520`. That route belongs to the old 8250 driver path and previously caused signature/WDAC risk. Only test it later if logs prove QSM Code 28 blocks the 8280 DSP path after Phase10.

## Validation changes

`Trace-AliothAudioDependencyState.ps1` now records native and Surface 8280 target rows separately for:

- `CDI native / QCOM0532`
- `SCSS native / QCOM0521`
- `ADSP native / QCOM051D`
- `CDSP native / QCOM0523`
- `SPSS native / QCOM0599`
- `ADSP 8280 / QCOM061B`
- `CDSP 8280 / QCOM06B0`
- `SPSS 8280 / QCOM068D`
- `SCSS 8280 / QCOM061F`
- `QSM native / QCOM0520`
- `QSM 8250 / QCOM2520`

Run this updated diagnostic after the next UEFI build boots, then compare whether the 8280 DSP roots appear and bind before touching more drivers.
