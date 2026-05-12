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
        Invoke-Captured -FilePath reg.exe -Arguments @("unload", "HKLM\$HiveName") -IgnoreExitCode | Out-Null
        if ($script:LASTNATIVEEXITCODE -eq 0) {
            Write-Log "Unloaded HKLM\$HiveName on attempt $attempt."
            return
        }
        Write-Log "Hive unload attempt $attempt failed with exit code $($script:LASTNATIVEEXITCODE)."
    }
    throw "Failed to unload HKLM\$HiveName. Close windows that may hold the offline hive and retry."
}

function Get-OfflineControlSetName {
    param([string]$HiveName)

    $selectKey = "Registry::HKEY_LOCAL_MACHINE\$HiveName\Select"
    $current = (Get-ItemProperty -LiteralPath $selectKey -Name Current).Current
    return ("ControlSet{0:D3}" -f [int]$current)
}

function Set-RegValue {
    param(
        [string]$HiveName,
        [string]$ControlSet,
        [string]$RelativePath,
        [string]$Name,
        [string]$Type,
        [string]$Value
    )

    $regPath = "HKLM\$HiveName\$ControlSet\$RelativePath"
    Invoke-Captured -FilePath reg.exe -Arguments @("add", $regPath, "/v", $Name, "/t", $Type, "/d", $Value, "/f") | Out-Null
}

function Assert-Signature {
    param([string]$Path)

    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "" }
    $issuer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Issuer } else { "" }
    Write-Log "Signature: $Path => $($sig.Status); Subject=$subject; Issuer=$issuer"
    if ($sig.Status -ne "Valid") {
        throw "Invalid signature for ${Path}: $($sig.Status)"
    }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
if (-not $CandidateDir) {
    $CandidateDir = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\qcpilext8280"
}

$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$backupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("apply-qcpilext8280-binding-{0}.log" -f $stamp)
$backupDir = Join-Path $backupRoot ("qcpilext8280-binding-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Log "Applying qcpilEXT8280 PILC extension binding."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "CandidateDir: $CandidateDir"
Write-Log "BackupDir: $backupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$candidateFull = (Resolve-Path -LiteralPath $CandidateDir).Path
if ($candidateFull -is [array]) {
    throw "CandidateDir resolved to multiple paths. Use the exact qcpilext8280 directory."
}

$infPath = Join-Path $candidateFull "qcpilEXT8280.inf"
$catPath = Join-Path $candidateFull "qcpilext8280.cat"
if (-not (Test-Path -LiteralPath $infPath)) {
    throw "Candidate INF missing: $infPath"
}
if (-not (Test-Path -LiteralPath $catPath)) {
    throw "Candidate CAT missing: $catPath"
}

Copy-Item -LiteralPath $candidateFull -Destination (Join-Path $backupDir "qcpilext8280") -Recurse -Force
Assert-Signature -Path $catPath

$driverStore = Join-Path $root "Windows\System32\DriverStore\FileRepository"
Get-ChildItem -LiteralPath $driverStore -Directory -Filter "qcpilext8280.inf_*" -ErrorAction SilentlyContinue |
    Select-Object FullName, LastWriteTime |
    Format-List |
    Out-File -LiteralPath (Join-Path $backupDir "qcpilext8280-driverstore-before.txt") -Encoding UTF8

Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Add-Driver", "/Driver:$infPath")

Get-ChildItem -LiteralPath $driverStore -Directory -Filter "qcpilext8280.inf_*" -ErrorAction SilentlyContinue |
    Select-Object FullName, LastWriteTime |
    Format-List |
    Out-File -LiteralPath (Join-Path $backupDir "qcpilext8280-driverstore-after.txt") -Encoding UTF8

$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCPILEXT8280_SYSTEM_$PID"
$loaded = $false
try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true
    $controlSet = Get-OfflineControlSetName -HiveName $hiveName

    $deviceRelative = "Enum\ACPI\QCOM06E0\2&daba3ff&0"
    $devicePath = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$controlSet\$deviceRelative"
    if (-not (Test-Path -LiteralPath $devicePath)) {
        throw "QCOM06E0 enum key not found: $devicePath"
    }

    reg.exe query "HKLM\$hiveName\$controlSet\$deviceRelative" /s 2>&1 |
        Out-File -LiteralPath (Join-Path $backupDir "qcom06e0-registry-before.txt") -Encoding UTF8

    $values = @(
        @{ RelativePath = "$deviceRelative\SubsystemLoad\VENUS"; Name = "MemoryAlignment"; Type = "REG_DWORD"; Value = "0x00000000" }
        @{ RelativePath = "$deviceRelative\SubsystemLoad\VENUS"; Name = "MemoryReservation"; Type = "REG_DWORD"; Value = "0x00500000" }
        @{ RelativePath = "$deviceRelative\SubsystemLoad\GFXSUC"; Name = "MemoryAlignment"; Type = "REG_DWORD"; Value = "0x00001000" }
        @{ RelativePath = "$deviceRelative\SubsystemLoad\GFXSUC"; Name = "MemoryReservation"; Type = "REG_DWORD"; Value = "0x00005000" }
        @{ RelativePath = "$deviceRelative\PilConfig"; Name = "HypProtectionEnabled"; Type = "REG_DWORD"; Value = "0x00000001" }
        @{ RelativePath = "$deviceRelative\PilConfig"; Name = "DoNotReturnMemoryToHLOS"; Type = "REG_DWORD"; Value = "0x00000001" }
        @{ RelativePath = "$deviceRelative\PGCM"; Name = "BaseAddress"; Type = "REG_DWORD"; Value = "0x86700000" }
        @{ RelativePath = "$deviceRelative\PGCM"; Name = "Size"; Type = "REG_DWORD"; Value = "0x07D00000" }
        @{ RelativePath = "$deviceRelative\IMEM"; Name = "BaseAddress"; Type = "REG_DWORD"; Value = "0x146BF000" }
        @{ RelativePath = "$deviceRelative\IMEM"; Name = "Offset"; Type = "REG_DWORD"; Value = "0x0000094C" }
    )

    foreach ($entry in $values) {
        Set-RegValue -HiveName $hiveName -ControlSet $controlSet -RelativePath $entry.RelativePath -Name $entry.Name -Type $entry.Type -Value $entry.Value
    }

    reg.exe query "HKLM\$hiveName\$controlSet\$deviceRelative" /s 2>&1 |
        Out-File -LiteralPath (Join-Path $backupDir "qcom06e0-registry-after.txt") -Encoding UTF8

    $manifest = [pscustomobject]@{
        WindowsDrive = $WindowsDrive
        Root = $root
        CandidateDir = $candidateFull
        InfPath = $infPath
        BackupDir = $backupDir
        CreatedAt = (Get-Date).ToString("s")
        Notes = "Installs qcpilEXT8280 and ensures qcpilEXT8280 PILC extension registry values on ACPI\\QCOM06E0."
    }
    $manifest | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $backupDir "manifest.json") -Encoding UTF8
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}

Write-Log "qcpilEXT8280 PILC extension binding completed."
Write-Host "qcpilEXT8280 binding applied."
Write-Host "Backup: $backupDir"
Write-Host "Log: $script:LogPath"
Write-Host "Next: boot Phase9A UEFI, then run Trace-AliothPilcStartFailureDeep.ps1 and AudioDependencyState."
