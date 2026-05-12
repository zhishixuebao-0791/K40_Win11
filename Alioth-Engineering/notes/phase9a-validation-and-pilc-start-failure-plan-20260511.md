# Phase9A validation and PILC start failure plan - 2026-05-11

## Inputs

- UEFI: `Mu-alioth-1-acpi-hid-phase9a-20260511-174312.img`
- PILC ACPI shape log: `D:\Code\REDMIK40_Win11\PilcAcpiShape_20260511_161911`
- Audio dependency log: `D:\Code\REDMIK40_Win11\AudioDependencyState_20260511_163323`

## Result

Phase9A is effective at the ACPI ID level.

- `ACPI\QCOM06E0\2&DABA3FF&0` is present.
- Hardware IDs include `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`, `ACPI\QCOM06E0`, and `*QCOM06E0`.
- The Surface 8280 `qcsubsys` path is healthy: `ACPI\QCOM0620\2&DABA3FF&0` is present, `ProblemCode=0`, service `qcsubsys` is running.
- The supporting dependency chain is mostly healthy: `QCOM2533`, `QCOM250B`, `QCOM258D`, `QCOM250E`, `QCOM257C`, and `QCOM258B` are present and OK.

## Current blocker

`qcPILC` still fails to start:

- Device: `ACPI\QCOM06E0\2&DABA3FF&0`
- Service: `qcPILC`
- Status: `Error`
- ProblemCode: `31`
- SetupAPI: `CM_PROB_FAILED_ADD`
- Problem status: `0xc0000001`
- Device stack only shows `\Driver\ACPI`, so `qcPILC/qcPILFC` did not attach successfully.

This is no longer a simple WDAC/signature or `SUBSYS_MTP08280` issue. The driver package is selected and configured, but the driver fails during AddDevice/start.

## Registry evidence

The `QCOM06E0` enum node contains Surface-style extension values:

- `FirmwareIdentified=1`
- `DPOP\GUID={ED9E8101-05FA-46B7-82AA-8D58770D200B}`
- `IMEM\BaseAddress=0x146bf000`
- `IMEM\Offset=0x94c`
- `PGCM\BaseAddress=0x86700000`
- `PGCM\Size=0x7d00000`
- `PilConfig\DoNotReturnMemoryToHLOS=1`
- `PilConfig\HypProtectionEnabled=1`
- `SubsystemLoad\GFXSUC`
- `SubsystemLoad\VENUS`

The values exist, so the next question is whether they are sufficient and whether `qcPILC` rejects the current ACPI/runtime shape.

## Immediate next step

Do not continue broad driver injection, WDAC replacement, or qcsubsys work in this phase.

Run the new deep runtime trace after booting Phase9A into Windows:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcStartFailureDeep.ps1
```

Then return to Mass Storage and copy back the generated folder:

```text
D:\Code\REDMIK40_Win11\PilcStartFailureDeep_*
```

## Decision after next trace

If CodeIntegrity is clean and SetupAPI still shows only `CM_PROB_FAILED_ADD / 0xc0000001`, Phase10 should focus on PILC ACPI/runtime shape rather than signatures:

- compare `QCOM06E0` resources, dependency properties, and extension binding against a known working Surface 8280/8cx Gen3 device;
- verify whether `qcpilEXT8280` is naturally selected or only registry values were carried from earlier experiments;
- only then choose a Phase10 ACPI experiment.

