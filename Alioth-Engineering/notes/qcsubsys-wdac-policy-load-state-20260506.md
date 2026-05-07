# QCSUBSYS WDAC Policy Load State - 2026-05-06

## Input

- Phone-side diagnostic package: `D:\Code\REDMIK40_Win11\WdacPolicyLoadState_20260506_202619`
- Offline Windows drive while in Mass Storage: `D:`
- Target supplemental policy ID: `{86B04D39-E928-4F0F-937E-0F44B0909E79}`
- Target base driver policy ID: `{d2bda982-ccf6-4344-ac5b-0b44427b6816}`

## Observed State

The qcsubsys-only supplemental policy exists in the live Windows active policy folder:

- `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\{86B04D39-E928-4F0F-937E-0F44B0909E79}.cip`
- Size: `1300`
- SHA256: `6E0DCDCEA7317722BC305F023D1CA368069B1379C72D47417A6C43A88B44E1C3`

However, Code Integrity policy events only show the Microsoft driver base policy being activated:

- `{d2bda982-ccf6-4344-ac5b-0b44427b6816}` `Microsoft Windows Driver Policy`
- Status: `0x0`

There are no Code Integrity activation events for:

- `{86B04D39-E928-4F0F-937E-0F44B0909E79}`

`QCOM2522 / SSDD` is still blocked:

- Device: `ACPI\QCOM2522\2&DABA3FF&0`
- Driver: `qcsubsys8250.inf`
- Service: `qcsubsys`
- Problem code: `52`
- Problem status: `0xC0000428`
- Latest Code Integrity event: `qcsubsys8250.sys` hash could not be found on the system.

## Conclusion

The current blocker is not ACPI HID matching and not driver staging. The blocker is that the qcsubsys supplemental WDAC policy is not being loaded or accepted by the live Code Integrity policy chain.

The current hash-only supplemental policy should be treated as an ineffective experiment. Keeping it installed can confuse later diagnostics, so remove it before the next WDAC experiment unless a comparison run needs it.

## Next Direction

Do not continue broad INF aliasing or broad driver injection.

The next useful work is one of these controlled paths:

1. Determine whether this image can accept a signed supplemental policy for the active Microsoft driver base policy. This requires confirming whether the base policy allows supplemental/update signers.
2. If signed supplemental policy is not viable, investigate a base-policy merge/replacement path only with a reliable rollback route.
3. In parallel, search for a `qcsubsys8250` package whose catalog/signature is already accepted by the active Microsoft Windows Driver Policy.

Do not retry SSDE. It already caused a boot-blocking `0xC0000428` failure.

