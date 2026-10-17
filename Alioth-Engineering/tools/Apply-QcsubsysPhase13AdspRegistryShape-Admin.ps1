param(
    [string]$WindowsDrive = "E",
    [switch]$IncludeChildren,
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

function Get-RegistryValueBackup {
    param(
        [string]$HiveRoot,
        [string]$RelativePath,
        [string]$Name,
        [string]$PropertyType
    )

    $path = Join-Path $HiveRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{
            RelativePath = $RelativePath
            Name = $Name
            Existed = $false
            Value = $null
            PropertyType = $PropertyType
        }
    }

    $key = Get-Item -LiteralPath $path
    $property = Get-ItemProperty -LiteralPath $path -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $property) {
        return [pscustomobject]@{
            RelativePath = $RelativePath
            Name = $Name
            Existed = $false
            Value = $null
            PropertyType = $PropertyType
        }
    }

    return [pscustomobject]@{
        RelativePath = $RelativePath
        Name = $Name
        Existed = $true
        Value = $property.$Name
        PropertyType = $key.GetValueKind($Name).ToString()
    }
}

function Set-RegistryValue {
    param(
        [string]$HiveRoot,
        [pscustomobject]$Entry
    )

    $path = Join-Path $HiveRoot $Entry.RelativePath
    New-Item -Force -Path $path | Out-Null
    New-ItemProperty -LiteralPath $path -Name $Entry.Name -PropertyType $Entry.PropertyType -Value $Entry.Value -Force | Out-Null
    $valueText = if ($Entry.Value -is [array]) { $Entry.Value -join ", " } else { [string]$Entry.Value }
    Write-Log ("Set {0}\{1} ({2}) = {3}" -f $Entry.RelativePath, $Entry.Name, $Entry.PropertyType, $valueText)
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$backupRoot = Join-Path $projectRoot "Alioth-Engineering\backups"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogPath = Join-Path $logDir ("apply-qcsubsys-phase13-adsp-registry-shape-{0}.log" -f $stamp)
$backupDir = Join-Path $backupRoot ("qcsubsys-phase13-adsp-registry-shape-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Log "Applying qcsubsys Phase13 ADSP registry shape experiment."
Write-Log "WindowsDrive: $WindowsDrive"
Write-Log "IncludeChildren: $IncludeChildren"
Write-Log "BackupDir: $backupDir"

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $root "Windows\System32\Config\SYSTEM"
$hiveName = "ALIOTH_QCSUBSYS_PHASE13_SYSTEM_$PID"
$loaded = $false

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $controlSet = Get-OfflineControlSetName -HiveName $hiveName
    $hiveRoot = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$controlSet"
    $deviceRelative = "Enum\ACPI\QCOM061B\2&daba3ff&0"
    $devicePath = Join-Path $hiveRoot $deviceRelative
    if (-not (Test-Path -LiteralPath $devicePath)) {
        throw "QCOM061B ADSP device key not found: $devicePath"
    }

    $audioPdGuid = "{0A35A787-A69F-4A90-8B78-0710BA7BB82C}"
    $adspRpec = "{99CA9C16-4E1E-4970-B49E-2CA56753588B}"
    $pilTz = "{E2EB84C1-4068-4994-A48F-F3AC0D38DC29}"
    $fastRpc = "{E022FF1A-C06C-42D8-94FE-90D876FC0B75}"
    $glink = "{F9D15453-8335-434c-AA72-FCD925F135F3}"

    $values = @(
        [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\PDInfo"; Name = "NumPDs"; PropertyType = "DWord"; Value = 1 },
        [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\PDInfo\0"; Name = "PDName"; PropertyType = "String"; Value = "msm/adsp/audio_pd" },
        [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\PDInfo\0"; Name = "GUID"; PropertyType = "String"; Value = $audioPdGuid },
        [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\0\ADSP"; Name = "RPEC"; PropertyType = "MultiString"; Value = @($adspRpec) },
        [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\0\ADSP"; Name = "Interfaces"; PropertyType = "MultiString"; Value = @($pilTz, $fastRpc, $glink) },
        [pscustomobject]@{ RelativePath = "$deviceRelative\0\ADSP"; Name = "RPEC"; PropertyType = "MultiString"; Value = @($adspRpec) },
        [pscustomobject]@{ RelativePath = "$deviceRelative\0\ADSP"; Name = "Interfaces"; PropertyType = "MultiString"; Value = @($pilTz, $fastRpc, $glink) }
    )

    if ($IncludeChildren) {
        foreach ($profile in @("Desktop", "Mobile")) {
            $values += [pscustomobject]@{ RelativePath = "$deviceRelative\Device Parameters\$profile"; Name = "NumChildren"; PropertyType = "DWord"; Value = 2 }
            for ($index = 0; $index -lt 2; $index++) {
                $childPath = "$deviceRelative\Device Parameters\$profile\$index"
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "_HID"; PropertyType = "String"; Value = "QCOM2510" }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "_UID"; PropertyType = "DWord"; Value = $index }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "_ADR"; PropertyType = "DWord"; Value = $index }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "DeviceType"; PropertyType = "DWord"; Value = 0x0000001D }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "SupriseRemoval"; PropertyType = "DWord"; Value = 1 }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "ChildRemoval"; PropertyType = "DWord"; Value = 1 }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "FriendlyName"; PropertyType = "String"; Value = "Slimbus Device $index" }
                $values += [pscustomobject]@{ RelativePath = $childPath; Name = "SurpriseRemovePD"; PropertyType = "String"; Value = $audioPdGuid }
            }
        }
    }

    $backup = foreach ($entry in $values) {
        Get-RegistryValueBackup -HiveRoot $hiveRoot -RelativePath $entry.RelativePath -Name $entry.Name -PropertyType $entry.PropertyType
    }
    $backup | ConvertTo-Json -Depth 6 | Out-File -LiteralPath (Join-Path $backupDir "registry-values-backup.json") -Encoding UTF8

    foreach ($entry in $values) {
        Set-RegistryValue -HiveRoot $hiveRoot -Entry $entry
    }

    $manifest = [pscustomobject]@{
        WindowsDrive = $WindowsDrive
        Root = $root
        ControlSet = $controlSet
        DeviceRelativePath = $deviceRelative
        IncludeChildren = [bool]$IncludeChildren
        BackupDir = $backupDir
        CreatedAt = (Get-Date).ToString("s")
        RollbackCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$projectRoot\Alioth-Engineering\tools\Rollback-QcsubsysPhase13AdspRegistryShape-Admin.ps1`" -WindowsDrive $WindowsDrive -BackupDir `"$backupDir`""
    }
    $manifest | ConvertTo-Json -Depth 6 | Out-File -LiteralPath (Join-Path $backupDir "manifest.json") -Encoding UTF8

    Write-Log "qcsubsys Phase13 ADSP registry shape experiment applied."
    Write-Log "Rollback command: $($manifest.RollbackCommand)"
    Write-Host "qcsubsys Phase13 ADSP registry shape experiment applied."
    Write-Host "Backup: $backupDir"
    Write-Host "Log: $script:LogPath"
} finally {
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}
