# ACPI HID Phase6 validation

Date: 2026-05-06

## Inputs

- UEFI image tested: `Mu-alioth-1-acpi-hid-phase6-20260506-085247.img`
- Diagnostics:
  - `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_152918`
  - `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_153431`

## Result

Phase6 ACPI remap succeeded:

- `SSDD` is no longer only the native stale `ACPI\QCOM0522`.
- `SSDD kona` is present as `ACPI\QCOM2522\2&DABA3FF&0`.
- It matches `qcsubsys8250.inf` as `ACPI\QCOM2522`.
- It installs as `Qualcomm Subsystem Dependency Device`, service `qcsubsys`.

Current blocker:

- `QCOM2522 / qcsubsys` reports `ProblemCode 52`.
- `ProblemStatus 3221226536` is `0xC0000428`.
- This is a signature / Code Integrity failure, not an ACPI HID miss.
- Local signature check for `qcsubsys8250.cat` and `qcsubsys8250.sys` reports: certificate chain cannot be built to a trusted root.
- The signer chain is `Windows On Andromeda Production PCA 2023 -> Windows On Andromeda KMCI Codesigning`.

## Dependency state

Already running or correctly installed:

- `RPEN / QCOM2533`: OK, `QCRPEN`
- `SCM0 / QCOM250B`: OK, `qcscm`
- `GLNK / QCOM258D`: OK, `qcGLINK`
- `IPC0 / QCOM250E`: OK, `QCIPC_ROUTER`
- `PDSR / QCOM257C`: previously validated running
- `TFTP / QCOM258B`: previously validated running

Still blocked:

- `PILC / QCOM251B`: Code 31, service `qcPILC`
- `SSDD / QCOM2522`: Code 52, service `qcsubsys`
- `ADSP / QCOM051D`: not present yet
- `QSM / QCOM0520`: not present yet
- `ARPC / QCOM0560`: not present yet
- `ARPD / QCOM058A`: not present yet

## Decision

Do not build Phase7 HID remaps yet. `QCOM2522` now reaches the correct driver, but Windows refuses to load `qcsubsys` because the Andromeda signing chain is not trusted.

Next experiment should be minimal:

1. Apply the DesktopSignature trust package offline:
   `powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\apply-woa-andromeda-signature-trust-admin.ps1 -WindowsDrive D`
2. Boot Phase6 UEFI again.
3. Re-run:
   - `Trace-AliothAcpiPhase3State.ps1`
   - `Trace-AliothAudioDependencyState.ps1`
4. Success criteria:
   - `QCOM2522` no longer reports Code 52.
   - `qcsubsys` appears in the device stack or starts cleanly.
   - No new recovery/0xc0000428 boot failure.

Only after `qcsubsys` is trusted should we continue with ADSP/QSM/ARPC/ARPD exposure or further ACPI work.
