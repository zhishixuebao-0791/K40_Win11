param(
    [string]$WindowsDrive = "D",
    [string]$SignatureDriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-woa-andromeda-signature-trust-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($SignatureDriverRoot) { $argsList += @("-SignatureDriverRoot", $SignatureDriverRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }
if ($AllowHostSystemDrive) { $argsList += "-AllowHostSystemDrive" }

& powershell @argsList
