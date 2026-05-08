# ACPI HID Phase8 Build Result - 2026-05-08

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase8-20260508-181146.img`
- SHA256: `776652ab98e4e11c9e9ed9d90837135f45c4fc77bab51b49d6eed320f5d562af`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase8-build-20260508-181042.log`
- Build status: success

## ACPI HID Remaps

Phase8 keeps the working Phase7 dependency route:

- `QCOM0533 -> QCOM2533`
- `QCOM050B -> QCOM250B`
- `QCOM058D -> QCOM258D`
- `QCOM050E -> QCOM250E`
- `QCOM057C -> QCOM257C`
- `QCOM058B -> QCOM258B`
- `QCOM0522/QCOM2522 -> QCOM0620`

Phase8 changes the PILC route:

- `QCOM051B/QCOM251B -> QCOM06E0`

Static AML verification passed:

- Present: `QCOM06E0`, `QCOM2533`, `QCOM250B`, `QCOM258D`, `QCOM250E`, `QCOM257C`, `QCOM258B`, `QCOM0620`
- Absent: `QCOM051B`, `QCOM251B`, `QCOM0533`, `QCOM050B`, `QCOM058D`, `QCOM050E`, `QCOM057C`, `QCOM058B`, `QCOM0522`, `QCOM2522`

## Notes

The build log includes a missing `*.pdb` copy message under `DxeCore`, but the make rule marks it as ignored and the final build status is success.

The build script also prints that the local Mu-Silicium repository is old. This is informational for the current experiment; avoid pulling upstream during this validation series unless we intentionally start a new baseline.

## Win10 Validation Steps

Copy this image back to:

```powershell
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase8-20260508-181146.img
```

Before booting Phase8, stage the Surface Pro 9 5G PIL candidate while the phone is in Mass Storage:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-Qcpil8280Candidate-Admin.ps1" -WindowsDrive D
```

Boot first. Do not flash persistently yet:

```powershell
fastboot boot C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase8-20260508-181146.img
```

After Windows boots, collect:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothPilcFailure.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-Qcsubsys8280Experiment.ps1
```

## Validation Gate

The next pass is successful if:

- `QCOM06E0Present=True`
- `QCOM251B` is absent or phantom only
- `qcPILC` binds to the Surface `qcpil.sys` path
- PILC Problem Code becomes `0`
- `QCOM0620/qcsubsys8280` remains OK
