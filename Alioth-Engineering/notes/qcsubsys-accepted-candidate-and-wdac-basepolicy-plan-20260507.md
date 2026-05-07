# qcsubsys Accepted Candidate and WDAC Base Policy Plan - 2026-05-07

## Current Decision

Do not retry unsigned/hash-only supplemental WDAC policy.

Evidence from `WdacPolicyChain_20260507_101525` shows:

- The previous qcsubsys hash supplemental policy is not loaded.
- Code Integrity still reports `qcsubsys8250.sys` hash missing.
- `QCOM2522 / SSDD` still fails with Code 52 and `0xC0000428`.
- The active Microsoft Windows Driver Policy is likely backed by `D:\Windows\System32\CodeIntegrity\driversipolicy.p7b`, not by a normal `{policy-id}.cip` under `CiPolicies\Active`.

## Accepted qcsubsys Candidate Search

Local audit output:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\logs\QcsubsysCandidateAudit_20260507_112350`

SM8250/Kona candidate found:

- `C:\yjc_code\K40_Win11\sound_code\windows_silicon_qcom_kona\Drivers\Subsystems\CombinedSubsystem\qcsubsys8250.inf`
- `DriverVer = 10/30/2024, 1.0.2140.0000`
- `CatalogFile = qcsubsys8250.cat`
- Hardware ID: `ACPI\QCOM2522`
- Service binary: `qcsubsys8250.sys`
- `qcsubsys8250.sys` SHA256: `E33AB8E622C50347184A9D5717F93576F012C549D922A5062E11D620C6A997E1`
- Signer: `Windows On Andromeda KMCI Codesigning`
- Authenticode status on host: `UnknownError`

This is the same package already blocked by the Microsoft driver policy.

Other local findings:

- `WOA-Drivers-main` contains `qcsubsys850.sys` for SDM845.
- `qcsubsys850.sys` is Qualcomm-signed and Authenticode-valid on the host.
- It is not an SM8250/Kona package and has no direct `qcsubsys8250.inf` equivalent in the local tree, so it is not a safe replacement for `QCOM2522`.

Public search status:

- Searches for `qcsubsys8250.inf`, `qcsubsys8250.sys`, `QCOM2522 qcsubsys`, and `Qualcomm Subsystem Dependency Device 8250` did not produce a confirmed Microsoft-accepted SM8250 replacement package.
- Do not use broad third-party driver index packages blindly; they must be treated only as candidates until their INF IDs, hashes, and signature chain are proven.

## New Tooling

Repeatable audit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Audit-QcsubsysCandidates.ps1"
```

Base-policy backup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Backup-WdacBasePolicy-Admin.ps1" -WindowsDrive D
```

Latest backup created:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\backups\wdac-basepolicy-20260507-113031`

Base-policy source trace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Trace-WdacBasePolicySource-Admin.ps1" -WindowsDrive D
```

Latest trace output:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\logs\WdacBasePolicySource_20260507_113102`

Trace result:

- `driversipolicy.p7b` exists.
- SHA256: `B751601D6165D9D505F60057AD479417F68C6B574E9F2AADA3991D130916C74F`
- `certutil -dump` shows Microsoft chain:
  - `Microsoft Windows`
  - `Microsoft Windows Production PCA 2011`
  - `Microsoft Root Certificate Authority 2010`
- `VbsSiPolicy.p7b` and `driver.stl` were also captured.
- `SiPolicy.p7b` is not present.

Base-policy rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-WdacBasePolicy-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir>" -RestoreActivePolicies -ExactActiveRestore
```

Controlled apply wrapper, dry-run by default:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-WdacBasePolicyExperiment-Admin.ps1" -WindowsDrive D -CandidatePolicyPath "<candidate-driversipolicy.p7b>"
```

Actual apply requires `-Apply`. It also refuses non-Microsoft-signed candidates unless explicitly overridden.

## Risk Boundary

Replacing `driversipolicy.p7b` is a boot-chain-level experiment.

Before any apply:

1. Run `Backup-WdacBasePolicy-Admin.ps1` from elevated Administrator PowerShell.
2. Confirm backup contains `driversipolicy.p7b`, `VbsSiPolicy.p7b`, `driver.stl`, and `CiPolicies\Active`.
3. Confirm rollback command is available from the host while the phone is in Mass Storage.
4. Only then test a candidate policy.

## Next Step

Since no accepted `qcsubsys8250` replacement is currently confirmed, the next useful step is not another driver injection.

Next action should be:

1. Run the base-policy backup and source trace as Administrator on Win10 while the phone is in Mass Storage.
2. Analyze the copied `driversipolicy.p7b` and Active `.cip` files.
3. Decide whether a Microsoft-signed or accepted base policy can be reconstructed/merged.
4. If not, the remaining options are:
   - find a genuinely Microsoft-policy-accepted SM8250 `qcsubsys8250` package;
   - or perform an explicit risky base-policy replacement experiment with a verified rollback path.
