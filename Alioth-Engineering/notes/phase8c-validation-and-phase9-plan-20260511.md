# Phase8C PILC Validation And Phase9 Plan - 2026-05-11

## Inputs

- `D:\Code\REDMIK40_Win11\PilcAcpiShape_20260511_142854`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260511_144007`
- Current UEFI baseline: Phase8, with `PILC` remapped to `QCOM06E0` and `SSDD` remapped to `QCOM0620`.
- Current Windows-side experiment: Phase8C full `qcpilEXT8280` registry payload was applied manually to `Enum\ACPI\QCOM06E0\2&daba3ff&0`.

## Evidence

- `QCOM0620` is still healthy:
  - `ACPI\QCOM0620\2&DABA3FF&0`
  - `Service=qcsubsys`
  - `ProblemCode=0`

- `QCOM06E0` is still the active blocker:
  - `ACPI\QCOM06E0\2&DABA3FF&0`
  - `Service=qcPILC`
  - `DriverInfPath=oem16.inf`
  - `MatchingDeviceId=ACPI\QCOM06E0`
  - `ProblemCode=31`
  - SetupAPI: `CM_PROB_FAILED_ADD`, `problem status: 0xc0000001`

- `qcpilEXT8280` registry values are present after Phase8C:
  - `SubsystemLoad\VENUS\MemoryAlignment=0`
  - `SubsystemLoad\VENUS\MemoryReservation=0x00500000`
  - `SubsystemLoad\GFXSUC\MemoryAlignment=0x1000`
  - `SubsystemLoad\GFXSUC\MemoryReservation=0x5000`
  - `PilConfig\HypProtectionEnabled=1`
  - `PilConfig\DoNotReturnMemoryToHLOS=1`
  - `PGCM\BaseAddress=0x86700000`
  - `PGCM\Size=0x07D00000`
  - `IMEM\BaseAddress=0x146BF000`
  - `IMEM\Offset=0x94C`
  - `DPOP\GUID={ED9E8101-05FA-46B7-82AA-8D58770D200B}`
  - `MSAL\Type=1`

- `qcpilEXT8280.inf` itself only matches:
  - `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`
  - `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_QRD08280`
  - `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_CDP08280`

- Current Alioth ACPI still exposes:
  - `HardwareIds=ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08250;ACPI\QCOM06E0;*QCOM06E0`
  - `CompatibleIds=ACPI\VEN_QCOM&DEV_06E0`

- The current decompiled DSDT shape for `PILC` is minimal:
  - `Device (PILC) { Name (_HID, "QCOM051B") }`
  - `Scope (\_SB.PILC)` only defines `_SUB`; no `_STA`, no `_CRS`, no `_DSD`, no explicit `_DEP`.

## Conclusion

Phase8C rules out the simple hypothesis that `QCOM06E0/qcPILC` fails only because `qcpilEXT8280` registry values are missing.

The failure is now most likely one of these:

1. `PILC` ACPI identity is incomplete for the Surface 8280 driver path because `_SUB` still resolves to `MTP08250`, so the real `qcpilEXT8280.inf` extension does not bind naturally.
2. `PILC` ACPI shape is too thin for `qcpil.sys`: no `_CRS`, `_DSD`, or resource description is exposed, so AddDevice/start fails before the ADSP child chain can enumerate.
3. Surface 8280 `qcpil.sys` expects 8280-specific ACPI/resource semantics that cannot be satisfied by registry values alone.

Do not continue WDAC, qcsubsys, or broad driver injection work until `QCOM06E0/qcPILC` leaves Code 31.

## Phase9 Plan

### Phase9A: Natural qcpilEXT8280 binding test

Goal: determine whether natural extension binding changes `qcPILC` behavior beyond the manual registry payload.

Change only `PILC` subsystem identity:

- Keep `_HID` as `QCOM06E0`.
- Override only `\_SB.PILC._SUB` to return `MTP08280`.
- Keep `SSDD/QCOM0620` unchanged.
- Do not add new drivers.

Validation criteria:

- `HardwareIds` should become `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280;ACPI\QCOM06E0;*QCOM06E0`.
- `ExtendedConfigurationIds` should include the real `qcpilEXT8280.inf` package, not only `qcpilfilterext.inf`.
- If `ProblemCode` changes from 31 or `qcPILC` starts, continue with ADSP dependency enumeration.
- If still Code 31, Phase9A is considered failed and we move to ACPI resource shape.

### Phase9B: PILC ACPI resource shape test

Goal: determine whether `qcPILC` needs explicit ACPI resources.

Compare against a known working Surface 8280 ACPI dump if available. If not available, build a conservative test using current Alioth memory-map evidence:

- Add a `_CRS` under `PILC` only if the Surface reference confirms it.
- Candidate resource areas to compare before changing:
  - PGCM: `0x86700000`, size `0x07D00000` from Surface 8280 extension.
  - Alioth/Kona 8250 PGCM from original driver: `0x8BD80000`, size `0x0E780000`.
  - IMEM: `0x146BF000`, offset `0x94C`.

Validation criteria:

- `QCOM06E0` must stop reporting `CM_PROB_FAILED_ADD`.
- If it still fails with `0xc0000001`, revert Phase9B and stop; continuing into ADSP aliases will not help.

### Phase9C: Controlled fallback to native 8250 PILC

Only consider this if Phase9A and Phase9B both fail.

- Revert `PILC` to `QCOM251B`.
- Keep only already-proven dependency remaps that do not trigger Code Integrity failures.
- This route likely reopens old WDAC/signature issues, so it is lower priority than fixing the 8280 `PILC` path.

## Next Immediate Operation

Switch to Ubuntu and build Phase9A UEFI:

1. Patch `Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.asl` and `DSDT.aml`.
2. Preserve Phase8 HID remaps.
3. Add a targeted `PILC._SUB -> MTP08280` override.
4. Build `Mu-alioth-1-acpi-hid-phase9a-<timestamp>.img`.
5. Flash/boot it on the K40.
6. Run:
   - `Trace-AliothPilcAcpiShape.ps1`
   - `Trace-AliothAudioDependencyState.ps1`

