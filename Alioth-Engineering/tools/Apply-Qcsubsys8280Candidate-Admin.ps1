param(
    [string]$WindowsDrive = "D",
    [string]$CandidateDir,
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

function Unload-HiveWithRetry {
    param([string]$HiveName)

    for ($attempt = 1; $attempt -le 8; $attempt++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds (250 * $attempt)
        $out = Invoke-Captured -FilePath reg.exe -Arguments @("unload", "HKLM\$HiveName") -IgnoreExitCode
        if ($script:LASTNATIVEEXITCODE -eq 0) {
            Write-Log "Unloaded HKLM\$HiveName on attempt $attempt."
            return $true
        }
        Write-Log "Hive unload attempt $attempt failed with exit code $($script:LASTNATIVEEXITCODE)."
    }

    Write-Log "WARNING: HKLM\$HiveName is still loaded. Close PowerShell windows and run Cleanup-OrphanAliothHives-Admin.ps1."
    return $false
}

function Assert-Signature {
    param(
        [string]$Path,
        [string]$RequiredSubjectFragment
    )

    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    Write-Log "Signature: $Path => $($sig.Status); Subject=$($sig.SignerCertificate.Subject); Issuer=$($sig.SignerCertificate.Issuer)"
    if ($sig.Status -ne "Valid") {
        throw "Invalid signature for ${Path}: $($sig.Status)"
    }
    if ($RequiredSubjectFragment -and ($sig.SignerCertificate.Subject -notlike "*$RequiredSubjectFragment*")) {
        throw "Unexpected signer for $Path. Expected subject fragment: $RequiredSubjectFragment"
    }
}

function Add-CompatibleId {
    param(
        [string]$InstanceKey,
        [string]$Alias
    )

    $props = Get-ItemProperty -LiteralPath $InstanceKey -ErrorAction Stop
    $hardwareId = @()
    $compatibleId = @()
    if ($null -ne $props.HardwareID) {
        $hardwareId = @($props.HardwareID)
    }
    if ($null -ne $props.CompatibleIDs) {
        $compatibleId = @($props.CompatibleIDs)
    }

    $newCompatible = @($compatibleId + $Alias | Where-Object { $_ } | Select-Object -Unique)
    Set-ItemProperty -LiteralPath $InstanceKey -Name "CompatibleIDs" -Type MultiString -Value $newCompatible

    return [pscustomobject]@{
        Key = $InstanceKey
        HardwareID = $hardwareId
        CompatibleIDs = $compatibleId
        NewCompatibleIDs = $newCompatible
        AliasAdded = $Alias
    }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
if (-not $CandidateDir) {
    $CandidateDir = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\qcsubsys8280"
}

$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$backupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("apply-qcsubsys8280-candidate-{0}.log" -f $stamp)
$backupDir = Join-Path $backupRoot ("qcsubsys8280-candidate-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Log "Applying official Surface Pro 9 5G qcsubsys8280 candidate."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "CandidateDir: $CandidateDir"
Write-Log "BackupDir: $backupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$candidateFull = (Resolve-Path -LiteralPath $CandidateDir).Path
$inf = Join-Path $candidateFull "qcsubsys8280.inf"
$cat = Join-Path $candidateFull "qcsubsys8280.cat"
$sys = Join-Path $candidateFull "qcsubsys8280.sys"
foreach ($path in @($inf, $cat, $sys)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Candidate file missing: $path"
    }
}

Assert-Signature -Path $cat -RequiredSubjectFragment "Microsoft Windows Hardware Compatibility Publisher"
Assert-Signature -Path $sys -RequiredSubjectFragment "QUALCOMM"

Copy-Item -LiteralPath $inf,$cat,$sys -Destination $backupDir -Force
Get-FileHash -Algorithm SHA256 -LiteralPath $inf,$cat,$sys |
    ConvertTo-Json -Depth 3 |
    Out-File -LiteralPath (Join-Path $backupDir "candidate-hashes.json") -Encoding UTF8

$dismBefore = Join-Path $backupDir "dism-drivers-before.txt"
Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Get-Drivers", "/Format:Table") -IgnoreExitCode |
    Out-File -LiteralPath $dismBefore -Encoding UTF8

Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Add-Driver", "/Driver:$inf")

$systemHivePath = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCSUBSYS8280_SYSTEM_$PID"
$hiveLoaded = $false
$enumBackup = @()

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHivePath)
    $hiveLoaded = $true

    $base = "Registry::HKEY_LOCAL_MACHINE\$hiveName"
    $targetIds = @("QCOM2522", "QCOM0522")
    foreach ($controlSet in Get-ChildItem -LiteralPath $base -ErrorAction Stop | Where-Object { $_.PSChildName -match "^ControlSet\d{3}$" }) {
        foreach ($id in $targetIds) {
            $devRoot = Join-Path $controlSet.PSPath "Enum\ACPI\$id"
            if (-not (Test-Path -LiteralPath $devRoot)) {
                Write-Log "No ACPI\$id root under $($controlSet.PSChildName)."
                continue
            }
            foreach ($instance in Get-ChildItem -LiteralPath $devRoot -ErrorAction Stop) {
                $enumBackup += Add-CompatibleId -InstanceKey $instance.PSPath -Alias "ACPI\QCOM0620"
                Write-Log "Added compatible alias ACPI\QCOM0620 to $($instance.PSPath)."
            }
        }
    }

    if ($enumBackup.Count -eq 0) {
        throw "No QCOM2522/QCOM0522 ACPI enum instance found. Boot Phase6 UEFI once, then retry from Mass Storage."
    }

    $enumBackup | ConvertTo-Json -Depth 8 |
        Out-File -LiteralPath (Join-Path $backupDir "enum-backup.json") -Encoding UTF8
} finally {
    if ($hiveLoaded) {
        Unload-HiveWithRetry -HiveName $hiveName | Out-Null
    }
}

$dismAfter = Join-Path $backupDir "dism-drivers-after.txt"
Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Get-Drivers", "/Format:Table") -IgnoreExitCode |
    Out-File -LiteralPath $dismAfter -Encoding UTF8

$manifest = [pscustomobject]@{
    WindowsDrive = $WindowsDrive
    Root = $root
    CandidateDir = $candidateFull
    BackupDir = $backupDir
    Alias = "ACPI\QCOM0620"
    SourceIds = @("QCOM2522", "QCOM0522")
    CreatedAt = (Get-Date).ToString("s")
    RollbackCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$projectRoot\tools\Rollback-Qcsubsys8280Candidate-Admin.ps1`" -WindowsDrive $WindowsDrive -BackupDir `"$backupDir`""
}
$manifest | ConvertTo-Json -Depth 5 |
    Out-File -LiteralPath (Join-Path $backupDir "manifest.json") -Encoding UTF8

Write-Log "qcsubsys8280 candidate apply completed."
Write-Log "Rollback command: $($manifest.RollbackCommand)"
Write-Host "qcsubsys8280 candidate applied."
Write-Host "Backup: $backupDir"
Write-Host "Log: $script:LogPath"
Write-Host "Next: boot Phase6 UEFI, then run AudioDependencyState and QcsubsysCiDeep diagnostics."
