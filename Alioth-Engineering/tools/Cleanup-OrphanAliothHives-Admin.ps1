param(
    [switch]$WhatIfOnly
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

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $script:LogPath -Append
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$script:LogPath = Join-Path $logDir ("cleanup-orphan-alioth-hives-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

$hives = Get-ChildItem -LiteralPath "Registry::HKEY_LOCAL_MACHINE" |
    Where-Object { $_.PSChildName -like "ALIOTH_*" } |
    Select-Object -ExpandProperty PSChildName

if (-not $hives) {
    Write-Log "No orphan ALIOTH hives found."
    Write-Host "No orphan ALIOTH hives found."
    return
}

foreach ($hive in $hives) {
    Write-Log "Found HKLM\$hive"
    if ($WhatIfOnly) {
        Write-Host "Would unload HKLM\$hive"
        continue
    }

    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    $output = & reg.exe unload "HKLM\$hive" 2>&1
    $output | Tee-Object -FilePath $script:LogPath -Append
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Unloaded HKLM\$hive"
    } else {
        Write-Log "Failed to unload HKLM\$hive with exit code $LASTEXITCODE. Close other PowerShell/regedit windows and retry."
    }
}

Write-Host "Cleanup log: $script:LogPath"
