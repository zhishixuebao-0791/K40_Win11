param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$WdacRebuildabilityDir,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

function Resolve-OfflineWindowsRoot {
    param([string]$Drive)
    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage Windows drive, normally D:."
        }
    }
    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\CodeIntegrity"))) {
        throw "Offline CodeIntegrity directory not found under $root"
    }
    return $root
}

function Get-FileBrief {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Present = $false; Length = $null; Sha256 = $null; SignatureStatus = $null }
    }
    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    return [pscustomobject]@{
        Path = $Path
        Present = $true
        Length = $item.Length
        Sha256 = $hash.Hash
        SignatureStatus = [string]$sig.Status
        SignatureType = [string]$sig.SignatureType
    }
}

$projectRoot = Get-ProjectRoot
$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive

if (-not (Test-Path -LiteralPath $WdacRebuildabilityDir)) {
    throw "WdacRebuildabilityDir not found: $WdacRebuildabilityDir"
}

$candidateXml = Join-Path $WdacRebuildabilityDir "qcsubsys-hash-only-test.xml"
$candidateBin = Join-Path $WdacRebuildabilityDir "qcsubsys-hash-only-test.p7b"
if (-not (Test-Path -LiteralPath $candidateXml)) {
    throw "Missing candidate XML: $candidateXml"
}
if (-not (Test-Path -LiteralPath $candidateBin)) {
    throw "Missing candidate binary: $candidateBin"
}

$xmlText = Get-Content -LiteralPath $candidateXml -Raw
foreach ($needle in @("qcsubsys8250.sys", "Hash Sha256", "Hash Page Sha256", "PolicyType=`"Base Policy`"")) {
    if ($xmlText -notmatch [regex]::Escape($needle)) {
        throw "Candidate XML does not contain expected marker: $needle"
    }
}

$stageDir = Join-Path $projectRoot ("Alioth-Engineering\experiments\wdac-qcsubsys-hash-basepolicy-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

Copy-Item -LiteralPath $candidateXml -Destination (Join-Path $stageDir "qcsubsys-hash-only-test.xml") -Force
Copy-Item -LiteralPath $candidateBin -Destination (Join-Path $stageDir "qcsubsys-hash-only-test.p7b") -Force

$currentDriverPolicy = Join-Path $root "Windows\System32\CodeIntegrity\driversipolicy.p7b"
$records = @(
    Get-FileBrief -Path $candidateXml
    Get-FileBrief -Path $candidateBin
    Get-FileBrief -Path $currentDriverPolicy
)

$records | Format-List | Out-File -LiteralPath (Join-Path $stageDir "candidate-and-current-policy-records.txt") -Encoding UTF8
$records | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stageDir "candidate-and-current-policy-records.json") -Encoding UTF8

$commands = @"
# Dry run:
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-WdacBasePolicyExperiment-Admin.ps1" -WindowsDrive D -CandidatePolicyPath "$stageDir\qcsubsys-hash-only-test.p7b" -AllowNonMicrosoftSignedCandidate -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT

# Actual high-risk apply:
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Apply-WdacBasePolicyExperiment-Admin.ps1" -WindowsDrive D -CandidatePolicyPath "$stageDir\qcsubsys-hash-only-test.p7b" -AllowNonMicrosoftSignedCandidate -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT -Apply

# Rollback example, replace <backup-dir> with the backup directory printed by apply:
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\yjc_code\K40_Win11\tools\Rollback-WdacBasePolicy-Admin.ps1" -WindowsDrive D -BackupDir "<backup-dir>"
"@
$commands | Set-Content -LiteralPath (Join-Path $stageDir "commands.txt") -Encoding UTF8

Write-Host "Qcsubsys hash-only base-policy candidate staged:"
Write-Host "  $stageDir"
Write-Host "No offline Windows files were modified."
Write-Host "Review commands.txt before any apply."
