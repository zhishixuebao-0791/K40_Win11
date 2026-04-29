param(
    [string]$PreferredLetter = "R",
    [string]$LogRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $script:LogFile -Append
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $LogRoot "mount-esp-$timestamp.log"

$targetDisk = Get-Disk | Where-Object { $_.FriendlyName -eq 'Qualcomm MMC Storage' -and $_.BusType -eq 'USB' } | Select-Object -First 1
if ($null -eq $targetDisk) {
    throw "Qualcomm MMC Storage disk not found. Keep the phone in Mass Storage mode and rerun."
}

$targetPartition = Get-Partition -DiskNumber $targetDisk.Number -ErrorAction SilentlyContinue |
    Where-Object {
        $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -or
        $_.PartitionNumber -eq 36
    } |
    Sort-Object PartitionNumber |
    Select-Object -First 1

if ($null -eq $targetPartition) {
    throw ("Could not locate ESP on disk {0}." -f $targetDisk.Number)
}

if ($targetPartition.DriveLetter) {
    $mounted = "{0}:" -f $targetPartition.DriveLetter
    Write-Log ("ESP is already mounted as {0}" -f $mounted)
    Write-Output $mounted
    exit 0
}

$letter = $PreferredLetter.Trim().TrimEnd(':')
$diskpartScript = Join-Path $env:TEMP ("alioth-mount-esp-{0}.txt" -f ([guid]::NewGuid().ToString('N')))
@'
select disk {0}
select partition {1}
assign letter={2}
detail partition
'@ -f $targetDisk.Number, $targetPartition.PartitionNumber, $letter | Set-Content -LiteralPath $diskpartScript -Encoding ASCII

try {
    $output = & diskpart /s $diskpartScript 2>&1
    $output | ForEach-Object { Write-Log $_ }
} finally {
    Remove-Item -LiteralPath $diskpartScript -Force -ErrorAction SilentlyContinue
}

$mounted = "{0}:" -f $letter.ToUpperInvariant()
Write-Log ("Requested ESP mount as {0}" -f $mounted)
Write-Output $mounted
