# Phase12 Validation and Phase13 Plan - 2026-05-13

## Inputs

- Flashed UEFI: `Mu-alioth-1-acpi-hid-phase12-20260513-195332.img`
- `AcpiPhase3State_20260513_182309`
- `AudioDependencyState_20260513_183129`
- `QcsubsysAcpiShape_20260513_184200`

## Phase12 Result

Phase12 did not change the qcsubsys start outcome.

| Device | Role | Current result |
| --- | --- | --- |
| `QCOM0620` | SSDD dependency | OK, service `qcsubsys` |
| `QCOM06E0` | PIL dependency | OK, service `qcPILC` |
| `QCOM2533` | reset/power dependency | OK, service `QCRPEN` |
| `QCOM061B` | ADSP root | Code 31, `ProblemStatus=0xC0000034` |
| `QCOM06B0` | CDSP root | Code 31, `ProblemStatus=0xC0000034` |
| `QCOM061F` | SCSS root | Code 31, `ProblemStatus=0xC0000034` |
| `QCOM068D` | SPSS root | Code 31, `ProblemStatus=0xC000003B` |
| `QCOM0532` | CDI native node | Code 28 |
| `QCOM0520` | QSM native node | Code 28 |

SetupAPI still shows successful INF selection and failure during device start/AddDevice, so the active blocker remains qcsubsys runtime input shape, not driver binding, service creation, or Code Integrity.

## Important Delta

Phase12 AML contains:

- `PDInfo.NumPDs = 1`
- `PDInfo.0.PDName = msm/adsp/audio_pd`
- `PDInfo.0.GUID = {0A35A787-A69F-4A90-8B78-0710BA7BB82C}`
- ADSP/CDSP/SCSS/SPSS `RPEC`
- ADSP/CDSP/SCSS/SPSS `Interfaces`

The phone registry after boot still shows:

- `QCOM061B\...\Device Parameters\PDInfo\NumPDs = 0`
- no visible `PDInfo\0`
- no visible `msm/adsp/audio_pd`
- no visible `0\ADSP\RPEC`
- no visible `0\ADSP\Interfaces`

This strongly suggests standard ACPI `_DSD` properties are not being materialized into the registry shape consumed by `qcsubsys8280.sys`.

## Phase13 Direction

Do not build another UEFI image yet.

The next useful experiment is registry-backed and ADSP-scoped:

1. Patch only `ACPI\QCOM061B\2&daba3ff&0`.
2. Set ADSP `PDInfo` from the 8250 INF shape.
3. Set ADSP `RPEC` and `Interfaces` both under `Device Parameters\0\ADSP` and `0\ADSP`, because previous PIL experiments showed driver-visible values can exist in both shapes.
4. Boot once and run the same three diagnostic scripts.
5. If `QCOM061B` changes from `0xC0000034` or starts, then test child creation separately with `-IncludeChildren`.

Prepared scripts:

- `Alioth-Engineering\tools\Apply-QcsubsysPhase13AdspRegistryShape-Admin.ps1`
- `Alioth-Engineering\tools\Rollback-QcsubsysPhase13AdspRegistryShape-Admin.ps1`

Default apply command for the current Mass Storage mapping:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Apply-QcsubsysPhase13AdspRegistryShape-Admin.ps1 -WindowsDrive E
```

Do not pass `-IncludeChildren` on the first run. That switch adds the 8250 Slimbus child-device registry shape and should be tested only after the core ADSP metadata changes the failure signature.
