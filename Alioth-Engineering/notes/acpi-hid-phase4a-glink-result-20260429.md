# ACPI HID Phase4a GLINK Runtime Result - 2026-04-29

## Input logs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260429_191256`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260429_191625`
- `D:\Code\REDMIK40_Win11\AudioRootTrace_20260429_191807`
- `D:\Code\REDMIK40_Win11\AudioRootCause_20260429_191851`

## Confirmed progress

| Device | Runtime ID | Service | State | Meaning |
|---|---:|---|---|---|
| `SCM0` | `QCOM250B` | `qcscm` | OK, running | Phase4a SCM remap is good. |
| `GLNK` | `QCOM258D` | `qcGLINK` | OK, running | Narrow GLINK driver injection succeeded. |
| `RPEN` | `QCOM2533` | `QCRPEN` | OK, running | Existing Phase3 remap remains good. |
| `AudioService` | `QCOM05D2` | existing audio orientation service | OK | Existing alias remains good. |
| `IPC0` | `QCOM050E` | none | Code 28 | New active blocker. Kona driver expects `QCOM250E`. |
| `PILC` | `QCOM251B` | `qcPILC` | Code 31 | Still fails to start. Do not treat this as a driver-missing issue. |
| `FSA4480` | `FSA04480` | `fsa4480` | Code 51 | Still only the Type-C analog switch; not the main audio root. |

## Interpretation

The dependency chain advanced by one step:

`RPEN/QCOM2533` -> `GLNK/QCOM258D` -> `IPC0/QCOM050E`

Before the GLINK driver injection, `QCOM258D` was Code 28. After injecting only `qcglink8250`, it is OK and running. This validates the ACPI HID remap approach for this dependency.

`IPC0/QCOM050E` is now present and reports Code 28, with dependency provider `ACPI\QCOM258D\0`. This means it is no longer hidden behind GLINK. Its driver package is not installed and the current ACPI HID still uses the 05xx form. Kona `qcipcrouter8250.inf` expects `ACPI\QCOM250E`.

## Next step

Build Phase4b UEFI with only this additional ACPI HID remap:

- `IPC0`: `QCOM050E -> QCOM250E`

Keep the existing Phase4a remaps:

- `PILC`: `QCOM051B -> QCOM251B`
- `RPEN`: `QCOM0533 -> QCOM2533`
- `SCM0`: `QCOM050B -> QCOM250B`
- `GLNK`: `QCOM058D -> QCOM258D`

After flashing Phase4b, inject only IPCRouter:

- Script: `C:\yjc_code\K40_Win11\tools\apply-audio-ipcrouter-phase4b-admin.ps1`
- Source: `C:\yjc_code\K40_Win11\sound_code\windows_silicon_qcom_kona\Drivers\Cellular\IPCRouter\qcipcrouter8250.inf`

Do not add `ADSP/QSM/SSDD` in the same step. The next gate is whether `QCOM250E/QCIPC_ROUTER` becomes OK/running.
