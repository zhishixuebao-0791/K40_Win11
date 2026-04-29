param(
    [string]$WindowsDrive = "D",
    [string]$DriverRoot,
    [switch]$SkipDism,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

function Write-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($script:LogPath) {
        $line | Add-Content -LiteralPath $script:LogPath -Encoding UTF8
    }
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    if ($output) {
        $output | ForEach-Object { Write-Log ([string]$_) }
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code $exitCode`: $FilePath"
    }

    return $exitCode
}

function Get-WindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be a removable drive such as D:. Use -AllowHostSystemDrive only if you intentionally target this PC."
        }
    }

    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows"))) {
        throw "Windows directory not found on drive $root"
    }
    return $root
}

function Write-SignatureState {
    param([string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log "Signature target missing: $path"
            continue
        }

        $sig = Get-AuthenticodeSignature -LiteralPath $path
        $subject = ""
        if ($sig.SignerCertificate) {
            $subject = $sig.SignerCertificate.Subject
        }
        Write-Log ("Signature: {0} => {1}; {2}" -f $path, $sig.Status, $subject)
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator

if (-not $DriverRoot) {
    $DriverRoot = Join-Path $repoRoot "sound_code\windows_silicon_qcom_kona\Drivers\Cellular\IPCRouter"
}

$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-ipcrouter-phase4b-apply-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying Alioth audio IPCRouter phase4b narrow driver experiment."
Write-Log "WindowsDrive=$WindowsDrive"
Write-Log "DriverRoot=$DriverRoot"

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$infPath = Join-Path $DriverRoot "qcipcrouter8250.inf"
$catPath = Join-Path $DriverRoot "qcipcrouter8250.cat"
$sysPath = Join-Path $DriverRoot "qcipcrouter8250.sys"
$dllPath = Join-Path $DriverRoot "qsocketipcrum.dll"

foreach ($required in @($infPath, $catPath, $sysPath, $dllPath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required IPCRouter driver file not found: $required"
    }
}

Write-SignatureState -Paths @($catPath, $sysPath)

if (-not $SkipDism) {
    Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$windowsRoot", "/Add-Driver", "/Driver:$infPath")
} else {
    Write-Log "SkipDism was set; not adding IPCRouter driver."
}

Write-Log "IPCRouter phase4b apply completed. Boot Mu-alioth phase4b, then run Trace-AliothAcpiPhase3State.ps1 and Trace-AliothAudioDependencyState.ps1."
