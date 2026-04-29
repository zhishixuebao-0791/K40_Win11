param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$KonaRoot
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

function Remove-StaleHiveMount([string]$HiveName) {
    $regPath = "Registry::$HiveName"
    if (Test-Path -LiteralPath $regPath) {
        Write-Log "Found stale mounted hive at $HiveName, attempting unload."
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $HiveName) -AllowFailure
        Start-Sleep -Milliseconds 300
    }
}

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$KonaRoot = if ($KonaRoot) { $KonaRoot } else { Resolve-RepoPath -Root $workspaceRoot -RepoName "windows_silicon_qcom_kona" }
if (-not (Test-Path $KonaRoot)) {
    throw "Kona root not found: $KonaRoot"
}

$socRoot = Join-Path $KonaRoot "Drivers\SOC"
if (-not (Test-Path $socRoot)) {
    throw "Kona SOC root not found: $socRoot"
}

$logRoot = Join-Path $engineeringRoot "logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogFile = Join-Path $logRoot ("rollback-kona-soc-drivers-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Starting offline rollback for Kona SOC drivers."
Write-Log "Kona SOC root: $socRoot"

$socInfFiles = Get-ChildItem -LiteralPath $socRoot -Recurse -Filter "*.inf" -File
$socInfNames = $socInfFiles | ForEach-Object { $_.Name.ToLowerInvariant() } | Sort-Object -Unique
$socSysNames = Get-ChildItem -LiteralPath $socRoot -Recurse -Filter "*.sys" -File |
    ForEach-Object { $_.Name.ToLowerInvariant() } | Sort-Object -Unique

Write-Log ("Discovered {0} SOC INF files and {1} SYS files." -f $socInfNames.Count, $socSysNames.Count)

$offlineInfDir = Join-Path $WindowsDrive "Windows\INF"
$matchingOems = New-Object System.Collections.Generic.List[string]

Get-ChildItem -LiteralPath $offlineInfDir -Filter "oem*.inf" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }
    $lower = $content.ToLowerInvariant()
    foreach ($infName in $socInfNames) {
        if ($lower.Contains($infName)) {
            $matchingOems.Add($_.Name)
            break
        }
    }
}

$matchingOems = $matchingOems | Sort-Object -Unique
Write-Log ("Matched {0} offline oem INF packages to Kona SOC." -f $matchingOems.Count)

$systemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$legacyHiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM"
$hiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM_{0}" -f $PID
Remove-StaleHiveMount -HiveName $legacyHiveName
Remove-StaleHiveMount -HiveName $hiveName
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $hiveName, $systemHive)
try {
    $servicesPath = "Registry::$hiveName\ControlSet001\Services"
    if (Test-Path -LiteralPath $servicesPath) {
        Get-ChildItem -LiteralPath $servicesPath | ForEach-Object {
            try {
                $props = Get-ItemProperty -LiteralPath $_.PsPath -ErrorAction Stop
                $imagePath = [string]$props.ImagePath
                if (-not $imagePath) { return }
                $lowerImagePath = $imagePath.ToLowerInvariant()
                foreach ($sysName in $socSysNames) {
                    if ($lowerImagePath.Contains($sysName)) {
                        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
                            "add",
                            ($_.PsPath -replace '^Microsoft\.PowerShell\.Core\\Registry::',''),
                            "/v", "Start",
                            "/t", "REG_DWORD",
                            "/d", "4",
                            "/f"
                        ) -AllowFailure
                        Write-Log ("Disabled offline service {0} for {1}" -f $_.PSChildName, $sysName)
                        break
                    }
                }
            } catch {
                Write-Log ("Skipping service inspection for {0}: {1}" -f $_.PSChildName, $_.Exception.Message)
            }
        }
    }
} finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    try {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $hiveName) -AllowFailure
    } catch {
        Write-Log ("Non-fatal: failed to unload offline SYSTEM hive cleanly: {0}" -f $_.Exception.Message)
    }
}

foreach ($oem in $matchingOems) {
    Write-Log "Attempting offline driver removal for $oem"
    Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
        "/English",
        "/Image:$WindowsDrive\",
        "/Remove-Driver",
        "/Driver:$oem"
    ) -AllowFailure
}

Write-Log "Kona SOC rollback completed."
