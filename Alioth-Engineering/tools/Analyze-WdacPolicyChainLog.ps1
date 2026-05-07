param(
    [Parameter(Mandatory = $true)]
    [string]$LogDir,
    [string]$NotesDir = "C:\yjc_code\K40_Win11\Alioth-Engineering\notes"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $LogDir)) {
    throw "LogDir not found: $LogDir"
}
if (-not (Test-Path -LiteralPath $NotesDir)) {
    New-Item -ItemType Directory -Force -Path $NotesDir | Out-Null
}

function Read-FileText {
    param([string]$Name)
    $path = Join-Path $LogDir $Name
    if (Test-Path -LiteralPath $path) {
        return Get-Content -LiteralPath $path -Raw
    }
    return ""
}

function Get-ValueFromText {
    param(
        [string]$Text,
        [string]$Name
    )
    $match = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Name))=(.*)$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return ""
}

$summary = Read-FileText "00_Summary.txt"
$active = Read-FileText "01_ActivePolicies.txt"
$events = Read-FileText "06_CodeIntegrityPolicyEvents.txt"
$registry = Read-FileText "08_CiRegistryAndBoot.txt"
$qcsubsys = Read-FileText "09_QcsubsysCurrentState.txt"
$auto = Read-FileText "11_AutoVerdict.txt"

$basePolicyExists = Get-ValueFromText $auto "BasePolicyExists"
$oldSupplementalExists = Get-ValueFromText $auto "OldSupplementalPolicyExists"
$basePolicyEvents = Get-ValueFromText $auto "BasePolicyEvents"
$oldSupplementalEvents = Get-ValueFromText $auto "OldSupplementalPolicyEvents"
$hashMissingEvents = Get-ValueFromText $auto "QcsubsysHashMissingEvents"
$qcom2522Code52 = Get-ValueFromText $auto "Qcom2522Code52"

$hasRequireMsBootChain = $registry -match "RequireMicrosoftSignedBootChain\s+REG_DWORD\s+0x1"
$hasBaseActivation = $events -match "d2bda982-ccf6-4344-ac5b-0b44427b6816" -and $events -match "Status 0x0"
$hasQcsubsysBlock = $qcsubsys -match "CM_PROB_UNSIGNED_DRIVER|0xC0000428|hash could not be found"
$oldSupplementalPresentInActive = $active -match "86B04D39-E928-4F0F-937E-0F44B0909E79.*Exists=True"

$decision = "UNKNOWN"
$next = "Collect complete logs again immediately after boot."

if ($hasBaseActivation -and $hasQcsubsysBlock -and -not $oldSupplementalPresentInActive) {
    $decision = "BASE_POLICY_ACTIVE_QCSUBSYS_BLOCKED_CLEAN_SUPPLEMENTAL_STATE"
    $next = "Proceed to signed supplemental policy feasibility check. If no accepted update-policy signer can be established, prepare controlled base-policy merge/replacement experiment."
} elseif ($hasBaseActivation -and $hasQcsubsysBlock -and $oldSupplementalPresentInActive) {
    $decision = "BASE_POLICY_ACTIVE_QCSUBSYS_BLOCKED_OLD_SUPPLEMENTAL_STILL_PRESENT"
    $next = "Remove the stale qcsubsys supplemental CIP before the next experiment."
} elseif ($hasBaseActivation -and -not $hasQcsubsysBlock) {
    $decision = "BASE_POLICY_ACTIVE_QCSUBSYS_NOT_CURRENTLY_BLOCKED"
    $next = "Re-check QCOM2522/PILC/ADSP dependency state; WDAC may no longer be the current blocker."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = Join-Path $NotesDir "wdac-policy-chain-analysis-$timestamp.md"

$body = @"
# WDAC Policy Chain Analysis - $timestamp

## Input

- Log directory: `$LogDir`

## Extracted Facts

- BasePolicyExists: `$basePolicyExists`
- OldSupplementalPolicyExists: `$oldSupplementalExists`
- BasePolicyEvents: `$basePolicyEvents`
- OldSupplementalPolicyEvents: `$oldSupplementalEvents`
- QcsubsysHashMissingEvents: `$hashMissingEvents`
- Qcom2522Code52: `$qcom2522Code52`
- RequireMicrosoftSignedBootChain: `$hasRequireMsBootChain`
- Base policy activated with Status 0x0: `$hasBaseActivation`
- `qcsubsys` still blocked by CI: `$hasQcsubsysBlock`
- Old qcsubsys supplemental policy still present in Active: `$oldSupplementalPresentInActive`

## Decision

`$decision`

## Next Step

$next

## Engineering Constraint

Do not continue broad INF aliasing or broad driver injection until WDAC acceptance is resolved. The current evidence points to policy-chain acceptance, not ACPI matching.

"@

$body | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "WDAC policy chain analysis written: $report"
Write-Host "Decision: $decision"
Write-Host "Next: $next"

