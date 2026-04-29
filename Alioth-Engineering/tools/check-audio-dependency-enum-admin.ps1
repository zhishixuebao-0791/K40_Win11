param(
    [string]$WindowsDrive = "D"
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

function Invoke-Reg {
    param([string[]]$Arguments)

    Write-Log ("reg.exe " + ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & reg.exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    if ($output) {
        $output | ForEach-Object { Write-Log ([string]$_) }
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

Assert-Administrator

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-dependency-enum-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

$drive = $WindowsDrive.TrimEnd(':', '\')
$systemHive = "${drive}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) {
    throw "Offline SYSTEM hive not found or not accessible: $systemHive"
}

$hiveName = "ALIOTH_DEP_CHECK_$PID"
$hiveReg = "HKLM\$hiveName"
$enumRoot = "$hiveReg\ControlSet001\Enum\ACPI"

$targets = @(
    [pscustomobject]@{ Name = "PILC"; Native = "QCOM051B"; Driver = "QCOM251B"; Role = "ADSP dependency, already observed present" },
    [pscustomobject]@{ Name = "RPEN"; Native = "QCOM0533"; Driver = "QCOM2533"; Role = "ADSP/GLNK dependency, already observed present" },
    [pscustomobject]@{ Name = "GLNK"; Native = "QCOM058D"; Driver = "QCOM258D"; Role = "ARPC/SSDD/IPC0 dependency" },
    [pscustomobject]@{ Name = "IPC0"; Native = "QCOM050E"; Driver = "QCOM250E"; Role = "ADSP dependency" },
    [pscustomobject]@{ Name = "MMU0"; Native = "QCOM0509"; Driver = "QCOM2509"; Role = "ARPC dependency" },
    [pscustomobject]@{ Name = "SCM0"; Native = "QCOM050B"; Driver = "QCOM250B"; Role = "ARPC dependency" },
    [pscustomobject]@{ Name = "PDSR"; Native = "QCOM057C"; Driver = "QCOM257C"; Role = "SSDD dependency" },
    [pscustomobject]@{ Name = "TFTP"; Native = "QCOM058B"; Driver = "QCOM258B"; Role = "SSDD dependency" },
    [pscustomobject]@{ Name = "SSDD"; Native = "QCOM0522"; Driver = "QCOM2522"; Role = "ADSP dependency" },
    [pscustomobject]@{ Name = "QSM"; Native = "QCOM0520"; Driver = "QCOM2520"; Role = "Service manager sibling; useful subsystem signal" },
    [pscustomobject]@{ Name = "ARPC"; Native = "QCOM0560"; Driver = "QCOM2560"; Role = "ADSP dependency and FastRPC root" },
    [pscustomobject]@{ Name = "ADSP"; Native = "QCOM051D"; Driver = "QCOM251D"; Role = "Target audio DSP root" }
)

Write-Log "Checking Alioth audio dependency enumeration in $systemHive"
$load = Invoke-Reg -Arguments @("load", $hiveReg, $systemHive)
if ($load.ExitCode -ne 0) {
    throw "Failed to load offline SYSTEM hive. Close other PowerShell/Regedit windows and run cleanup-alioth-reg-hives-admin.ps1 first."
}

try {
    $rows = foreach ($target in $targets) {
        $native = Invoke-Reg -Arguments @("query", $enumRoot, "/f", $target.Native, "/s")
        $driver = Invoke-Reg -Arguments @("query", $enumRoot, "/f", $target.Driver, "/s")
        [pscustomobject]@{
            Name = $target.Name
            NativeId = $target.Native
            NativeFound = ($native.ExitCode -eq 0)
            DriverAlias = $target.Driver
            DriverAliasFound = ($driver.ExitCode -eq 0)
            Role = $target.Role
        }
    }

    "" | Add-Content -Path $script:LogPath -Encoding UTF8
    "==== Summary ====" | Add-Content -Path $script:LogPath -Encoding UTF8
    $rows | Format-Table -AutoSize | Out-String -Width 4096 | Add-Content -Path $script:LogPath -Encoding UTF8
    $rows | Format-Table -AutoSize
}
finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 1
    Invoke-Reg -Arguments @("unload", $hiveReg) | Out-Null
}

Write-Log "Wrote dependency enum log: $script:LogPath"
