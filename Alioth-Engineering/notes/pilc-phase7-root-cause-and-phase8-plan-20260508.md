# PILC Phase7 Root Cause and Phase8 Plan

Date: 2026-05-08

## Evidence

Inputs:

- `D:\Code\REDMIK40_Win11\Qcsubsys8280Experiment_20260508_130743`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260508_130859`
- `D:\Code\REDMIK40_Win11\PilcFailureTrace_20260508_131617`

Phase7 result:

- `QCOM0620Present=True`
- `QCOM2522StillPresent=False`
- `QCOM0522StillPresent=False`
- `QCOM0620Service=qcsubsys`
- `Qcsubsys8280Selected=True`
- `Qcsubsys8280CiBlocked=False`
- `qcsubsys` is running from `qcsubsys8280.sys`

Current blocker:

- `PILC/QCOM251B` is present.
- `PILC` is matched to `qcPILC` / `qcpil8250.inf`.
- `PILC` fails with `CM_PROB_FAILED_ADD` / Problem Code 31.
- Current boot Code Integrity and Kernel-PnP focused logs do not show a `qcPILC` signature or WDAC block.

Interpretation:

- The `qcsubsys8250` WDAC/signature blocker has been bypassed by the Surface `qcsubsys8280` route.
- The next blocker is no longer WDAC for `qcsubsys`; it is `PILC` driver/device start.
- The old Kona `qcpil8250` package may not be compatible with the current Phase7 dependency chain, or the ACPI identity/resources exposed for `PILC` are not what the driver expects.

## Driver comparison

Current Kona PIL path:

- INF: `windows_silicon_qcom_kona\Drivers\SOC\HexagonLoader\qcpil8250.inf`
- HID: `ACPI\QCOM251B`
- Service: `qcPILC`
- Binary: `qcpil8250.sys`
- Registers `PlatformExecute = async secure %13%\QcSkExt8250.exe`

Surface Pro 9 5G PIL path:

- INF: `SurfaceUpdate\qcpil\qcpil.inf`
- HID: `ACPI\QCOM06E0`
- Service: `qcPILC`
- Binary: `qcpil.sys`
- Filter extension: `SurfaceUpdate\qcpilfilterext\qcpilfilterext.inf`, also `ACPI\QCOM06E0`
- Platform extension: `SurfaceUpdate\qcpilext8280\qcpilEXT8280.inf`, `ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280`

## Phase8 proposal

Phase8A should be narrow:

- Keep Phase7 `SSDD/QCOM0620` unchanged.
- Remap only `PILC` from `QCOM251B` to `QCOM06E0`.
- Stage Surface `qcpil.inf` and `qcpilfilterext.inf`.
- Do not initially force `SUBSYS_MTP08280`.
- Reboot and collect:
  - `Trace-AliothPilcFailure.ps1`
  - `Trace-AliothAudioDependencyState.ps1`
  - `Trace-Qcsubsys8280Experiment.ps1`

Pass criteria:

- `QCOM06E0Present=True`
- `PILC/QCOM251B` is no longer present, or only appears as phantom.
- `qcPILC` binds to Surface `qcpil.sys`.
- PILC Problem Code becomes `0`.

If Phase8A still fails:

- Phase8B should evaluate adding or emulating the `SUBSYS_MTP08280` path for `PILC` so `qcpilext8280.inf` can bind.
- Do not modify ADSP/CDSP/SPSS HIDs until PILC is stable.

## Scripts added or updated

- Updated `Trace-AliothPilcFailure.ps1` to include `QCOM06E0` and `qcPILFC`.
- Updated `Trace-AliothAudioDependencyState.ps1` to add `PILC 8280 / QCOM06E0`.
- Added `Apply-Qcpil8280Candidate-Admin.ps1`.
- Added `Rollback-Qcpil8280Candidate-Admin.ps1`.
- Added `build-acpi-hid-phase8.sh` to build the Phase8 UEFI image on Ubuntu.

## Phase8 execution order

On Win10 Mass Storage, stage the Surface PIL candidate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-Qcpil8280Candidate-Admin.ps1" -WindowsDrive D
```

On Ubuntu, build Phase8:

```bash
cd /home/ucchip/K40_Win11
bash tools/build-acpi-hid-phase8.sh
```

Copy the generated `UEFI-Images/Mu-alioth-1-acpi-hid-phase8-*.img` back to Win10 and boot it with fastboot for validation.
