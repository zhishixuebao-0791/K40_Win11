# Driver Requirements

## Short answer

You need both driver layers if the goal is a functional Windows installation.

## Why one pack is not enough

`Kona` / `SM8250` common drivers usually carry the SoC-facing pieces:

- ACPI bridge
- buses
- PMIC
- power management
- UFS or storage helpers
- USB
- graphics base
- cellular plumbing
- GNSS
- audio base

`Alioth` device drivers or extensions usually carry board-specific pieces:

- touchscreen
- panel or display tuning
- storage extension packages
- audio tuning or ACDB linkage
- sensors calibration or sensor routing
- WLAN / Bluetooth board routing
- camera sensor mappings
- device information and setup extensions

## Practical rule

- If you only have `Kona` drivers, Windows may boot but many alioth peripherals
  will still be missing or misconfigured.
- If you only have `alioth` drivers, they still depend on the underlying SoC
  driver base to bind correctly.

## Engineering implication

This scaffold keeps the common Qualcomm layer and the device-specific alioth
layer separate on purpose, because later packaging should preserve that split.

In public WOA manifests, the common SM8250 layer is typically referenced as
`components\QC8250`.
