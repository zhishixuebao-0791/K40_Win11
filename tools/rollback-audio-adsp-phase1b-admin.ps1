param(
    [string]$WindowsDrive = "D",
    [switch]$DisableService
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\rollback-audio-adsp-phase1b-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($DisableService) { $argsList += "-DisableService" }

& powershell @argsList
