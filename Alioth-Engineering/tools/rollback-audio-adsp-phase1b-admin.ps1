param(
    [string]$WindowsDrive = "D",
    [switch]$DisableService
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

    foreach ($instance in @(Get-ChildItem -LiteralPath $enumRoot -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $instance.PSPath
        $oldCompatibleIds = @($props.CompatibleIDs)
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

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-adsp-phase1b-rollback-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Rolling back Alioth audio ADSP phase 1b."

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$systemHive = Join-Path $windowsRoot "Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) {
    throw "Offline SYSTEM hive not found or not accessible: $systemHive"
}

$hiveName = "ALIOTH_AUDIO_ADSP_ROLLBACK_SYSTEM_$PID"
$hiveReg = "HKLM\$hiveName"
$hivePs = "HKLM:\$hiveName"

Invoke-Native -FilePath "reg.exe" -Arguments @("load", $hiveReg, $systemHive)
try {
    $controlSets = @(Get-ChildItem -LiteralPath $hivePs |
        Where-Object { $_.PSChildName -match '^ControlSet\d{3}$' } |
        Sort-Object PSChildName)

    foreach ($controlSet in $controlSets) {
        Remove-CompatibleId -ControlSetPath $controlSet.PSPath -AcpiId "ACPI\QCOM051D" -AliasId "ACPI\QCOM251D"
        if ($DisableService) {
            $servicePath = Join-Path $controlSet.PSPath "Services\qcsubsys"
            if (Test-Path -LiteralPath $servicePath) {
                Set-ItemProperty -LiteralPath $servicePath -Name "Start" -Value 4 -Type DWord
                Write-Log "Set offline qcsubsys Start=4 in $(Split-Path -Leaf $controlSet.PSPath)"
            }
        }
    }
}
finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 1
    Invoke-Native -FilePath "reg.exe" -Arguments @("unload", $hiveReg) -AllowFailure
}

Write-Log "Phase-1b ADSP alias rollback completed."
