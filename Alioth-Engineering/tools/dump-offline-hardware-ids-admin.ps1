param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$LogRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-Drive([string]$Drive) {
    if ($Drive.Length -eq 1) {
        return "$Drive`:"
    }
    if ($Drive.Length -ge 2 -and $Drive[1] -eq ':') {
        return $Drive.Substring(0, 2)
    }
    throw "Invalid drive value: $Drive"
}

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Invoke-LoggedNative([string]$FilePath, [string[]]$Arguments) {
    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $output = & $FilePath @Arguments 2>&1
    if ($output) {
        $output | Tee-Object -FilePath $script:LogFile -Append | Out-Host
    }
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $FilePath)
    }
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $LogRoot "offline-hardware-ids-$timestamp.log"

$offlineSystemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$tempSystemHiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM"

Write-Log "Dumping offline hardware IDs from $WindowsDrive"
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $tempSystemHiveName, $offlineSystemHive)
try {
    $roots = @(
        "$tempSystemHiveName\ControlSet001\Enum\ACPI",
        "$tempSystemHiveName\ControlSet001\Enum\PCI",
        "$tempSystemHiveName\ControlSet001\Enum\USB",
        "$tempSystemHiveName\ControlSet001\Enum\USBDEVICE",
        "$tempSystemHiveName\ControlSet001\Enum\ROOT"
    )

    foreach ($root in $roots) {
        if (-not (Test-Path "Registry::$root")) {
            continue
        }

        Write-Log "Enumerating $root"
        Get-ChildItem -Path "Registry::$root" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $keyName = $_.Name
            if ($keyName -match 'QCOM|USB|UCSI|XHCI|URS|HID_UCS|TYPEC|TCPC|PMIC') {
                Write-Log "Key: $keyName"
                try {
                    $props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                    foreach ($prop in $props.PSObject.Properties) {
                        if ($prop.Name -in @("HardwareID", "CompatibleIDs", "DeviceDesc", "Service", "Class", "ClassGUID", "Driver")) {
                            Write-Log ("  {0}: {1}" -f $prop.Name, ($prop.Value -join '; '))
                        }
                    }
                } catch {
                    Write-Log "  Failed to read properties: $($_.Exception.Message)"
                }
            }
        }
    }
} finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    try {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $tempSystemHiveName)
    } catch {
        Write-Log ("Non-fatal: failed to unload offline SYSTEM hive cleanly: {0}" -f $_.Exception.Message)
    }
}

Write-Log "Offline hardware ID dump completed."
