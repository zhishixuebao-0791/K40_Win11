param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [Parameter(Mandatory = $true)]
    [string]$WimPath,

    [int]$ImageIndex = 1,

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
        $output | ForEach-Object {
            Add-Content -LiteralPath $script:LogFile -Value $_ -Encoding UTF8
            Write-Host $_
        }
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

    return $mountLetter
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
$EspDrive = Normalize-Drive $EspDrive
$TemplatePath = if ($TemplatePath) { $TemplatePath } else { Join-Path $engineeringRoot "templates\alioth-audit-mode-unattend.xml" }
$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }

if (-not (Test-Path $WimPath)) {
    throw "WIM not found: $WimPath"
}
if (-not (Test-Path $TemplatePath)) {
    throw "Audit unattend template not found: $TemplatePath"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$script:LogFile = Join-Path $LogRoot ("reset-clean-base-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Resetting Alioth Windows partition to clean WIM base."
Write-Log ("Windows drive: {0}" -f $WindowsDrive)
Write-Log ("WIM path: {0}" -f $WimPath)
Write-Log ("Image index: {0}" -f $ImageIndex)

if (-not (Test-Path "$WindowsDrive\")) {
    throw "Target Windows drive is not mounted: $WindowsDrive"
}

Write-Log ("Formatting {0} as NTFS (WIN)." -f $WindowsDrive)
$formatWinOutput = & format.com $WindowsDrive /FS:NTFS /Q /V:WIN /Y 2>&1
$formatWinOutput | ForEach-Object { Write-Log $_ }

Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
    "/Apply-Image",
    "/ImageFile:$WimPath",
    "/Index:$ImageIndex",
    "/ApplyDir:$WindowsDrive\"
)

if (-not $EspDrive) {
    $EspDrive = Mount-TargetEsp
}

Write-Log ("Using ESP drive: {0}" -f $EspDrive)
Write-Log ("Formatting {0} as FAT32 (ESP)." -f $EspDrive)
$formatEspOutput = & format.com $EspDrive /FS:FAT32 /Q /V:ESP /Y 2>&1
$formatEspOutput | ForEach-Object { Write-Log $_ }

Invoke-LoggedNative -FilePath "bcdboot.exe" -Arguments @(
    "$WindowsDrive\Windows",
    "/s", $EspDrive,
    "/f", "UEFI",
    "/v"
)

$pantherDir = Join-Path $WindowsDrive "Windows\Panther"
$pantherUnattendDir = Join-Path $pantherDir "Unattend"
$sysprepDir = Join-Path $WindowsDrive "Windows\System32\Sysprep"
$sysprepPantherDir = Join-Path $sysprepDir "Panther"
New-Item -ItemType Directory -Force -Path $pantherDir, $pantherUnattendDir, $sysprepDir, $sysprepPantherDir | Out-Null

Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $pantherDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $pantherUnattendDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $sysprepDir "unattend.xml") -Force
Copy-Item -LiteralPath $TemplatePath -Destination (Join-Path $sysprepPantherDir "unattend.xml") -Force
Write-Log "Staged audit-mode unattend.xml to Panther and Sysprep."

$offlineSystemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$hiveName = "HKLM\ALIOTH_RESET_SYSTEM_{0}" -f $PID
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $hiveName, $offlineSystemHive)
try {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$hiveName\Setup",
        "/v", "UnattendFile",
        "/t", "REG_SZ",
        "/d", "C:\Windows\Panther\unattend.xml",
        "/f"
    )
} finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    try {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $hiveName)
    } catch {
        Write-Log ("Non-fatal: failed to unload offline SYSTEM hive cleanly: {0}" -f $_.Exception.Message)
    }
}

$bcdStore = Join-Path $EspDrive "EFI\Microsoft\Boot\BCD"
if (-not (Test-Path $bcdStore)) {
    throw "BCD store was not created on target ESP: $bcdStore"
}
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{default}", "recoveryenabled", "No")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{default}", "bootstatuspolicy", "IgnoreAllFailures")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/set", "{bootmgr}", "displaybootmenu", "No")
Invoke-LoggedNative -FilePath "bcdedit.exe" -Arguments @("/store", $bcdStore, "/timeout", "0")

Write-Log "Clean base reset completed."
Write-Log "No Qualcomm/Kona drivers were injected in this pass."
