$ErrorActionPreference = 'Stop'

$fastboot = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$image = Join-Path $root 'UEFI-Images\Mu-alioth-1.img'
$log = Join-Path $root 'flash-uefi-to-boot-a.log'

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
Write-Log 'Starting persistent UEFI flash to boot_a.'

if (-not (Test-Path $image)) {
    throw ('UEFI image not found: ' + $image)
}

$device = & $fastboot devices
if (-not ($device | Select-String -Pattern 'fastboot')) {
    throw 'No fastboot device detected.'
}

$slot = Invoke-FastbootText 'getvar current-slot'
$slot | ForEach-Object { Write-Log $_ }
if (-not ($slot | Select-String -Pattern 'current-slot:b')) {
    Write-Log 'Warning: active slot is not b. Script will still only flash boot_a.'
}

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $image
Write-Log ('Flashing image SHA256 ' + $hash.Hash)
& $fastboot flash boot_a $image
Write-Log 'Flash to boot_a completed.'
