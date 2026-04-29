param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\rollback-fsa4480-minimal-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering FSA4480 rollback not found: $scriptPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -WindowsDrive $WindowsDrive
