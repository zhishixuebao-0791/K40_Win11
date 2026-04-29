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

function Find-AcpiDeviceInstances {
    param(
        [string]$ControlSetPath,
        [string]$NativeMatch
    )

    $enumRoot = Join-Path $ControlSetPath "Enum\ACPI"
    if (-not (Test-Path -LiteralPath $enumRoot)) {
        return @()
    }

    $matches = New-Object System.Collections.ArrayList
    $keys = @(Get-ChildItem -LiteralPath $enumRoot -Recurse -ErrorAction SilentlyContinue)
    foreach ($key in $keys) {
        $props = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $props) {
            continue
        }

        $hardwareIds = @($props.HardwareID)
        if ($hardwareIds.Count -eq 0) {
            continue
        }

        foreach ($hardwareId in $hardwareIds) {
            if ([string]$hardwareId -like "*$NativeMatch*") {
                [void]$matches.Add($key)
                break
            }
        }
    }

    return @($matches)
}

function Add-CompatibleId {
    param(
        [string]$ControlSetPath,
        [string]$NativeMatch,
        [string]$AliasId,
        [System.Collections.ArrayList]$Changes
    )

    $instances = @(Find-AcpiDeviceInstances -ControlSetPath $ControlSetPath -NativeMatch $NativeMatch)
    if (-not $instances) {
        Write-Log "Device instance not found, skipping alias ${AliasId} for native match ${NativeMatch}"
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
            NativeMatch = $NativeMatch
            AliasId = $AliasId
            OldHardwareID = $oldHardwareId
            OldCompatibleIDs = $oldCompatibleIds
            NewCompatibleIDs = $newCompatibleIds
        })

        Write-Log "Added compatible alias $AliasId to $($instance.Name)"
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator
if (-not $ExperimentRoot) {
    $ExperimentRoot = Join-Path $repoRoot "Alioth-Engineering\experiments\audio-deps-phase2a"
}

$packageRoot = Join-Path $ExperimentRoot "signed-driver-package"
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-deps-phase2a-apply-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying Alioth audio dependency phase 2a."

if (-not (Test-Path -LiteralPath $packageRoot)) {
    $prepare = Join-Path $PSScriptRoot "prepare-audio-deps-phase2a.ps1"
    Invoke-Native -FilePath "powershell.exe" -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $prepare)
}

if (-not (Test-Path -LiteralPath $packageRoot)) {
    throw "Phase-2a package not found after prepare: $packageRoot"
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

$hiveName = "ALIOTH_AUDIO_DEPS2A_SYSTEM_$PID"
$hiveReg = "HKLM\$hiveName"
$hivePs = "HKLM:\$hiveName"
$changes = New-Object System.Collections.ArrayList
$aliases = @(
    [pscustomobject]@{ NativeMatch = "QCOM051B"; AliasId = "ACPI\QCOM251B"; Name = "PILC" },
    [pscustomobject]@{ NativeMatch = "QCOM0533"; AliasId = "ACPI\QCOM2533"; Name = "RPEN" },
    [pscustomobject]@{ NativeMatch = "QCOM0509"; AliasId = "ACPI\VEN_QCOM&DEV_2509&REV_0002"; Name = "SMMU" },
    [pscustomobject]@{ NativeMatch = "QCOM050B"; AliasId = "ACPI\QCOM250B"; Name = "SCM" }
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
            Add-CompatibleId -ControlSetPath $controlSet.PSPath -NativeMatch $alias.NativeMatch -AliasId $alias.AliasId -Changes $changes
        }
    }

    $backupPath = Join-Path $logRoot ("audio-deps-phase2a-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
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
    [gc]::Collect()
    Start-Sleep -Milliseconds 300
    Invoke-Native -FilePath "reg.exe" -Arguments @("unload", $hiveReg) -AllowFailure
}

Write-Log "Phase-2a dependency alias apply completed. Boot Mu-alioth, then collect AudioRootTrace/AudioRootCause and run dependency enum again."
