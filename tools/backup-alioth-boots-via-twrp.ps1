$ErrorActionPreference = 'Stop'

$fastboot = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe'
$adb = 'C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\adb.exe'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$twrp = Join-Path $root 'HMK40-twrp-12.0-13.0\[BOOT]twrp-13.0.img'
$backupRoot = Join-Path $root 'boot-backups'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = Join-Path $backupRoot $stamp
$log = Join-Path $dest 'backup-alioth-boots-via-twrp.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

function Wait-ForAdbRecovery {
    $deadline = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $deadline) {
        $list = & $adb devices
        if ($list | Select-String -Pattern "^\S+\s+(recovery|device)$") {
            return
        }
        Start-Sleep -Seconds 3
    }
    throw 'Timed out waiting for adb after booting TWRP.'
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
New-Item -ItemType File -Force -Path $log | Out-Null

Write-Log 'Starting TWRP-backed boot partition backup.'
if (-not (Test-Path -LiteralPath $twrp)) {
    throw ('TWRP image not found: ' + $twrp)
}

$device = & $fastboot devices
if (-not ($device | Select-String -Pattern 'fastboot')) {
    throw 'No fastboot device detected.'
}

Write-Log 'Booting temporary TWRP.'
& $fastboot boot $twrp
Wait-ForAdbRecovery

$paths = @(
    '/dev/block/by-name/boot_a',
    '/dev/block/bootdevice/by-name/boot_a'
)
$bootAPath = $null
foreach ($path in $paths) {
    $result = & $adb shell "if [ -e $path ]; then echo FOUND:$path; fi"
    if ($result -match '^FOUND:') {
        $bootAPath = $result.Replace('FOUND:','').Trim()
        break
    }
}
if (-not $bootAPath) {
    throw 'Unable to locate boot_a block device in TWRP.'
}
$bootBPath = $bootAPath -replace 'boot_a$', 'boot_b'
Write-Log ('Resolved boot paths: ' + $bootAPath + ' / ' + $bootBPath)

foreach ($part in @(
    @{ Name = 'boot_a'; Src = $bootAPath },
    @{ Name = 'boot_b'; Src = $bootBPath }
)) {
    $remote = '/tmp/' + $part.Name + '.img'
    $local = Join-Path $dest ($part.Name + '.img')
    Write-Log ('Dumping ' + $part.Name + ' from ' + $part.Src)
    & $adb shell "dd if=$($part.Src) of=$remote bs=4M"
    Write-Log ('Pulling ' + $part.Name + ' to ' + $local)
    & $adb pull $remote $local
    $item = Get-Item -LiteralPath $local
    if ($item.Length -le 0) {
        throw ('Backup file is empty: ' + $local)
    }
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $local
    Write-Log ('SHA256 ' + $part.Name + ' ' + $hash.Hash)
}

Write-Log 'Rebooting back to fastboot.'
& $adb reboot bootloader
Write-Log 'TWRP-backed boot partition backup completed.'
