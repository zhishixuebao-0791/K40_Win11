# Phase9A PILC qcpilEXT8280 binding analysis - 2026-05-11

## Inputs

- UEFI: `Mu-alioth-1-acpi-hid-phase9a-20260511-174312.img`
- Deep trace: `D:\Code\REDMIK40_Win11\PilcStartFailureDeep_20260511_171250`

## Confirmed state

Phase9A is effective at the ACPI identity layer:

- `ACPI\QCOM06E0\2&DABA3FF&0` is present.
- Hardware IDs include `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`.
- `qcsubsys` is no longer the current blocker. `ACPI\QCOM0620\2&DABA3FF&0` starts successfully with `ProblemCode=0`.

The current failure is still `qcPILC` start/AddDevice:

- Device: `ACPI\QCOM06E0\2&DABA3FF&0`
- Service: `qcPILC`
- Driver: `oem16.inf`, `qcpil.inf`
- ProblemCode: `31`
- SetupAPI: `CM_PROB_FAILED_ADD`
- Problem status: `0xc0000001`
- Device stack: only `\Driver\ACPI`

## New finding

The Surface 8280 extension package `qcpilEXT8280.inf` should match this exact hardware ID:

```text
ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280
```

However the phone offline DriverStore does not currently contain:

```text
D:\Windows\System32\DriverStore\FileRepository\qcpilext8280.inf_*
```

The active device only reports `qcpilfilterext` in `ExtendedConfigurationIds`:

```text
oem17.inf:ACPI\QCOM06E0,PIL_Device_Ext.NT,02/12/2023,1.0.3681.5800
```

This means the current test has not yet proven that the official Surface `qcpilEXT8280` extension is installed and naturally available to PnP.

## Next action

Before Phase10 ACPI changes, run the narrow offline extension binding step:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-QcpilExt8280Binding-Admin.ps1" -WindowsDrive D
```

Then boot Phase9A again and collect:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcStartFailureDeep.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AudioDependencyState.ps1
```

## Decision gate

If the next trace shows `qcpilext8280.inf_*` installed and `ExtendedConfigurationIds` includes the Surface 8280 extension but `qcPILC` still fails with `0xc0000001`, Phase10 should move to ACPI/runtime shape instead of driver package selection.

If `qcPILC` starts, continue to ADSP/audio-root enumeration and stop changing PILC.
