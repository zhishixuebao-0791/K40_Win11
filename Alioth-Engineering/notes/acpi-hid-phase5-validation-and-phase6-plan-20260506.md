# ACPI HID Phase5 Validation and Phase6 Plan - 2026-05-06

## Evidence

Input logs:

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_132621`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_133139`

Phase5 result:

- `PDSR/QCOM257C` is enumerated and bound to `qcpdsr`.
- `qcpdsr` service is `Running`.
- `TFTP/QCOM258B` is enumerated and bound to `QcTftpKmdf`.
- `QcTftpKmdf` service is `Running`.

Remaining blocker:

- `SSDD/QCOM0522` is still present as native HID and reports Code 28.
- `SSDD/QCOM2522` is not present.
- `qcsubsys8250.inf` matches `ACPI\QCOM2522`, not `ACPI\QCOM0522`.

## Decision

Phase5 is successful. The next narrow experiment should be Phase6:

- ACPI HID remap: `QCOM0522 -> QCOM2522`
- Driver package: `qcsubsys8250.inf`
- Do not touch `QCOM0520/QCOM251D/QCOM2560/QCOM258A` yet.

## Prepared Win10 Script

The SSDD driver injection script is prepared, but should be run only after booting a Phase6 UEFI image:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-ssdd-phase6-admin.ps1" -WindowsDrive D
```

## Validation Gate

After Phase6 UEFI and SSDD driver injection:

- `SSDD/QCOM2522` should bind to `qcsubsys`.
- `qcsubsys` should be `Running` or at least the device should move away from Code 28.
- If new `QSM/QCOM0520`, `ADSP/QCOM051D`, `ARPC/QCOM0560`, or `ARPD/QCOM058A` devices appear, collect fresh `AcpiPhase3State` and `AudioDependencyState` logs before doing any further remap.
