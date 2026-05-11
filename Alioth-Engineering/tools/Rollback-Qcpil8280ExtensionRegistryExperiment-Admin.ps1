param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
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
    $systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
    if (-not (Test-Path -LiteralPath $systemHive)) {
        throw "Offline SYSTEM hive not found: $systemHive"
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
    throw "Failed to unload HKLM\$HiveName. Close PowerShell windows and retry."
}

function Restore-DwordValue {
    param(
        [string]$HiveRoot,
        [object]$Entry
    )

    $path = Join-Path $HiveRoot $Entry.RelativePath
    if ($Entry.Existed) {
        New-Item -Path $path -Force | Out-Null
        New-ItemProperty -LiteralPath $path -Name $Entry.Name -PropertyType DWord -Value ([int]$Entry.Value) -Force | Out-Null
        Write-Log ("Restored {0}\{1}=0x{2:X8}" -f $Entry.RelativePath, $Entry.Name, [int]$Entry.Value)
    } elseif (Test-Path -LiteralPath $path) {
        Remove-ItemProperty -LiteralPath $path -Name $Entry.Name -ErrorAction SilentlyContinue
        Write-Log ("Removed added value {0}\{1}" -f $Entry.RelativePath, $Entry.Name)
    }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("rollback-qcpil8280-extension-registry-{0}.log" -f $stamp)

$manifestPath = Join-Path $BackupDir "manifest.json"
$backupPath = Join-Path $BackupDir "registry-values-backup.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}
if (-not (Test-Path -LiteralPath $backupPath)) {
    throw "Registry backup not found: $backupPath"
}

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$backup = @(Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json)
$hiveName = "ALIOTH_QCPIL_EXT_ROLLBACK_SYSTEM_$PID"
$loaded = $false

try {
    Write-Log "Rolling back qcpil8280 extension registry-only experiment."
    Write-Log "WindowsDrive: $WindowsDrive"
    Write-Log "BackupDir: $BackupDir"
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$($manifest.ControlSet)"
    foreach ($entry in $backup) {
        Restore-DwordValue -HiveRoot $hiveRoot -Entry $entry
    }

    Write-Log "qcpil8280 extension registry-only experiment rollback completed."
    Write-Host "qcpil8280 extension registry-only experiment rollback completed."
    Write-Host "Log: $script:LogPath"
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}
