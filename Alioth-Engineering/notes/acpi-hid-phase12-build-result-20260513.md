# Phase12 UEFI Build Result - 2026-05-13

## Goal

Phase12 keeps the successful Phase11 DSP-root enumeration shape and adds only qcsubsys-facing ACPI metadata to the four failing Surface 8280 subsystem roots:

- `ADSP / QCOM061B`
- `CDSP / QCOM06B0`
- `SCSS / QCOM061F`
- `SPSS / QCOM068D`

The build does not change driver packages, WDAC, or the Phase11 `_DEP` reduction.

## Phase12 Change

The new build script is:

```text
/home/ucchip/K40_Win11/Alioth-Engineering/tools/build-acpi-hid-phase12.sh
```

It preserves the Phase11 dependency set for `ADSP`, `CDSP`, and `SCSS`:

```asl
Name(_DEP, Package(0x3)
{
    \_SB_.PEP0,
    \_SB_.PILC,
    \_SB_.RPEN
})
```

It then adds `_DSD` device-property metadata to `ADSP`, `CDSP`, `SCSS`, and `SPSS` using the standard ACPI device-properties UUID. The metadata is based on the qcsubsys registry/property names visible in the available 8280/8250 packages and driver strings:

- `SubsystemName`
- `RPEC`
- `Interfaces`
- ADSP-only `PDInfo.NumPDs`, `PDInfo.0.PDName`, and `PDInfo.0.GUID`

Important GUIDs included in AML:

- ADSP RPEC: `{99CA9C16-4E1E-4970-B49E-2CA56753588B}`
- CDSP RPEC: `{DDAE0B76-6595-4469-A254-AD116DC4012A}`
- SCSS RPEC: `{2c17a886-fe66-4e10-a6ec-9e9ea942eb24}`
- SPSS RPEC: `{3692ce30-33e7-4b69-9f09-83efe52e107d}`
- PIL TZ interface: `{E2EB84C1-4068-4994-A48F-F3AC0D38DC29}`
- FastRPC interface: `{E022FF1A-C06C-42D8-94FE-90D876FC0B75}`
- GLINK interface: `{F9D15453-8335-434c-AA72-FCD925F135F3}`
- ADSP audio PD: `{0A35A787-A69F-4A90-8B78-0710BA7BB82C}`, `msm/adsp/audio_pd`

## Build Result

Build succeeded.

- Build log: `/home/ucchip/K40_Win11/Alioth-Engineering/logs/mu-alioth-phase12-build-20260513-195237.log`
- Output image: `/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase12-20260513-195332.img`
- SHA256: `63b32591f672fbb95a63eb1162da8e8a98f28f1785628e86ef9a49b5a4922750`
- Image size: `2119680` bytes

`iasl -f` still reports the same upstream legacy ACPICA errors already present in previous phases. AML generation completed and the Phase12 verification passed.

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
- `PDInfo.0.PDName`
- `msm/adsp/audio_pd`
- all four RPEC GUIDs
- PIL TZ, FastRPC, and GLINK interface GUIDs

The script also verified stale DSP HID values are absent:

- `QCOM051D`
- `QCOM0523`
- `QCOM0599`
- `QCOM0521`

## Validation Plan

Boot or flash:

```text
/home/ucchip/K40_Win11/UEFI-Images/Mu-alioth-1-acpi-hid-phase12-20260513-195332.img
```

Then run the existing phone-side diagnostics:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1
powershell -ExecutionPolicy Bypass -File C:\Code\REDMIK40_Win11\Trace-QcsubsysAcpiShape.ps1
```

Decision points:

- If `QCOM061B/QCOM06B0/QCOM061F/QCOM068D` move from Code 31 to started, continue the audio child stack.
- If the Code 31 status changes, use the new status as the next blocker.
- If status stays `0xC0000034` / `0xC000003B`, the failing inputs are likely not supplied through ACPI `_DSD`; next step should be either registry-backed qcsubsys property injection or restoring a single dependency at a time, not more broad driver injection.
