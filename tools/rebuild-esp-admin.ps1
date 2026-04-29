$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'rebuild-esp-admin.log'
$diskpartScript = Join-Path $root '_diskpart_rebuild_esp.txt'
$targetDisk = $null
$espDrive = $null
$windowsDrive = $null

function Get-FreeDriveLetter {
    $used = @(
        Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID } | ForEach-Object {
            $_.DeviceID.TrimEnd(':').ToUpperInvariant()
        }
    )

    foreach ($letter in @('S','R','T','U','V','W','X','Y','Z','Q','P','O')) {
        if ($used -notcontains $letter) {
            return ($letter + ':\')
        }
    }

    throw 'No free drive letter available for ESP mount.'
}

function Write-Log {
    param([string]$Message)
    $parent = Split-Path -Parent $log
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

function Get-OfflineWindowsDrive {
    $candidates = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 3 } |
        ForEach-Object { $_.DeviceID } |
        Where-Object { $_ -and $_ -ne 'C:' }

    foreach ($drive in $candidates) {
        if (Test-Path "$drive\Windows\System32") {
            return $drive
        }
    }

    throw 'Could not locate offline Windows drive automatically.'
}

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
Write-Log 'Rebuild ESP started.'

$targetDisk = Get-Disk | Where-Object { $_.FriendlyName -eq 'Qualcomm MMC Storage' -and $_.BusType -eq 'USB' } | Select-Object -First 1
if ($null -eq $targetDisk) {
    throw 'Qualcomm MMC Storage disk not found. Keep the phone in Mass Storage mode and rerun.'
}

Write-Log ("Detected target disk: {0} ({1})" -f $targetDisk.Number, $targetDisk.FriendlyName)

$existingEsp = Get-CimInstance Win32_Volume | Where-Object {
    $_.Label -eq 'ESP' -and $_.FileSystem -eq 'FAT32'
} | Select-Object -First 1

if ($null -ne $existingEsp -and $existingEsp.DriveLetter) {
    $espDrive = $existingEsp.DriveLetter
    Write-Log ("Reusing existing ESP mount: {0}" -f $espDrive)
} else {
    $espDrive = Get-FreeDriveLetter
    Write-Log ("Mounting target ESP as {0}" -f $espDrive)
    @'
select disk {0}
select partition 36
assign letter={1}
detail partition
'@ -f $targetDisk.Number, $espDrive.TrimEnd(':\') | Set-Content -LiteralPath $diskpartScript -Encoding ASCII

    $diskpartOutput = & diskpart /s $diskpartScript 2>&1
    $diskpartOutput | ForEach-Object { Write-Log $_ }
}

if (-not (Test-Path $espDrive)) {
    throw ("ESP was not mounted after diskpart. Expected path: {0}" -f $espDrive)
}

$windowsDrive = Get-OfflineWindowsDrive
Write-Log ("Detected offline Windows drive: {0}" -f $windowsDrive)

Write-Log ("Formatting {0} as FAT32 with standard Windows layout." -f $espDrive)
$formatOutput = & format.com $espDrive.TrimEnd('\') /FS:FAT32 /Q /V:ESP /Y 2>&1
$formatOutput | ForEach-Object { Write-Log $_ }

Write-Log 'Rebuilding EFI boot files with BCDBoot.'
$bcdbootOutput = & bcdboot "$windowsDrive\Windows" /s $espDrive.TrimEnd('\') /f UEFI /v 2>&1
$bcdbootOutput | ForEach-Object { Write-Log $_ }

Write-Log 'Listing rebuilt EFI tree.'
Get-ChildItem -Recurse -LiteralPath (Join-Path $espDrive 'EFI') -ErrorAction Stop |
    Select-Object FullName, Length |
    ForEach-Object { Write-Log ("EFI {0}" -f $_.FullName) }

Write-Log 'Rebuild ESP completed.'
