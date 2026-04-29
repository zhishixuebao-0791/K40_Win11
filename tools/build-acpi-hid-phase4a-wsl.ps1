param(
    [string]$MuRoot,
    [string]$OutputDir,
    [switch]$Clean,
    [switch]$SetupApt
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path (Join-Path (Join-Path $workspaceRoot "Alioth-Engineering") "tools") "build-acpi-hid-phase4a-wsl.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Build script not found: $scriptPath"
}

$forward = @{}
if ($PSBoundParameters.ContainsKey("MuRoot")) { $forward.MuRoot = $MuRoot }
if ($PSBoundParameters.ContainsKey("OutputDir")) { $forward.OutputDir = $OutputDir }
if ($PSBoundParameters.ContainsKey("Clean")) { $forward.Clean = $Clean }
if ($PSBoundParameters.ContainsKey("SetupApt")) { $forward.SetupApt = $SetupApt }

& $scriptPath @forward
