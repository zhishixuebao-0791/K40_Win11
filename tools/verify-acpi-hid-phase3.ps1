param(
    [string]$MuRoot,
    [string]$ImagePath
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\verify-acpi-hid-phase3.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
)

if ($MuRoot) { $argsList += @("-MuRoot", $MuRoot) }
if ($ImagePath) { $argsList += @("-ImagePath", $ImagePath) }

& powershell @argsList
