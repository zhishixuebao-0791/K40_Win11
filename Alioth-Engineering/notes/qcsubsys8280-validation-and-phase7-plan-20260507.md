# qcsubsys8280 validation and Phase7 plan - 2026-05-07

## Inputs

- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260507_182603`
- `D:\Code\REDMIK40_Win11\QcsubsysCiDeep_20260507_182854`

## Findings

The official Surface Pro 9 5G `qcsubsys8280` package was staged, but it did not bind to the live SSDD device.

Evidence:

- `qcsubsys8280.inf` exists in the driver store as `oem15.inf`.
- `qcsubsys8280.inf` signer is `Microsoft Windows Hardware Compatibility Publisher`.
- The live SSDD instance is still `ACPI\QCOM2522\2&daba3ff&0`.
- The live SSDD instance is still bound to `oem5.inf`, original name `qcsubsys8250.inf`.
- The selected matching device ID is still `ACPI\QCOM2522`.
- The device still has `CM_PROB_UNSIGNED_DRIVER` / problem status `0xC0000428`.
- The older native `QCOM0522` registry instance contains the added compatible ID `ACPI\QCOM0620`, but it is not the active bound SSDD instance.

The important ranking issue is that the current ACPI hardware ID `ACPI\QCOM2522` is an exact match for the old unsigned `qcsubsys8250` package. The added compatible ID `ACPI\QCOM0620` is weaker and does not override the exact match.

## Conclusion

The failed result does not prove `qcsubsys8280.sys` is rejected by Microsoft Driver Policy. It proves the experiment did not force Windows to select `qcsubsys8280`; Windows kept selecting the old exact-match `qcsubsys8250`.

Do not continue WDAC/base-policy experiments for this branch yet. The safer next step is ACPI-first:

- Change the SSDD ACPI `_HID` from `QCOM0522 -> QCOM0620` in the UEFI image.
- Keep the other Phase6 remaps unchanged.
- Do not add or remove `driversipolicy.p7b`.
- Keep the official `qcsubsys8280` package staged.

## Phase7 target

Phase7 should keep:

- `QCOM051B -> QCOM251B`
- `QCOM0533 -> QCOM2533`
- `QCOM050B -> QCOM250B`
- `QCOM058D -> QCOM258D`
- `QCOM050E -> QCOM250E`
- `QCOM057C -> QCOM257C`
- `QCOM058B -> QCOM258B`

Phase7 should replace the Phase6 SSDD mapping:

- old Phase6: `QCOM0522 -> QCOM2522`
- new Phase7: `QCOM0522 -> QCOM0620`

Expected result:

- SSDD appears as `ACPI\QCOM0620`.
- Windows selects `qcsubsys8280.inf` / `oem15.inf` as an exact hardware-ID match.
- If Code 52 disappears, Microsoft Driver Policy accepts this official package.
- If Code 52 remains for `qcsubsys8280.sys`, then the policy problem is confirmed even for WHCP package and WDAC/base-policy work becomes unavoidable.

## Validation after Phase7 boot

Collect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-AliothAcpiPhase3State.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-AliothAudioDependencyState.ps1"
```

Then collect a qcsubsys-specific diagnostic updated to search `QCOM0620`, `qcsubsys8280`, and `oem15.inf`, because the current `QcsubsysCiDeep` script is still focused on `QCOM2522` / `qcsubsys8250`.
