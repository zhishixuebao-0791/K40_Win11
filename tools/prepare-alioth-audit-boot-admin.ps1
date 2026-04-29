param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$EspDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\prepare-alioth-audit-boot-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering audit-prep script not found: $scriptPath"
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($EspDrive) {
    $args += @("-EspDrive", $EspDrive)
}

powershell @args
