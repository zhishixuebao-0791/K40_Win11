# ACPI HID Phase4b Validation - 2026-05-06

## Inputs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_104959`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_105355`
- `D:\Code\REDMIK40_Win11\AudioRootTrace_20260506_105842`
- `D:\Code\REDMIK40_Win11\AudioRootCause_20260506_105928`

## Findings

Phase4b ACPI remap is active:

- `SCM0/QCOM250B`: `qcscm`, `OK`, running.
- `GLNK/QCOM258D`: `qcGLINK`, `OK`, running.
- `RPEN/QCOM2533`: `QCRPEN`, `OK`, running.
- `PILC/QCOM251B`: `qcPILC`, still Code 31.
- `IPC0/QCOM250E`: present, but Code 28 and no service/driver bound.

This means the Phase4b UEFI side worked: `IPC0` is now exposed as `QCOM250E`.

The failure is currently on the driver-install side:

- `D:\Windows\System32\DriverStore\FileRepository` has no `qcipcrouter8250*` package.
- `D:\Windows\INF\setupapi.dev.log` has no `QCOM250E`, `qcipcrouter8250`, or `QCIPC_ROUTER` install record.
- `AcpiPhase3State` reports `IPC0/QCOM250E` as Code 28 with no matching device ID.

## Correction

The diagnostics had an incorrect expected service name for IPC0:

- Old: `qcipcrtr`
- Correct: `QCIPC_ROUTER`

Updated:

- `tools\Trace-AliothAcpiPhase3State.ps1`
- `tools\Trace-AliothAudioDependencyState.ps1`

## Next Action

Run the Phase4b IPC Router injection from an elevated Administrator PowerShell on the Win10 host while the phone is in Mass Storage mode and the phone Windows partition is `D:`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-ipcrouter-phase4b-admin.ps1" -WindowsDrive D
```

Expected successful apply log should include:

- `qcipcrouter8250.inf`
- `QCIPC_ROUTER`
- DISM driver package installed successfully

After that, boot Phase4b UEFI again and rerun:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\trace-alioth-audio-roots.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\trace-alioth-audio-root-causes.ps1"
```

Validation gate:

- `IPC0/QCOM250E` should bind `QCIPC_ROUTER`.
- If it becomes `OK`, continue to the next dependency stage.
- If it changes from Code 28 to Code 31 or another start error, then the driver matched but failed to start, and the next investigation should move to `_DEP`/dependency readiness rather than INF matching.
