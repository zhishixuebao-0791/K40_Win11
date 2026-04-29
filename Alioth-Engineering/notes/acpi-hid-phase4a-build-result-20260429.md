# ACPI HID Phase4a Build Result

## Result

Phase4a UEFI build completed successfully on Ubuntu.

Output image:

`/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase4a-20260429-120534.img`

SHA256:

`f7f9766b0c01f5ca2df88bf18c619c2c1225e882d0a32ec1a771eb42b0dfeb25`

Build log:

`/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase4a-build-20260429-120430.log`

## Static Verification

`DSDT.asl` and `DSDT.aml` under `sound_code/Mu-Silicium/Silicium-ACPI/Platforms/Xiaomi/alioth` contain:

- `QCOM251B`
- `QCOM2533`
- `QCOM250B`
- `QCOM258D`

They no longer contain:

- `QCOM051B`
- `QCOM0533`
- `QCOM050B`
- `QCOM058D`

## Transfer Back To Win10

Copy this one file back to the Win10 host:

`UEFI-Images/Mu-alioth-1-acpi-hid-phase4a-20260429-120534.img`

Suggested Win10 destination:

`C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase4a-20260429-120534.img`

## First Validation

First test with temporary boot only:

```powershell
& 'C:\yjc_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe' boot 'C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase4a-20260429-120534.img'
```

Do not permanently flash this image until boot and Windows-side diagnostics are confirmed.

After Windows boots, rerun:

- `D:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRoots.ps1`
- `D:\Code\REDMIK40_Win11\Trace-AliothAudioRootCauses.ps1`

Expected signs:

- `ACPI\QCOM250B` appears and binds to `qcscm`.
- `ACPI\QCOM258D` appears and binds to `qcglink`.
- `ACPI\QCOM050B` and `ACPI\QCOM058D` are no longer active devices.
- `ACPI\QCOM251B/qcPILC` either starts or changes error code.
