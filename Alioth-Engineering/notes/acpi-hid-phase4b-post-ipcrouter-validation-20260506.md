# ACPI HID Phase4b Post-IPCRouter Validation - 2026-05-06

## Inputs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_113328`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_113727`

## Result

Phase4b target is successful.

- `IPC0/QCOM250E` is present.
- It binds `QCIPC_ROUTER`.
- Device status is `OK`.
- Service `QCIPC_ROUTER` is `Running`.
- Driver package is `oem11.inf:ACPI\QCOM250E,IPC_ROUTER_Device.NT`.

Current good chain:

- `RPEN/QCOM2533`: `QCRPEN`, `OK`, running.
- `SCM0/QCOM250B`: `qcscm`, `OK`, running.
- `GLNK/QCOM258D`: `qcGLINK`, `OK`, running.
- `IPC0/QCOM250E`: `QCIPC_ROUTER`, `OK`, running.

Known remaining issue:

- `PILC/QCOM251B`: `qcPILC`, Code 31.

## New Dependency Evidence

After IPC Router is running, the next visible dependency candidates are:

- `PDSR/QCOM057C`
- `TFTP/QCOM058B`

They are present in `AudioDependencyState_20260506_113727\02_RegistryEnumMatches.txt`:

- `QCOM057C`: `HardwareID = ACPI\VEN_QCOM&DEV_057C&SUBSYS_MTP08250, ACPI\QCOM057C, *QCOM057C`
- `QCOM058B`: `HardwareID = ACPI\VEN_QCOM&DEV_058B&SUBSYS_MTP08250, ACPI\QCOM058B, *QCOM058B`
- Both have no service/driver binding and retain old native 05xx IDs.

The matching signed Kona drivers expect:

- `qcpdsr.inf`: `ACPI\QCOM257C`
- `QcTftpKmdf.inf`: `ACPI\QCOM258B`

## Recommendation

Proceed with a narrow Phase5 ACPI HID experiment:

- Keep all previous remaps:
  - `QCOM051B` -> `QCOM251B`
  - `QCOM0533` -> `QCOM2533`
  - `QCOM050B` -> `QCOM250B`
  - `QCOM058D` -> `QCOM258D`
  - `QCOM050E` -> `QCOM250E`
- Add:
  - `PDSR`: `QCOM057C` -> `QCOM257C`
  - `TFTP`: `QCOM058B` -> `QCOM258B`

Then inject only these two drivers:

- `Drivers\Subsystems\ProtectionDomainServiceRegistry\qcpdsr.inf`
- `Drivers\SOC\Transports\QcTftpKmdf.inf`

Prepared Win10-side apply script for after Phase5 UEFI is built and booted:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-pdsr-tftp-phase5-admin.ps1" -WindowsDrive D
```

Validation gate for Phase5:

- `PDSR/QCOM257C` should bind `qcpdsr`.
- `TFTP/QCOM258B` should bind `QcTftpKmdf`.
- If both become `OK`, rerun full audio root diagnostics to check whether `SSDD/QSM/ADSP/ARPC/ARPD` begin to enumerate.

Do not jump to broad audio driver injection yet. The logs now support continuing dependency activation one layer at a time.
