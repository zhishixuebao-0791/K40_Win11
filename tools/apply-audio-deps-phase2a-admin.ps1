param(
    [string]$WindowsDrive = "D",
    [string]$ExperimentRoot,
    [switch]$SkipDism
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-audio-deps-phase2a-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($ExperimentRoot) { $argsList += @("-ExperimentRoot", $ExperimentRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }

& powershell @argsList
