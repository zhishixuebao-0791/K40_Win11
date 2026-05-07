# QCSUBSYS WDAC Hash Policy Validation - 2026-05-06

## Inputs

- `D:\Code\REDMIK40_Win11\AcpiPhase3State_20260506_195115`
- `D:\Code\REDMIK40_Win11\AudioDependencyState_20260506_195541`
- `D:\Code\REDMIK40_Win11\QcsubsysCiDeep_20260506_200032`

## Result

The supplemental WDAC file exists offline:

- `D:\Windows\System32\CodeIntegrity\CiPolicies\Active\{86B04D39-E928-4F0F-937E-0F44B0909E79}.cip`
- Size: `1300`

But the live diagnostics still show:

- `QCOM2522 / SSDD`: `ProblemCode 52`
- `ProblemStatus 0xC0000428`
- `qcsubsys8250.sys` Authenticode status: `Valid`
- CodeIntegrity event 3004 still reports the qcsubsys image hash could not be found on the system.

The CodeIntegrity policy events show repeated activation of only:

- `{d2bda982-ccf6-4344-ac5b-0b44427b6816}` `Microsoft Windows Driver Policy`

No current event references the supplemental policy:

- `{86B04D39-E928-4F0F-937E-0F44B0909E79}`

## Interpretation

The qcsubsys-only supplemental hash policy was copied to the active policy directory, but it did not affect the kernel CI decision. The most likely explanation is that this Windows-on-ARM image does not accept this unsigned supplemental policy format under its current driver policy chain, or the supplemental policy is not being loaded at boot.

This means the current blocker is no longer ACPI HID matching and not driver package staging. The blocker is WDAC/CI policy acceptance for `qcsubsys8250.sys`.

## Next Step

Run `Trace-WdacPolicyLoadState.ps1` in the phone Windows environment to confirm with `CiTool` and CodeIntegrity events whether the supplemental policy is loaded, ignored, or rejected.

If the supplemental policy is ignored/rejected, the next controlled experiment should be one of:

1. A signed supplemental policy, if we can identify or create an accepted update-policy signer path.
2. A base-policy merge experiment using the active Microsoft Windows Driver Policy as the target, only if the base policy can be safely exported/reconstructed and rolled back.
3. A different signed qcsubsys package source whose catalog is already accepted by this image's active driver policy.

Do not continue broad INF aliasing or SSDE. SSDE already produced a boot-blocking `0xc0000428` failure and is not the right path.
