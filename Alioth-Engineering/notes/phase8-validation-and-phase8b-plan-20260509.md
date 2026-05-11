# Phase8 validation and Phase8B plan - 2026-05-09

## Inputs

- `D:\Code\REDMIK40_Win11\Qcsubsys8280Experiment_20260508_202841`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260508_202939`
- `D:\Code\REDMIK40_Win11\PilcFailureTrace_20260508_204007`

## Result

Phase8 moved the blocker forward.

- `QCOM0620Present=True`
- `QCOM0620Service=qcsubsys`
- `QCOM0620InfPath=oem15.inf`
- `Qcsubsys8280Selected=True`
- `Qcsubsys8280CiBlocked=False`
- `QCOM06E0Present=True`
- `QCOM06E0Service=qcPILC`
- `QCOM06E0` selected Surface `qcpil.inf` as `oem16.inf`
- `QCOM06E0` selected Surface `qcpilfilterext.inf` as `oem17.inf`
- Current boot Code Integrity and Kernel-PnP focused logs are clean

The current failure is:

- `ACPI\QCOM06E0\2&DABA3FF&0`
- `CM_PROB_FAILED_ADD`
- Problem status `0xc0000001`

## Interpretation

This is no longer a WDAC/signature problem. The Surface `qcsubsys8280` path passed, and Surface `qcpil/qcpilfilterext` binds. The failure happens when starting the `QCOM06E0` PILC device.

The Surface package also contains `qcpilext8280.inf`, but it matches:

- `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`
- `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_QRD08280`
- `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_CDP08280`

The Alioth Phase8 device currently reports:

- `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08250`

So the extension registry values are not being applied automatically. Those values include `PilConfig`, `SubsystemLoad`, and `PGCM` settings that may be required before `qcpil.sys` can start.

## Phase8B experiment

Before rebuilding UEFI, run a registry-only experiment on the offline Windows partition:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-Qcpil8280ExtensionRegistryExperiment-Admin.ps1" -WindowsDrive D
```

Then boot Phase8 again and collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-AliothPilcFailure.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-Qcsubsys8280Experiment.ps1"
```

If `QCOM06E0` becomes Code 0, formalize the fix in the next UEFI by making PILC expose the Surface-compatible subsystem path or by carrying equivalent ACPI/registry configuration.

If `QCOM06E0` remains Code 31, rollback and move to ACPI `_CRS/_DSD` comparison for PILC.
