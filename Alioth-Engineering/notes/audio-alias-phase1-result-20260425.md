# Audio Alias Phase 1 Result

## Input logs

- `D:\Code\REDMIK40_Win11\AudioRootTrace_20260425_094042`
- `D:\Code\REDMIK40_Win11\AudioRootCause_20260425_094202`

## Result

Phase 1 was partially successful.

`ACPI\QCOM05D2` successfully bound to the original signed Kona `AudioService8250.inf` package through the `ACPI\QCOM25D2` CompatibleID alias.

Evidence:

- PnP now shows `Qualcomm(R) Audio Device Orientation Service`
- Instance: `ACPI\QCOM05D2\0`
- Status: `OK`
- `setupapi.dev.log` shows selection of `ACPI\QCOM25D2 [AudioService_Inst]`

`ACPI\QCOM0560` and `ACPI\QCOM058A` did not bind because their offline registry keys did not exist when the phase-1 script ran:

- `ControlSet001\Enum\ACPI\QCOM0560` not found
- `ControlSet001\Enum\ACPI\QCOM058A` not found

This means the issue is not the ADSPRPC/ADSPRPCD driver package itself. Those packages were added to DriverStore and their services exist, but there are no matching PnP devices to bind.

## New direction

The missing earlier root is likely `ADSP`.

DSDT exposes:

- `Device (ADSP)`
- `_HID QCOM051D`
- `_STA` returns `0x0F`

Kona has a matching subsystem driver, but it expects:

- `ACPI\QCOM251D`
- INF: `Drivers\Subsystems\CombinedSubsystem\qcsubsys8250.inf`

That driver contains `ADSP_Children`, which creates:

- `ADSP\QCOM2510` Slimbus child devices

Therefore the next narrow experiment is:

- `ACPI\QCOM051D -> ACPI\QCOM251D`
- Install only original signed `qcsubsys8250.inf`
- Do not inject SOC, USBFn, PMIC, PCIe, storage, or broad platform packages

## Prepared phase 1b

Prepared package:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\experiments\audio-adsp-phase1b\signed-driver-package`

Apply script:

- `C:\yjc_code\K40_Win11\tools\apply-audio-adsp-phase1b-admin.ps1`

Rollback script:

- `C:\yjc_code\K40_Win11\tools\rollback-audio-adsp-phase1b-admin.ps1`

Phone-side verification script:

- `C:\Code\REDMIK40_Win11\Trace-AudioAliasState.ps1`

## Expected phase 1b signal

Useful success does not require audio output yet. Useful success means one of these appears after boot:

- `ACPI\QCOM051D` bound to `qcsubsys`
- `Qualcomm(R) Aqstic(TM)` device appears
- `ADSP\QCOM2510` child devices appear
- Later `SLM1/ADCM/AUDD` evidence begins to appear

If none of those appear, the issue moves from INF matching toward ACPI dependency/resource exposure.
