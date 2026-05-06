param(
    [string]$WindowsDrive = "D",
    [string]$PdsrDriverRoot,
    [string]$TftpDriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\apply-audio-pdsr-tftp-phase5-admin.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath,
    "-WindowsDrive", $WindowsDrive
)

if ($PdsrDriverRoot) { $argsList += @("-PdsrDriverRoot", $PdsrDriverRoot) }
if ($TftpDriverRoot) { $argsList += @("-TftpDriverRoot", $TftpDriverRoot) }
if ($SkipDism) { $argsList += "-SkipDism" }
if ($AllowHostSystemDrive) { $argsList += "-AllowHostSystemDrive" }

& powershell @argsList
