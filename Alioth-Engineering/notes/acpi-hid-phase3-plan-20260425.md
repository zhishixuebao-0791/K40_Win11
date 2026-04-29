# ACPI HID Phase 3 Plan

## Goal

Stop modifying driver INF files and stop broad driver injection. Instead, make Mu-alioth expose the dependency ACPI IDs expected by the original signed Kona drivers.

## Phase 3a Scope

- `PILC`: change `_HID` from `QCOM051B` to `QCOM251B`.
- `RPEN`: change `_HID` from `QCOM0533` to `QCOM2533`.

These two devices are already enumerated by Windows as native 05xx devices. Previous offline CompatibleIDs aliases did not persist after boot, so this phase moves the mapping into AML.

## Current Status

- Patched source: `Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.asl`.
- Patched AML: `Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.aml`.
- Direct binary patching of the existing `Mu-alioth-1.img` is not viable because the ACPI payload is inside the compressed UEFI FV.
- The Android boot image kernel payload was also decompressed and scanned. The decompressed payload still does not contain plain `QCOM051B`, `QCOM0533`, `QCOM251B`, or `QCOM2533`, so a safe equal-length byte patch is not available.

## Build Requirement

Rebuild Mu-Silicium on Linux/WSL Ubuntu 24.04. The current Windows host does not have `wsl`, `make`, `nasm`, `mono`, `clang/lld`, or `aarch64-linux-gnu-gcc`.

Recommended command once WSL Ubuntu is available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\build-acpi-hid-phase3-wsl.ps1" -Clean -SetupApt
```

If dependencies are already installed in WSL:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\build-acpi-hid-phase3-wsl.ps1" -Clean
```

## Validation

Boot the newly built image with fastboot first. Do not flash it permanently until the boot result is confirmed.

Expected Windows-side results:

- `ACPI\QCOM251B` exists and binds to the original signed `qcpil8250` package.
- `ACPI\QCOM2533` exists and binds to the original signed `qcrpen8250` package.
- `QCOM051B` and `QCOM0533` should not reappear as the active device IDs.

If this works, continue with the next dependency layer. If this fails, the next debugging target is AML `_STA` / `_DEP` behavior rather than INF aliasing.
