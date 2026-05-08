# ACPI HID Phase7 validation - 2026-05-08

## Inputs

- UEFI image: `Mu-alioth-1-acpi-hid-phase7-20260508-120337.img`
- Logs:
  - `D:\Code\REDMIK40_Win11\Qcsubsys8280Experiment_20260508_111810`
  - `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260508_111915`
  - `D:\Code\REDMIK40_Win11\AudioDependencyState_20260508_112447`
  - `D:\Code\REDMIK40_Win11\Qcsubsys8280Experiment_20260508_120144`
  - `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260508_120312`
  - `D:\Code\REDMIK40_Win11\AudioDependencyState_20260508_120750`

## Findings

- Phase7 exposed `ACPI\QCOM0620\2&DABA3FF&0`.
- `QCOM0620` selected `oem15.inf`, matching `ACPI\QCOM0620`.
- `oem15.inf` points at `qcsubsys8280.inf_arm64_aa16b5350e005f78\qcsubsys8280.sys`.
- `qcsubsys` service now points to `qcsubsys8280.sys`.
- `qcsubsys` service enum contains only `ACPI\QCOM0620\2&daba3ff&0`.
- Current log set did not show `qcsubsys8280.sys` Code Integrity block.
- Historical `qcsubsys8250.sys` CI failures still exist in the event log, but they are from the old `QCOM2522` path and should not be treated as current Phase7 failure without current-boot evidence.
- Follow-up 12:01 logs confirm `QCOM0620Present=True`, `QCOM2522StillPresent=False`, `QCOM0522StillPresent=False`, `QCOM0620InfPath=oem15.inf`, `QCOM0620MatchingDeviceId=ACPI\QCOM0620`, and `QCOM0620Service=qcsubsys`.
- `qcsubsys` is running from `qcsubsys8280.inf_arm64_aa16b5350e005f78\qcsubsys8280.sys`.
- The `Qcsubsys8280Selected=False` field in the 12:01 verdict was a script detection bug, not a real driver selection failure.
- The old `AudioDependencyState_20260508_120750` summary is misleading because it used stale non-present registry nodes for `QCOM0522/QCOM2522` and did not correctly prefer the live `QCOM0620` device.

## Interpretation

The WDAC/qcsubsys blocker is cleared for the Phase7 route. The active SSDD path is now the official Surface `qcsubsys8280` package through `QCOM0620`.

The remaining gap is functional enumeration: `PILC/QCOM251B` is present but fails with Code 31, while ADSP/QSM/ARPC/ARPD audio roots still do not appear. The next blocker is likely before ADSP root enumeration, not WDAC policy.

## Script fixes made

- `Trace-AliothAcpiPhase3State.ps1` now includes `SSDD phase7 8280 / QCOM0620`.
- `Trace-AliothAudioDependencyState.ps1` now separates:
  - `SSDD phase6 / QCOM2522`
  - `SSDD phase7 / QCOM0620`
- `Trace-Qcsubsys8280Experiment.ps1` now:
  - uses present PnP devices for `QCOM2522StillPresent`
  - reports `QCOM0620InfPath`, `QCOM0620MatchingDeviceId`, and `QCOM0620Service`
  - limits Code Integrity collection to current boot to reduce stale `qcsubsys8250` noise
  - treats `qcsubsys8280.sys` in the active `qcsubsys` service as valid evidence for `Qcsubsys8280Selected=True`
- `Trace-AliothAudioDependencyState.ps1` now:
  - explicitly reports `IsPresent`
  - tracks Surface 8280 companion IDs `QCOM061B`, `QCOM06B0`, `QCOM068D`, and `QCOM061F`
  - prefers live present devices over historical registry-only nodes

## Next direction

Boot Phase7 again and run the updated diagnostics from `C:\Code\REDMIK40_Win11`.

If `QCOM0620` remains present, `Qcsubsys8280Selected=True`, and `Qcsubsys8280CiBlocked=False`, move to the next ACPI/driver binding target:

1. Confirm the fixed dependency summary reports live `QCOM0620` and does not treat non-present `QCOM2522/QCOM0522` as active.
2. Capture focused current-boot logs for `PILC/QCOM251B` Code 31, including setupapi and CodeIntegrity entries for `qcPILC`.
3. Determine whether Phase8 should target `PILC` startup prerequisites or expose an 8280 ADSP companion HID such as `QCOM061B`.
4. Do not build Phase8 until the next exact ACPI dependency failure is confirmed from the fixed trace output.
