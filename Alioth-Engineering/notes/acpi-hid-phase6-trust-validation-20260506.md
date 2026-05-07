# ACPI HID Phase6 trust validation

Date: 2026-05-06

## Inputs

- UEFI image: `Mu-alioth-1-acpi-hid-phase6-20260506-085247.img`
- Offline trust script:
  - `tools/apply-woa-andromeda-signature-trust-admin.ps1`
- Post-trust diagnostics:
  - `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_160144`
  - `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_160635`

## Result

The Andromeda DesktopSignature package was applied and the expected offline certificate registry keys were present, but `qcsubsys` still does not load:

- `SSDD kona / ACPI\QCOM2522\2&DABA3FF&0` is still present.
- It is still matched to `qcsubsys8250.inf`.
- It still reports `ProblemCode 52`.
- `ProblemStatus 3221226536` is still `0xC0000428`.

This means Phase6 ACPI HID remap is still valid, but the blocker has moved fully into kernel code integrity / signing policy.

## Current state

Working or starting:

- `RPEN / QCOM2533`: OK, `QCRPEN`
- `SCM0 / QCOM250B`: OK, `qcscm`
- `GLNK / QCOM258D`: OK, `qcGLINK`
- `IPC0 / QCOM250E`: OK, `QCIPC_ROUTER`
- `PDSR / QCOM257C`: previously validated running
- `TFTP / QCOM258B`: previously validated running

Blocked:

- `SSDD / QCOM2522`: Code 52, `qcsubsys`
- `PILC / QCOM251B`: Code 31, `qcPILC`
- `FSA4480 / FSA04480`: Code 51, `fsa4480`

Not present yet:

- `ADSP / QCOM051D or QCOM251D`
- `QSM / QCOM0520 or QCOM2520`
- `ARPC / QCOM0560 or QCOM2560`
- `ARPD / QCOM058A or QCOM258A`

## Decision

Do not build Phase7 HID remaps yet. More ACPI ID changes will not fix `qcsubsys` Code 52.

Next step is evidence collection from the live phone OS:

- collect Code Integrity event log entries
- confirm live certificate store state
- confirm live `qcsubsys8250.sys` and `.cat` signature status
- confirm boot/CI policy state

New phone-side script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Collect-QcsubsysCodeIntegrity.ps1"
```

The live phone diagnostics in `D:\Code\REDMIK40_Win11\QcsubsysCodeIntegrity_20260506_171506` show:

- `qcsubsys8250.sys` and `qcsubsys8250.cat` are Authenticode-valid in the live phone OS.
- PnP still reports `CM_PROB_UNSIGNED_DRIVER / 0xC0000428`.
- Code Integrity reports that the file hash could not be found on the system.
- `CI\Protected\Licensed` is still `0`.

This points at SSDE / CI policy state, not missing certificate store entries.

Next minimal experiment should install only:

- `SUPPORT.DESKTOP.BASE\Signature\SSDE\ssde.inf`

Run from elevated PowerShell on the Win10 host while the phone is in Mass Storage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-woa-ssde-admin.ps1" -WindowsDrive D
```

That experiment is separate from Phase7 ACPI work.
