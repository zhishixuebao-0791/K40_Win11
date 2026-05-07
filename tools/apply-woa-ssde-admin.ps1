param(
    [string]$WindowsDrive = "D",
    [string]$SsdeDriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-woa-ssde-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($SsdeDriverRoot) { $argsList += @("-SsdeDriverRoot", $SsdeDriverRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }
if ($AllowHostSystemDrive) { $argsList += "-AllowHostSystemDrive" }

& powershell @argsList
