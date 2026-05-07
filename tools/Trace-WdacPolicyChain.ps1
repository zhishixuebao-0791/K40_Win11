param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [string[]]$PolicyIds = @(
        "d2bda982-ccf6-4344-ac5b-0b44427b6816",
        "86B04D39-E928-4F0F-937E-0F44B0909E79",
        "1283ac0f-fff1-49ae-ada1-8a933130cad6",
        "2678656c-05ef-481f-bc5b-ebd8c991502d"
    ),
    [int]$MaxEvents = 800
)

$engineScript = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Trace-WdacPolicyChain.ps1"
if (-not (Test-Path -LiteralPath $engineScript)) {
    throw "Alioth-Engineering trace script not found: $engineScript"
}

& $engineScript -OutputRoot $OutputRoot -PolicyIds $PolicyIds -MaxEvents $MaxEvents

