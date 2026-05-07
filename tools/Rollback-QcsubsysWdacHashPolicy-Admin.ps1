param(
    [string]$WindowsDrive = "D",
    [string]$PolicyId,
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

function Get-WindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be D: or another removable drive."
        }
    }

    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\CodeIntegrity"))) {
        throw "Offline CodeIntegrity directory not found under $root"
    }
    return $root
}

Assert-Administrator

$root = Get-WindowsRoot -Drive $WindowsDrive
$activeDir = Join-Path $root "Windows\System32\CodeIntegrity\CiPolicies\Active"
if (-not (Test-Path -LiteralPath $activeDir)) {
    Write-Host "Active CI policy directory not found: $activeDir"
    return
}

$removed = @()
if ($PolicyId) {
    $name = $PolicyId.Trim('{}')
    $target = Join-Path $activeDir ("{" + $name + "}.cip")
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Force
        $removed += $target
    }
} else {
    $markerRoots = Get-ChildItem -LiteralPath (Join-Path $root "Code\REDMIK40_Win11") -Directory -Filter "QcsubsysWdacHash_*" -ErrorAction SilentlyContinue
    foreach ($markerRoot in $markerRoots) {
        $marker = Join-Path $markerRoot.FullName "policy-id.txt"
        if (-not (Test-Path -LiteralPath $marker)) {
            continue
        }

        $content = Get-Content -LiteralPath $marker -ErrorAction SilentlyContinue
        $line = $content | Where-Object { $_ -match "^PolicyId=" } | Select-Object -First 1
        if ($line -and $line -match "PolicyId=\{?([0-9a-fA-F-]{36})\}?") {
            $target = Join-Path $activeDir ("{" + $Matches[1] + "}.cip")
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Force
                $removed += $target
            }
        }
    }
}

if ($removed.Count -eq 0) {
    Write-Host "No qcsubsys WDAC hash policy was removed."
} else {
    Write-Host "Removed qcsubsys WDAC hash policy file(s):"
    $removed | ForEach-Object { Write-Host "  $_" }
}
