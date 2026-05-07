param(
    [string]$WindowsDrive = "D",
    [string]$BackupRoot,
    [string]$BackupDir,
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

function Copy-IfPresent {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Source) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        return $true
    }
    return $false
}

function Get-FileRecord {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Path = $Path
            Present = $false
            Length = $null
            Sha256 = $null
        }
    }

    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return [pscustomobject]@{
        Path = $Path
        Present = $true
        Length = $item.Length
        Sha256 = $hash.Hash
    }
}

$projectRoot = Get-ProjectRoot
if (-not $BackupRoot) {
    $BackupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
}

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
if (-not $BackupDir) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $BackupRoot "wdac-basepolicy-$timestamp"
} else {
    $backupDir = $BackupDir
}
$baseDir = Join-Path $backupDir "CodeIntegrity"
$activeBackupDir = Join-Path $baseDir "CiPolicies\Active"

New-Item -ItemType Directory -Force -Path $activeBackupDir | Out-Null

$coreFiles = @(
    "driversipolicy.p7b",
    "VbsSiPolicy.p7b",
    "driver.stl",
    "SiPolicy.p7b"
)

$records = @()
foreach ($name in $coreFiles) {
    $src = Join-Path $ciRoot $name
    $dst = Join-Path $baseDir $name
    [void](Copy-IfPresent -Source $src -Destination $dst)
    $records += Get-FileRecord -Path $src
}

$activeDir = Join-Path $ciRoot "CiPolicies\Active"
$activeRecords = @()
if (Test-Path -LiteralPath $activeDir) {
    Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $activeBackupDir $_.Name) -Force
        $activeRecords += Get-FileRecord -Path $_.FullName
    }
}

$manifest = [pscustomobject]@{
    CreatedAt = (Get-Date).ToString("s")
    WindowsDrive = $WindowsDrive.TrimEnd(':', '\')
    OfflineWindowsRoot = $root
    CodeIntegrityRoot = $ciRoot
    CoreFiles = $records
    ActivePolicyFiles = $activeRecords
}

$manifestPath = Join-Path $backupDir "manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "WDAC base-policy backup completed:"
Write-Host "  $backupDir"
Write-Host "Manifest:"
Write-Host "  $manifestPath"
