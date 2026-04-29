param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$EspDrive,

    [string]$TemplatePath,

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
    if ([string]::IsNullOrWhiteSpace($Drive)) {
        return $null
    }
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

function Get-FreeDriveLetter {
    $used = @(
        Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID } | ForEach-Object {
            $_.DeviceID.TrimEnd(':').ToUpperInvariant()
        }
    )

    foreach ($letter in @('R','S','T','U','V','W','X','Y','Z','Q','P','O')) {
        if ($used -notcontains $letter) {
            return "$letter`:"
        }
    }

    throw "No free drive letter available for ESP mount."
}

function Mount-TargetEsp {
    $targetDisk = Get-Disk | Where-Object { $_.FriendlyName -eq 'Qualcomm MMC Storage' -and $_.BusType -eq 'USB' } | Select-Object -First 1
    if ($null -eq $targetDisk) {
        throw "Qualcomm MMC Storage disk not found. Keep the phone in Mass Storage mode and rerun."
    }

    Write-Log ("Detected target disk: {0} ({1})" -f $targetDisk.Number, $targetDisk.FriendlyName)

    $targetPartition = Get-Partition -DiskNumber $targetDisk.Number -ErrorAction SilentlyContinue |
        Where-Object {
            $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' -or
            $_.PartitionNumber -eq 36
        } |
        Sort-Object PartitionNumber |
        Select-Object -First 1

    if ($null -eq $targetPartition) {
        throw ("Could not locate the target ESP partition on disk {0}." -f $targetDisk.Number)
    }

    if ($targetPartition.DriveLetter) {
        return ("{0}:" -f $targetPartition.DriveLetter)
    }

    $mountLetter = Get-FreeDriveLetter
    $diskpartScript = Join-Path $env:TEMP ("alioth-mount-esp-{0}.txt" -f ([guid]::NewGuid().ToString('N')))
    @'
select disk {0}
select partition {1}
assign letter={2}
detail partition
'@ -f $targetDisk.Number, $targetPartition.PartitionNumber, $mountLetter.TrimEnd(':') | Set-Content -LiteralPath $diskpartScript -Encoding ASCII

    try {
        $diskpartOutput = & diskpart /s $diskpartScript 2>&1
        $diskpartOutput | ForEach-Object { Write-Log $_ }
    } finally {
        Remove-Item -LiteralPath $diskpartScript -Force -ErrorAction SilentlyContinue
    }

    $refreshedPartition = Get-Partition -DiskNumber $targetDisk.Number -PartitionNumber $targetPartition.PartitionNumber -ErrorAction SilentlyContinue
    if ($null -eq $refreshedPartition -or -not $refreshedPartition.DriveLetter) {
        throw ("ESP was not mounted after diskpart. Expected path: {0}\" -f "$mountLetter\")
    }

    return ("{0}:" -f $refreshedPartition.DriveLetter)
}

function Find-EspDrive([string]$PreferredDrive) {
    $preferred = Normalize-Drive $PreferredDrive
    if ($preferred -and (Test-Path "$preferred\")) {
        Write-Log ("Using preferred ESP drive {0}" -f $preferred)
        return $preferred
    }

    return (Mount-TargetEsp)
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$TemplatePath = if ($TemplatePath) { $TemplatePath } else { Join-Path $engineeringRoot "templates\alioth-audit-mode-unattend.xml" }
$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}
if (-not (Test-Path $TemplatePath)) {
    throw "Audit-mode unattend template not found: $TemplatePath"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $LogRoot "prepare-audit-boot-$timestamp.log"

$esp = Find-EspDrive $EspDrive
$bcdStore = Join-Path $esp "EFI\Microsoft\Boot\BCD"

Write-Log "Preparing offline audit boot for $WindowsDrive"
Write-Log "Using ESP drive $esp"

$pantherDir = Join-Path $WindowsDrive "Windows\Panther"
$pantherUnattendDir = Join-Path $pantherDir "Unattend"
$sysprepDir = Join-Path $WindowsDrive "Windows\System32\Sysprep"
$sysprepPantherDir = Join-Path $sysprepDir "Panther"
New-Item -ItemType Directory -Force -Path $pantherDir, $pantherUnattendDir, $sysprepDir, $sysprepPantherDir | Out-Null

Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $pantherDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $pantherUnattendDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $sysprepDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $sysprepPantherDir "unattend.xml") -Force
Write-Log "Staged audit-mode unattend.xml to Panther and Sysprep locations."

$offlineSystemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$tempSystemHiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM"
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $tempSystemHiveName, $offlineSystemHive)
try {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$tempSystemHiveName\Setup",
        "/v", "UnattendFile",
        "/t", "REG_SZ",
        "/d", "C:\Windows\Panther\unattend.xml",
        "/f"
    )
} finally {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $tempSystemHiveName)
}

Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{default}", "recoveryenabled", "No")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{default}", "bootstatuspolicy", "IgnoreAllFailures")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{bootmgr}", "displaybootmenu", "No")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/timeout", "0")

Write-Log "Audit-mode boot preparation completed successfully."
Write-Log "Suggested next step: exit Mass Storage, boot Windows, and verify whether the device enters Audit Mode instead of OOBE."
