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

function Get-OfflineControlSetName {
    param([string]$HiveName)

    $selectKey = "Registry::HKEY_LOCAL_MACHINE\$HiveName\Select"
    $current = (Get-ItemProperty -LiteralPath $selectKey -Name Current).Current
    return ("ControlSet{0:D3}" -f [int]$current)
}

function Convert-DwordForReg {
    param([object]$Value)

    if ($null -eq $Value) {
        return "0"
    }

    $int64 = [int64]$Value
    if ($int64 -lt 0) {
        $int64 = $int64 + 4294967296
    }
    return ("0x{0:X8}" -f $int64)
}

function Restore-RegValue {
    param(
        [string]$HiveName,
        [string]$ControlSet,
        [pscustomobject]$Entry
    )

    $regPath = "HKLM\$HiveName\$ControlSet\$($Entry.RelativePath)"
    if (-not $Entry.Existed) {
        Invoke-Captured -FilePath reg.exe -Arguments @("delete", $regPath, "/v", $Entry.Name, "/f") -IgnoreExitCode | Out-Null
        Write-Log ("Deleted {0}\{1} if present" -f $Entry.RelativePath, $Entry.Name)
        return
    }

    $value = [string]$Entry.Value
    if ($Entry.Type -eq "REG_DWORD") {
        $value = Convert-DwordForReg -Value $Entry.Value
    }

    Invoke-Captured -FilePath reg.exe -Arguments @("add", $regPath, "/v", $Entry.Name, "/t", $Entry.Type, "/d", $value, "/f") | Out-Null
    Write-Log ("Restored {0}\{1} ({2}) = {3}" -f $Entry.RelativePath, $Entry.Name, $Entry.Type, $value)
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("rollback-qcpil8280-full-extension-registry-{0}.log" -f $stamp)

if (-not (Test-Path -LiteralPath $BackupDir)) {
    throw "BackupDir not found: $BackupDir"
}
$backupJson = Join-Path $BackupDir "registry-values-backup.json"
if (-not (Test-Path -LiteralPath $backupJson)) {
    throw "Registry backup not found: $backupJson"
}

Write-Log "Rolling back qcpil8280 full extension registry experiment."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "BackupDir: $BackupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCPIL_FULL_EXT_ROLLBACK_SYSTEM_$PID"
$loaded = $false

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $controlSet = Get-OfflineControlSetName -HiveName $hiveName
    $entries = @(Get-Content -LiteralPath $backupJson -Raw | ConvertFrom-Json)
    foreach ($entry in $entries) {
        Restore-RegValue -HiveName $hiveName -ControlSet $controlSet -Entry $entry
    }

    Write-Log "qcpil8280 full extension registry rollback completed."
    Write-Host "qcpil8280 full extension registry rollback completed."
    Write-Host "Log: $script:LogPath"
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}
