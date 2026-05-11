# Phase8B PILC Code 31 Analysis - 2026-05-09

## Current Evidence

- `Qcsubsys8280Experiment_20260509_170004` confirms the Phase7/8 `QCOM0620 -> qcsubsys8280` path is working:
  - `QCOM0620Present=True`
  - `Qcsubsys8280Selected=True`
  - `Qcsubsys8280CiBlocked=False`
- `AudioDependencyState_20260509_165234` shows the current blocker is `QCOM06E0 -> qcPILC`:
  - `Status=Error`
  - `ProblemCode=31`
  - `ProblemStatus=3221225473` (`0xC0000001`)
  - `Service=qcPILC`
  - `Device_Stack={\Driver\ACPI}` in detailed properties, meaning the PIL driver stack did not attach/start successfully.
- `PilcFailureTrace_20260509_164904` has no useful Code Integrity or Kernel-PnP block events for `qcPILC/qcPILFC`.

## Interpretation

This is no longer a WDAC/hash/signature problem for `qcsubsys`. The failing edge is `PILC/QCOM06E0`, where the Surface `qcPILC` driver is selected but fails during AddDevice/start.

Phase8B wrote Surface `qcpilext8280`-style registry values to `QCOM06E0`, but the device remains Code 31. That suggests simple registry extension values are not enough. The next useful evidence is the ACPI/PnP shape of `QCOM06E0`: resources, dependency properties, extension filter state, DriverStore INF content, and current-boot setup/events.

## Next Step

Run the phone-side read-only diagnostic script:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcAcpiShape.ps1
```

Expected output folder:

```text
C:\Code\REDMIK40_Win11\PilcAcpiShape_YYYYMMDD_HHMMSS
```

Copy that folder back through Mass Storage. Use it to decide between:

- ACPI resource/DSD mismatch fix in Mu-Silicium Phase9.
- Surface `QCOM06E0` subsystem/extension binding experiment.
- Reverting PILC to the original 8250 path and fixing native `QCOM251B` instead.

## Optional Rollback

Phase8B registry-only changes can be rolled back with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-Qcpil8280ExtensionRegistryExperiment-Admin.ps1" -WindowsDrive D -BackupDir "C:\yjc_code\K40_Win11\Alioth-Engineering\backups\qcpil8280-extension-registry-pre-apply-20260509-164204"
```

Do not roll back before collecting `PilcAcpiShape` unless we explicitly want a before/after comparison.
