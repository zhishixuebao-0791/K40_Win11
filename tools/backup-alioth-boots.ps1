$ErrorActionPreference = 'Stop'

$fastboot = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$backupRoot = Join-Path $root 'boot-backups'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = Join-Path $backupRoot $stamp
$log = Join-Path $dest 'backup-alioth-boots.log'

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

New-Item -ItemType Directory -Force -Path $dest | Out-Null
New-Item -ItemType File -Force -Path $log | Out-Null

Write-Log 'Starting boot partition backup.'
$device = & $fastboot devices
if (-not ($device | Select-String -Pattern 'fastboot')) {
    throw 'No fastboot device detected.'
}

$vars = Invoke-FastbootText 'getvar all'
$vars | Set-Content -LiteralPath (Join-Path $dest 'fastboot-getvar-all.txt') -Encoding UTF8
$slotLine = $vars | Select-String -Pattern 'current-slot:'
if ($slotLine) {
    Write-Log ('Detected ' + $slotLine.Line.Trim())
}

foreach ($part in 'boot_a', 'boot_b') {
    $outFile = Join-Path $dest ($part + '.img')
    Write-Log ('Fetching ' + $part + ' to ' + $outFile)
    & $fastboot fetch $part $outFile
    if (-not (Test-Path $outFile)) {
        throw ('Backup missing for ' + $part)
    }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outFile
    Write-Log ('SHA256 ' + $part + ' ' + $hash.Hash)
}

Write-Log 'Boot partition backup completed.'
