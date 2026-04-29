param(
    [string]$DtbPath,
    [string]$EvidencePath,
    [string]$OutputPath
)

$workspaceRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $workspaceRoot "Alioth-Engineering\tools\compare-alioth-dtb-vs-windows-audio.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Alioth engineering DTB/Windows audio compare script not found: $scriptPath"
}

$argsList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-EvidencePath", $EvidencePath)
if ($DtbPath) {
    $argsList += @("-DtbPath", $DtbPath)
}
if ($OutputPath) {
    $argsList += @("-OutputPath", $OutputPath)
}

powershell @argsList
