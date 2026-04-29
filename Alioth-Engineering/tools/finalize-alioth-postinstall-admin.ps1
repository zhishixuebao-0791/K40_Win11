param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$LogRoot
)

$ErrorActionPreference = "Stop"
$engineeringRoot = Split-Path -Parent $PSScriptRoot
$script:TargetUser = "jcyang"
$script:TargetPassword = "ucchip@2026"

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

function Invoke-LoggedNative([string]$FilePath, [string[]]$Arguments, [switch]$AllowFailure) {
    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $oldPreference = $ErrorActionPreference
    $nativePrefExists = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
    if ($nativePrefExists) {
        $oldNativePreference = $PSNativeCommandUseErrorActionPreference
        $script:PSNativeCommandUseErrorActionPreference = $false
    }
    $ErrorActionPreference = "Continue"
    try {
        $output = & $FilePath @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $oldPreference
        if ($nativePrefExists) {
            $script:PSNativeCommandUseErrorActionPreference = $oldNativePreference
        }
    }
    if ($output) {
        $output | ForEach-Object {
            Add-Content -LiteralPath $script:LogFile -Value $_ -Encoding UTF8
            Write-Host $_
        }
    }
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $FilePath)
    }
}

function Remove-StaleHiveMounts([string]$Pattern) {
    $mounted = Get-ChildItem Registry::HKEY_LOCAL_MACHINE -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like $Pattern }
    foreach ($item in $mounted) {
        try {
            Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", "HKLM\$($item.PSChildName)") -AllowFailure
        } catch {
            Write-Log ("Non-fatal: failed to unload stale hive HKLM\{0}: {1}" -f $item.PSChildName, $_.Exception.Message)
        }
    }
}

function Invoke-RegLoadWithRetry([string]$HiveName, [string]$HivePath) {
    Remove-StaleHiveMounts (($HiveName -replace '^HKLM\\', '') + "*")
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $HiveName, $HivePath)
            return
        } catch {
            if ($attempt -eq 5) {
                throw
            }
            Write-Log ("Retrying hive load for {0} after lock/access failure. Attempt {1}/5" -f $HivePath, $attempt)
            Start-Sleep -Seconds 2
        }
    }
}

function Invoke-RegLoadBestEffort([string]$HiveName, [string]$HivePath) {
    try {
        Invoke-RegLoadWithRetry -HiveName $HiveName -HivePath $HivePath
        return $true
    } catch {
        Write-Log ("Non-fatal: unable to load offline hive {0}: {1}" -f $HivePath, $_.Exception.Message)
        return $false
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
$script:LogFile = Join-Path $LogRoot ("finalize-postinstall-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Finalizing Alioth postinstall state for $WindowsDrive"

$oobeTemplate = Join-Path $engineeringRoot "templates\alioth-oobe-bypass-unattend.xml"
if (-not (Test-Path $oobeTemplate)) {
    throw "OOBE template not found: $oobeTemplate"
}

$pantherDir = Join-Path $WindowsDrive "Windows\Panther"
$pantherUnattendDir = Join-Path $pantherDir "Unattend"
$sysprepDir = Join-Path $WindowsDrive "Windows\System32\Sysprep"
$sysprepPantherDir = Join-Path $sysprepDir "Panther"
New-Item -ItemType Directory -Force -Path $pantherDir, $pantherUnattendDir, $sysprepDir, $sysprepPantherDir | Out-Null

Copy-Item -LiteralPath $oobeTemplate -Destination (Join-Path $pantherDir "unattend.xml") -Force
Copy-Item -LiteralPath $oobeTemplate -Destination (Join-Path $pantherUnattendDir "unattend.xml") -Force
Copy-Item -LiteralPath $oobeTemplate -Destination (Join-Path $sysprepDir "unattend.xml") -Force
Copy-Item -LiteralPath $oobeTemplate -Destination (Join-Path $sysprepPantherDir "unattend.xml") -Force
Write-Log "Staged OOBE-bypass unattend.xml to Panther and Sysprep."

$setupScriptsDir = Join-Path $WindowsDrive "Windows\Setup\Scripts"
$commonStartupDir = Join-Path $WindowsDrive "ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
New-Item -ItemType Directory -Force -Path $setupScriptsDir, $commonStartupDir | Out-Null

$bootstrapPs1 = Join-Path $setupScriptsDir "AliothBootstrap.ps1"
$bootstrapVbs = Join-Path $setupScriptsDir "AliothBootstrap.vbs"
$legacyLandscapePs1 = Join-Path $setupScriptsDir "AliothLandscape.ps1"
$legacyLandscapeCmd = Join-Path $commonStartupDir "AliothLandscape.cmd"
Remove-Item -LiteralPath $legacyLandscapePs1, $legacyLandscapeCmd, (Join-Path $commonStartupDir "AliothBootstrap.cmd") -Force -ErrorAction SilentlyContinue

$bootstrapScript = @'
$ErrorActionPreference = "Continue"
$log = "C:\Windows\Temp\AliothBootstrap.log"
$targetUser = "jcyang"
$targetPassword = "ucchip@2026"

function Write-Log([string]$Message) {
  "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message | Add-Content -Path $log -Encoding UTF8
}

function Invoke-Logged([scriptblock]$Action) {
  try {
    & $Action
  } catch {
    Write-Log ("Command failed: {0}" -f $_.Exception.Message)
  }
}

function Ensure-TargetUser {
  & cmd.exe /c "net user $targetUser" > $null 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Log ("Creating local administrator {0}." -f $targetUser)
    Invoke-Logged { & cmd.exe /c "net user $targetUser $targetPassword /add" }
  } else {
    Write-Log ("User {0} already exists. Skipping creation." -f $targetUser)
  }

  Write-Log ("Ensuring {0} belongs to Administrators." -f $targetUser)
  Invoke-Logged { & cmd.exe /c "net localgroup Administrators $targetUser /add" }
}

function Enable-TargetAutoLogon {
  $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
  New-ItemProperty -Path $winlogon -Name "AutoAdminLogon" -Value "1" -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $winlogon -Name "DefaultUserName" -Value $targetUser -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $winlogon -Name "DefaultPassword" -Value $targetPassword -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $winlogon -Name "AutoLogonCount" -Value 1 -PropertyType DWord -Force | Out-Null
  Write-Log ("Configured one-time {0} autologon." -f $targetUser)
}

function Remove-BootstrapRunEntry {
  $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
  Remove-ItemProperty -Path $runKey -Name "AliothBootstrap" -Force -ErrorAction SilentlyContinue
  Remove-ItemProperty -Path $runKey -Name "AliothCleanupSysprepUi" -Force -ErrorAction SilentlyContinue
  Write-Log "Removed Alioth bootstrap Run entries."
}

function Rotate-Landscape {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion;
    public short dmDriverVersion;
    public short dmSize;
    public short dmDriverExtra;
    public int dmFields;
    public int dmPositionX;
    public int dmPositionY;
    public int dmDisplayOrientation;
    public int dmDisplayFixedOutput;
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel;
    public int dmPelsWidth;
    public int dmPelsHeight;
    public int dmDisplayFlags;
    public int dmDisplayFrequency;
    public int dmICMMethod;
    public int dmICMIntent;
    public int dmMediaType;
    public int dmDitherType;
    public int dmReserved1;
    public int dmReserved2;
    public int dmPanningWidth;
    public int dmPanningHeight;
  }
  [DllImport("user32.dll")] public static extern int EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
  [DllImport("user32.dll")] public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);
}
"@
  $dev = New-Object NativeDisplay+DEVMODE
  $dev.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($dev)
  [void][NativeDisplay]::EnumDisplaySettings($null, -1, [ref]$dev)
  if ($dev.dmPelsHeight -gt $dev.dmPelsWidth) {
    $currentWidth = $dev.dmPelsWidth
    $currentHeight = $dev.dmPelsHeight
    $dev.dmDisplayOrientation = 1
    $dev.dmPelsWidth = $currentHeight
    $dev.dmPelsHeight = $currentWidth
    $dev.dmFields = 0x180000
    $result = [NativeDisplay]::ChangeDisplaySettings([ref]$dev, 0)
    Write-Log ("Landscape rotation result={0}" -f $result)
  } else {
    Write-Log "Display is already landscape."
  }
}

function Cleanup-Bootstrap {
  Remove-Item -LiteralPath "C:\Windows\Setup\Scripts\AliothBootstrap.ps1" -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "C:\Windows\Setup\Scripts\AliothBootstrap.vbs" -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "C:\Windows\Setup\Scripts\AliothLandscape.ps1" -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\AliothLandscape.cmd" -Force -ErrorAction SilentlyContinue
  Write-Log "Bootstrap artifacts cleaned up."
}

$currentUser = [Environment]::UserName
Write-Log ("Bootstrap running as {0}" -f $currentUser)

if ($currentUser -eq "Administrator") {
  Invoke-Logged { & cmd.exe /c "taskkill /im sysprep.exe /f" }
  Ensure-TargetUser
  Enable-TargetAutoLogon
  Write-Log "Launching silent sysprep to exit Audit Mode."
  Start-Process -FilePath "$env:WINDIR\System32\Sysprep\Sysprep.exe" -ArgumentList "/quiet /oobe /reboot /unattend:C:\Windows\Panther\unattend.xml" -WindowStyle Hidden
  exit 0
}

Invoke-Logged { & cmd.exe /c "net user Administrator /active:no" }
Remove-BootstrapRunEntry
Rotate-Landscape
Cleanup-Bootstrap
'@
Set-Content -LiteralPath $bootstrapPs1 -Value $bootstrapScript -Encoding UTF8

$bootstrapVbsContent = @'
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -File ""C:\Windows\Setup\Scripts\AliothBootstrap.ps1""", 0, False
'@
Set-Content -LiteralPath $bootstrapVbs -Value $bootstrapVbsContent -Encoding ASCII
Write-Log "Staged hidden Alioth bootstrap launcher for audit exit and landscape fix."

$softwareHive = Join-Path $WindowsDrive "Windows\System32\Config\SOFTWARE"
$systemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$softwareHiveName = "HKLM\ALIOTH_POST_SOFTWARE_{0}" -f $PID
$systemHiveName = "HKLM\ALIOTH_POST_SYSTEM_{0}" -f $PID

Invoke-RegLoadWithRetry -HiveName $softwareHiveName -HivePath $softwareHive
try {
    $existingTargetUser = Test-Path (Join-Path $WindowsDrive "Users\$($script:TargetUser)")
    Write-Log ("Detected existing offline user profile for {0}: {1}" -f $script:TargetUser, $existingTargetUser)
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows\CurrentVersion\RunOnce",
        "/v", "AliothCleanupSysprepUi",
        "/t", "REG_SZ",
        "/d", "cmd /c taskkill /im sysprep.exe /f >nul 2>&1",
        "/f"
    )
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows\CurrentVersion\Run",
        "/v", "AliothBootstrap",
        "/t", "REG_SZ",
        "/d", "wscript.exe C:\Windows\Setup\Scripts\AliothBootstrap.vbs",
        "/f"
    )
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows NT\CurrentVersion\Winlogon",
        "/v", "AutoAdminLogon",
        "/t", "REG_SZ",
        "/d", "1",
        "/f"
    ) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows NT\CurrentVersion\Winlogon",
        "/v", "DefaultUserName",
        "/t", "REG_SZ",
        "/d", $script:TargetUser,
        "/f"
    ) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows NT\CurrentVersion\Winlogon",
        "/v", "DefaultPassword",
        "/t", "REG_SZ",
        "/d", $script:TargetPassword,
        "/f"
    ) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows NT\CurrentVersion\Winlogon",
        "/v", "AutoLogonCount",
        "/t", "REG_DWORD",
        "/d", "1",
        "/f"
    ) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add",
        "$softwareHiveName\Microsoft\Windows\CurrentVersion\OOBE",
        "/v", "BypassNRO",
        "/t", "REG_DWORD",
        "/d", "1",
        "/f"
    ) -AllowFailure
} finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    try {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $softwareHiveName)
    } catch {
        Write-Log ("Non-fatal: failed to unload offline SOFTWARE hive cleanly: {0}" -f $_.Exception.Message)
    }
}

if (Invoke-RegLoadBestEffort -HiveName $systemHiveName -HivePath $systemHive) {
    try {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "add",
            "$systemHiveName\Setup",
            "/v", "UnattendFile",
            "/t", "REG_SZ",
            "/d", "C:\Windows\Panther\unattend.xml",
            "/f"
        )
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "delete",
            "$systemHiveName\Setup",
            "/v", "CmdLine",
            "/f"
        ) -AllowFailure
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "add",
            "$systemHiveName\Setup\Status\ChildCompletion",
            "/v", "setup.exe",
            "/t", "REG_DWORD",
            "/d", "3",
            "/f"
        ) -AllowFailure
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "add",
            "$systemHiveName\Setup",
            "/v", "OOBEInProgress",
            "/t", "REG_DWORD",
            "/d", "0",
            "/f"
        ) -AllowFailure
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "add",
            "$systemHiveName\Setup",
            "/v", "SystemSetupInProgress",
            "/t", "REG_DWORD",
            "/d", "0",
            "/f"
        ) -AllowFailure
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
            "add",
            "$systemHiveName\Setup",
            "/v", "AuditInProgress",
            "/t", "REG_DWORD",
            "/d", "0",
            "/f"
        ) -AllowFailure
    } finally {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        try {
            Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $systemHiveName)
        } catch {
            Write-Log ("Non-fatal: failed to unload offline SYSTEM hive cleanly: {0}" -f $_.Exception.Message)
        }
    }
} else {
    Write-Log "Skipping offline SYSTEM edits. Bootstrap + offline SOFTWARE changes are sufficient for this pass."
}

Write-Log "Alioth postinstall finalization completed."
Write-Log "Next boot should enter desktop once more, then bootstrap will reuse/create jcyang as needed, silently exit Audit Mode, and only rotate if the display is still portrait."
