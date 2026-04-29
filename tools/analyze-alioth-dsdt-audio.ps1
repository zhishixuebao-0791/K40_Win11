param(
    [string]$RawAcpiRoot = "D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309",
    [string]$IaslPath,
    [string]$OutputDir
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\analyze-alioth-dsdt-audio.ps1"
$defaultIaslPath = Join-Path $workspaceRoot "tools\acpica\iasl.exe"

if (-not $IaslPath) {
    $IaslPath = $defaultIaslPath
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Alioth DSDT audio analysis script not found: $scriptPath"
}

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-RawAcpiRoot", $RawAcpiRoot,
    "-IaslPath", $IaslPath
)

if ($OutputDir) {
    $argsList += @("-OutputDir", $OutputDir)
}

& powershell @argsList
