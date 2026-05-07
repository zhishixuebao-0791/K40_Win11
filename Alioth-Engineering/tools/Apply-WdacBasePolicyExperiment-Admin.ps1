param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$CandidatePolicyPath,
    [string]$BackupDir,
    [switch]$Apply,
    [switch]$AllowNonMicrosoftSignedCandidate,
    [string]$RiskAcknowledgement,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

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
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage drive letter, normally D:."
        }
    }

    $root = "${normalized}:\"
    $ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
    if (-not (Test-Path -LiteralPath $ciRoot)) {
        throw "Offline CodeIntegrity directory not found: $ciRoot"
    }
    return $root
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $CandidatePolicyPath)) {
    throw "CandidatePolicyPath not found: $CandidatePolicyPath"
}

$projectRoot = Get-ProjectRoot
$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
$target = Join-Path $ciRoot "driversipolicy.p7b"

$candidate = Get-Item -LiteralPath $CandidatePolicyPath
$sig = Get-AuthenticodeSignature -LiteralPath $candidate.FullName
$hash = Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256
$signer = [string]$sig.SignerCertificate.Subject

Write-Host "Candidate policy:"
Write-Host "  Path: $($candidate.FullName)"
Write-Host "  Length: $($candidate.Length)"
Write-Host "  SHA256: $($hash.Hash)"
Write-Host "  SignatureStatus: $($sig.Status)"
Write-Host "  Signer: $signer"

$looksMicrosoftSigned = ($sig.Status -eq "Valid" -and $signer -match "Microsoft")
if (-not $looksMicrosoftSigned -and -not $AllowNonMicrosoftSignedCandidate) {
    throw "Candidate is not a valid Microsoft-signed policy. Refusing by default because RequireMicrosoftSignedBootChain is enabled. Re-run with -AllowNonMicrosoftSignedCandidate only for an explicit risky experiment."
}

if ($AllowNonMicrosoftSignedCandidate -and $RiskAcknowledgement -ne "I_UNDERSTAND_THIS_CAN_BREAK_BOOT") {
    throw "Non-Microsoft-signed base-policy replacement requires -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT."
}

if (-not $BackupDir) {
    $BackupDir = Join-Path $projectRoot ("Alioth-Engineering\backups\wdac-basepolicy-pre-apply-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

if (-not $Apply) {
    Write-Host "Dry run only. No files were changed."
    Write-Host "To apply after verifying rollback path, re-run with -Apply."
    return
}

$backupTool = Join-Path $projectRoot "Alioth-Engineering\tools\Backup-WdacBasePolicy-Admin.ps1"
if (-not (Test-Path -LiteralPath $backupTool)) {
    throw "Backup tool not found: $backupTool"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backupTool -WindowsDrive $WindowsDrive -BackupDir $BackupDir

$candidateRecord = [pscustomobject]@{
    AppliedAt = (Get-Date).ToString("s")
    WindowsDrive = $WindowsDrive
    CandidatePolicyPath = $candidate.FullName
    CandidateLength = $candidate.Length
    CandidateSha256 = $hash.Hash
    CandidateSignatureStatus = [string]$sig.Status
    CandidateSigner = $signer
    Target = $target
    RiskAcknowledgement = $RiskAcknowledgement
}
$candidateRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BackupDir "candidate-policy-record.json") -Encoding UTF8

Copy-Item -LiteralPath $candidate.FullName -Destination $target -Force
Write-Host "Applied candidate as:"
Write-Host "  $target"
Write-Host "If boot fails, enter Mass Storage and run Rollback-WdacBasePolicy-Admin.ps1 with:"
Write-Host "  -BackupDir `"$BackupDir`""
