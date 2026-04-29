param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [Parameter(Mandatory = $true)]
    [string]$WimPath,

    [int]$ImageIndex = 1,

    [string]$EspDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\reset-alioth-clean-base-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering script not found: $scriptPath"
}

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive,
    "-WimPath", $WimPath,
    "-ImageIndex", $ImageIndex
)

if ($EspDrive) {
    $arguments += @("-EspDrive", $EspDrive)
}

& powershell @arguments
