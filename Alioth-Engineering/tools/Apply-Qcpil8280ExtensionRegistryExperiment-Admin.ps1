param(
    [string]$WindowsDrive = "D",
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

function Get-RegistryValueBackup {
    param(
        [string]$HiveRoot,
        [string]$RelativePath,
        [string]$Name
    )

    $path = Join-Path $HiveRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            RelativePath = $RelativePath
            Name = $Name
            Existed = $false
            Value = $null
            PropertyType = "DWord"
        }
    }

    $property = Get-ItemProperty -LiteralPath $path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $property) {
        return [pscustomobject]@{
            RelativePath = $RelativePath
            Name = $Name
            Existed = $false
            Value = $null
            PropertyType = "DWord"
        }
    }

    return [pscustomobject]@{
        RelativePath = $RelativePath
        Name = $Name
        Existed = $true
        Value = $property.$Name
        PropertyType = "DWord"
    }
}

function Set-DwordValue {
    param(
        [string]$HiveRoot,
        [string]$RelativePath,
        [string]$Name,
        [int]$Value
    )

    $path = Join-Path $HiveRoot $RelativePath
    New-Item -Path $path -Force | Out-Null
    New-ItemProperty -LiteralPath $path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    Write-Log ("Set {0}\{1}=0x{2:X8}" -f $RelativePath, $Name, $Value)
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$backupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("apply-qcpil8280-extension-registry-{0}.log" -f $stamp)
$backupDir = Join-Path $backupRoot ("qcpil8280-extension-registry-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Log "Applying qcpil8280 extension registry-only experiment."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "BackupDir: $backupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCPIL_EXT_SYSTEM_$PID"
$loaded = $false

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $controlSet = Get-OfflineControlSetName -HiveName $hiveName
    $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$controlSet"
    $deviceRelative = "Enum\ACPI\QCOM06E0\2&daba3ff&0"
    $devicePath = Join-Path $hiveRoot $deviceRelative
    if (-not (Test-Path -LiteralPath $devicePath)) {
        throw "QCOM06E0 device key not found: $devicePath"
    }

    $values = @(
        [pscustomobject]@{ RelativePath = "$deviceRelative\SubsystemLoad\VENUS"; Name = "MemoryAlignment"; Value = 0x00000000 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\SubsystemLoad\VENUS"; Name = "MemoryReservation"; Value = 0x00500000 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\SubsystemLoad\GFXSUC"; Name = "MemoryAlignment"; Value = 0x00001000 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\PilConfig"; Name = "HypProtectionEnabled"; Value = 0x00000001 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\PilConfig"; Name = "DoNotReturnMemoryToHLOS"; Value = 0x00000001 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\PGCM"; Name = "BaseAddress"; Value = 0x86700000 }
        [pscustomobject]@{ RelativePath = "$deviceRelative\PGCM"; Name = "Size"; Value = 0x07D00000 }
    )

    $backup = foreach ($entry in $values) {
        Get-RegistryValueBackup -HiveRoot $hiveRoot -RelativePath $entry.RelativePath -Name $entry.Name
    }
    $backup | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $backupDir "registry-values-backup.json") -Encoding UTF8

    foreach ($entry in $values) {
        Set-DwordValue -HiveRoot $hiveRoot -RelativePath $entry.RelativePath -Name $entry.Name -Value $entry.Value
    }

    $manifest = [pscustomobject]@{
        WindowsDrive = $WindowsDrive
        Root = $root
        ControlSet = $controlSet
        DeviceRelativePath = $deviceRelative
        BackupDir = $backupDir
        CreatedAt = (Get-Date).ToString("s")
        RollbackCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$projectRoot\tools\Rollback-Qcpil8280ExtensionRegistryExperiment-Admin.ps1`" -WindowsDrive $WindowsDrive -BackupDir `"$backupDir`""
    }
    $manifest | ConvertTo-Json -Depth 5 | Out-File -LiteralPath (Join-Path $backupDir "manifest.json") -Encoding UTF8

    Write-Log "qcpil8280 extension registry-only experiment applied."
    Write-Log "Rollback command: $($manifest.RollbackCommand)"
    Write-Host "qcpil8280 extension registry-only experiment applied."
    Write-Host "Backup: $backupDir"
    Write-Host "Log: $script:LogPath"
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}
