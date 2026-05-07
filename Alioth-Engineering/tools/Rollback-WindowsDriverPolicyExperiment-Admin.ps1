param(
    [Parameter(Mandatory = $true)]
    [string]$BackupDir
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

Assert-Administrator

$json = Join-Path $BackupDir "disable-results.json"
if (-not (Test-Path -LiteralPath $json)) {
    throw "disable-results.json not found: $json"
}

$records = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
foreach ($record in $records) {
    if ($record.Action -ne "Renamed") { continue }
    if (-not $record.DisabledPath) { continue }
    if (-not (Test-Path -LiteralPath $record.DisabledPath)) {
        Write-Host "Disabled file missing, skipping: $($record.DisabledPath)"
        continue
    }
    Move-Item -LiteralPath $record.DisabledPath -Destination $record.Path -Force
    Write-Host "Restored $($record.Path)"
}

Write-Host "Windows Driver Policy experiment rollback completed."
