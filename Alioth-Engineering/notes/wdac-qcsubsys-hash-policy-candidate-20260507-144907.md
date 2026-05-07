# WDAC qcsubsys Hash Policy Candidate - 2026-05-07 14:49

## Input

- Phone log: `D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_144907`

## Result

Hash-only qcsubsys policy generation succeeded:

- `NewQcsubsysHashPolicyXml=True`
- `NewQcsubsysHashPolicyBinary=True`

Files:

- `D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_144907\qcsubsys-hash-only-test.xml`
- `D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_144907\qcsubsys-hash-only-test.p7b`

Staged copy:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\experiments\wdac-qcsubsys-hash-basepolicy-20260507-150814`

Candidate binary:

- SHA256: `921904B372B20D9CF3F6798646C7F152F5599DF22BBD2FC7631EE4848DAE7AFB`
- Length: `1152`
- Signature: none / unknown to Authenticode

Current deployed Microsoft driver policy:

- Path: `D:\Windows\System32\CodeIntegrity\driversipolicy.p7b`
- SHA256: `B751601D6165D9D505F60057AD479417F68C6B574E9F2AADA3991D130916C74F`
- Length: `229162`

## Candidate XML Rules

The hash-only XML contains exact hash allow rules for:

- `qcsubsys8250.sys`
- SHA1 hash
- SHA256 hash
- Page SHA1 hash
- Page SHA256 hash

Important: WDAC XML hash values are Authenticode/page hashes and may not equal the normal `Get-FileHash` whole-file SHA256.

## Risk Assessment

This candidate is technically cleaner than the FilePublisher candidate because it avoids the incorrect generated version gate:

- FilePublisher candidate used `FileName="qcsubsys8180.sys"`
- FilePublisher candidate used `MinimumFileVersion="1.0.2140.0"`
- Actual deployed `qcsubsys8250.sys` reports `FileVersion=1.0.2120.0`

However, the hash-only candidate is still high risk:

- It is a base policy.
- It is unsigned.
- It appears to allow only qcsubsys-related rules.
- Replacing `driversipolicy.p7b` with it may break boot or block other kernel drivers.

## Prepared Tooling

Staging script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Stage-QcsubsysHashBasePolicyCandidate-Admin.ps1" -WindowsDrive D -WdacRebuildabilityDir "D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_144907"
```

Dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-WdacBasePolicyExperiment-Admin.ps1" -WindowsDrive D -CandidatePolicyPath "C:\yjc_code\K40_Win11\Alioth-Engineering\experiments\wdac-qcsubsys-hash-basepolicy-20260507-150814\qcsubsys-hash-only-test.p7b" -AllowNonMicrosoftSignedCandidate -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT
```

Actual apply requires:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-WdacBasePolicyExperiment-Admin.ps1" -WindowsDrive D -CandidatePolicyPath "C:\yjc_code\K40_Win11\Alioth-Engineering\experiments\wdac-qcsubsys-hash-basepolicy-20260507-150814\qcsubsys-hash-only-test.p7b" -AllowNonMicrosoftSignedCandidate -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT -Apply
```

Rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-WdacBasePolicy-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir>"
```

## Recommendation

Do not apply automatically.

Before apply:

1. Ensure phone can reliably enter Mass Storage even if Windows fails to boot.
2. Keep the printed backup directory from `Apply-WdacBasePolicyExperiment-Admin.ps1`.
3. If boot fails, immediately return to Mass Storage and run rollback.

This is now the first technically valid base-policy replacement candidate, but it remains a boot-chain risk.
