# Offline Driver Injection And OOBE Bypass

## Goal

Make the existing `alioth` Windows image easier to validate when input devices are
unstable during OOBE.

This plan does two things:

1. Inject the public `Kona / SM8250` platform pack offline.
2. Stage an unattend file so the image can skip most OOBE interaction and create
   a local admin account automatically.

## Why this is the best current path

`Mu-Silicium` already proves that:

- Windows boot works on `alioth`
- mass storage works on `alioth`
- Windows-side `USB Host Mode` is still marked unavailable
- Windows-side `Touchscreen` is still marked unavailable

That means the current blocker is not deployment anymore. The blocker is platform
device enablement, especially USB host.

## Recommended driver source order

1. `C:\yjc_code\K40_Win11\sound_code\windows_silicon_qcom_kona`
   This is the `QC8250` / Snapdragon 865 platform BSP and contains:
   - `Drivers\USBHost\QcXhciFilter8250.inf`
   - `Drivers\USB\TypeCPortManager\qcusbctcpm8250.inf`
   - `Drivers\USB\UCSI\qcusbcucsi8250.inf`
   - many SoC dependencies those USB packages rely on

2. `C:\yjc_code\K40_Win11\sound_code\windows_xiaomi_platforms_full\components\ANYSOC`
   Use the generic mobile support pieces for:
   - `usbdefaults.inf`
   - `fsa4480.inf`

## Validation flow

1. Put the phone into `Mass Storage`.
2. Identify the offline Windows drive, for example `D:`.
3. Run the admin script:
   - `Alioth-Engineering\tools\apply-alioth-offline-fixes-admin.ps1`
4. Exit `Mass Storage`.
5. Boot Windows again.
6. If input still fails or Windows crashes, go back to `Mass Storage`.
7. Run:
   - `Alioth-Engineering\tools\collect-alioth-offline-logs.ps1`

## Expected first result

The most realistic first success criterion is:

- Windows no longer blocks on manual OOBE interaction
- or USB host becomes more stable because the `Kona` platform stack binds better

Do not assume touch will work from this step alone. Touch is still likely waiting
on an `alioth`-specific layer.

## Current Alioth-Specific Findings

- Public `windows_silicon_qcom_kona` drivers stage successfully, but the USB Host
  pieces are not currently binding on `alioth`.
- Standard `SkipMachineOOBE` and `SkipUserOOBE` staging is not suppressing OOBE on
  this deployed image.
- The current fallback path is:
  1. use persistent UEFI on `boot_a`
  2. use `prepare-alioth-audit-boot-admin.ps1` to force Audit Mode and suppress
     auto-repair during testing
  3. use `dump-offline-hardware-ids-admin.ps1` to export alioth's actual offline
     hardware IDs for INF matching work
