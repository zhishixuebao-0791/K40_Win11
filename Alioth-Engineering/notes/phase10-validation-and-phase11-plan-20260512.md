# Phase10 validation and Phase11 plan - 2026-05-12

## Inputs

- UEFI image: `Mu-alioth-1-acpi-hid-phase10-20260512-131428.img`
- Phone log: `D:\Code\REDMIK40_Win11\AudioDependencyState_20260512_102234`

## Phase10 result

The stable pieces stayed stable:

- `PILC 8280 / ACPI\QCOM06E0`: `Status=OK`, `ProblemCode=0`, service `qcPILC`
- `SSDD phase7 / ACPI\QCOM0620`: `Status=OK`, `ProblemCode=0`, service `qcsubsys`
- `RPEN / QCOM2533`, `SCM0 / QCOM250B`, `GLNK / QCOM258D`, `IPC0 / QCOM250E`, `PDSR / QCOM257C`, and `TFTP / QCOM258B` remain OK.

Phase10 produced only a partial 8280 DSP-root exposure:

- `SPSS 8280 / ACPI\QCOM068D`: present, matched `oem15.inf`, service `qcsubsys`, but `ProblemCode=31`
- `ADSP 8280 / ACPI\QCOM061B`: not present
- `CDSP 8280 / ACPI\QCOM06B0`: not present
- `SCSS 8280 / ACPI\QCOM061F`: not present

Native or remaining nodes:

- `CDI native / ACPI\QCOM0532`: present, `ProblemCode=28`, no service
- `QSM native / ACPI\QCOM0520`: present, `ProblemCode=28`, no service
- `FSA4480`: still `ProblemCode=51`; keep it out of the current DSP-root path.

## Interpretation

This is no longer a PILC problem.

The important new evidence is that `QCOM068D` can reach Windows and bind to `qcsubsys`, so the Phase10 ACPI patch path is viable. The failure is now narrower:

- Runtime Windows does not enumerate `QCOM061B`, `QCOM06B0`, or `QCOM061F`.
- `QCOM068D` starts driver selection but fails device start with Code 31.
- `QCOM068D` depends on `QCOM0519`, `QCOM06E0`, and `QCOM2533`; `QCOM06E0` and `QCOM2533` are OK, so `QCOM0519/PEP0` state must be checked before assuming the `qcsubsys` driver itself is wrong.

## Next diagnostic action

Before building Phase11, collect runtime ACPI state with the updated script:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

The updated `Trace-AliothAcpiPhase3State.ps1` now includes Phase10 IDs:

- `QCOM0532`
- `QCOM0521`
- `QCOM061F`
- `QCOM051D`
- `QCOM061B`
- `QCOM0523`
- `QCOM06B0`
- `QCOM0599`
- `QCOM068D`

## Phase11 direction

If runtime ACPI confirms only `QCOM068D` appears:

- Do not inject more drivers.
- Inspect Phase10 AML patch positions for `ADSP`, `CDSP`, and `SCSS`; the compiled AML contains those strings, but Windows did not enumerate the devices.
- Build Phase11 to patch the actual active devices or their `_STA/_DEP` path, not only the string occurrence.

If runtime ACPI shows `QCOM061B/QCOM06B0/QCOM061F` in the table but not in PnP:

- Focus on `_STA`, `_DEP`, and parent scope ordering.
- Check whether missing `QCOM0519/PEP0` or unresolved `ARPC` blocks enumeration.

If all 8280 DSP roots appear but fail Code 28:

- Install only the matching Surface 8280 extension packages.

If `QCOM068D` remains Code 31:

- Trace `QCOM0519` and related PEP/dependency state first. Do not change WDAC or broad-inject 8250 packages.
