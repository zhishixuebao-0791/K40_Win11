param(
    [string]$WindowsDrive = "D",
    [string]$PolicyDir,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

$engineScript = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Apply-QcsubsysWdacHashPolicy-Admin.ps1"
if (-not (Test-Path -LiteralPath $engineScript)) {
    throw "Alioth-Engineering apply script not found: $engineScript"
}

& $engineScript -WindowsDrive $WindowsDrive -PolicyDir $PolicyDir -AllowHostSystemDrive:$AllowHostSystemDrive
