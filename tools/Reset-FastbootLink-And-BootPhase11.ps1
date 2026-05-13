param(
    [string]$FastbootPath = "C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\fastboot.exe",
    [string]$AdbPath = "C:\jcy_software\Android\sdk\commandlinetools-win-14742923_latest\platform-tools\adb.exe",
    [string]$ImagePath = "C:\yjc_code\K40_Win11\UEFI-Images\Mu-alioth-1-acpi-hid-phase11-20260513-141246.img",
    [int]$WaitSeconds = 45
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$stamp] $Message"
}

function Get-FastbootLines {
    if (-not (Test-Path -LiteralPath $FastbootPath)) {
        throw "fastboot.exe not found: $FastbootPath"
    }
    $output = & $FastbootPath devices -l 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        return @()
    }
    return @($output | Where-Object { $_ -match "\S" })
}

if (-not (Test-Path -LiteralPath $ImagePath)) {
    throw "UEFI image not found: $ImagePath"
}

Write-Step "Cleaning normal adb/fastboot processes."
Get-Process adb,fastboot -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        Write-Step "Stopped $($_.ProcessName) PID $($_.Id)."
    } catch {
        Write-Step "Could not stop $($_.ProcessName) PID $($_.Id): $($_.Exception.Message)"
    }
}

if (Test-Path -LiteralPath $AdbPath) {
    Write-Step "Stopping adb server."
    & $AdbPath kill-server 2>$null | Out-Null
}

Write-Step "Checking fastboot visibility."
$devices = Get-FastbootLines
if ($devices.Count -eq 0) {
    Write-Host ""
    Write-Host "fastboot cannot see the phone right now."
    Write-Host "Required physical recovery:"
    Write-Host "1. Unplug the phone USB cable from the Win10 PC."
    Write-Host "2. Hold Power + Volume Down until the phone returns to FASTBOOT."
    Write-Host "3. Plug the phone directly into a motherboard USB port. Avoid USB hub/dock for fastboot."
    Write-Host "4. Wait for Android Bootloader Interface to appear, then press Enter here."
    [void][System.Console]::ReadLine()

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
        Start-Sleep -Seconds 2
        $devices = Get-FastbootLines
        if ($devices.Count -gt 0) { break }
        Write-Step "Waiting for fastboot device..."
    } while ((Get-Date) -lt $deadline)
}

if ($devices.Count -eq 0) {
    throw "fastboot still cannot see the phone. Reboot the Win10 PC to release stuck WinUSB handles, then run this script again."
}

Write-Step "Detected fastboot device:"
$devices | ForEach-Object { Write-Host $_ }

Write-Step "Booting Phase11 UEFI image."
& $FastbootPath boot $ImagePath
if ($LASTEXITCODE -ne 0) {
    throw "fastboot boot failed with exit code $LASTEXITCODE."
}

Write-Step "fastboot boot completed. Watch the phone screen for Project Silicium/Windows startup."
