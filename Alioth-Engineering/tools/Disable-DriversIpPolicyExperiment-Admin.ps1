param(
    [string]$WindowsDrive = "D",
    [string]$BackupDir,
    [switch]$Apply,
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
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage Windows drive, normally D:."
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

if ($Apply -and $RiskAcknowledgement -ne "I_UNDERSTAND_THIS_CAN_BREAK_BOOT") {
    throw "Disabling driversipolicy.p7b requires -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT."
}

$projectRoot = Get-ProjectRoot
$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
$policyPath = Join-Path $ciRoot "driversipolicy.p7b"

if (-not (Test-Path -LiteralPath $policyPath)) {
    throw "driversipolicy.p7b not found: $policyPath"
}

$policy = Get-Item -LiteralPath $policyPath
$hash = Get-FileHash -LiteralPath $policyPath -Algorithm SHA256
$sig = Get-AuthenticodeSignature -LiteralPath $policyPath

Write-Host "Current driversipolicy.p7b:"
Write-Host "  Path: $policyPath"
Write-Host "  Length: $($policy.Length)"
Write-Host "  SHA256: $($hash.Hash)"
Write-Host "  SignatureStatus: $($sig.Status)"

if (-not $BackupDir) {
    $BackupDir = Join-Path $projectRoot ("Alioth-Engineering\backups\disable-driversipolicy-pre-apply-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

if (-not $Apply) {
    Write-Host "Dry run only. No files were changed."
    Write-Host "To disable after verifying rollback path, re-run with -Apply -RiskAcknowledgement I_UNDERSTAND_THIS_CAN_BREAK_BOOT."
    return
}

$backupTool = Join-Path $projectRoot "Alioth-Engineering\tools\Backup-WdacBasePolicy-Admin.ps1"
if (-not (Test-Path -LiteralPath $backupTool)) {
    throw "Backup tool not found: $backupTool"
}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $backupTool -WindowsDrive $WindowsDrive -BackupDir $BackupDir

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$disabledPath = "$policyPath.disabled-by-alioth-$stamp"
$aclBeforePath = Join-Path $BackupDir "driversipolicy-acl-before.txt"
$aclAfterPath = Join-Path $BackupDir "driversipolicy-acl-after-grant.txt"
& icacls.exe $policyPath | Out-File -LiteralPath $aclBeforePath -Encoding UTF8

Write-Host "Taking ownership and granting Administrators full control for offline rename."
& takeown.exe /F $policyPath /A | Out-String | Write-Host
& icacls.exe $policyPath /grant "*S-1-5-32-544:F" | Out-String | Write-Host
& icacls.exe $policyPath | Out-File -LiteralPath $aclAfterPath -Encoding UTF8

Move-Item -LiteralPath $policyPath -Destination $disabledPath -Force

$record = [pscustomobject]@{
    AppliedAt = (Get-Date).ToString("s")
    WindowsDrive = $WindowsDrive
    OriginalPath = $policyPath
    DisabledPath = $disabledPath
    OriginalSha256 = $hash.Hash
    OriginalLength = $policy.Length
    SignatureStatus = [string]$sig.Status
    BackupDir = $BackupDir
}
$record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BackupDir "disable-driversipolicy-record.json") -Encoding UTF8

Write-Host "driversipolicy.p7b disabled by rename:"
Write-Host "  $disabledPath"
Write-Host "Backup directory:"
Write-Host "  $BackupDir"
Write-Host "Rollback command:"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"C:\yjc_code\K40_Win11\tools\Rollback-WdacBasePolicy-Admin.ps1`" -WindowsDrive D -BackupDir `"$BackupDir`""
