param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [Parameter(Mandatory = $true)]
    [string]$EspDrive,

    [string]$WimPath,

    [int]$ImageIndex = 1,

    [string]$LogRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $engineeringRoot

if (-not $WimPath) {
    $WimPath = Join-Path $workspaceRoot "win11_iso\install.wim"
}

if (-not $LogRoot) {
    $LogRoot = Join-Path $engineeringRoot "logs"
}

function Normalize-Drive([string]$drive) {
    if ($drive.Length -eq 1) {
        return "$drive`:"
    }
    if ($drive.Length -ge 2 -and $drive[1] -eq ':') {
        return $drive.Substring(0, 2)
    }
    throw "Invalid drive value: $drive"
}

$WindowsDrive = Normalize-Drive $WindowsDrive
$EspDrive = Normalize-Drive $EspDrive

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $LogRoot "deploy-$timestamp.log"

function Write-Log([string]$message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
    $line | Tee-Object -FilePath $logFile -Append
}

Write-Log "Starting alioth experimental deployment"
Write-Log "WIM: $WimPath"
Write-Log "Image index: $ImageIndex"
Write-Log "Windows drive: $WindowsDrive"
Write-Log "ESP drive: $EspDrive"

if (-not (Test-Path $WimPath)) {
    throw "WIM not found: $WimPath"
}

if (-not (Test-Path "$WindowsDrive\")) {
    throw "Windows target drive not found: $WindowsDrive"
}

if (-not (Test-Path "$EspDrive\")) {
    throw "ESP target drive not found: $EspDrive"
}

Write-Log "Applying Windows image with DISM"
dism /Apply-Image /ImageFile:$WimPath /Index:$ImageIndex /ApplyDir:"$WindowsDrive\" /CheckIntegrity | Tee-Object -FilePath $logFile -Append

Write-Log "Writing boot files with bcdboot"
bcdboot "$WindowsDrive\Windows" /s "$EspDrive" /f UEFI | Tee-Object -FilePath $logFile -Append

Write-Log "Deployment finished"
Write-Log "Next step: inject driver packs if available, then first-boot the device"
