param(
    [string]$WindowsDrive = "D",
    [string]$SsddDriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-audio-ssdd-phase6-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($SsddDriverRoot) { $argsList += @("-SsddDriverRoot", $SsddDriverRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }
if ($AllowHostSystemDrive) { $argsList += "-AllowHostSystemDrive" }

& powershell @argsList
