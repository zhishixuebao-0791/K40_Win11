# ACPI HID Phase5 Build Result - 2026-05-06

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase5-20260506-065212.img`
- SHA256: `f37bdcf15a6c420a5fd788332e581843962f31674e7a1ca3325eaa3169b4572c`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase5-build-20260506-065110.log`
- Build status: success

## ACPI HID Remaps

Phase5 keeps all Phase4b remaps and adds the two newly exposed dependency devices:

- `QCOM051B -> QCOM251B`
- `QCOM0533 -> QCOM2533`
- `QCOM050B -> QCOM250B`
- `QCOM058D -> QCOM258D`
- `QCOM050E -> QCOM250E`
- `QCOM057C -> QCOM257C`
- `QCOM058B -> QCOM258B`

Static ASL/AML verification passed:

- Present: `QCOM251B`, `QCOM2533`, `QCOM250B`, `QCOM258D`, `QCOM250E`, `QCOM257C`, `QCOM258B`
- Absent: `QCOM051B`, `QCOM0533`, `QCOM050B`, `QCOM058D`, `QCOM050E`, `QCOM057C`, `QCOM058B`

## Win10 Validation Steps

Copy this image back to:

```powershell
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase5-20260506-065212.img
```

Boot it first, do not flash persistently yet:

```powershell
fastboot boot C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase5-20260506-065212.img
```

After Windows boots once and you return to Mass Storage, apply only the Phase5 PDSR/TFTP driver package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-pdsr-tftp-phase5-admin.ps1" -WindowsDrive D
```

Then boot Phase5 again and collect:

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

The next pass is successful only if these devices bind without new boot-blocking recovery errors:

- `PDSR/QCOM257C` should bind to `qcpdsr`.
- `TFTP/QCOM258B` should bind to `QcTftpKmdf`.

If both bind cleanly, inspect whether additional audio/ADSP devices appear, especially `SSDD`, `QSM`, `ADSP`, `ARPC`, or `ARPD`.
