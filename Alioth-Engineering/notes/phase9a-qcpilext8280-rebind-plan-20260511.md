# Phase9A qcpilEXT8280 rebind plan - 2026-05-11

## Inputs

- PILC deep trace: `D:\Code\REDMIK40_Win11\PilcStartFailureDeep_20260511_184116`
- Audio dependency state: `D:\Code\REDMIK40_Win11\AudioDependencyState_20260511_185911`

## Result

The offline `qcpilEXT8280` installation succeeded at DriverStore level:

```text
D:\Windows\System32\DriverStore\FileRepository\qcpilext8280.inf_arm64_0ac6ef587d216e20
D:\Windows\INF\oem18.inf
```

`oem18.inf` contains the expected Surface 8280 PILC extension match:

```text
ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280
```

## Remaining blocker

`ACPI\QCOM06E0\2&DABA3FF&0` still has:

- `ProblemCode=31`
- `ProblemStatus=0xc0000001`
- `Service=qcPILC`
- `DeviceStack=\Driver\ACPI`
- `ExtendedConfigurationIds=oem17.inf:ACPI\QCOM06E0,PIL_Device_Ext.NT,...`

`qcpilEXT8280` is installed but not selected as an extended configuration for the live `QCOM06E0` device. SetupAPI still shows the old 2026-05-08 device install path selecting only `oem16.inf` and `oem17.inf`.

## Next action

Run the phone-side online rebind script from Windows on the K40:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Refresh-QcpilExt8280Binding-OnPhone.ps1
```

The script will:

- re-add `qcpilEXT8280.inf` online with `/install`;
- run `pnputil /scan-devices`;
- attempt `pnputil /restart-device`, `/disable-device`, and `/enable-device` for `ACPI\QCOM06E0\2&DABA3FF&0`;
- collect before/after PnP state and recent SetupAPI/CodeIntegrity/Kernel-PnP evidence.

## Decision gate

If the next output shows `ExtendedConfigurationIds` now includes `oem18.inf` and `qcPILC` still fails with `0xc0000001`, stop driver package work and move to Phase10 ACPI/runtime shape.

If `oem18.inf` still does not bind after online rebind, the next experiment should force a controlled PnP reinstall of only `QCOM06E0` rather than continuing UEFI changes.
