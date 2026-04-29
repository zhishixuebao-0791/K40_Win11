param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\fix-alioth-setup-loop-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering script not found: $scriptPath"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -WindowsDrive $WindowsDrive
