param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$DriverInfName = "fsa4480.inf",

    [string]$ServiceName = "fsa4480",

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

function Invoke-LoggedNative([string]$FilePath, [string[]]$Arguments, [switch]$AllowFailure) {
    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    $output = & $FilePath @Arguments 2>&1
    if ($output) {
        $output | ForEach-Object {
            Add-Content -LiteralPath $script:LogFile -Value $_ -Encoding UTF8
            Write-Host $_
        }
    }
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $FilePath)
    }
    return $output
}

function Remove-StaleHiveMounts([string]$Pattern) {
    $mounted = Get-ChildItem Registry::HKEY_LOCAL_MACHINE -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like $Pattern }
    foreach ($item in $mounted) {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", "HKLM\$($item.PSChildName)") -AllowFailure | Out-Null
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
            Write-Log ("Retrying hive load for {0}. Attempt {1}/5" -f $HivePath, $attempt)
            Start-Sleep -Seconds 2
        }
    }
}

function Parse-DismDriverBlocks([object[]]$Lines) {
    $items = @()
    $current = @{}
    foreach ($line in $Lines) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) {
            if ($current.Count -gt 0) {
                $items += [pscustomobject]$current
                $current = @{}
            }
            continue
        }
        if ($text -match '^\s*Published Name\s*:\s*(.+)$') {
            $current.PublishedName = $matches[1].Trim()
            continue
        }
        if ($text -match '^\s*Original File Name\s*:\s*(.+)$') {
            $current.OriginalFileName = $matches[1].Trim()
            continue
        }
        if ($text -match '^\s*Provider Name\s*:\s*(.+)$') {
            $current.ProviderName = $matches[1].Trim()
            continue
        }
        if ($text -match '^\s*Class Name\s*:\s*(.+)$') {
            $current.ClassName = $matches[1].Trim()
            continue
        }
    }
    if ($current.Count -gt 0) {
        $items += [pscustomobject]$current
    }
    return $items
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows\System32")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$script:LogFile = Join-Path $LogRoot ("rollback-fsa4480-minimal-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Rolling back FSA4480 single-point experiment."
Write-Log ("Offline Windows drive: {0}" -f $WindowsDrive)

$systemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$hiveName = "HKLM\ALIOTH_FSA4480_SYSTEM_{0}" -f $PID

Invoke-RegLoadWithRetry -HiveName $hiveName -HivePath $systemHive
try {
    $serviceRoot = "$hiveName\ControlSet001\Services\$ServiceName"
    $serviceRootPs = "Registry::$serviceRoot"
    if (Test-Path -LiteralPath $serviceRootPs) {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("add", $serviceRoot, "/v", "Start", "/t", "REG_DWORD", "/d", "4", "/f")
        Write-Log ("Disabled offline service {0} (Start=4)." -f $ServiceName)
    } else {
        Write-Log ("Offline service {0} not present." -f $ServiceName)
    }
} finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $hiveName) -AllowFailure | Out-Null
}

$driverInventory = Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
    "/English",
    "/Image:$WindowsDrive\",
    "/Get-Drivers"
) -AllowFailure

$parsed = Parse-DismDriverBlocks -Lines $driverInventory
$matches = $parsed | Where-Object {
    $_.OriginalFileName -and $_.OriginalFileName.Trim().ToLowerInvariant() -eq $DriverInfName.ToLowerInvariant()
}

if (-not $matches) {
    Write-Log ("No offline published driver packages found for {0}." -f $DriverInfName)
} else {
    foreach ($match in $matches) {
        if ($match.PublishedName) {
            Write-Log ("Removing published driver package {0} ({1})." -f $match.PublishedName, $match.OriginalFileName)
            Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
                "/English",
                "/Image:$WindowsDrive\",
                "/Remove-Driver",
                "/Driver:$($match.PublishedName)"
            ) -AllowFailure | Out-Null
        }
    }
}

Write-Log "FSA4480 rollback completed."
