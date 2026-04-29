param(
    [string]$MuRoot,
    [switch]$NoCompile
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\prepare-acpi-hid-phase3.ps1"

$argsList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $scriptPath
)

if ($MuRoot) { $argsList += @("-MuRoot", $MuRoot) }
if ($NoCompile) { $argsList += "-NoCompile" }

& powershell @argsList
