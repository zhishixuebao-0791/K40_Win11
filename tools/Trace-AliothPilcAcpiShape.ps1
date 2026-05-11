param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 800
)

$script = "C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Trace-AliothPilcAcpiShape.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Implementation script not found: $script"
}

& $script -OutputRoot $OutputRoot -MaxEvents $MaxEvents
