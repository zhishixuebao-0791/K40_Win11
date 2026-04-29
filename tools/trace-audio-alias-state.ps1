param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\trace-audio-alias-state.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -OutputRoot $OutputRoot
