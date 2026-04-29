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
$script:LogFile = Join-Path $LogRoot ("fix-setup-loop-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

Write-Log "Fixing offline setup loop state for $WindowsDrive"

$systemHive = Join-Path $WindowsDrive "Windows\System32\Config\SYSTEM"
$hiveName = "HKLM\ALIOTH_SETUPFIX_{0}" -f $PID
Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("load", $hiveName, $systemHive)
try {
    $setupRoot = "$hiveName\Setup"
    $childCompletion = "$setupRoot\Status\ChildCompletion"

    Write-Log "Dumping current offline Setup state."
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("query", $setupRoot) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("query", $childCompletion) -AllowFailure

    Write-Log "Applying ChildCompletion setup.exe=3 fix."
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add", $childCompletion,
        "/v", "setup.exe",
        "/t", "REG_DWORD",
        "/d", "3",
        "/f"
    )

    Write-Log "Disabling recovery loop flags that interfere with continuing setup."
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add", $setupRoot,
        "/v", "SystemSetupInProgress",
        "/t", "REG_DWORD",
        "/d", "1",
        "/f"
    )
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @(
        "add", $setupRoot,
        "/v", "SetupType",
        "/t", "REG_DWORD",
        "/d", "2",
        "/f"
    ) -AllowFailure

    Write-Log "Dumping updated offline Setup state."
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("query", $setupRoot) -AllowFailure
    Invoke-LoggedNative -FilePath "reg.exe" -Arguments @("query", $childCompletion) -AllowFailure
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

Write-Log "Offline setup-loop fix completed."
