param()

$ErrorActionPreference = "Continue"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

Assert-Administrator

$loaded = @()
$regOutput = & reg.exe query HKLM 2>&1
foreach ($line in $regOutput) {
    $text = [string]$line
    if ($text -match 'HKEY_LOCAL_MACHINE\\(ALIOTH_[^\s\\]+)') {
        $loaded += $Matches[1]
    }
}

$loaded = @($loaded | Sort-Object -Unique)

if (-not $loaded) {
    Write-Log "No loaded HKLM\ALIOTH_* registry hives found."
    exit 0
}

foreach ($name in $loaded) {
    Write-Log "Trying to unload HKLM\$name"
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    $output = & reg.exe unload "HKLM\$name" 2>&1
    $exit = $LASTEXITCODE
    if ($output) {
        $output | ForEach-Object { Write-Log ([string]$_) }
    }
    if ($exit -eq 0) {
        Write-Log "Unloaded HKLM\$name"
    } else {
        Write-Log "Failed to unload HKLM\$name. Close all PowerShell/Regedit windows that touched it, then run this script again."
    }
}
