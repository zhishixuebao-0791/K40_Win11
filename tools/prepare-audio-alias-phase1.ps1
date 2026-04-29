param(
    [string]$SourceRoot,
    [string]$ExperimentRoot
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\prepare-audio-alias-phase1.ps1"

$argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath)
if ($SourceRoot) { $argsList += @("-SourceRoot", $SourceRoot) }
if ($ExperimentRoot) { $argsList += @("-ExperimentRoot", $ExperimentRoot) }

& powershell @argsList
