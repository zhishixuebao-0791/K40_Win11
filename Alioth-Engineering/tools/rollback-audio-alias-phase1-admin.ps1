param(
    [string]$WindowsDrive = "D",
    [switch]$DisableServices
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

function Remove-CompatibleId {
    param(
        [string]$ControlSetPath,
        [string]$AcpiId,
        [string]$AliasId
    )

    $enumRoot = Join-Path $ControlSetPath ("Enum\ACPI\" + ($AcpiId -replace '^ACPI\\', ''))
    if (-not (Test-Path -LiteralPath $enumRoot)) {
        Write-Log "Device key not found, skipping alias removal: $enumRoot"
        return
    }

    $instances = @(Get-ChildItem -LiteralPath $enumRoot -ErrorAction SilentlyContinue)
    foreach ($instance in $instances) {
        $props = Get-ItemProperty -LiteralPath $instance.PSPath
        $oldCompatibleIds = @($props.CompatibleIDs)
        if ($oldCompatibleIds.Count -eq 0) {
            continue
        }

        $newCompatibleIds = @($oldCompatibleIds | Where-Object { $_ -and ($_ -ne $AliasId) })
        if ($newCompatibleIds.Count -ne $oldCompatibleIds.Count) {
            if ($newCompatibleIds.Count -gt 0) {
                Set-ItemProperty -LiteralPath $instance.PSPath -Name "CompatibleIDs" -Value ([string[]]$newCompatibleIds)
            } else {
                Remove-ItemProperty -LiteralPath $instance.PSPath -Name "CompatibleIDs" -ErrorAction SilentlyContinue
            }
            Write-Log "Removed compatible alias $AliasId from $($instance.Name)"
        }
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
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-alias-phase1-rollback-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Rolling back Alioth audio alias phase 1."

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $windowsRoot "Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) {
    throw "Offline SYSTEM hive not found or not accessible: $systemHive"
}

$hiveName = "ALIOTH_AUDIO_ALIAS_ROLLBACK_SYSTEM_$PID"
$hiveReg = "HKLM\$hiveName"
$hivePs = "HKLM:\$hiveName"
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

    foreach ($controlSet in $controlSets) {
        foreach ($alias in $aliases) {
            Remove-CompatibleId -ControlSetPath $controlSet.PSPath -AcpiId $alias.NativeId -AliasId $alias.AliasId
        }

        if ($DisableServices) {
            Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "AudioService" -Start 4
            Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "qcadsprpc" -Start 4
            Set-ServiceStartIfPresent -ControlSetPath $controlSet.PSPath -ServiceName "qcadsprpcd" -Start 4
        }
    }
}
finally {
    Invoke-Native -FilePath "reg.exe" -Arguments @("unload", $hiveReg) -AllowFailure
}

Write-Log "Phase-1 alias rollback completed. DriverStore packages are left in place; aliases were removed."
