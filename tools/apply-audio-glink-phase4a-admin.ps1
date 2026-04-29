param(
    [string]$WindowsDrive = "D",
    [string]$DriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-audio-glink-phase4a-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($DriverRoot) { $argsList += @("-DriverRoot", $DriverRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }
if ($AllowHostSystemDrive) { $argsList += "-AllowHostSystemDrive" }

& powershell @argsList
