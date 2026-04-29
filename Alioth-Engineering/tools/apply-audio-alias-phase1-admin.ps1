param(
    [string]$WindowsDrive = "D",
    [string]$ExperimentRoot,
    [switch]$SkipDism
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($script:LogPath) {
        $line | Add-Content -Path $script:LogPath -Encoding UTF8
    }
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    if ($output) {
        $output | ForEach-Object { Write-Log ([string]$_) }
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code $exitCode`: $FilePath"
    }

    return $exitCode
}

function Get-WindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows"))) {
        throw "Windows directory not found on drive $root"
    }
    return $root
}

function Add-CompatibleId {
    param(
        [string]$ControlSetPath,
        [string]$AcpiId,
        [string]$AliasId,
        [System.Collections.ArrayList]$Changes
    )

    $enumRoot = Join-Path $ControlSetPath ("Enum\ACPI\" + ($AcpiId -replace '^ACPI\\', ''))
    if (-not (Test-Path -LiteralPath $enumRoot)) {
        Write-Log "Device key not found, skipping alias: $enumRoot"
        return
    }

    $instances = @(Get-ChildItem -LiteralPath $enumRoot -ErrorAction SilentlyContinue)
    if (-not $instances) {
        Write-Log "No instances found under: $enumRoot"
        return
    }

    foreach ($instance in $instances) {
        $props = Get-ItemProperty -LiteralPath $instance.PSPath
        $oldHardwareId = @($props.HardwareID)
        $oldCompatibleIds = @($props.CompatibleIDs)

        $newCompatibleIds = @($oldCompatibleIds | Where-Object { $_ })
        if ($newCompatibleIds -notcontains $AliasId) {
            $newCompatibleIds += $AliasId
        }

        if ($oldCompatibleIds.Count -gt 0) {
            Set-ItemProperty -LiteralPath $instance.PSPath -Name "CompatibleIDs" -Value ([string[]]$newCompatibleIds)
        } else {
            New-ItemProperty -LiteralPath $instance.PSPath -Name "CompatibleIDs" -PropertyType MultiString -Value ([string[]]$newCompatibleIds) -Force | Out-Null
        }

        [void]$Changes.Add([pscustomobject]@{
            ControlSet = Split-Path -Leaf $ControlSetPath
            DeviceKey = $instance.Name
            NativeId = $AcpiId
            AliasId = $AliasId
            OldHardwareID = $oldHardwareId
            OldCompatibleIDs = $oldCompatibleIds
            NewCompatibleIDs = $newCompatibleIds
        })

        Write-Log "Added compatible alias $AliasId to $($instance.Name)"
    }
}

function Set-ServiceStartIfPresent {
    param(
        [string]$ControlSetPath,
        [string]$ServiceName,
        [int]$Start
    )

    $servicePath = Join-Path $ControlSetPath ("Services\" + $ServiceName)
    if (Test-Path -LiteralPath $servicePath) {
        Set-ItemProperty -LiteralPath $servicePath -Name "Start" -Value $Start -Type DWord
        Write-Log "Set offline service $ServiceName Start=$Start in $(Split-Path -Leaf $ControlSetPath)"
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator
if (-not $ExperimentRoot) {
    $ExperimentRoot = Join-Path $repoRoot "Alioth-Engineering\experiments\audio-alias-phase1"
}

$packageRoot = Join-Path $ExperimentRoot "signed-driver-package"
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-alias-phase1-apply-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying Alioth audio alias phase 1."

if (-not (Test-Path -LiteralPath $packageRoot)) {
    $prepare = Join-Path $PSScriptRoot "prepare-audio-alias-phase1.ps1"
    Invoke-Native -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $prepare)
}

if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "Phase-1 package not found after prepare: $packageRoot"
}

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $windowsRoot "Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) {
    throw "Offline SYSTEM hive not found or not accessible: $systemHive"
}

if (-not $SkipDism) {
    Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$windowsRoot", "/Add-Driver", "/Driver:$packageRoot", "/Recurse")
} else {
    Write-Log "SkipDism was set; not adding driver packages."
}

$hiveName = "ALIOTH_AUDIO_ALIAS_SYSTEM_$PID"
$hiveReg = "HKLM\$hiveName"
$hivePs = "HKLM:\$hiveName"
$changes = New-Object System.Collections.ArrayList
$aliases = @(
    [pscustomobject]@{ NativeId = "ACPI\QCOM05D2"; AliasId = "ACPI\QCOM25D2" },
    [pscustomobject]@{ NativeId = "ACPI\QCOM0560"; AliasId = "ACPI\QCOM2560" },
    [pscustomobject]@{ NativeId = "ACPI\QCOM058A"; AliasId = "ACPI\QCOM258A" }
)

Invoke-Native -FilePath "reg.exe" -Arguments @("load", $hiveReg, $systemHive)
try {
    $controlSets = @(Get-ChildItem -LiteralPath $hivePs |
        Where-Object { $_.PSChildName -match '^ControlSet\d{3}$' } |
        Sort-Object PSChildName)

    if (-not $controlSets) {
        throw "No ControlSetXXX keys found in offline SYSTEM hive."
    }

    foreach ($controlSet in $controlSets) {
        foreach ($alias in $aliases) {
            Add-CompatibleId -ControlSetPath $controlSet.PSPath -AcpiId $alias.NativeId -AliasId $alias.AliasId -Changes $changes
        }

        Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "AudioService" -Start 2
        Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "qcadsprpc" -Start 3
        Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "qcadsprpcd" -Start 3
    }

    $backupPath = Join-Path $logRoot ("audio-alias-phase1-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
    [ordered]@{
        Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        WindowsDrive = $WindowsDrive
        WindowsRoot = $windowsRoot
        PackageRoot = $packageRoot
        Changes = $changes
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $backupPath -Encoding UTF8
    Write-Log "Wrote registry backup: $backupPath"
}
finally {
    Invoke-Native -FilePath "reg.exe" -Arguments @("unload", $hiveReg) -AllowFailure
}

Write-Log "Phase-1 alias apply completed. Reboot/boot Mu-alioth and collect audio root trace after testing."
