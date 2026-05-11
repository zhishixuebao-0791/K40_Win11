# PILC ACPI Shape Result and Phase8C Plan - 2026-05-09

## Evidence From `PilcAcpiShape_20260509_172657`

- `QCOM06E0` is present and selects the official Surface Pro 9 5G PIL driver:
  - `Service=qcPILC`
  - `DriverInfPath=oem16.inf`
  - `MatchingDeviceId=ACPI\QCOM06E0`
  - `ProblemCode=31`
  - `ProblemStatus=0xC0000001`
- `qcpilfilterext.inf` is selected as an extension:
  - `ExtendedConfigurationIds=oem17.inf:ACPI\QCOM06E0,PIL_Device_Ext.NT,...`
  - Registry contains `Filters\*Upper\qcPILFC`.
- The more important Surface package `qcpilEXT8280.inf` does not bind through PnP because it only matches:
  - `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`
  - Current alioth ACPI exposes `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08250`.
- `QCOM06E0` has no WMI allocated resource entries in the trace. Working dependencies such as `QCOM258D` do have allocated IRQ resources.
- The current registry has only part of the `qcpilEXT8280.inf` payload. Missing values include at least:
  - `SubsystemLoad\GFXSUC\MemoryReservation`
  - `IMEM\BaseAddress`
  - `IMEM\Offset`
  - `DPOP\GUID`
  - `MSAL\Type`

## Interpretation

The blocker has moved from WDAC/qcsubsys to PILC ACPI/extension shape. Surface `qcPILC` and `qcPILFC` are accepted and selected, but `qcPILC` fails during device start. The most plausible low-risk next experiment is to manually apply the full `qcpilEXT8280.inf` registry payload to `QCOM06E0`.

This avoids a UEFI rebuild and tests whether the missing Surface 8280 extension registry is sufficient.

## Phase8C Apply Command

Run from elevated Administrator PowerShell on Win10 while the phone is in Mass Storage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-Qcpil8280FullExtensionRegistry-Admin.ps1" -WindowsDrive D
```

Then boot Phase8 UEFI and collect:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcAcpiShape.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

## Rollback

The apply script prints a backup path. If boot behavior worsens, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-Qcpil8280FullExtensionRegistry-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir-from-apply-output>"
```

## If Phase8C Fails

If `QCOM06E0` still remains Code 31 after full extension values are present, the next step should be a UEFI Phase9 ACPI change:

- Either expose PILC subsystem as `MTP08280` so `qcpilEXT8280.inf` binds naturally.
- Or compare `_SB.PILC` `_CRS/_DSD/_DEP` against a Surface 8280 ACPI dump and patch alioth PILC resource shape.
