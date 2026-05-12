# qcpilEXT8280 rebind success and next validation - 2026-05-11

## Inputs

- Rebind log: `D:\Code\REDMIK40_Win11\QcpilExt8280Rebind_20260511_193911`

## Result

The online qcpilEXT8280 rebind succeeded.

Before rebind:

- `ACPI\QCOM06E0\2&DABA3FF&0`
- `ProblemCode=31`
- `ProblemStatus=0xC0000001`
- Driver extension list: `oem17.inf` only
- Device stack: `\Driver\ACPI`

After rebind:

- `ProblemCode=0`
- Status: started / OK
- Driver extension list: `oem18.inf` and `oem17.inf`
- `oem18.inf` is `qcpilEXT8280.inf`
- Device stack: `\Driver\qcPILFC`, `\Driver\qcPILC`, `\Driver\ACPI`

SetupAPI confirms the decisive transition:

```text
Driver INF - oem18.inf (...\qcpilext8280.inf)
Configuration - ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280
Configuration: oem18.inf:ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280,*
Install Device: Starting device 'ACPI\QCOM06E0\2&DABA3FF&0'
```

CodeIntegrity and Kernel-PnP did not report matching current-boot errors.

## Caveat

The live device state reports `DEVPKEY_Device_IsRebootRequired=True`. This means the next validation must prove that the `qcPILC` started state persists after reboot, not only after an online PnP rebind.

## Next validation

Boot Phase9A/active UEFI into Windows once more, then run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcStartFailureDeep.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AudioDependencyState.ps1
```

Then return to Mass Storage and inspect the new logs.

## Decision gate

If `QCOM06E0` remains `ProblemCode=0` after reboot, stop working on PILC/qcpil and move to the next dependency layer:

- check whether ADSP/SCSS/CDSP/SPSS/QSM instances appear or remain absent;
- check whether FSA4480 still waits on `QCOM0511`;
- decide the next ACPI HID/resource experiment from the new dependency state.

If `QCOM06E0` falls back to `ProblemCode=31`, the next step is to make the `qcpilEXT8280` rebind persistent, likely by staging a startup task or a controlled device reinstall path, before touching ACPI again.
