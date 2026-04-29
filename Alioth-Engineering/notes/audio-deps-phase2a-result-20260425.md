# Alioth Audio Dependency Phase 2a Result - 2026-04-25

## Inputs

- Offline enum log: `Alioth-Engineering\logs\audio-dependency-enum-20260425-115257.log`
- Phone-side state log: `D:\Code\REDMIK40_Win11\AudioDependencyState_20260425_120537`
- Phase 2a backup: `Alioth-Engineering\logs\audio-deps-phase2a-backup-20260425-112003.json`

## Result

Phase 2a did not bring up the ADSP audio dependency chain.

The injected driver packages are present:

- `qcPILC` from `qcpil8250.inf`
- `QCRPEN` from `qcrpen8250.inf`
- `qcscm` from `qcscm8250.inf`
- `qcsmmu` from `qcsmmu8250.inf`

But the expected devices did not bind to these services after boot.

## Evidence

The offline apply backup shows the aliases were written successfully before boot:

- `QCOM051B -> ACPI\QCOM251B`
- `QCOM0533 -> ACPI\QCOM2533`
- `QCOM0509 -> ACPI\VEN_QCOM&DEV_2509&REV_0002`
- `QCOM050B -> ACPI\QCOM250B`

After boot, the phone-side registry shows the aliases did not persist on the active device nodes:

- `QCOM051B` only has `ACPI\VEN_QCOM&DEV_051B`
- `QCOM0533` only has `ACPI\VEN_QCOM&DEV_0533`
- `QCOM050B` only has `ACPI\VEN_QCOM&DEV_050B`
- `QCOM0509` was not found by the phone-side registry trace

The present PnP query did not show these nodes as active devices. Registry remnants have `ConfigFlags = 64`, consistent with failed/incomplete install state rather than functional devices.

## Interpretation

Offline `CompatibleIDs` alias injection is not stable for these low-level dependency nodes. Windows/ACPI rebuilds the device compatible-id list during boot and drops the injected 25xx aliases before driver matching completes.

This differs from `QCOM05D2 -> QCOM25D2`, where the alias persisted and `AudioService` bound successfully.

## Next Direction

Do not continue with more offline `CompatibleIDs` alias attempts for `PILC/RPEN/MMU0/SCM0`.

The next safe experiment should be one of:

1. Create a very narrow exact-ID INF experiment for demand-start/non-boot-critical dependencies first, excluding boot-start SCM.
2. Patch ACPI IDs in Mu-Silicium AML from 05xx to the 25xx IDs expected by the signed Kona INF files.

Preferred next step: inspect whether Mu-Silicium can change `_HID` IDs for only the already-enumerated dependency devices, starting with `PILC` and `RPEN`, because this preserves signed driver packages and avoids unsigned boot-start driver risk.
