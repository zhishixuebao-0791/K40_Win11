param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [switch]$RemoveDriverPackage,
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
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage drive letter, normally D:."
        }
    }

    $root = "${normalized}:\"
    $configDir = Join-Path $root "Windows\System32\Config"
    if (-not (Test-Path -LiteralPath $configDir)) {
        throw "Offline Config directory not found: $configDir"
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
            return $true
        }
        Write-Log "Hive unload attempt $attempt failed with exit code $($script:LASTNATIVEEXITCODE)."
    }

    Write-Log "WARNING: HKLM\$HiveName is still loaded. Close PowerShell windows and run Cleanup-OrphanAliothHives-Admin.ps1."
    return $false
}

function Restore-EnumValue {
    param(
        [string]$Key,
        [object]$BackupEntry
    )

    if (-not (Test-Path -LiteralPath $Key)) {
        Write-Log "Enum key missing during rollback: $Key"
        return
    }

    if ($null -eq $BackupEntry.CompatibleIDs -or @($BackupEntry.CompatibleIDs).Count -eq 0) {
        Remove-ItemProperty -LiteralPath $Key -Name "CompatibleIDs" -ErrorAction SilentlyContinue
        Write-Log "Removed CompatibleIDs from $Key"
    } else {
        Set-ItemProperty -LiteralPath $Key -Name "CompatibleIDs" -Type MultiString -Value @($BackupEntry.CompatibleIDs)
        Write-Log "Restored CompatibleIDs on $Key"
    }
}

Assert-Administrator

if (-not (Test-Path -LiteralPath $BackupDir)) {
    throw "BackupDir not found: $BackupDir"
}

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$script:LogPath = Join-Path $logDir ("rollback-qcsubsys8280-candidate-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Rolling back qcsubsys8280 candidate alias."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "BackupDir: $BackupDir"

$enumBackupPath = Join-Path $BackupDir "enum-backup.json"
if (-not (Test-Path -LiteralPath $enumBackupPath)) {
    throw "enum-backup.json not found: $enumBackupPath"
}

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHivePath = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCSUBSYS8280_ROLLBACK_SYSTEM_$PID"
$hiveLoaded = $false

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHivePath)
    $hiveLoaded = $true

    $backupEntries = @(Get-Content -LiteralPath $enumBackupPath -Raw | ConvertFrom-Json)
    foreach ($entry in $backupEntries) {
        $relative = ([string]$entry.Key) -replace "^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\ALIOTH_QCSUBSYS8280_SYSTEM_\d+", ""
        $relative = $relative -replace "^Registry::HKEY_LOCAL_MACHINE\\ALIOTH_QCSUBSYS8280_SYSTEM_\d+", ""
        $relative = $relative.TrimStart('\')
        if (-not $relative) {
            Write-Log "Could not derive relative key for backup entry: $($entry.Key)"
            continue
        }
        $targetKey = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$relative"
        Restore-EnumValue -Key $targetKey -BackupEntry $entry
    }
} finally {
    if ($hiveLoaded) {
        Unload-HiveWithRetry -HiveName $hiveName | Out-Null
    }
}

if ($RemoveDriverPackage) {
    Write-Log "RemoveDriverPackage requested. Attempting best-effort DISM removal."
    $drivers = Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Get-Drivers", "/Format:List") -IgnoreExitCode
    $published = $null
    for ($i = 0; $i -lt $drivers.Count; $i++) {
        if ($drivers[$i] -match "qcsubsys8280\.inf") {
            for ($j = $i; $j -ge [Math]::Max(0, $i - 8); $j--) {
                if ($drivers[$j] -match "(oem\d+\.inf)") {
                    $published = $Matches[1]
                    break
                }
            }
            if ($published) { break }
        }
    }
    if ($published) {
        Invoke-Captured -FilePath dism.exe -Arguments @("/Image:$root", "/Remove-Driver", "/Driver:$published") -IgnoreExitCode | Out-Null
        Write-Log "Attempted removal of published package: $published"
    } else {
        Write-Log "Could not locate published qcsubsys8280 package name; leaving DriverStore package installed."
    }
}

Write-Log "qcsubsys8280 candidate rollback completed."
Write-Host "qcsubsys8280 candidate alias rollback completed."
Write-Host "Log: $script:LogPath"
