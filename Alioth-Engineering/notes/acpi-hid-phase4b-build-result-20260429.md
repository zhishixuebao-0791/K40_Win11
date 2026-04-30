# ACPI HID Phase4b Build Result - 2026-04-29

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase4b-20260429-162458.img`
- SHA256: `1908e671fcf217385e2e36eefb2159c867bf97281e1db205aa3201413b8d9e49`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase4b-build-20260429-162355.log`

## ACPI HID Remaps

Phase4b keeps the previous Phase3/Phase4a remaps and adds IPC0:

- `PILC`: `QCOM051B` -> `QCOM251B`
- `RPEN`: `QCOM0533` -> `QCOM2533`
- `SCM0`: `QCOM050B` -> `QCOM250B`
- `GLNK`: `QCOM058D` -> `QCOM258D`
- `IPC0`: `QCOM050E` -> `QCOM250E`

## Static Verification

Verified in `Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.asl`:

- `QCOM251B` at line 61922
- `QCOM2533` at line 61917
- `QCOM250B` at line 80069
- `QCOM250E` at line 81136
- `QCOM258D` at line 81145

Verified in `DSDT.aml`:

- Present: `QCOM251B`, `QCOM2533`, `QCOM250B`, `QCOM250E`, `QCOM258D`
- Absent: `QCOM051B`, `QCOM0533`, `QCOM050B`, `QCOM050E`, `QCOM058D`

The EDK2 build completed successfully. The non-fatal `*.pdb` copy warnings are from post-build debug-symbol collection and did not block image generation.

## Win10 Validation Plan

Copy this image back to:

```powershell
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase4b-20260429-162458.img
```

First validation should use temporary boot only:

```powershell
fastboot boot C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase4b-20260429-162458.img
```

After one boot into Windows and returning to Mass Storage, inject only the IPC router dependency driver:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\apply-audio-ipcrouter-phase4b-admin.ps1" -WindowsDrive D
```

Then boot Phase4b again and collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\trace-alioth-audio-roots.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Code\REDMIK40_Win11\trace-alioth-audio-root-causes.ps1"
```

Expected gate for Phase4b: `IPC0/QCOM250E` should bind `qcipcrtr` and become `OK` or at least move away from Code 28. If this passes, the next narrow ACPI remap target should be selected from the updated dependency logs.
