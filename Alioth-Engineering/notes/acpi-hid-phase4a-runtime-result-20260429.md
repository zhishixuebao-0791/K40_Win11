# ACPI HID Phase4a Runtime Result - 2026-04-29

## Input logs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260429_170958`
- `D:\Code\REDMIK40_Win11\AudioRootTrace_20260429_170608`
- `D:\Code\REDMIK40_Win11\AudioRootCause_20260429_170712`

## Result summary

| Device | Runtime ID | Expected service | Result | Interpretation |
|---|---:|---|---|---|
| `PILC` | `QCOM251B` | `qcPILC` | Error Code 31, `ProblemStatus=3221225524` | HID remap still binds the driver, but the driver cannot start. |
| `RPEN` | `QCOM2533` | `QCRPEN` | OK, running | Phase3 remap remains good. |
| `AudioService` | `QCOM05D2` with `QCOM25D2` compatible ID | Audio service driver | OK | Existing alias path remains good. |
| `FSA4480` | `FSA04480` | `fsa4480` | Error Code 51 | Still not a full audio root; expected until upstream dependencies work. |
| `SCM0` | `QCOM250B` | `qcscm` | OK, running | Phase4a `QCOM050B -> QCOM250B` succeeded. |
| `GLNK` | `QCOM258D` | `qcGLINK` | Error Code 28 | Phase4a `QCOM058D -> QCOM258D` succeeded at ACPI level, but the GLINK driver was not installed in the image. |
| `IPC0` | `QCOM250E` | `qcipcrtr` | Not present | Not included in Phase4a. |
| `QSM` | `QCOM2520` | `qcsubsys` | Not present | Not included in Phase4a. |
| `SSDD` | `QCOM2522` | `qcsubsys` | Not present | Not included in Phase4a. |
| `ADSP` | `QCOM251D` | `qcsubsys` | Not present | Not included in Phase4a. |

## Key finding

Phase4a is a partial success. It proves that `SCM0` can be converted from the Mu-Silicium 05xx HID to the Kona 25xx HID and run with the signed Kona `qcscm` driver.

The `GLNK` ACPI side also changed correctly to `QCOM258D`, but Windows reports Code 28 because no `qcGLINK` service or DriverStore package is present. This is different from the earlier `PILC` Code 31 case. `GLNK` has not yet been tested as a running driver.

## Next action

Do not expand to `ADSP/QSM/SSDD/IPC0` yet. First inject only the signed Kona GLINK package:

- Source: `C:\yjc_code\K40_Win11\sound_code\windows_silicon_qcom_kona\Drivers\SOC\Buses\GLINK\qcglink8250.inf`
- Target: phone Windows partition in Mass Storage mode, currently expected as `D:`
- Script: `C:\yjc_code\K40_Win11\tools\apply-audio-glink-phase4a-admin.ps1`

After booting Phase4a again, collect:

- `Trace-AliothAcpiPhase3State.ps1`
- `Trace-AliothAudioDependencyState.ps1`
- `Trace-AliothAudioRoots.ps1`
- `Trace-AliothAudioRootCauses.ps1`

The next decision depends on `QCOM258D`:

- If `QCOM258D/qcGLINK` becomes OK/running, proceed to Phase4b for `IPC0/QCOM250E`, `QSM/QCOM2520`, `SSDD/QCOM2522`, and then `ADSP/QCOM251D`.
- If `QCOM258D/qcGLINK` becomes Code 31, stop HID expansion and inspect GLINK resources / `_CRS` / `_DEP` before touching ADSP.
