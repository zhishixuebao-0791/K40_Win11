# Alioth ACPI Phase3 State Analysis

## Inputs

- Phone-side log root: `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260429_170100`
- UEFI under test: `Mu-alioth-1-acpi-hid-phase3-20260429-094408.img`
- Phase3 ACPI HID edits:
  - `PILC`: `QCOM051B -> QCOM251B`
  - `RPEN`: `QCOM0533 -> QCOM2533`

## Current Runtime Result

| Device | Runtime ID | Driver/service | Status | Meaning |
| --- | --- | --- | --- | --- |
| PILC | `ACPI\QCOM251B\2&DABA3FF&0` | `qcPILC`, `qcpil8250.inf` | Error, Code 31, ProblemStatus `3221225524` | Phase3 HID remap worked and the signed Kona PIL driver matched, but the device cannot start yet. |
| RPEN | `ACPI\QCOM2533\2&DABA3FF&0` | `QCRPEN`, `qcrpen8250.inf` | OK, service running | Phase3 HID remap worked completely for RPEN. |
| AudioService | `ACPI\QCOM05D2\0` | `AudioService8250.inf` through `QCOM25D2` compatible alias | OK | Existing alias path is usable for this simple audio service. |
| FSA4480 | `ACPI\FSA04480\2&DABA3FF&0` | `fsa4480`, `fsa4480.inf` | Error, Code 51 | HID is already correct. The failure is not an ID mismatch; it is likely dependency/resource/runtime readiness. |
| SCM0 | `ACPI\QCOM050B\0` | none | Error, Code 28 | Device is present but no driver is bound. Kona driver expects `ACPI\QCOM250B`. |
| GLNK | `ACPI\QCOM058D\0` | none | Error, Code 28 | Device is present but no driver is bound. Kona driver expects `ACPI\QCOM258D`. |

The old native `QCOM051B` and `QCOM0533` entries still exist as stale registry/devnode records, but `IsPresent=False`. They are not the active devices after Phase3.

## Driver-INF Evidence

Local signed Kona package matches these IDs:

- `Drivers\SOC\System\SCM\qcscm8250.inf`: `ACPI\QCOM250B`
- `Drivers\SOC\Buses\GLINK\qcglink8250.inf`: `ACPI\QCOM258D`
- `Drivers\Cellular\IPCRouter\qcipcrouter8250.inf`: `ACPI\QCOM250E`
- `Drivers\Subsystems\CombinedSubsystem\qcsubsys8250.inf`: `ACPI\QCOM251D`, `ACPI\QCOM2520`, `ACPI\QCOM2522`
- `Drivers\Audio\RPC\ADSPRPC\qcadsprpc8250.inf`: `ACPI\QCOM2560`
- `Drivers\Audio\RPC\ADSPRPCD\qcadsprpcd8250.inf`: `ACPI\QCOM258A`
- `Drivers\SOC\Transports\QcTftpKmdf.inf`: `ACPI\QCOM258B`
- `Drivers\Subsystems\ProtectionDomainServiceRegistry\qcpdsr.inf`: `ACPI\QCOM257C`
- `Drivers\SOC\SMMU\qcsmmu8250.inf`: `ACPI\VEN_QCOM&DEV_2509&REV_0001/0002`

## Interpretation

Phase3 proved the ACPI HID remap direction is valid. Windows accepted the new ACPI IDs, selected original signed Kona drivers, and successfully started RPEN.

The remaining blocker is dependency order. `qcPILC` now binds but fails to start, while two currently present dependency-layer devices still have no driver:

- `SCM0/QCOM050B`, depended on by `ARPC` and other platform devices.
- `GLNK/QCOM058D`, with `DependencyProviders` already pointing at the now-working `QCOM2533/RPEN`.

This makes `SCM0` and `GLNK` the best next targets. They are already present in Windows, so we can validate the effect immediately after changing HID without needing to guess whether hidden audio roots will appear.

## Recommended Phase4a Scope

Patch only these two ACPI HIDs first:

- `SCM0`: `QCOM050B -> QCOM250B`
- `GLNK`: `QCOM058D -> QCOM258D`

Do not change these yet in Phase4a:

- `IPC0`: `QCOM050E -> QCOM250E`
- `ADSP`: `QCOM051D -> QCOM251D`
- `QSM`: `QCOM0520 -> QCOM2520`
- `SSDD`: `QCOM0522 -> QCOM2522`
- `ARPC`: `QCOM0560 -> QCOM2560`
- `ARPD`: `QCOM058A -> QCOM258A`
- `PDSR`: `QCOM057C -> QCOM257C`
- `TFTP`: `QCOM058B -> QCOM258B`
- `SMMU`: `QCOM0509 -> ACPI\VEN_QCOM&DEV_2509&REV_0001/0002`

Reason: those are not all currently visible in the Phase3 state summary, and changing too many dependency HIDs in one UEFI build makes a boot regression harder to isolate.

## Validation After Phase4a

After building and booting the Phase4a UEFI image, rerun:

- `D:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRoots.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRootCauses.ps1`

Expected useful outcomes:

- `ACPI\QCOM250B` appears and binds to `qcscm`.
- `ACPI\QCOM258D` appears and binds to `qcglink`.
- `QCOM050B/QCOM058D` become stale, not active.
- `QCOM251B/qcPILC` either starts or changes error code.
- More downstream devices such as `ADSP`, `ARPC`, `ARPD`, `QSM`, or `SSDD` may begin enumerating.

If Phase4a is stable and improves the dependency state, Phase4b can expand to `IPC0/QCOM250E`, `ADSP/QCOM251D`, `QSM/QCOM2520`, and `SSDD/QCOM2522`.
