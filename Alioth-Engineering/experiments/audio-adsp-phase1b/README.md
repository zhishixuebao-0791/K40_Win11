# Alioth Audio ADSP Phase 1b

## Why this phase exists

Phase 1 successfully bound `ACPI\QCOM05D2` to the signed Kona `AudioService8250.inf` package through a CompatibleID alias.

It did not bind `QCOM0560/QCOM058A` because those device keys were not present in the offline registry at apply time. The likely missing earlier root is `ADSP`:

- DSDT exposes `ACPI\QCOM051D`
- Kona `qcsubsys8250.inf` expects `ACPI\QCOM251D`
- `qcsubsys8250.inf` creates `ADSP\QCOM2510` Slimbus children
- Those children are needed before later `SLM1/ADCM/AUDD` experiments make sense

## Scope

This phase only installs the original signed `qcsubsys8250.inf` package and adds this offline CompatibleID alias:

| Native Mu-alioth ID | Driver ID expected by Kona INF | Package |
| --- | --- | --- |
| `ACPI\QCOM051D` | `ACPI\QCOM251D` | `qcsubsys8250.inf` |

The INF is not edited.

## Apply

Run while the phone is in Mass Storage and the phone Windows partition is mounted as `D:`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\apply-audio-adsp-phase1b-admin.ps1 -WindowsDrive D
```

## Verify

After booting phone Windows, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AudioAliasState.ps1
```

Expected useful result:

- `ACPI\QCOM051D` binds to `Qualcomm(R) Aqstic(TM)` or `qcsubsys`
- New `ADSP\QCOM2510` devices appear
- Possibly later `SLM1`, `ADCM`, or `AUDD` evidence starts appearing

## Rollback

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\yjc_code\K40_Win11\tools\rollback-audio-adsp-phase1b-admin.ps1 -WindowsDrive D -DisableService
```

## Stop criteria

- Boot regression
- Recovery screen
- New signature error
- USB input/network baseline breaks
