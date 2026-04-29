param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsDrive,

    [string]$ExperimentRoot,

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

if (-not (Test-Admin)) {
    throw "Run this script in an Administrator PowerShell window."
}

$WindowsDrive = Normalize-Drive $WindowsDrive
if (-not (Test-Path "$WindowsDrive\Windows\System32")) {
    throw "No offline Windows installation found on $WindowsDrive"
}

$ExperimentRoot = if ($ExperimentRoot) {
    $ExperimentRoot
} else {
    Join-Path $engineeringRoot "experiments\audio-fsa4480-minimal"
}

$LogRoot = if ($LogRoot) { $LogRoot } else { Join-Path $engineeringRoot "logs" }
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$script:LogFile = Join-Path $LogRoot ("apply-fsa4480-minimal-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

$infPath = Join-Path $ExperimentRoot "fsa4480.inf"
$sysPath = Join-Path $ExperimentRoot "fsa4480.sys"
$catPath = Join-Path $ExperimentRoot "fsa4480.cat"
$hwidPath = Join-Path $ExperimentRoot "candidate-hwid.txt"

foreach ($path in @($infPath, $sysPath, $catPath, $hwidPath)) {
    if (-not (Test-Path $path)) {
        throw "Experiment artifact missing: $path"
    }
}

$targetHwid = (Get-Content -LiteralPath $hwidPath -ErrorAction Stop | Select-Object -First 1).Trim()
Write-Log "Applying single-point FSA4480 experiment package."
Write-Log ("Offline Windows drive: {0}" -f $WindowsDrive)
Write-Log ("Experiment root: {0}" -f $ExperimentRoot)
Write-Log ("Target candidate hardware ID: {0}" -f $targetHwid)
Write-Log "This script injects only fsa4480.inf and does not touch Kona Audio/SOC/USBFn."

Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
    "/English",
    "/Image:$WindowsDrive\",
    "/Add-Driver",
    "/Driver:$infPath"
)

Write-Log "Collecting current offline driver inventory after injection."
Invoke-LoggedNative -FilePath "dism.exe" -Arguments @(
    "/English",
    "/Image:$WindowsDrive\",
    "/Get-Drivers"
) -AllowFailure

Write-Log "FSA4480 minimal injection completed."
Write-Log "Next step: reboot into Windows, verify whether ACPI\\FSA04480 is resolved and whether any audio-root evidence changes."
