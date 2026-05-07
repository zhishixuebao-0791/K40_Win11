# Qcsubsys Deep CI Analysis

Date: 2026-05-06

## Inputs

- `D:\Code\REDMIK40_Win11\QcsubsysCiDeep_20260506_183414`

## Findings

`QCOM2522 / SSDD` is still correctly enumerated and matched:

- Instance: `ACPI\QCOM2522\2&DABA3FF&0`
- BIOS path: `\_SB.SSDD`
- Hardware IDs:
  - `ACPI\VEN_QCOM&DEV_2522&SUBSYS_MTP08250`
  - `ACPI\QCOM2522`
  - `*QCOM2522`
- Driver: `oem5.inf`
- Original INF: `qcsubsys8250.inf`
- Service: `qcsubsys`
- Problem: `CM_PROB_UNSIGNED_DRIVER`
- Problem status: `0xC0000428`

Dependencies are present at the PnP property level:

- Providers:
  - `ACPI\QCOM258D\0`
  - `ACPI\QCOM257C\2&daba3ff&0`
  - `ACPI\QCOM258B\2&daba3ff&0`
- Dependents:
  - `\_SB.SCSS`
  - `\_SB.ADSP`
  - `\_SB.AMSS`
  - `\_SB.CDSP`

So the current blocker is not ACPI HID matching and not the `_DEP` provider list.

## File And Signature Evidence

Target driver:

- `qcsubsys8250.sys`
- SHA1: `61D2755108AD4A8843AFAB878212FC4FA7911B7A`
- SHA256: `E33AB8E622C50347184A9D5717F93576F012C549D922A5062E11D620C6A997E1`

Catalog:

- `qcsubsys8250.cat`
- SHA1: `996B578BED8C385A20C5B83656626D0B39FC3DD5`
- SHA256: `D2744FFA19275C29B32B23512F2B9711EFE73ED5B59AD2316E62E9C903074498`

Both `.sys` and `.cat` show Authenticode `Valid` in PowerShell. The signer is:

- Subject: `Windows On Andromeda KMCI Codesigning`
- Issuer: `Windows On Andromeda Production PCA 2023`

## Code Integrity Evidence

The recurring CI event is Event ID `3004`:

- File: `...\qcsubsys8250.sys`
- `SecureRequired = 0x1`
- `RequestedSigningLevel = 1`
- Process: `System`

CI policy activation is Event ID `3099`:

- Policy: `Microsoft Windows Driver Policy`
- Policy GUID: `{d2bda982-ccf6-4344-ac5b-0b44427b6816}`
- Policy ID: `10.0.27805.0`
- Options: `0x80880200`
- Status: `0x0`

The human-readable CI event says the file hash could not be found on the system. This matches the device's `Code 52 / 0xC0000428`.

## SSDE State

SSDE is cleanly rolled back:

- no `ssde` service key
- no matching SSDE OEM INF
- no SSDE DriverStore directory

This confirms the current failure is only `qcsubsys`, not leftover SSDE.

## Decision

The next experiment should be a single-file WDAC supplemental hash allow policy for `qcsubsys8250.sys`.

Do not continue:

- SSDE
- broader driver injections
- more ACPI HID remaps

Reason: the failing evidence is precise and file-hash based. The smallest meaningful intervention is to allow exactly the SHA256 hash of `qcsubsys8250.sys` under the active Microsoft Windows Driver Policy.

## Prepared Scripts

Phone-side generate-only script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Prepare-QcsubsysWdacHashPolicy.ps1"
```

It generates but does not install:

- XML policy
- `.cip` binary policy
- `policy-id.txt`
- log

Only after reviewing generation output should `-Apply` be used.

Mass Storage rollback script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-QcsubsysWdacHashPolicy-Admin.ps1" -WindowsDrive D
```

The rollback removes the generated qcsubsys WDAC `.cip` file from the offline Active policy directory.
