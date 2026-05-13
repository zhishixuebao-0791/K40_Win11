# Phase11 UEFI Build Result - 2026-05-13

## Goal

Phase11 keeps the Phase10 audio HID mapping, but narrows the DSP-root dependency experiment.

Phase10 result showed:

- `SPSS/QCOM068D` appeared in Windows PnP, but failed at driver start with Code 31.
- `ADSP/QCOM061B`, `CDSP/QCOM06B0`, and `SCSS/QCOM061F` still did not appear in Windows PnP.
- `SPSS` had a smaller top-level `_DEP` set than `ADSP/CDSP/SCSS`.

Phase11 therefore changes only the top-level `_DEP` for `ADSP`, `CDSP`, and `SCSS` to match the working-enough `SPSS` dependency shape:

```asl
Name(_DEP, Package(0x3)
{
    \_SB_.PEP0,
    \_SB_.PILC,
    \_SB_.RPEN
})
```

This tests whether `ARPC`, `SSDD`, `GLNK`, or `IPC0` dependency gating was preventing `ADSP/CDSP/SCSS` from enumerating.

## Build Result

Build succeeded.

- Build script: `/home/ucchip/K40_Win11/Alioth-Engineering/tools/build-acpi-hid-phase11.sh`
- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase11-build-20260513-141151.log`
- Output image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase11-20260513-141246.img`
- SHA256: `6e2ef6f7a0a6025c4fc263f13360e25c389ef6743ea708eee2d56c6c74b6c960`

## Build Verification

The script verified the patched AML contains:

- `QCOM06E0`
- `QCOM0620`
- `QCOM061B`
- `QCOM06B0`
- `QCOM068D`
- `QCOM061F`
- `QCOM0520`
- `QCOM0532`
- `MTP08280`

The script also verified the stale HID values are absent:

- `QCOM051D`
- `QCOM0523`
- `QCOM0599`
- `QCOM0521`

Phase11-specific verification passed: the `ADSP`, `CDSP`, and `SCSS` device blocks no longer include `ARPC` in their top-level `_DEP` before `_HID`.

## Win10 Validation Plan

Copy the image back to:

```text
C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase11-20260513-141246.img
```

Flash or boot this UEFI on K40, enter Windows, then run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
```

Return to Mass Storage and collect the generated log folders.

Success criteria for this phase:

- `ADSP/QCOM061B` appears in PnP.
- `CDSP/QCOM06B0` appears in PnP.
- `SCSS/QCOM061F` appears in PnP.

Do not inject or change drivers before this validation. Phase11 is only an ACPI dependency-gating test.
