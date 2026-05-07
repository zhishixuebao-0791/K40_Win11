# WDAC Rebuildability Validation - 2026-05-07 12:11

## Input

- Phone log: `D:\Code\REDMIK40_Win11\WdacRebuildability_20260507_121106`

## Findings

The phone-side ConfigCI environment can generate a new policy XML from the installed `qcsubsys8250` DriverStore package:

- Output XML: `qcsubsys-newcipolicy-test.xml`
- `NewQcsubsysPolicyXml=True`

The generated XML allows the Andromeda signer:

- Signer: `Windows On Andromeda KMCI Codesigning`
- Root TBS value: `C6B08A5477584DE1A30B21A9566F93E8FBD2BA60589B6E3DE9C29CAD1FC8BE90`
- Driver file hash remains the known `qcsubsys8250.sys` package.

The previous script incorrectly attempted to use `ConvertFrom-CIPolicy` as a p7b-to-XML decompiler.

Correct interpretation:

- `ConvertFrom-CIPolicy` compiles XML to binary policy.
- It does not reverse-convert deployed `driversipolicy.p7b` back to XML.
- Therefore the deployed Microsoft `driversipolicy.p7b` cannot be merged with a qcsubsys rule using built-in tools unless we obtain the original XML source.

The official Driver Policy GUID files were not found in the phone Windows partition:

- `{784C4414-79F4-4C32-A6A5-F0FB42A51D0D}.cip`: not found
- `{8F9CB695-5D48-48D6-A329-7202B44607E3}.cip`: not found
- `{D2BDA982-CCF6-4344-AC5B-0B44427B6816}.cip`: not found

However, ESP was not mounted during the phone-side trace:

- `D:\EFI\Microsoft\Boot`: missing
- `D:\EFI\Microsoft\Boot\CiPolicies\Active`: missing

## Decision

Base-policy merge/rebuild is not available from the deployed `driversipolicy.p7b`.

The next proof point is whether a qcsubsys-only policy XML can compile to binary on the phone. The script has been corrected to generate `qcsubsys-newcipolicy-test.p7b`.

## Next Steps

1. Boot K40 Win11 and rerun:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-WdacRebuildabilityOnPhone.ps1"
```

2. Return to Mass Storage and inspect the new `WdacRebuildability_*` folder.

Expected new verdict keys:

- `NewQcsubsysPolicyXml=True`
- `NewQcsubsysPolicyBinary=True`
- `MergeWithExistingDriversIpPolicySupported=False`

3. From elevated Win10 PowerShell, run ESP-inclusive trace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Trace-WindowsDriverPolicyFiles-Admin.ps1" -WindowsDrive D -MountEsp
```

4. If ESP has official Driver Policy files, prefer a controlled disable/restore experiment.

5. If ESP also has no official Driver Policy files, the only remaining base-policy experiment is replacing `D:\Windows\System32\CodeIntegrity\driversipolicy.p7b` with a generated candidate, with rollback prepared first.
