# ACPI HID Phase6 Build Result - 2026-05-06

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase6-20260506-085247.img`
- SHA256: `065ea9b056adc6c96935916de52ae3706deb2d708cd5e4d664a14097c57af141`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase6-build-20260506-085143.log`
- Build status: success

## ACPI HID Remaps

Phase6 keeps all Phase5 remaps and adds the narrow SSDD remap:

- `QCOM051B -> QCOM251B`
- `QCOM0533 -> QCOM2533`
- `QCOM050B -> QCOM250B`
- `QCOM058D -> QCOM258D`
- `QCOM050E -> QCOM250E`
- `QCOM057C -> QCOM257C`
- `QCOM058B -> QCOM258B`
- `QCOM0522 -> QCOM2522`

Static ASL/AML verification passed:

- Present: `QCOM251B`, `QCOM2533`, `QCOM250B`, `QCOM258D`, `QCOM250E`, `QCOM257C`, `QCOM258B`, `QCOM2522`
- Absent: `QCOM051B`, `QCOM0533`, `QCOM050B`, `QCOM058D`, `QCOM050E`, `QCOM057C`, `QCOM058B`, `QCOM0522`

## Win10 Validation Steps

Copy this image back to:

```powershell
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase6-20260506-085247.img
```

Boot it first, do not flash persistently yet:

```powershell
fastboot boot C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase6-20260506-085247.img
```

After Windows boots once and you return to Mass Storage, apply only the Phase6 SSDD driver package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-ssdd-phase6-admin.ps1" -WindowsDrive D
```

Then boot Phase6 again and collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Trace-AliothAcpiPhase3State.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Trace-AliothAudioDependencyState.ps1"
```

If possible, also collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\trace-alioth-audio-roots.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\trace-alioth-audio-root-causes.ps1"
```

## Validation Gate

The next pass is successful if:

- `SSDD/QCOM2522` binds to `qcsubsys`.
- `qcsubsys` is `Running`, or at minimum `SSDD` moves away from Code 28.
- No new boot-blocking recovery or signature error appears.

If `QSM/QCOM0520`, `ADSP/QCOM051D`, `ARPC/QCOM0560`, or `ARPD/QCOM058A` appears after this pass, collect fresh logs before any further ACPI remap.
