$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath
)

$fastboot = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'restore-boot-a.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

New-Item -ItemType File -Force -Path $log | Out-Null
Write-Log ('Restoring boot_a from ' + $ImagePath)

if (-not (Test-Path $ImagePath)) {
    throw ('Restore image not found: ' + $ImagePath)
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $ImagePath
Write-Log ('Restore image SHA256 ' + $hash.Hash)
& $fastboot flash boot_a $ImagePath
Write-Log 'Restore boot_a completed.'
