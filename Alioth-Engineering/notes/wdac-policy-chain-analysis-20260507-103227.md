# WDAC Policy Chain Analysis - 20260507-103227

## Input

- Log directory: $LogDir

## Extracted Facts

- BasePolicyExists: $basePolicyExists
- OldSupplementalPolicyExists: $oldSupplementalExists
- BasePolicyEvents: $basePolicyEvents
- OldSupplementalPolicyEvents: $oldSupplementalEvents
- QcsubsysHashMissingEvents: $hashMissingEvents
- Qcom2522Code52: $qcom2522Code52
- RequireMicrosoftSignedBootChain: $hasRequireMsBootChain
- Base policy activated with Status 0x0: $hasBaseActivation
- qcsubsys still blocked by CI: $hasQcsubsysBlock
- Old qcsubsys supplemental policy still present in Active: $oldSupplementalPresentInActive

## Decision

$decision

## Next Step

Proceed to signed supplemental policy feasibility check. If no accepted update-policy signer can be established, prepare controlled base-policy merge/replacement experiment.

## Engineering Constraint

Do not continue broad INF aliasing or broad driver injection until WDAC acceptance is resolved. The current evidence points to policy-chain acceptance, not ACPI matching.

