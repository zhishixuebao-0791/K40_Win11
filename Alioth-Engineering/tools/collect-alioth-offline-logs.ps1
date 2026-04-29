param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot

function Normalize-Drive([string]$Drive) {
    if ($Drive.Length -eq 1) {
        return "$Drive`:"
    }
    if ($Drive.Length -ge 2 -and $Drive[1] -eq ':') {
        return $Drive.Substring(0, 2)
    }
    throw "Invalid drive value: $Drive"
}

$WindowsDrive = Normalize-Drive $WindowsDrive
$OutputRoot = if ($OutputRoot) { $OutputRoot } else { Join-Path $engineeringRoot "collected-logs" }

if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDir = Join-Path $OutputRoot $timestamp
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$paths = @(
    "$WindowsDrive\Windows\Panther",
    "$WindowsDrive\Windows\INF\setupapi.dev.log",
    "$WindowsDrive\Windows\INF\setupapi.app.log",
    "$WindowsDrive\Windows\ntbtlog.txt",
    "$WindowsDrive\Windows\Minidump",
    "$WindowsDrive\Windows\MEMORY.DMP",
    "$WindowsDrive\Windows\System32\LogFiles",
    "$WindowsDrive\Windows\System32\LogFiles\Srt\SrtTrail.txt",
    "$WindowsDrive\Windows\debug\NetSetup.log"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Copy-Item -Path $path -Destination $outputDir -Recurse -Force
    }
}

Write-Output "Offline logs copied to: $outputDir"
