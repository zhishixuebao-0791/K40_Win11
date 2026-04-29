# Redmi K40 Next Steps Priority Plan

## Current Baseline

The current baseline is already useful:

- Windows boots
- Persistent UEFI boot works
- Powered USB hub works
- USB keyboard/mouse work
- USB Ethernet works
- Manual landscape rotation works
- A secondary local admin user (`jcyang`) can log in

This baseline should be preserved.

## What To Fix First

These are the items that are either already fixed or are the safest remaining fixes.

### 1. Keep The Current Session/Login Flow Stable

Target:

- stop recurring Sysprep/Audit friction
- stop relying on `Administrator`
- use `jcyang` as the normal administrator account

Reason:

- this is a usability issue, not a platform-driver issue
- it does not require risky Qualcomm platform injection

### 2. Keep External Input And Networking As The Working Standard

Target:

- always use the powered hub
- keep USB mouse/keyboard
- keep USB Ethernet

Reason:

- these already work
- they remove pressure to solve every internal device immediately

### 3. Do Not Touch Broad Platform Drivers

Do not inject:

- full `windows_silicon_qcom_kona`
- `Drivers\\SOC`
- `Drivers\\USBFn`
- other broad platform packages

Reason:

- previous attempts caused repeated boot failures
- the current diagnostics still show many missing Qualcomm ACPI devices
- broad injection is not compatible with the current stable baseline

## Safe Driver Candidates

Based on the diagnostics and the local source trees, there is only one clear exact-match, low-scope candidate currently visible:

### FSA4480

Diagnostic package shows:

- `ACPI\\VEN_FSA0&DEV_4480&SUBSYS_MTP08250`

Local repository exact INF match:

- [fsa4480.inf](</C:/yjc_code/K40_Win11/sound_code/windows_xiaomi_platforms_full/components/ANYSOC/Hardware/HARDWARE.USB.FSA4480/fsa4480.inf>)

Why this matters:

- it is a Type-C / analog switch related device
- it is not a giant platform bundle
- it is the cleanest exact-match candidate found so far

Why it is still not first:

- it is unlikely to be sufficient by itself to restore internal speaker output
- it may help only with USB-C / analog routing behavior

Conclusion:

- this is the first driver candidate worth testing later
- but not before the current stable session flow is fully settled

## Devices To Ignore For Now

### ACPI0011 / HID Button over Interrupt Driver

Current state:

- `ConfigManagerErrorCode = 51`

Reason to defer:

- not part of the core usability blockers
- keyboard, mouse, display, and Ethernet are already working

### The Large Qualcomm ACPI Device Block

Current diagnostics show many missing devices like:

- `QCOM050A`
- `QCOM0511`
- `QCOM0512`
- `QCOM0518`
- `QCOM058C`
- `QCOM0593`
- and many others

Reason to defer:

- these belong to the platform layer
- trying to “clean up as many as possible” is exactly the path that previously broke boot

## Internal Audio: Best Current Interpretation

The current evidence says:

- internal audio is not blocked by one simple missing generic INF
- it is blocked by missing `alioth`-specific board enablement and/or missing audio root-device exposure

Evidence:

- diagnostics do not show the expected Qualcomm audio root IDs such as:
  - `ADCM\\...`
  - `AUDD\\...`
  - `ADSP\\QCOM2510`
  - `ACPI\\QCOM2560`
  - `ACPI\\QCOM258A`
  - `ACPI\\QCOM25D2`
- local `Mu-Silicium` status for `alioth` still marks:
  - `Speakers = ❌`
  - `Microphone = ❌`

## Internal Audio Minimal Experiment Design

This is **design only**, not an immediate injection plan.

### Goal

Test only the minimum audio-related stack needed to see whether audio root devices can appear, without destabilizing boot.

### Scope

Only these directories are allowed in the first experiment:

- [Drivers\\Audio\\ADCM](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/ADCM>)
- [Drivers\\Audio\\Device](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/Device>)
- [Drivers\\Audio\\AudMiniport](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/AudMiniport>)
- [Drivers\\Audio\\Slimbus](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/Slimbus>)
- [Drivers\\Audio\\RPC\\ADSPRPC](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/RPC/ADSPRPC>)
- [Drivers\\Audio\\RPC\\ADSPRPCD](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Drivers/Audio/RPC/ADSPRPCD>)
- [Extensions\\Audio\\ACDB\\MTP](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Extensions/Audio/ACDB/MTP>)
- [Extensions\\Audio\\AudMiniport\\MTP](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Extensions/Audio/AudMiniport/MTP>)
- [Extensions\\Audio\\Device](</C:/yjc_code/K40_Win11/sound_code/windows_silicon_qcom_kona/Extensions/Audio/Device>)

### Hard Exclusions

Do not include:

- `Drivers\\SOC`
- `Drivers\\USBFn`
- non-audio PMIC / PCIe / platform drivers
- any package outside the audio chain

### Preconditions

Before any audio experiment:

1. save a fresh diagnostics package
2. keep Android fallback intact
3. make sure the current Windows partition is considered the restore point

### Success Criteria

The first audio experiment is **not** “speaker works”.

The first success criteria are only:

1. Windows still boots
2. no `0xc0000428`
3. at least one audio root device begins to enumerate, such as:
   - `ADCM\\...`
   - `AUDD\\...`
   - `ADSP\\QCOM2510`
   - `ACPI\\QCOM2560`
   - `ACPI\\QCOM258A`
   - `ACPI\\QCOM25D2`
4. `MEDIA`-class devices begin to appear in diagnostics

If those do not appear, stop the audio experiment immediately.

## Best Practical Recommendation

For now, the most suitable order is:

1. preserve the current stable baseline
2. finish session/login cleanup
3. continue using powered hub + USB Ethernet
4. if sound is needed immediately, use external USB audio
5. later test `FSA4480` as the first safe exact-match candidate
6. only after that, design and execute the audio-only minimal experiment
