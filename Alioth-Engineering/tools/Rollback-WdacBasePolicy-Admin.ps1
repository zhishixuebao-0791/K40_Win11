param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [switch]$RestoreActivePolicies,
    [switch]$ExactActiveRestore,
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

if (-not (Test-Path -LiteralPath $BackupDir)) {
    throw "BackupDir not found: $BackupDir"
}

$manifest = Join-Path $BackupDir "manifest.json"
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "manifest.json not found in backup: $BackupDir"
}

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
$backupCiRoot = Join-Path $BackupDir "CodeIntegrity"

if (-not (Test-Path -LiteralPath $backupCiRoot)) {
    throw "Backup CodeIntegrity directory not found: $backupCiRoot"
}

$preRollbackDir = Join-Path $BackupDir ("pre-rollback-current-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force -Path $preRollbackDir | Out-Null

$coreFiles = @(
    "driversipolicy.p7b",
    "VbsSiPolicy.p7b",
    "driver.stl",
    "SiPolicy.p7b"
)

foreach ($name in $coreFiles) {
    $current = Join-Path $ciRoot $name
    $backup = Join-Path $backupCiRoot $name
    $disabledMatches = Get-ChildItem -LiteralPath $ciRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$name.disabled-by-alioth-*" }
    if (Test-Path -LiteralPath $current) {
        Copy-Item -LiteralPath $current -Destination (Join-Path $preRollbackDir $name) -Force
    }
    foreach ($disabled in $disabledMatches) {
        Copy-Item -LiteralPath $disabled.FullName -Destination (Join-Path $preRollbackDir $disabled.Name) -Force
        Remove-Item -LiteralPath $disabled.FullName -Force
    }
    if (Test-Path -LiteralPath $backup) {
        if (Test-Path -LiteralPath $current) {
            & takeown.exe /F $current /A | Out-Null
            & icacls.exe $current /grant "*S-1-5-32-544:F" | Out-Null
        }
        Copy-Item -LiteralPath $backup -Destination $current -Force
        Write-Host "Restored $name"
    }
}

if ($RestoreActivePolicies) {
    $activeDir = Join-Path $ciRoot "CiPolicies\Active"
    $backupActiveDir = Join-Path $backupCiRoot "CiPolicies\Active"
    New-Item -ItemType Directory -Force -Path $activeDir | Out-Null

    $currentActiveBackup = Join-Path $preRollbackDir "CiPolicies-Active"
    New-Item -ItemType Directory -Force -Path $currentActiveBackup | Out-Null
    Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $currentActiveBackup $_.Name) -Force
    }

    if ($ExactActiveRestore) {
        Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    if (Test-Path -LiteralPath $backupActiveDir) {
        Get-ChildItem -LiteralPath $backupActiveDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $activeDir $_.Name) -Force
            Write-Host "Restored Active policy $($_.Name)"
        }
    }
}

Write-Host "WDAC base-policy rollback completed."
Write-Host "Current files before rollback were saved to:"
Write-Host "  $preRollbackDir"
