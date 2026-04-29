# Alioth PlatformID Analysis

## What is known

From `Mu-Silicium\Platforms\Xiaomi\aliothPkg\alioth.dsc`:

- Manufacturer: `Xiaomi`
- Retail model: `alioth`
- Device model `0`: `POCO F3` / `M2012K11AG` / `K11AG`
- Device model `1`: `Redmi K40` / `M2012K11AC` / `K11AC`
- Device model `2`: `Mi 11X` / `M2012K11AI` / `K11AI`

From existing `FirmwareGen` Xiaomi profiles:

- `Xiaomi.SDM855.POCO X3 Pro.vayu`
- `Xiaomi.SDM855.K20 Pro.raphael`
- `Redmi.SM_RENNELL_AB.Note 9S.miatoll`

From generic Qualcomm 865/8250 profiles:

- `Qualcomm.SM_KONA.MTP.*`
- `Qualcomm.SMP_KONA.MTP.*`

## Current inference

The alioth profile should not use the generic Qualcomm MTP IDs as its final
device identity.

The current highest-confidence candidate set is:

- `Redmi.SM8250.Redmi K40.alioth`
- `Xiaomi.SM8250.POCO F3.alioth`
- `Mi.SM8250.Mi 11X.alioth`

## Why this is still not final

We have not yet observed the runtime-reported PlatformID from a working alioth
Windows or PE environment.

The final value should be verified at runtime using one of these methods:

1. Boot an experimental Windows image and inspect the platform string used by
   `Img2Ffu` / setup / hardware identification.
2. Dump SMBIOS and ACPI information from the running environment.
3. Compare against a known public `alioth` Windows driver package if one
   becomes available.

## Practical recommendation

For experimental work, keep all three alioth family IDs in the template until
the real runtime value is captured.
