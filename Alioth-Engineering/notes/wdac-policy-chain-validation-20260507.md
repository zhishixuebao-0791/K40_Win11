# WDAC Policy Chain Validation - 2026-05-07

## Input

- Phone-side log: `D:\Code\REDMIK40_Win11\WdacPolicyChain_20260507_101525`
- Mass Storage Windows drive: `D:`
- Baseline backup: `C:\yjc_code\K40_Win11\Alioth-Engineering\backups\wdac-policy-baseline-20260507-104215`

## Current State

- The previous qcsubsys hash supplemental policy was removed:
  - `{86B04D39-E928-4F0F-937E-0F44B0909E79}.cip` is not present in `CiPolicies\Active`.
- `QCOM2522 / SSDD` still fails:
  - Problem code: `52`
  - Problem status: `0xC0000428`
  - Service: `qcsubsys`
  - Driver: `qcsubsys8250.inf`
- Latest Code Integrity event still blocks:
  - `qcsubsys8250.sys`
  - Reason: file hash could not be found on the system.

## Policy Chain Findings

The active policy folder contains several Microsoft/VerifiedAndReputable policies:

- `{1283AC0F-FFF1-49AE-ADA1-8A933130CAD6}.cip`
- `{2678656C-05EF-481F-BC5B-EBD8C991502D}.cip`
- related flight/test variants

The policy activation event repeatedly shows:

- `{d2bda982-ccf6-4344-ac5b-0b44427b6816}`
- `Microsoft Windows Driver Policy`
- Status `0x0`

But `{d2bda982-ccf6-4344-ac5b-0b44427b6816}.cip` is not present under `CiPolicies\Active`.

The likely on-disk source for the driver base policy is:

- `D:\Windows\System32\CodeIntegrity\driversipolicy.p7b`

Evidence:

- `driversipolicy.p7b` is Microsoft-signed.
- Certificate chain: `Microsoft Windows` -> `Microsoft Windows Production PCA 2011` -> `Microsoft Root Certificate Authority 2010`.
- The system has `RequireMicrosoftSignedBootChain=1`.

No copied Active policy string evidence shows an obvious Andromeda/Qualcomm update signer that would allow our own unsigned or self-signed supplemental policy.

## Local Candidate Driver Scan

Local `sound_code` currently has only one Kona qcsubsys8250 package:

- `C:\yjc_code\K40_Win11\sound_code\windows_silicon_qcom_kona\Drivers\Subsystems\CombinedSubsystem\qcsubsys8250.inf`
- `qcsubsys8250.cat`
- `qcsubsys8250.sys`

No alternate Kona `qcsubsys8250` package was found locally.

## Decision

The current WDAC blocker is not solved by INF aliasing, certificate-store import, or a hash-only supplemental policy copied to Active.

Unsigned/self-generated supplemental policy is not a viable next assumption. The evidence points to a Microsoft-signed driver policy chain where the loaded driver base policy is backed by `driversipolicy.p7b` rather than a normal editable Active `.cip`.

## Next Direction

Proceed in this order:

1. Extract/decode enough metadata from `driversipolicy.p7b` to determine whether the policy can be safely reconstructed or merged.
2. Search for a Microsoft-accepted `qcsubsys8250` package before modifying base policy.
3. If no accepted package exists, prepare a controlled base-policy replacement/merge experiment with strict rollback:
   - backup `driversipolicy.p7b` (completed)
   - backup all `CiPolicies\Active` files (completed)
   - produce a test policy that allows only the current `qcsubsys8250.sys` hash
   - test boot with a known rollback path through Mass Storage

Do not retry broad driver injection or SSDE.
