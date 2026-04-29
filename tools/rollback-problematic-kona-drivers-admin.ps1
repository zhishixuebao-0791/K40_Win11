param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$ProblemDriver = "qcppx8250"
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\rollback-problematic-kona-drivers-admin.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering script not found: $scriptPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath -WindowsDrive $WindowsDrive -ProblemDriver $ProblemDriver
