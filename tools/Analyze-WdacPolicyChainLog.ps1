param(
    [Parameter(Mandatory = $true)]
    [string]$LogDir,
    [string]$NotesDir = "C:\yjc_code\K40_Win11\Alioth-Engineering\notes"
)

$engineScript = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Analyze-WdacPolicyChainLog.ps1"
if (-not (Test-Path -LiteralPath $engineScript)) {
    throw "Alioth-Engineering analyzer script not found: $engineScript"
}

& $engineScript -LogDir $LogDir -NotesDir $NotesDir

