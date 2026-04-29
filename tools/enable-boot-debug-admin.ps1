$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'enable-boot-debug-admin.log'
$diskpartScript = Join-Path $root '_diskpart_mount_esp_for_debug.txt'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
Write-Log 'Enable boot debug started.'

$targetDisk = Get-Disk | Where-Object { $_.FriendlyName -eq 'Qualcomm MMC Storage' -and $_.BusType -eq 'USB' } | Select-Object -First 1
if ($null -eq $targetDisk) {
    throw 'Qualcomm MMC Storage disk not found. Keep the phone in Mass Storage mode and rerun.'
}

Write-Log ("Detected target disk: {0}" -f $targetDisk.Number)

$existingEsp = Get-CimInstance Win32_Volume | Where-Object { $_.Label -eq 'ESP' -and $_.FileSystem -eq 'FAT32' } | Select-Object -First 1
if ($null -ne $existingEsp -and $existingEsp.DriveLetter) {
    $espDrive = $existingEsp.DriveLetter
    Write-Log ("Reusing existing ESP mount: {0}" -f $espDrive)
} else {
    $espDrive = 'R:'
    @'
select disk {0}
select partition 36
assign letter={1}
'@ -f $targetDisk.Number, $espDrive.TrimEnd(':') | Set-Content -LiteralPath $diskpartScript -Encoding ASCII
    $diskpartOutput = & diskpart /s $diskpartScript 2>&1
    $diskpartOutput | ForEach-Object { Write-Log $_ }
}

if (-not (Test-Path ($espDrive + '\EFI\Microsoft\Boot\BCD'))) {
    throw ('BCD not found at ' + $espDrive + '\EFI\Microsoft\Boot\BCD')
}

Write-Log 'Enabling BCD diagnostics.'
$store = $espDrive + '\EFI\Microsoft\Boot\BCD'
$cmds = @(
    "bcdedit /store `"$store`" /set {default} bootlog Yes",
    "bcdedit /store `"$store`" /set {default} sos Yes",
    "bcdedit /store `"$store`" /set {bootmgr} displaybootmenu Yes",
    "bcdedit /store `"$store`" /set {bootmgr} timeout 5",
    "bcdedit /store `"$store`" /set {default} bootstatuspolicy DisplayAllFailures"
)

foreach ($cmd in $cmds) {
    Write-Log ('RUN ' + $cmd)
    $output = cmd /c $cmd 2>&1
    $output | ForEach-Object { Write-Log $_ }
}

Write-Log 'Enable boot debug completed.'
