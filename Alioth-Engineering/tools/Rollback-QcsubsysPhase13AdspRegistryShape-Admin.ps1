param(
    [string]$WindowsDrive = "E",
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
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be E: or another removable/offline drive."
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

function Get-OfflineControlSetName {
    param([string]$HiveName)

    $selectKey = "Registry::HKEY_LOCAL_MACHINE\$HiveName\Select"
    $current = (Get-ItemProperty -LiteralPath $selectKey -Name Current).Current
    return ("ControlSet{0:D3}" -f [int]$current)
}

function Restore-RegistryValue {
    param(
        [string]$HiveRoot,
        [pscustomobject]$Entry
    )

    $path = Join-Path $HiveRoot $Entry.RelativePath
    if (-not $Entry.Existed) {
        if (Test-Path -LiteralPath $path) {
            Remove-ItemProperty -LiteralPath $path -Name $Entry.Name -ErrorAction SilentlyContinue
        }
        Write-Log ("Deleted {0}\{1} if present" -f $Entry.RelativePath, $Entry.Name)
        return
    }

    New-Item -Force -Path $path | Out-Null
    New-ItemProperty -LiteralPath $path -Name $Entry.Name -PropertyType $Entry.PropertyType -Value $Entry.Value -Force | Out-Null
    $valueText = if ($Entry.Value -is [array]) { $Entry.Value -join ", " } else { [string]$Entry.Value }
    Write-Log ("Restored {0}\{1} ({2}) = {3}" -f $Entry.RelativePath, $Entry.Name, $Entry.PropertyType, $valueText)
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("rollback-qcsubsys-phase13-adsp-registry-shape-{0}.log" -f $stamp)

if (-not (Test-Path -LiteralPath $BackupDir)) {
    throw "BackupDir not found: $BackupDir"
}
$backupJson = Join-Path $BackupDir "registry-values-backup.json"
if (-not (Test-Path -LiteralPath $backupJson)) {
    throw "Registry backup not found: $backupJson"
}

Write-Log "Rolling back qcsubsys Phase13 ADSP registry shape experiment."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "BackupDir: $BackupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCSUBSYS_PHASE13_ROLLBACK_SYSTEM_$PID"
$loaded = $false

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $controlSet = Get-OfflineControlSetName -HiveName $hiveName
    $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$controlSet"
    $entries = @(Get-Content -LiteralPath $backupJson -Raw | ConvertFrom-Json)
    foreach ($entry in $entries) {
        Restore-RegistryValue -HiveRoot $hiveRoot -Entry $entry
    }

    Write-Log "qcsubsys Phase13 ADSP registry shape rollback completed."
    Write-Host "qcsubsys Phase13 ADSP registry shape rollback completed."
    Write-Host "Log: $script:LogPath"
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}
