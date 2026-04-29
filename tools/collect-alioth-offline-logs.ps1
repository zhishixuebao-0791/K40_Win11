param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\collect-alioth-offline-logs.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering log collector not found: $scriptPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -WindowsDrive $WindowsDrive
