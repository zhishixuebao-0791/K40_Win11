param(
    [string]$WindowsDrive = "D",
    [string]$EspDrive,
    [switch]$MountEsp,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window when -MountEsp is used."
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
        foreach ($part in $parts) {
            return $part
        }
    }
    return $null
}

function Mount-PhoneEsp {
    param([string]$PreferredLetter)

    Assert-Administrator
    $letter = $PreferredLetter.TrimEnd(':', '\')
    if (-not $letter) { $letter = "R" }

    $part = Find-PhoneEspPartition
    if (-not $part) {
        throw "Could not find phone ESP partition on Qualcomm USB storage."
    }

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

function Get-PolicyFileRecord {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Present = $false; Length = $null; Sha256 = $null }
    }
    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    return [pscustomobject]@{ Path = $Path; Present = $true; Length = $item.Length; Sha256 = $hash.Hash }
}

$projectRoot = Get-ProjectRoot
$logRoot = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$outDir = Join-Path $logRoot ("WindowsDriverPolicyFiles_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$winRoot = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$espRoot = $null
if ($EspDrive) {
    $espRoot = "${($EspDrive.TrimEnd(':','\'))}:\"
} elseif ($MountEsp) {
    $espRoot = Mount-PhoneEsp -PreferredLetter "R"
}

$guids = @(
    "784C4414-79F4-4C32-A6A5-F0FB42A51D0D",
    "8F9CB695-5D48-48D6-A329-7202B44607E3",
    "D2BDA982-CCF6-4344-AC5B-0B44427B6816"
)

$roots = @(
    (Join-Path $winRoot "Windows\System32\CodeIntegrity\CiPolicies\Active")
)
if ($espRoot -and (Test-Path -LiteralPath $espRoot)) {
    $roots += (Join-Path $espRoot "EFI\Microsoft\Boot\CiPolicies\Active")
}

$records = @()
foreach ($root in $roots) {
    foreach ($guid in $guids) {
        $records += Get-PolicyFileRecord -Path (Join-Path $root ("{$guid}.cip"))
    }
}

$records | Format-List | Out-File -LiteralPath (Join-Path $outDir "policy-file-records.txt") -Encoding UTF8
$records | Export-Csv -LiteralPath (Join-Path $outDir "policy-file-records.csv") -NoTypeInformation -Encoding UTF8

@(
    "WindowsRoot=$winRoot",
    "EspRoot=$espRoot",
    "PolicyPresentCount=$(@($records | Where-Object Present).Count)",
    "If the 784C/8F9C policies are present, Microsoft documents these as Windows Driver Policy audit/enforcement policies.",
    "If only D2BDA982 is active in CodeIntegrity events and no 784C/8F9C files exist, this system is using an older/embedded driver policy source and disabling by GUID file may not be sufficient."
) | Set-Content -LiteralPath (Join-Path $outDir "00_verdict.txt") -Encoding UTF8

Write-Host "Windows Driver Policy file trace completed:"
Write-Host "  $outDir"
