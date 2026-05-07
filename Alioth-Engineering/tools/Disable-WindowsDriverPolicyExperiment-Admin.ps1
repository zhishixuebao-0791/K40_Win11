param(
    [string]$WindowsDrive = "D",
    [string]$EspDrive,
    [switch]$MountEsp,
    [switch]$Apply,
    [switch]$IncludeLegacyD2Policy,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

function Resolve-OfflineWindowsRoot {
    param([string]$Drive)
    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage Windows drive, normally D:."
        }
    }
    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\CodeIntegrity"))) {
        throw "Offline CodeIntegrity directory not found under $root"
    }
    return $root
}

function Find-PhoneEspPartition {
    $phoneDisks = Get-Disk | Where-Object { $_.FriendlyName -match "Qualcomm|MMC|Storage" -and $_.BusType -eq "USB" }
    foreach ($disk in $phoneDisks) {
        $parts = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -and $_.Size -gt 100MB -and $_.Size -lt 2GB }
        foreach ($part in $parts) { return $part }
    }
    return $null
}

function Mount-PhoneEsp {
    param([string]$PreferredLetter)
    $letter = $PreferredLetter.TrimEnd(':', '\')
    if (-not $letter) { $letter = "R" }
    $part = Find-PhoneEspPartition
    if (-not $part) { throw "Could not find phone ESP partition on Qualcomm USB storage." }
    $script = @(
        "select disk $($part.DiskNumber)",
        "select partition $($part.PartitionNumber)",
        "assign letter=$letter",
        "exit"
    )
    $dp = Join-Path $env:TEMP ("alioth-mount-esp-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
    $script | Set-Content -LiteralPath $dp -Encoding ASCII
    & diskpart.exe /s $dp | Out-String | Write-Host
    Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue
    return "${letter}:\"
}

function Backup-And-Disable {
    param(
        [string]$Path,
        [string]$BackupDir,
        [string]$Stamp,
        [bool]$DoApply
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        [pscustomobject]@{ Path = $Path; Present = $false; Action = "Missing" }
        return
    }

    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    $relName = ($Path -replace '[:\\]+','_').Trim('_')
    Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupDir $relName) -Force

    if ($DoApply) {
        $disabledPath = "$Path.disabled-by-alioth-$Stamp"
        Move-Item -LiteralPath $Path -Destination $disabledPath -Force
        [pscustomobject]@{ Path = $Path; Present = $true; Action = "Renamed"; DisabledPath = $disabledPath; Sha256 = $hash.Hash; Length = $item.Length }
    } else {
        [pscustomobject]@{ Path = $Path; Present = $true; Action = "DryRunWouldRename"; DisabledPath = "$Path.disabled-by-alioth-$Stamp"; Sha256 = $hash.Hash; Length = $item.Length }
    }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $projectRoot "Alioth-Engineering\backups\windows-driver-policy-disable-$stamp"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

$winRoot = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$espRoot = $null
if ($EspDrive) {
    $espRoot = "${($EspDrive.TrimEnd(':','\'))}:\"
} elseif ($MountEsp) {
    $espRoot = Mount-PhoneEsp -PreferredLetter "R"
}

$guids = @(
    "784C4414-79F4-4C32-A6A5-F0FB42A51D0D",
    "8F9CB695-5D48-48D6-A329-7202B44607E3"
)
if ($IncludeLegacyD2Policy) {
    $guids += "D2BDA982-CCF6-4344-AC5B-0B44427B6816"
}

$targets = @()
$targets += $guids | ForEach-Object { Join-Path (Join-Path $winRoot "Windows\System32\CodeIntegrity\CiPolicies\Active") ("{$_}.cip") }
if ($espRoot -and (Test-Path -LiteralPath $espRoot)) {
    $targets += $guids | ForEach-Object { Join-Path (Join-Path $espRoot "EFI\Microsoft\Boot\CiPolicies\Active") ("{$_}.cip") }
}

$results = foreach ($target in $targets) {
    Backup-And-Disable -Path $target -BackupDir $backupDir -Stamp $stamp -DoApply:$Apply
}

$results | Format-List | Tee-Object -FilePath (Join-Path $backupDir "disable-results.txt")
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupDir "disable-results.json") -Encoding UTF8

Write-Host "Backup directory:"
Write-Host "  $backupDir"
if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply to rename policy files."
}
