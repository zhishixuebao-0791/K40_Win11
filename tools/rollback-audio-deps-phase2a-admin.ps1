param(
    [string]$WindowsDrive = "D",
    [switch]$DisableServices
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\rollback-audio-deps-phase2a-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($DisableServices) { $argsList += "-DisableServices" }

& powershell @argsList
