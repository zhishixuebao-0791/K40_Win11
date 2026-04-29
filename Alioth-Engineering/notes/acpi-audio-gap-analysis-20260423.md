# ACPI Audio Gap Analysis 2026-04-23

## Current conclusion

- `alioth.dts` contains a clear board-level audio topology:
  - `fsa4480@42`
  - `bolero-cdc`
  - `tx-macro`
  - `rx-macro`
  - `wsa-macro`
  - `va-macro`
  - `sound { compatible = "qcom,kona-asoc-snd"; ... }`
- Windows currently enumerates only:
  - `ACPI\FSA04480`
- Windows does **not** enumerate the Qualcomm audio root devices that Kona audio drivers expect:
  - `ADCM`
  - `AUDD`
  - `ADSP\QCOM2510`
  - `SLM1\QCOM2524`
  - `ACPI\QCOM2560`
  - `ACPI\QCOM258A`
  - `ACPI\QCOM25D2`

## Why this matters

This means the current bottleneck is no longer "missing Windows audio INF files".  
The stronger hypothesis is:

1. The Linux/DTB side has the audio topology.
2. The current Mu-Silicium Windows path does not expose equivalent ACPI devices for alioth audio.
3. Therefore, injecting more Windows audio drivers is unlikely to make the missing root devices appear.

## Mu-Silicium local source evidence

- `alioth.dts` contains:
  - `fsa4480@42`
  - `bolero-cdc`
  - `tx-macro@3220000`
  - `rx-macro@3200000`
  - `wsa-macro@3240000`
  - `va-macro@3370000`
  - `qcom,model = "kona-mtp-snd-card"`
  - `qcom,msm-mbhc-usbc-audio-supported = <0x01>`
- `aliothPkg` local source contains almost no editable audio ACPI source.
- `Include\ACPI.inc` just packs a prebuilt `alioth/DSDT.aml`.

## Recommended next direction

- Keep Windows driver experiments narrow.
- Do not inject `Kona Audio` yet.
- Export richer ACPI evidence from current Windows.
- Compare that evidence directly against `alioth.dts`.
- If the gap remains the same, the next real engineering direction is `Mu-Silicium -> aliothPkg / ACPI / DSDT` rather than Windows INF work.
