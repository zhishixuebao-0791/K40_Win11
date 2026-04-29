param(
    [string]$PreferredLetter = "R"
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\mount-alioth-esp-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering ESP mount script not found: $scriptPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -PreferredLetter $PreferredLetter
