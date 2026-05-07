# WDAC Rebuildability Validation - 2026-05-07 14:16

## Input

- Phone log: `D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_141636`
- ESP-inclusive host trace: `C:\yjc_code\K40_Win11\Alioth-Engineering\logs\WindowsDriverPolicyFiles_20260507_142012`

## Confirmed

Phone-side ConfigCI can generate and compile a qcsubsys-only base policy:

- `NewQcsubsysPolicyXml=True`
- `NewQcsubsysPolicyBinary=True`
- Binary: `qcsubsys-newcipolicy-test.p7b`
- SHA256: `3547F6CB723F65ED08748C84822A7B895D40D9FE9A525F69B7730ECA911A3B52`
- Authenticode: unsigned / no standard embedded signature

The deployed Microsoft driver policy cannot be reverse-converted to XML with available tools:

- `DriversIpPolicyReverseConvertSupported=False`
- `MergeWithExistingDriversIpPolicySupported=False`

ESP-inclusive policy file trace found no official Driver Policy GUID files:

- `D:\Windows\System32\CodeIntegrity\CiPolicies\Active\{784C4414-79F4-4C32-A6A5-F0FB42A51D0D}.cip`: missing
- `D:\Windows\System32\CodeIntegrity\CiPolicies\Active\{8F9CB695-5D48-48D6-A329-7202B44607E3}.cip`: missing
- `D:\Windows\System32\CodeIntegrity\CiPolicies\Active\{D2BDA982-CCF6-4344-AC5B-0B44427B6816}.cip`: missing
- `R:\EFI\Microsoft\Boot\CiPolicies\Active\{784C4414-79F4-4C32-A6A5-F0FB42A51D0D}.cip`: missing
- `R:\EFI\Microsoft\Boot\CiPolicies\Active\{8F9CB695-5D48-48D6-A329-7202B44607E3}.cip`: missing
- `R:\EFI\Microsoft\Boot\CiPolicies\Active\{D2BDA982-CCF6-4344-AC5B-0B44427B6816}.cip`: missing

Therefore the official GUID-file disable route is not available on this install.

## Candidate Quality Issue

The generated FilePublisher policy is not a good replacement candidate yet.

Reason:

- The generated XML uses `FileName="qcsubsys8180.sys"`.
- The actual deployed file is `qcsubsys8250.sys`, but its version resource reports:
  - `OriginalFilename = qcsubsys8180.sys`
  - `FileVersion = 1.0.2120.0000`
- The generated policy uses:
  - `MinimumFileVersion = 1.0.2140.0`

This version mismatch can prevent the rule from matching the actual deployed driver.

## Script Update

`Trace-WdacRebuildabilityOnPhone.ps1` has been updated and copied to:

- `D:\Code\REDMIK40_Win11\Trace-WdacRebuildabilityOnPhone.ps1`

The updated script now also generates a hash-only policy:

- `qcsubsys-hash-only-test.xml`
- `qcsubsys-hash-only-test.p7b`

This avoids FilePublisher filename/version mismatch and is a better candidate for a controlled base-policy replacement experiment.

## Decision

Do not apply `qcsubsys-newcipolicy-test.p7b`.

Next proof point is the hash-only candidate.

## Next Step

Boot K40 Win11 and rerun:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-WdacRebuildabilityOnPhone.ps1"
```

Then return to Mass Storage and inspect the new `WdacRebuildability_*` folder.

We need:

- `NewQcsubsysHashPolicyXml=True`
- `NewQcsubsysHashPolicyBinary=True`
- XML contains the exact hash for `qcsubsys8250.sys`, not a FilePublisher version rule.

Only after that should we consider a high-risk replacement of `driversipolicy.p7b`, with rollback already prepared.
