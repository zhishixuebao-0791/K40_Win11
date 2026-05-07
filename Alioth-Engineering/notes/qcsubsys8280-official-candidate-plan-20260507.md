# qcsubsys8280 official candidate plan - 2026-05-07

## Current blocker

The deployed `qcsubsys8250.sys` is still blocked by Windows Code Integrity / Microsoft Driver Policy. Previous attempts proved:

- Importing the Andromeda signer certificate does not satisfy kernel CI.
- Hash-only supplemental WDAC policy is not loaded/accepted.
- Removing or disabling `driversipolicy.p7b` breaks boot at `winload.efi`.

Therefore, the current safest path is not to modify base policy. The next controlled experiment is to use a Microsoft WHCP-signed same-family driver package and make the existing SSDD device match it with a narrow compatible ID alias.

## Found candidate

Downloaded official Microsoft Surface Pro 9 with 5G driver package:

- Source: https://www.microsoft.com/en-us/download/details.aspx?id=105941
- Local MSI: `C:\yjc_code\K40_Win11\sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\SurfacePro9-5G_Win11_22621_25.070.2191.0.msi`
- Extracted candidate: `C:\yjc_code\K40_Win11\sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\qcsubsys8280`

Relevant files:

- `qcsubsys8280.inf`
- `qcsubsys8280.cat`
- `qcsubsys8280.sys`

Signature audit:

- `qcsubsys8280.cat`: valid, signer `Microsoft Windows Hardware Compatibility Publisher`
- `qcsubsys8280.sys`: valid, signer `QUALCOMM Inc.`

Driver audit:

- `qcsubsys8280.sys` SHA256: `4DBA00A1B636D6B5737DAE82324B65E3E71FA0D969B06BEEB0B6DFF591D6A1DF`
- File version: `1.0.0.17556`
- Original filename: `qcsubsys8280.sys`

INF hardware IDs:

- ADSP: `ACPI\QCOM061B`
- SSDD / Subsystem Dependency Device: `ACPI\QCOM0620`
- CDSP: `ACPI\QCOM06B0`
- SPSS: `ACPI\QCOM068D`
- SCSS: `ACPI\QCOM061F`

## Proposed experiment

Do not change `driversipolicy.p7b`.

1. Inject only the official `qcsubsys8280` package into offline `D:\`.
2. Add compatible ID `ACPI\QCOM0620` to the existing offline SSDD enum instance (`QCOM2522` or fallback `QCOM0522`).
3. Boot Phase6 UEFI.
4. Collect `AudioDependencyState`, `AudioRootTrace`, `AudioRootCause`, and `QcsubsysCiDeep`.

Expected useful outcomes:

- If `qcsubsys8280.sys` loads without Code 52, Microsoft Driver Policy acceptance is confirmed and we can decide whether to continue with a 8280 alias route.
- If it is still blocked, then the problem is not just Andromeda signing; policy scope is stricter than expected and the base-policy route needs a separate safe lab design.
- If it loads but the device malfunctions, then the package is policy-accepted but not functionally compatible with SM8250 SSDD.

## Scripts created

Apply:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-Qcsubsys8280Candidate-Admin.ps1" -WindowsDrive D
```

Rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-Qcsubsys8280Candidate-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir-printed-by-apply>"
```

Optional best-effort driver package removal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-Qcsubsys8280Candidate-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir-printed-by-apply>" -RemoveDriverPackage
```

## Safety position

This is safer than the base-policy experiment because it keeps the Microsoft driver policy files intact and only uses a WHCP-signed Microsoft-distributed driver package plus an offline ACPI-compatible-ID alias. It is still an experiment, so keep the backup directory printed by the apply script.
