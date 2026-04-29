param(
    [string]$SourceRoot,
    [string]$ExperimentRoot
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\prepare-audio-deps-phase2a.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
)

if ($SourceRoot) { $argsList += @("-SourceRoot", $SourceRoot) }
if ($ExperimentRoot) { $argsList += @("-ExperimentRoot", $ExperimentRoot) }

& powershell @argsList
