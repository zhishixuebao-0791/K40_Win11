param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$KonaRoot,

    [string]$AnysocRoot,

    [string]$TemplatePath,

    [string]$LogRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $engineeringRoot

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

function Resolve-RepoPath([string]$Root, [string]$RepoName) {
    $direct = Join-Path $Root $RepoName
    if (Test-Path $direct) {
        return $direct
    }

    $match = Get-ChildItem -LiteralPath $Root -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $RepoName } |
        Select-Object -First 1

    if ($match) {
        return $match.FullName
    }

    return $null
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

$KonaRoot = if ($KonaRoot) { $KonaRoot } else { Resolve-RepoPath -Root $workspaceRoot -RepoName "windows_silicon_qcom_kona" }
$XiaomiPlatformsRoot = Resolve-RepoPath -Root $workspaceRoot -RepoName "windows_xiaomi_platforms_full"
$AnysocRoot = if ($AnysocRoot) {
    $AnysocRoot
} elseif ($XiaomiPlatformsRoot) {
    Join-Path $XiaomiPlatformsRoot "components\ANYSOC"
} else {
    $null
}
$TemplatePath = if ($TemplatePath) { $TemplatePath } else { Join-Path $engineeringRoot "templates\alioth-oobe-bypass-unattend.xml" }
$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }

$WindowsDrive = Normalize-Drive $WindowsDrive

if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

if (-not (Test-Path $KonaRoot)) {
    throw "Kona root not found: $KonaRoot"
}

if (-not (Test-Path $AnysocRoot)) {
    throw "ANYSOC root not found: $AnysocRoot"
}

if (-not (Test-Path $TemplatePath)) {
    throw "Unattend template not found: $TemplatePath"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $LogRoot "offline-fixes-$timestamp.log"

Write-Log "Applying offline fixes to $WindowsDrive"
Write-Log "Kona root: $KonaRoot"
Write-Log "ANYSOC root: $AnysocRoot"

$excludedDriverRoots = @(
    (Join-Path $KonaRoot "Drivers\SOC")
) | ForEach-Object {
    try {
        [IO.Path]::GetFullPath($_)
    } catch {
        $_
    }
}

$allDriverRoots = @(
    (Join-Path $KonaRoot "Drivers"),
    (Join-Path $KonaRoot "Extensions"),
    (Join-Path $KonaRoot "Libraries"),
    (Join-Path $KonaRoot "Services"),
    (Join-Path $KonaRoot "Settings"),
    (Join-Path $AnysocRoot "Support\Desktop\SUPPORT.DESKTOP.MOBILE_COMPONENTS\Source\Settings\USBFn"),
    (Join-Path $AnysocRoot "Hardware\HARDWARE.USB.FSA4480")
) | Where-Object { Test-Path $_ }

$driverRoots = $allDriverRoots | Where-Object {
    $resolved = try { [IO.Path]::GetFullPath($_) } catch { $_ }
    $excludedDriverRoots -notcontains $resolved
}

foreach ($excludedRoot in $excludedDriverRoots) {
    if (Test-Path $excludedRoot) {
        Write-Log "Excluding high-risk driver root from offline injection: $excludedRoot"
    }
}

foreach ($driverRoot in $driverRoots) {
    Write-Log "Injecting drivers from: $driverRoot"
    Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
        "/Image:$WindowsDrive\",
        "/Add-Driver",
        "/Driver:$driverRoot",
        "/Recurse"
    )
}

$pantherDir = Join-Path $WindowsDrive "Windows\Panther"
$pantherUnattendDir = Join-Path $pantherDir "Unattend"
$sysprepDir = Join-Path $WindowsDrive "Windows\System32\Sysprep"
$sysprepPantherDir = Join-Path $sysprepDir "Panther"
New-Item -ItemType Directory -Force -Path $pantherDir, $pantherUnattendDir, $sysprepDir, $sysprepPantherDir | Out-Null

$pantherUnattend = Join-Path $pantherDir "unattend.xml"
$pantherNamedUnattend = Join-Path $pantherUnattendDir "unattend.xml"
$sysprepUnattend = Join-Path $sysprepDir "unattend.xml"
$sysprepPantherUnattend = Join-Path $sysprepPantherDir "unattend.xml"

Copy-Item -LiteralPath $TemplatePath -Destination $pantherUnattend -Force
Copy-Item -LiteralPath $TemplatePath -Destination $pantherNamedUnattend -Force
Copy-Item -LiteralPath $TemplatePath -Destination $sysprepUnattend -Force
Copy-Item -LiteralPath $TemplatePath -Destination $sysprepPantherUnattend -Force
Write-Log "Staged unattend.xml to Panther and Sysprep locations."

$offlineSoftwareHive = Join-Path $WindowsDrive "Windows\System32\Config\SOFTWARE"
$offlineSystemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$tempHiveName = "HKLM\ALIOTH_OFFLINE_SOFTWARE"
$tempSystemHiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM"

Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $tempHiveName, $offlineSoftwareHive)
try {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$tempHiveName\Microsoft\Windows\CurrentVersion\OOBE",
        "/v", "BypassNRO",
        "/t", "REG_DWORD",
        "/d", "1",
        "/f"
    )
} finally {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $tempHiveName)
}

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

Write-Log "Offline fixes completed successfully."
Write-Log "Suggested next step: exit Mass Storage, boot Windows, then validate USB input and OOBE behavior."
