param(
    [string]$WindowsDrive = "D",
    [string]$PolicyDir,
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

function Resolve-WindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be D: or another removable drive."
        }
    }

    $root = "${normalized}:\"
    $ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
    if (-not (Test-Path -LiteralPath $ciRoot)) {
        throw "Offline CodeIntegrity directory not found: $ciRoot"
    }

    $driverStore = Join-Path $root "Windows\System32\DriverStore\FileRepository"
    if (-not (Test-Path -LiteralPath $driverStore)) {
        throw "Offline DriverStore not found: $driverStore"
    }

    return $root
}

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $script:LogPath -Append
}

function Read-PolicyId {
    param([string]$PolicyIdFile)

    if (-not (Test-Path -LiteralPath $PolicyIdFile)) {
        throw "Missing policy-id.txt: $PolicyIdFile"
    }

    $content = Get-Content -LiteralPath $PolicyIdFile -Raw
    if ($content -notmatch "PolicyId=\{?([0-9a-fA-F-]{36})\}?") {
        throw "Could not parse PolicyId from $PolicyIdFile"
    }

    return $Matches[1].ToUpperInvariant()
}

Assert-Administrator

if (-not $PolicyDir) {
    throw "PolicyDir is required. Example: -PolicyDir D:\Code\REDMIK40_Win11\QcsubsysWdacHash_20260506_193602"
}

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$script:LogPath = Join-Path $logDir ("apply-qcsubsys-wdac-hash-policy-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Applying qcsubsys-only WDAC hash policy."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "PolicyDir: $PolicyDir"

$root = Resolve-WindowsRoot -Drive $WindowsDrive
$activeDir = Join-Path $root "Windows\System32\CodeIntegrity\CiPolicies\Active"
New-Item -ItemType Directory -Force -Path $activeDir | Out-Null

$policyDirFull = (Resolve-Path -LiteralPath $PolicyDir).Path
$xmlPath = Join-Path $policyDirFull "Alioth-Qcsubsys8250-Hash-Allow.xml"
$cipPath = Join-Path $policyDirFull "Alioth-Qcsubsys8250-Hash-Allow.cip"
$policyIdPath = Join-Path $policyDirFull "policy-id.txt"

if (-not (Test-Path -LiteralPath $xmlPath)) {
    throw "Missing policy XML: $xmlPath"
}
if (-not (Test-Path -LiteralPath $cipPath)) {
    throw "Missing policy CIP: $cipPath"
}
if ((Get-Item -LiteralPath $cipPath).Length -le 0) {
    throw "Policy CIP is empty: $cipPath"
}

$xml = Get-Content -LiteralPath $xmlPath -Raw
if ($xml -match "Enabled:Audit Mode") {
    throw "Refusing to apply audit-mode policy. Regenerate with the fixed Prepare-QcsubsysWdacHashPolicy.ps1 script."
}
if ($xml -notmatch "<BasePolicyID>\{D2BDA982-CCF6-4344-AC5B-0B44427B6816\}</BasePolicyID>") {
    throw "Unexpected BasePolicyID in XML. Refusing to apply."
}

$policyId = Read-PolicyId -PolicyIdFile $policyIdPath
if ($xml -notmatch "<PolicyID>\{$policyId\}</PolicyID>") {
    throw "PolicyID in XML does not match policy-id.txt: $policyId"
}

$target = Join-Path $activeDir ("{" + $policyId + "}.cip")
Copy-Item -LiteralPath $cipPath -Destination $target -Force

$copied = Get-Item -LiteralPath $target
Write-Log "Applied CIP: $target"
Write-Log "CIP size: $($copied.Length)"
Write-Log "Rollback command: powershell -NoProfile -ExecutionPolicy Bypass -File `"$projectRoot\tools\Rollback-QcsubsysWdacHashPolicy-Admin.ps1`" -WindowsDrive $WindowsDrive -PolicyId $policyId"
Write-Log "Completed. Boot Phase6 UEFI and re-run AcpiPhase3State, AudioDependencyState, and QcsubsysCiDeep diagnostics."

Write-Host "Applied qcsubsys WDAC hash policy: $target"
Write-Host "Log: $script:LogPath"
