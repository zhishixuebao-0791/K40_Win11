# Redmi K40 Driver Strategy Based on DriverDiagnostics_20260422_130006

## Summary

- Current system is usable enough for further work:
  - Windows boots
  - USB keyboard/mouse work when the hub is externally powered
  - USB Ethernet works
  - Display works
- Current system is not suitable for broad Qualcomm/Kona driver injection.
- Best next-step strategy is to keep the current baseline stable and only attempt very narrow, ID-driven driver experiments later.

## Evidence From The Diagnostic Package

### What works now

- USB stack is alive:
  - `USB xHCI Compliant Host Controller`
  - `USB Root Hub (USB 3.0)`
  - `Generic USB Hub`
  - `Synopsys USB 3.0 Dual-Role Controller`
- Input through powered hub works:
  - HID keyboard
  - HID mouse
- Wired networking works:
  - `ASIX AX88179 USB 3.0 to Gigabit Ethernet Adapter`

### What is still missing

- `65` problem devices in total
- `64` devices are `ConfigManagerErrorCode = 28` (`driver not installed`)
- `1` device is `ConfigManagerErrorCode = 51`
- Missing devices are dominated by Qualcomm ACPI nodes such as:
  - `ACPI\VEN_QCOM&DEV_050A&SUBSYS_MTP08250`
  - `ACPI\VEN_QCOM&DEV_0518&SUBSYS_MTP08250`
  - `ACPI\VEN_QCOM&DEV_0511&SUBSYS_MTP08250`
  - `ACPI\VEN_QCOM&DEV_0512&SUBSYS_MTP08250`
  - `ACPI\VEN_QCOM&DEV_0593&SUBSYS_MTP08250`
  - `ACPI\VEN_QCOM&DEV_058C&SUBSYS_MTP08250`
  - `ACPI\VEN_FSA0&DEV_4480&SUBSYS_MTP08250`

### Audio-specific evidence

- Sound settings show no output device and no input device.
- No `MEDIA`-class device is visible in the current signed-driver snapshot.
- The diagnostics package does **not** show the classic Qualcomm 8250 audio root IDs needed by the public Kona audio stack, such as:
  - `ADCM\VEN_QCOM&DEV_2525...`
  - `AUDD\VEN_QCOM&DEV_2537...`
  - `AUDD\QCOM252C`
  - `ADSP\QCOM2510`
  - `ACPI\QCOM2560`
  - `ACPI\QCOM258A`
  - `ACPI\QCOM25D2`

### Project Silicium alioth status

- `Mu-Silicium` currently marks `alioth` audio as unsupported:
  - `Speakers = ❌`
  - `Microphone = ❌`

## Main Conclusion

The most suitable driver plan is:

1. Keep the current working baseline stable.
2. Stop all broad Qualcomm/Kona driver injection.
3. Treat internal audio as **currently blocked by missing alioth-specific enablement**, not as a simple missing generic INF.
4. Only run future experiments with a narrow, class-by-class, hardware-ID-driven package.

## What Not To Do

Do **not** repeat any of the following:

- Do not inject the whole `windows_silicon_qcom_kona` tree.
- Do not inject `Drivers\\SOC`.
- Do not inject `Drivers\\USBFn`.
- Do not inject boot-start PMIC / PCIe / platform drivers just to chase one missing feature.
- Do not attempt to solve audio by “trying all 8250 audio drivers”.

Reason:

- Previous wide injection caused repeated `0xc0000428` boot failures.
- The diagnostic package shows that many expected root audio IDs are not even enumerated on this build.

## Recommended Plan

### Phase 0: Freeze The Current Working Baseline

Before any new driver work:

- Keep the current Windows partition as the “known usable” baseline.
- Keep `boot_b` as Android fallback.
- Export a fresh diagnostics package before every new experiment.
- If possible, make a partition-level backup before any narrow injection test.

### Phase 1: Use External Devices For Missing Features

For practical use right now:

- Keep using the powered USB hub.
- Use USB Ethernet for networking.
- If sound is needed immediately, prefer:
  - USB audio dongle
  - USB sound card
  - Type-C audio device that enumerates as standard USB audio

This is currently the fastest and lowest-risk way to get working sound.

### Phase 2: Build A Driver Roadmap By Priority

Priority should be:

1. Stable login/session flow
2. External-input stability
3. External audio workaround
4. Internal audio
5. Touchscreen
6. Sensors / battery / charging polish

Reason:

- The system is already useful with powered USB input and Ethernet.
- Internal audio is currently not the easiest next win.

### Phase 3: Internal Audio Only As A Narrow Experiment

Only attempt internal audio when all of the following are true:

- The current baseline has been backed up.
- No broad platform driver injection is pending.
- A dedicated audio-only test bundle is prepared.

That audio-only test bundle must be limited to:

- `windows_silicon_qcom_kona\\Drivers\\Audio\\ADCM`
- `windows_silicon_qcom_kona\\Drivers\\Audio\\Device`
- `windows_silicon_qcom_kona\\Drivers\\Audio\\AudMiniport`
- `windows_silicon_qcom_kona\\Drivers\\Audio\\Slimbus`
- `windows_silicon_qcom_kona\\Drivers\\Audio\\RPC\\ADSPRPC`
- `windows_silicon_qcom_kona\\Drivers\\Audio\\RPC\\ADSPRPCD`
- `windows_silicon_qcom_kona\\Extensions\\Audio\\ACDB\\MTP`
- `windows_silicon_qcom_kona\\Extensions\\Audio\\AudMiniport\\MTP`
- `windows_silicon_qcom_kona\\Extensions\\Audio\\Device`

Even then, success is not guaranteed, because the current diagnostics do not show the expected audio root IDs.

### Phase 4: Real Fix Path For Internal Audio

The real long-term fix is likely one of these:

- Obtain an `alioth`-specific Windows device pack that includes audio calibration and board extensions.
- Obtain `alioth`-specific ACDB / DSP / board routing material.
- Modify ACPI / platform exposure so the expected Qualcomm audio root devices enumerate properly.

Without one of those, generic 8250 audio packages are unlikely to fully bind.

## Practical Recommendation

For your project right now, the most suitable path is:

1. Accept the current baseline as usable.
2. Do not touch broad driver injection anymore.
3. Use external USB audio if you need sound immediately.
4. Delay internal audio until:
   - an alioth-specific pack is found, or
   - we intentionally build an audio-only experimental bundle.

## Next Best Engineering Step

If continuing driver work later, the next best step is:

- create an **audio-only experiment package**
- inject it on top of a backupable baseline
- collect a new diagnostics package
- verify whether any of these device classes start appearing:
  - `MEDIA`
  - `ADCM`
  - `AUDD`
  - `ADSP`
  - `ACPI\\QCOM2560`
  - `ACPI\\QCOM258A`
  - `ACPI\\QCOM25D2`

If they do not appear, stop the experiment and do not widen scope.
