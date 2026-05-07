param(
    [string]$WindowsDrive = "D",
    [string]$SsdeDriverRoot,
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
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\Config\SYSTEM"))) {
        throw "Offline Windows SYSTEM hive not found under $root"
    }
    return $root
}

function Resolve-SsdeDriverRoot {
    param([string]$RepoRoot)

    if ($SsdeDriverRoot) {
        if (-not (Test-Path -LiteralPath (Join-Path $SsdeDriverRoot "ssde.inf"))) {
            throw "ssde.inf not found under SsdeDriverRoot: $SsdeDriverRoot"
        }
        return $SsdeDriverRoot
    }

    $candidates = @(
        (Join-Path $RepoRoot "sound_code\windows_qcom_platforms\components\ANYSOC\Support\Desktop\SUPPORT.DESKTOP.BASE\Signature\SSDE"),
        (Join-Path $RepoRoot "sound_code\windows_xiaomi_platforms_full\components\ANYSOC\Support\Desktop\SUPPORT.DESKTOP.BASE\Signature\SSDE")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate "ssde.inf")) {
            return $candidate
        }
    }

    throw "Could not locate SSDE package under known source roots."
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

function Get-OfflineDword {
    param(
        [string]$HiveName,
        [string]$Key,
        [string]$Value
    )

    $path = "HKLM\$HiveName\$Key"
    $output = & reg.exe query $path /v $Value 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "Offline registry value missing: $Key\$Value"
        return $null
    }

    $line = $output | Where-Object { $_ -match "\s+$Value\s+REG_DWORD\s+" } | Select-Object -First 1
    if (-not $line) {
        Write-Log "Offline registry value parse failed: $Key\$Value"
        return $null
    }

    $raw = ($line -split "\s+")[-1]
    Write-Log "Offline registry value: $Key\$Value=$raw"
    return [Convert]::ToInt32(($raw -replace "^0x", ""), 16)
}

function Test-OfflineSsdeState {
    param([string]$WindowsRoot)

    $hiveName = "ALIOTH_SSDE_SYSTEM_{0}" -f (Get-Random)
    $hivePath = Join-Path $WindowsRoot "Windows\System32\Config\SYSTEM"
    try {
        Invoke-Native -FilePath "reg.exe" -Arguments @("load", "HKLM\$hiveName", $hivePath)

        $controlSet = "ControlSet001"
        $selectOutput = & reg.exe query "HKLM\$hiveName\Select" /v Current 2>&1
        if ($LASTEXITCODE -eq 0) {
            $currentLine = $selectOutput | Where-Object { $_ -match "\s+Current\s+REG_DWORD\s+" } | Select-Object -First 1
            if ($currentLine) {
                $currentRaw = ($currentLine -split "\s+")[-1]
                $current = [Convert]::ToInt32(($currentRaw -replace "^0x", ""), 16)
                $controlSet = "ControlSet{0:D3}" -f $current
            }
        }
        Write-Log "Offline active control set: $controlSet"

        $whql = Get-OfflineDword -HiveName $hiveName -Key "$controlSet\Control\CI\Policy" -Value "WhqlSettings"
        $licensed = Get-OfflineDword -HiveName $hiveName -Key "$controlSet\Control\CI\Protected" -Value "Licensed"
        $serviceStart = Get-OfflineDword -HiveName $hiveName -Key "$controlSet\Services\ssde" -Value "Start"

        if ($whql -ne 1) {
            throw "SSDE verification failed: CI Policy WhqlSettings is not 1."
        }
        if ($licensed -ne 1) {
            throw "SSDE verification failed: CI Protected Licensed is not 1."
        }
        if ($serviceStart -ne 0) {
            throw "SSDE verification failed: ssde service Start is not 0 (boot start)."
        }

        Write-Log "SSDE offline registry verification passed."
    } finally {
        Invoke-Native -FilePath "reg.exe" -Arguments @("unload", "HKLM\$hiveName") -AllowFailure | Out-Null
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator

$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$script:LogPath = Join-Path $logRoot ("woa-ssde-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Applying WOA SSDE package to offline Alioth Windows image."
Write-Log "WindowsDrive=$WindowsDrive"

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$ssdeRoot = Resolve-SsdeDriverRoot -RepoRoot $repoRoot
$ssdeInf = Join-Path $ssdeRoot "ssde.inf"
$ssdeCat = Join-Path $ssdeRoot "ssde.cat"
$ssdeSys = Join-Path $ssdeRoot "ssde.sys"

Write-Log "SsdeDriverRoot=$ssdeRoot"
Write-SignatureState -Paths @($ssdeInf, $ssdeCat, $ssdeSys)

if (-not $SkipDism) {
    Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$windowsRoot", "/Add-Driver", "/Driver:$ssdeInf")
} else {
    Write-Log "SkipDism was set; not adding SSDE package."
}

Test-OfflineSsdeState -WindowsRoot $windowsRoot

Write-Log "WOA SSDE apply completed. Boot Phase6 UEFI, then re-run AcpiPhase3State, AudioDependencyState, and QcsubsysCodeIntegrity diagnostics."
