# Qcsubsys CI Root Cause And Next Step

Date: 2026-05-06

## Inputs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_182452`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_182902`
- `D:\Code\REDMIK40_Win11\QcsubsysCodeIntegrity_20260506_183124`

## Current State

SSDE rollback succeeded. Windows boots again and no longer stops on `ssde.sys`.

`QCOM2522 / SSDD` is still present and still matched to the expected Kona package:

- Instance: `ACPI\QCOM2522\2&daba3ff&0`
- Driver: `oem5.inf`
- Original INF: `qcsubsys8250.inf`
- Service: `qcsubsys`
- Device status: `ProblemCode 52`
- Problem status: `0xC0000428`

`qcsubsys8250.sys` and `qcsubsys8250.cat` both validate with Authenticode in the live phone OS:

- Signer: `Windows On Andromeda KMCI Codesigning`
- Issuer: `Windows On Andromeda Production PCA 2023`
- Signature status: `Valid`

## Key Code Integrity Evidence

The blocking Code Integrity event is:

`Windows is unable to verify the image integrity of the file ...\qcsubsys8250.sys because file hash could not be found on the system.`

The active Windows Driver Policy is refreshed successfully:

- Policy ID: `{d2bda982-ccf6-4344-ac5b-0b44427b6816}`
- Name: `Microsoft Windows Driver Policy`

Boot CI state after SSDE rollback:

- `CI\Protected\Licensed = 0`
- `CI\Policy\VerifiedAndReputablePolicyState = 2`
- `CI\Config\VulnerableDriverBlocklistEnable = 1`

## Conclusion

This is not a normal certificate-store failure. The file and catalog are Authenticode-valid, but kernel Code Integrity does not accept `qcsubsys8250.sys` because the active driver policy cannot find an accepted file hash/policy entry for it.

SSDE is not a viable current path because it makes its own `ssde.sys` boot-start and fails with the same class of `0xc0000428` boot validation problem.

## New Deep Trace Script

New phone-side script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Code\REDMIK40_Win11\Trace-QcsubsysCiDeep.ps1"
```

It collects:

- extended PnP properties for `ACPI\QCOM2522`
- `qcsubsys8250.sys/.cat/.inf` signatures and hashes
- `certutil -dump` and `certutil -verify` catalog output
- CodeIntegrity parsed and XML events
- BCD, CI, DeviceGuard, Active CI policy directory state
- SetupAPI focused evidence
- SSDE rollback leftovers

## Next Direction

If the deep trace confirms the same pattern, the next experiment should be:

Create a `qcsubsys8250.sys`-only WDAC/CI hash allow policy and deploy it as a supplemental CI policy, without installing SSDE and without adding any broad driver package.

Rationale:

- It targets only one failing driver: `qcsubsys8250.sys`.
- It directly addresses the Code Integrity message: file hash not found.
- It avoids boot-start third-party code like `ssde.sys`.
- It is easier to roll back: remove one `.cip` policy file from `C:\Windows\System32\CodeIntegrity\CiPolicies\Active`.

Do not continue ACPI HID remaps until `qcsubsys` Code 52 is resolved. The ACPI side has already reached the dependency device; the current blocker is CI policy acceptance.
