# Alioth Windows Engineering Scaffold

This folder is a working scaffold for Redmi K40 / Poco F3 / Mi 11X (`alioth`)
Windows-on-ARM packaging.

It is not a ready-to-flash driver pack.

## What is required

For a usable Windows install on `alioth`, you realistically need both layers:

1. A platform/common Qualcomm driver pack for `Kona` / `SM8250`.
2. A device-specific Xiaomi `alioth` pack.

Reason:

- `Mu-Silicium` already shows `Mass Storage = yes` and `Windows Boot = yes`.
- The same status page also shows most Windows hardware features still missing.
- That means UEFI boot support exists, but Windows-side device enablement is still
  dependent on drivers.

## Local source mapping

This scaffold was derived from the following local sources:

- `.\sound_code\Mu-Silicium\Platforms\Xiaomi\aliothPkg`
- `.\sound_code\Mu-Silicium\Resources\Configs\alioth.conf`
- `.\sound_code\FirmwareGen\FirmwareGen\DeviceProfiles\MTP8250MaximizedForWindows.xml`
- `.\sound_code\windows_xiaomi_platforms_sparse\definitions\Desktop\ARM64\Internal\vayu.xml`
- `.\sound_code\windows_xiaomi_platforms_sparse\definitions\Desktop\ARM64\PE\vayu.xml`
- `.\sound_code\windows_xiaomi_platforms_sparse\tools\pack-vayu.cmd`
- `.\sound_code\device_xiaomi_alioth`
- `.\sound_code\vendor_xiaomi_alioth`
- `.\sound_code\firmware-xiaomi-alioth`

## Directory layout

- `profiles`
  - FirmwareGen device profile templates.
- `definitions`
  - DriverUpdater / FFU driver manifests.
- `components`
  - Expected placement for future driver payloads.
- `tools`
  - Packaging helper templates.
- `notes`
  - Short engineering notes and TODOs.

## Current assumptions

- `alioth` is a `Kona` / `SM8250` phone.
- Storage is UFS with `4096` byte logical sector size.
- Final FFU generation should use a device-specific profile, not the generic
  `MTP8250` partition layout.

## Next steps

1. Dump and normalize the final `alioth` GPT layout you actually want to ship.
2. Confirm the final Windows `PlatformIDs` exposed by alioth UEFI/ACPI.
3. Populate `components\QC8250` with the common SM8250 driver payload.
4. Populate `components\Devices\Alioth` with the device-specific payload.
5. Replace all TODO placeholders in `definitions` and `profiles`.
6. Only then use `FirmwareGen` to build a real FFU.
