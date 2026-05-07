# Phase6 SSDE Failure And Rollback

Date: 2026-05-06

## Symptom

After applying the WOA SSDE package, Alioth no longer reaches Windows. Windows Boot Manager stops at Recovery with:

- File: `\Windows\System32\DriverStore\FileRepository\ssde.inf_arm64_e6711c001f1d5b99\ssde.sys`
- Error: `0xc0000428`

This is a boot-time signature validation failure on `ssde.sys`.

## Installed State

The offline phone Windows image contains:

- OEM INF: `D:\Windows\INF\oem15.inf`
- DriverStore: `D:\Windows\System32\DriverStore\FileRepository\ssde.inf_arm64_e6711c001f1d5b99`
- Offline registry after apply:
  - `ControlSet001\Services\ssde\Start = 0`
  - `ControlSet001\Control\CI\Policy\WhqlSettings = 1`
  - `ControlSet001\Control\CI\Protected\Licensed = 1`

Because `ssde` is boot-start, Windows validates and loads it before reaching the desktop.

## Conclusion

SSDE is not safe to keep in the current boot path. It may be valid in the original WOA target environment, but on this Alioth image it creates a hard boot blocker before we can collect normal in-OS diagnostics.

## Recovery

Use the rollback script from an elevated Administrator PowerShell while the phone is in Mass Storage mode and the phone Windows partition is mounted as `D:`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\rollback-woa-ssde-admin.ps1" -WindowsDrive D
```

Expected result:

- `ssde` service is disabled offline with `Start = 4`.
- `CI\Protected\Licensed` is reset to `0`.
- `CI\Policy\WhqlSettings` is reset to `0` if present.
- SSDE OEM package such as `oem15.inf` is removed with DISM when possible.

After rollback, boot Phase6 UEFI again. The expected state is boot recovery from `ssde.sys`; `qcsubsys` may return to Code 52 until a safer signing or CI path is found.

## Next Direction

Do not continue with SSDE as a boot-start driver unless we first prove its signature chain and boot CI policy are accepted in the Alioth image. The safer next step is to restore boot, then compare CodeIntegrity state before and after without installing additional boot-start components.
