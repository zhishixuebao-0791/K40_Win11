param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$ProblemDriver = "qcppx8250"
)

$ErrorActionPreference = "Stop"

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

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$engineeringRoot = Split-Path -Parent $PSScriptRoot
$logRoot = Join-Path $engineeringRoot "logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogFile = Join-Path $logRoot ("rollback-problematic-kona-drivers-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Starting offline rollback for problematic driver: $ProblemDriver"

$systemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$hiveName = "HKLM\ALIOTH_OFFLINE_SYSTEM"
$serviceName = if ($ProblemDriver -match '8250$') {
    $ProblemDriver -replace '8250$',''
} else {
    $ProblemDriver
}
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $hiveName, $systemHive)
try {
    $serviceRoot = "$hiveName\ControlSet001\Services\$serviceName"
    $serviceRootPs = "Registry::$serviceRoot"
    if (Test-Path -LiteralPath $serviceRootPs) {
        Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("add", $serviceRoot, "/v", "Start", "/t", "REG_DWORD", "/d", "4", "/f")
        Write-Log "Disabled offline service $serviceName (Start=4)."
    } else {
        Write-Log "Offline service $serviceName not present."
    }
} finally {
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("unload", $hiveName) -AllowFailure
}

$offlineInfDir = Join-Path $WindowsDrive "Windows\INF"
$matchingOems = Get-ChildItem -LiteralPath $offlineInfDir -Filter "oem*.inf" -ErrorAction SilentlyContinue |
    Where-Object {
        try {
            Select-String -Path $_.FullName -Pattern $ProblemDriver -Quiet -ErrorAction Stop
        } catch {
            $false
        }
    }

if (-not $matchingOems) {
    Write-Log "No offline oem*.inf references found for $ProblemDriver."
} else {
    foreach ($oem in $matchingOems) {
        Write-Log "Attempting offline driver removal for $($oem.Name)"
        Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
            "/English",
            "/Image:$WindowsDrive\",
            "/Remove-Driver",
            "/Driver:$($oem.Name)"
        ) -AllowFailure
    }
}

Write-Log "Offline rollback completed."
