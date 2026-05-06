param(
    [string]$WindowsDrive = "D",
    [string]$PdsrDriverRoot,
    [string]$TftpDriverRoot,
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

function Add-DriverPackage {
    param(
        [string]$WindowsRoot,
        [string]$Name,
        [string]$DriverRoot,
        [string]$InfName,
        [string[]]$RequiredFiles
    )

    Write-Log "Preparing $Name driver from $DriverRoot"
    foreach ($requiredFile in $RequiredFiles) {
        $requiredPath = Join-Path $DriverRoot $requiredFile
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required $Name driver file not found: $requiredPath"
        }
    }

    $signatureTargets = foreach ($requiredFile in $RequiredFiles) {
        if ($requiredFile -match '\.(cat|sys)$') {
            Join-Path $DriverRoot $requiredFile
        }
    }
    Write-SignatureState -Paths $signatureTargets

    if (-not $SkipDism) {
        $infPath = Join-Path $DriverRoot $InfName
        Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$WindowsRoot", "/Add-Driver", "/Driver:$infPath")
    } else {
        Write-Log "SkipDism was set; not adding $Name driver."
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator

if (-not $PdsrDriverRoot) {
    $PdsrDriverRoot = Join-Path $repoRoot "sound_code\windows_silicon_qcom_kona\Drivers\Subsystems\ProtectionDomainServiceRegistry"
}
if (-not $TftpDriverRoot) {
    $TftpDriverRoot = Join-Path $repoRoot "sound_code\windows_silicon_qcom_kona\Drivers\SOC\Transports"
}

$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("audio-pdsr-tftp-phase5-apply-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying Alioth audio PDSR/TFTP phase5 narrow driver experiment."
Write-Log "WindowsDrive=$WindowsDrive"
Write-Log "PdsrDriverRoot=$PdsrDriverRoot"
Write-Log "TftpDriverRoot=$TftpDriverRoot"

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive

Add-DriverPackage `
    -WindowsRoot $windowsRoot `
    -Name "PDSR" `
    -DriverRoot $PdsrDriverRoot `
    -InfName "qcpdsr.inf" `
    -RequiredFiles @("qcpdsr.inf", "qcpdsr.cat", "qcpdsr.sys")

Add-DriverPackage `
    -WindowsRoot $windowsRoot `
    -Name "TFTP" `
    -DriverRoot $TftpDriverRoot `
    -InfName "QcTftpKmdf.inf" `
    -RequiredFiles @("QcTftpKmdf.inf", "QcTftpKmdf.cat", "QcTftpKmdf.sys")

Write-Log "PDSR/TFTP phase5 apply completed. Boot Mu-alioth phase5, then run Trace-AliothAcpiPhase3State.ps1 and Trace-AliothAudioDependencyState.ps1."
