param(
    [string]$WindowsDrive = "D",
    [string]$CandidateRoot,
    [switch]$IncludeSubsystemExtensions,
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
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be D: or another removable drive."
        }
    }

    $root = "${normalized}:\"
    $configDir = Join-Path $root "Windows\System32\Config"
    $driverStore = Join-Path $root "Windows\System32\DriverStore\FileRepository"
    if (-not (Test-Path -LiteralPath $configDir)) {
        throw "Offline Config directory not found: $configDir"
    }
    if (-not (Test-Path -LiteralPath $driverStore)) {
        throw "Offline DriverStore not found: $driverStore"
    }
    return $root
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $script:LogPath -Append
}

function Invoke-Captured {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $script:LASTNATIVEEXITCODE = 0
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>&1
        $script:LASTNATIVEEXITCODE = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    $output | Tee-Object -FilePath $script:LogPath -Append
    if (($script:LASTNATIVEEXITCODE -ne 0) -and (-not $IgnoreExitCode)) {
        throw "Command failed with exit code $($script:LASTNATIVEEXITCODE): $FilePath"
    }
    return $output
}

function Assert-Signature {
    param(
        [string]$Path,
        [string[]]$AllowedSubjectFragments
    )

    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
    $issuer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Issuer } else { "" }
    Write-Log "Signature: $Path => $($sig.Status); Subject=$subject; Issuer=$issuer"
    if ($sig.Status -ne "Valid") {
        throw "Invalid signature for ${Path}: $($sig.Status)"
    }
    if ($AllowedSubjectFragments -and -not (@($AllowedSubjectFragments | Where-Object { $subject -like "*$_*" }).Count -gt 0)) {
        throw "Unexpected signer for $Path. Expected one of: $($AllowedSubjectFragments -join ', ')"
    }
}

function Get-PublishedDriverNames {
    param([string]$Root)

    $output = Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$Root", "/Get-Drivers", "/Format:Table") -IgnoreExitCode
    $rows = foreach ($line in $output) {
        if ($line -match '^(oem\d+\.inf)\s+.+$') {
            $matches[1]
        }
    }
    return @($rows | Sort-Object -Unique)
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
if (-not $CandidateRoot) {
    $CandidateRoot = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate"
}

$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$backupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("apply-qcpil8280-candidate-{0}.log" -f $stamp)
$backupDir = Join-Path $backupRoot ("qcpil8280-candidate-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Log "Applying official Surface Pro 9 5G qcpil8280 candidate."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "CandidateRoot: $CandidateRoot"
Write-Log "BackupDir: $backupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$candidateFull = (Resolve-Path -LiteralPath $CandidateRoot).Path

$infPaths = @(
    Join-Path $candidateFull "qcpil\qcpil.inf",
    Join-Path $candidateFull "qcpilfilterext\qcpilfilterext.inf"
)
if ($IncludeSubsystemExtensions) {
    $infPaths += Join-Path $candidateFull "qcpilext8280\qcpilEXT8280.inf"
}

foreach ($infPath in $infPaths) {
    if (-not (Test-Path -LiteralPath $infPath)) {
        throw "Candidate INF missing: $infPath"
    }
    $folder = Split-Path -Parent $infPath
    Copy-Item -LiteralPath $folder -Destination (Join-Path $backupDir (Split-Path -Leaf $folder)) -Recurse -Force
    Get-ChildItem -LiteralPath $folder -File |
        Where-Object { $_.Extension -in ".cat", ".sys" } |
        ForEach-Object {
            $allowed = if ($_.Extension -ieq ".cat") {
                @("Microsoft Windows Hardware Compatibility Publisher", "Microsoft Windows Third Party Component CA")
            } else {
                @("QUALCOMM", "Microsoft Windows Hardware Compatibility Publisher")
            }
            Assert-Signature -Path $_.FullName -AllowedSubjectFragments $allowed
        }
}

$before = Get-PublishedDriverNames -Root $root
$before | Out-File -LiteralPath (Join-Path $backupDir "published-drivers-before.txt") -Encoding UTF8

foreach ($infPath in $infPaths) {
    Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Add-Driver", "/Driver:$infPath")
}

$after = Get-PublishedDriverNames -Root $root
$after | Out-File -LiteralPath (Join-Path $backupDir "published-drivers-after.txt") -Encoding UTF8
$newDrivers = @($after | Where-Object { $_ -notin $before })
$newDrivers | Out-File -LiteralPath (Join-Path $backupDir "published-drivers-added.txt") -Encoding UTF8

$manifest = [pscustomobject]@{
    WindowsDrive = $WindowsDrive
    Root = $root
    CandidateRoot = $candidateFull
    IncludedInfPaths = $infPaths
    IncludeSubsystemExtensions = [bool]$IncludeSubsystemExtensions
    BackupDir = $backupDir
    PublishedDriversAdded = $newDrivers
    CreatedAt = (Get-Date).ToString("s")
    RollbackCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$projectRoot\tools\Rollback-Qcpil8280Candidate-Admin.ps1`" -WindowsDrive $WindowsDrive -BackupDir `"$backupDir`""
}
$manifest | ConvertTo-Json -Depth 6 |
    Out-File -LiteralPath (Join-Path $backupDir "manifest.json") -Encoding UTF8

Write-Log "qcpil8280 candidate apply completed."
Write-Log "Rollback command: $($manifest.RollbackCommand)"
Write-Host "qcpil8280 candidate applied."
Write-Host "Backup: $backupDir"
Write-Host "Log: $script:LogPath"
Write-Host "Next: boot Phase8 UEFI, then run Trace-AliothPilcFailure and AudioDependencyState diagnostics."
