param(
    [string]$WindowsDrive = "D",
    [string]$SignatureDriverRoot,
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
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\Config\SOFTWARE"))) {
        throw "Offline Windows SOFTWARE hive not found under $root"
    }
    return $root
}

function Resolve-SignatureDriverRoot {
    param([string]$RepoRoot)

    if ($SignatureDriverRoot) {
        if (-not (Test-Path -LiteralPath (Join-Path $SignatureDriverRoot "desktopsignature.inf"))) {
            throw "desktopsignature.inf not found under SignatureDriverRoot: $SignatureDriverRoot"
        }
        return $SignatureDriverRoot
    }

    $candidates = @(
        (Join-Path $RepoRoot "sound_code\windows_qcom_platforms\components\ANYSOC\Support\Desktop\SUPPORT.DESKTOP.BASE\Signature\DesktopSignature"),
        (Join-Path $RepoRoot "sound_code\windows_xiaomi_platforms_full\components\ANYSOC\Support\Desktop\SUPPORT.DESKTOP.BASE\Signature\DesktopSignature")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "desktopsignature.inf")) {
            return $candidate
        }
    }

    throw "Could not locate DesktopSignature trust package under known source roots."
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
        $issuer = ""
        if ($sig.SignerCertificate) {
            $subject = $sig.SignerCertificate.Subject
            $issuer = $sig.SignerCertificate.Issuer
        }
        Write-Log ("Signature: {0} => {1}; Subject={2}; Issuer={3}; {4}" -f $path, $sig.Status, $subject, $issuer, $sig.StatusMessage)
    }
}

function Test-OfflineCertificateKey {
    param(
        [string]$HiveName,
        [string]$Store,
        [string]$Thumbprint
    )

    $path = "HKLM\$HiveName\Microsoft\SystemCertificates\$Store\Certificates\$Thumbprint"
    $exitCode = Invoke-Native -FilePath "reg.exe" -Arguments @("query", $path) -AllowFailure
    if ($exitCode -eq 0) {
        Write-Log "Offline certificate key present: $Store\$Thumbprint"
    } else {
        Write-Log "Offline certificate key missing: $Store\$Thumbprint"
    }
}

function Test-OfflineTrustKeys {
    param([string]$WindowsRoot)

    $hiveName = "ALIOTH_WOA_TRUST_SOFTWARE_{0}" -f (Get-Random)
    $hivePath = Join-Path $WindowsRoot "Windows\System32\Config\SOFTWARE"
    try {
        Invoke-Native -FilePath "reg.exe" -Arguments @("load", "HKLM\$hiveName", $hivePath)

        # Key evidence from DesktopSignature: Windows On Andromeda Root Platform Key.
        Test-OfflineCertificateKey -HiveName $hiveName -Store "Root" -Thumbprint "D9254DAC570E3D582B429B162A70E7AD23FC5736"
        Test-OfflineCertificateKey -HiveName $hiveName -Store "TrustedPublisher" -Thumbprint "D9254DAC570E3D582B429B162A70E7AD23FC5736"

        # Key evidence from DesktopSignature: Windows On Andromeda Data Recovery Agent.
        Test-OfflineCertificateKey -HiveName $hiveName -Store "TrustedPublisher" -Thumbprint "C767958C1A48D3831DB3FF69AA45083CB8397627"
    } finally {
        Invoke-Native -FilePath "reg.exe" -Arguments @("unload", "HKLM\$hiveName") -AllowFailure | Out-Null
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator

$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("woa-andromeda-signature-trust-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying WOA/Andromeda signature trust package to offline Alioth Windows image."
Write-Log "WindowsDrive=$WindowsDrive"

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$signatureRoot = Resolve-SignatureDriverRoot -RepoRoot $repoRoot
$signatureInf = Join-Path $signatureRoot "desktopsignature.inf"
$signatureCat = Join-Path $signatureRoot "desktopsignature.cat"

Write-Log "SignatureDriverRoot=$signatureRoot"
Write-SignatureState -Paths @($signatureInf, $signatureCat)

if (-not $SkipDism) {
    Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$windowsRoot", "/Add-Driver", "/Driver:$signatureInf")
} else {
    Write-Log "SkipDism was set; not adding DesktopSignature package."
}

Test-OfflineTrustKeys -WindowsRoot $windowsRoot

Write-Log "WOA/Andromeda signature trust apply completed. Boot Phase6 UEFI, then re-run AcpiPhase3State and AudioDependencyState diagnostics."
