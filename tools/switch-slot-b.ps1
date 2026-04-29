$ErrorActionPreference = 'Stop'

$fastboot = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'switch-slot-b.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

function Invoke-FastbootText {
    param([string]$Args)
    cmd /c ('"' + $fastboot + '" ' + $Args + ' 2>&1')
}

New-Item -ItemType File -Force -Path $log | Out-Null
Write-Log 'Setting active slot to b.'
& $fastboot set_active b
$check = Invoke-FastbootText 'getvar current-slot'
$check | ForEach-Object { Write-Log $_ }
Write-Log 'Slot switch to b completed.'
