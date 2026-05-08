# ACPI HID Phase7 Build Result - 2026-05-08

## Output

- Image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase7-20260508-120337.img`
- SHA256: `faa5a96a21d02314496708215cec355bcf53ae08157d9633f700665adf28669f`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase7-build-20260508-120230.log`
- Build status: success

## ACPI HID Remaps

Phase7 keeps the Phase6 dependency remaps:

- `QCOM051B -> QCOM251B`
- `QCOM0533 -> QCOM2533`
- `QCOM050B -> QCOM250B`
- `QCOM058D -> QCOM258D`
- `QCOM050E -> QCOM250E`
- `QCOM057C -> QCOM257C`
- `QCOM058B -> QCOM258B`

Phase7 changes SSDD from the Phase6 `QCOM2522` route to the official Surface Pro 9 5G `qcsubsys8280` route:

- `QCOM0522/QCOM2522 -> QCOM0620`

Static AML verification passed:

- Present: `QCOM251B`, `QCOM2533`, `QCOM250B`, `QCOM258D`, `QCOM250E`, `QCOM257C`, `QCOM258B`, `QCOM0620`
- Absent: `QCOM051B`, `QCOM0533`, `QCOM050B`, `QCOM058D`, `QCOM050E`, `QCOM057C`, `QCOM058B`, `QCOM0522`, `QCOM2522`

## Win10 Validation Steps

Copy this image back to:

```powershell
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase7-20260508-120337.img
```

Boot it first. Do not flash persistently yet:

```powershell
fastboot boot C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase7-20260508-120337.img
```

After Windows boots, collect:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-Qcsubsys8280Experiment.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

## Validation Gate

The next pass is successful if:

- SSDD appears as `ACPI\QCOM0620`.
- Windows selects `qcsubsys8280.inf` / `oem15.inf` instead of `qcsubsys8250.inf` / `oem5.inf`.
- No Code 52 / `0xC0000428` appears for `qcsubsys8280.sys`.

If `QCOM0620` binds to `qcsubsys8280` without Code 52, continue functional audio dependency diagnostics. If `qcsubsys8280` is selected but still blocked by Code 52, then the Microsoft Driver Policy problem is confirmed for this official package and the next branch is WDAC/base-policy work again.
