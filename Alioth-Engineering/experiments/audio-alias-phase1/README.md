# Alioth Audio Alias Phase 1

## Goal

This experiment keeps original signed Kona audio INF packages unchanged and adds only offline CompatibleID aliases for the ACPI devices that Mu-alioth exposes as `05xx`.

It is intended to test whether Windows can bind the first audio dependency layer without editing Mu-Silicium ACPI.

## Phase-1 aliases

| Native Mu-alioth ID | Driver ID expected by Kona INF | Package |
| --- | --- | --- |
| `ACPI\QCOM05D2` | `ACPI\QCOM25D2` | `AudioService8250.inf` |
| `ACPI\QCOM0560` | `ACPI\QCOM2560` | `qcadsprpc8250.inf` |
| `ACPI\QCOM058A` | `ACPI\QCOM258A` | `qcadsprpcd8250.inf` |

## Why this avoids the previous boot failures

The earlier broad Kona injections failed with `0xc0000428` on unrelated Qualcomm drivers. This experiment does not touch those packages.

It also does not modify the selected INF files. Modified INF files invalidate their catalog signatures, so this package copies and installs the original signed files only.

## Scripts

Prepare signed package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\prepare-audio-alias-phase1.ps1
```

Apply to offline phone Windows partition while in Mass Storage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\apply-audio-alias-phase1-admin.ps1 -WindowsDrive D
```

Rollback aliases if boot or device state regresses:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\rollback-audio-alias-phase1-admin.ps1 -WindowsDrive D -DisableServices
```

## Success criteria

- Windows still boots normally.
- No new `0xc0000428`.
- `ACPI\QCOM05D2`, `ACPI\QCOM0560`, or `ACPI\QCOM058A` bind to the copied signed packages.
- New downstream audio nodes or setupapi evidence appears.

## Stop criteria

- Boot regression.
- Recovery screen.
- New signature error.
- USB input/network baseline breaks.

If any stop condition occurs, use the rollback script first, then collect logs.
