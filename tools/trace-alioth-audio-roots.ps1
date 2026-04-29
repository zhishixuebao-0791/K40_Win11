param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\trace-alioth-audio-roots.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering audio-root trace script not found: $scriptPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -OutputRoot $OutputRoot
