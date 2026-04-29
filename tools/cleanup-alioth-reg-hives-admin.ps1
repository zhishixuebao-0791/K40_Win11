$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\cleanup-alioth-reg-hives-admin.ps1"

& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath
