# WDAC driversipolicy Rebuildability and Next Experiment - 2026-05-07

## Result

Do not continue the unsigned/hash-only supplemental-policy path.

Do not assume `driversipolicy.p7b` can be edited/merged to allow only `qcsubsys8250.sys`.

## Evidence

Local host test:

```powershell
ConvertFrom-CIPolicy -BinaryFilePath D:\Windows\System32\CodeIntegrity\driversipolicy.p7b -XmlFilePath <out.xml>
```

Result:

```text
Device Guard is not available in this edition of Windows.
```

The same error happens for `New-CIPolicy` on this Win10 host, so host-side ConfigCI cannot currently build or convert WDAC policies.

Existing base-policy trace:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\logs\WdacBasePolicySource_20260507_113102`
- `driversipolicy.p7b` SHA256: `B751601D6165D9D505F60057AD479417F68C6B574E9F2AADA3991D130916C74F`
- `certutil -dump` shows Microsoft chain:
  - `Microsoft Windows`
  - `Microsoft Windows Production PCA 2011`
  - `Microsoft Root Certificate Authority 2010`

Official Microsoft Driver Policy guidance says the policy allows WHCP-signed or allowlisted drivers and cannot be bypassed per-driver.

Implication:

- A qcsubsys-only exception is not a supported Microsoft Driver Policy operation.
- The practical choices are:
  - find a Microsoft Driver Policy accepted `qcsubsys8250` package;
  - or disable/replace the Driver Policy as a controlled boot-chain experiment with rollback.

## Current Driver Policy File Trace

Offline Windows partition trace without ESP mount:

- `C:\yjc_code\K40_Win11\Alioth-Engineering\logs\WindowsDriverPolicyFiles_20260507_120039`

Result under `D:\Windows\System32\CodeIntegrity\CiPolicies\Active`:

- `{784C4414-79F4-4C32-A6A5-F0FB42A51D0D}.cip`: not present
- `{8F9CB695-5D48-48D6-A329-7202B44607E3}.cip`: not present
- `{D2BDA982-CCF6-4344-AC5B-0B44427B6816}.cip`: not present

ESP was not mounted in this trace. ESP check still needs elevated PowerShell or phone-side trace.

## New Scripts

Phone-side rebuildability trace:

- Host copy: `C:\yjc_code\K40_Win11\tools\Trace-WdacRebuildabilityOnPhone.ps1`
- Phone copy: `D:\Code\REDMIK40_Win11\Trace-WdacRebuildabilityOnPhone.ps1`

Run on K40 Win11:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-WdacRebuildabilityOnPhone.ps1"
```

Offline policy file trace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Trace-WindowsDriverPolicyFiles-Admin.ps1" -WindowsDrive D -MountEsp
```

Dry-run disable experiment:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Disable-WindowsDriverPolicyExperiment-Admin.ps1" -WindowsDrive D -MountEsp
```

Actual disable requires `-Apply`.

Rollback:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-WindowsDriverPolicyExperiment-Admin.ps1" -BackupDir "<backup-dir>"
```

## Next Step

1. Boot into K40 Win11 and run `Trace-WdacRebuildabilityOnPhone.ps1`.
2. Return to Mass Storage and provide the generated `WdacRebuildability_*` folder.
3. If phone-side ConfigCI also cannot convert/rebuild the policy, stop pursuing merge/rebuild.
4. Then run ESP-inclusive policy file trace from elevated Win10 PowerShell.
5. If official Driver Policy files are found in ESP, do a dry-run disable first, then only apply after confirming rollback.
