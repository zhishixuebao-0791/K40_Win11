# ACPI HID Phase4b Plan - 2026-04-29

## Goal

Advance the audio dependency chain by one narrow step after Phase4a confirmed `QCOM258D/qcGLINK` is OK/running.

## New Phase4b ACPI HID remap

| ACPI device | Current Mu-Silicium HID | Kona driver HID | Driver package |
|---|---:|---:|---|
| `IPC0` | `QCOM050E` | `QCOM250E` | `qcipcrouter8250.inf` |

## Preserved remaps from Phase4a

| ACPI device | Native HID | Kona HID |
|---|---:|---:|
| `PILC` | `QCOM051B` | `QCOM251B` |
| `RPEN` | `QCOM0533` | `QCOM2533` |
| `SCM0` | `QCOM050B` | `QCOM250B` |
| `GLNK` | `QCOM058D` | `QCOM258D` |

## Validation gate

After booting the Phase4b image and injecting only IPCRouter, `ACPI\QCOM250E` should bind to the `QCIPC_ROUTER` service.

Do not add `ADSP/QSM/SSDD` in this phase. If `QCOM250E` fails with Code 31, inspect IPC0 `_CRS`, `_DEP`, and IPCRouter runtime logs before expanding the HID remaps.
