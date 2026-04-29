param(
    [string]$SourceRoot,
    [string]$ExperimentRoot
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $SourceRoot) {
    $sourceCandidate = Get-ChildItem -LiteralPath $repoRoot -Recurse -Directory -Filter "windows_silicon_qcom_kona" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($sourceCandidate) {
        $SourceRoot = $sourceCandidate.FullName
    }
}

if (-not $ExperimentRoot) {
    $ExperimentRoot = Join-Path $repoRoot "Alioth-Engineering\experiments\audio-deps-phase2a"
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Kona source root not found: $SourceRoot"
}

$packageRoot = Join-Path $ExperimentRoot "signed-driver-package"
$manifestPath = Join-Path $ExperimentRoot "manifest.json"

$items = @(
    [pscustomobject]@{
        Name = "PILC"
        Source = Join-Path $SourceRoot "Drivers\SOC\HexagonLoader"
        Destination = Join-Path $packageRoot "HexagonLoader"
        Inf = "qcpil8250.inf"
        NativeMatch = "QCOM051B"
        DriverAlias = "ACPI\QCOM251B"
    },
    [pscustomobject]@{
        Name = "RPEN"
        Source = Join-Path $SourceRoot "Drivers\SOC\ResetPower\ResetProtectionEnabler"
        Destination = Join-Path $packageRoot "ResetProtectionEnabler"
        Inf = "qcrpen8250.inf"
        NativeMatch = "QCOM0533"
        DriverAlias = "ACPI\QCOM2533"
    },
    [pscustomobject]@{
        Name = "SMMU"
        Source = Join-Path $SourceRoot "Drivers\SOC\SMMU"
        Destination = Join-Path $packageRoot "SMMU"
        Inf = "qcsmmu8250.inf"
        NativeMatch = "QCOM0509"
        DriverAlias = "ACPI\VEN_QCOM&DEV_2509&REV_0002"
    },
    [pscustomobject]@{
        Name = "SCM"
        Source = Join-Path $SourceRoot "Drivers\SOC\System\SCM"
        Destination = Join-Path $packageRoot "SCM"
        Inf = "qcscm8250.inf"
        NativeMatch = "QCOM050B"
        DriverAlias = "ACPI\QCOM250B"
    }
)

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

foreach ($item in $items) {
    if (-not (Test-Path -LiteralPath $item.Source)) {
        throw "Source driver directory not found: $($item.Source)"
    }

    $sourceInf = Join-Path $item.Source $item.Inf
    if (-not (Test-Path -LiteralPath $sourceInf)) {
        throw "Source INF not found: $sourceInf"
    }

    if (Test-Path -LiteralPath $item.Destination) {
        Remove-Item -LiteralPath $item.Destination -Recurse -Force
    }

    Write-Log "Copying signed package: $($item.Name)"
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Recurse -Force
}

$files = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName
$hashes = foreach ($file in $files) {
    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    [pscustomobject]@{
        RelativePath = $file.FullName.Substring($packageRoot.Length).TrimStart('\')
        Length = $file.Length
        SHA256 = $hash.Hash
    }
}

$manifest = [ordered]@{
    Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    PackageRoot = $packageRoot
    SourceRoot = $SourceRoot
    Strategy = "Phase 2a only targets already-enumerated low-level dependencies. INF files are not modified."
    Aliases = $items | Select-Object Name, NativeMatch, DriverAlias, Inf
    Files = $hashes
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Log "Prepared phase-2a signed package: $packageRoot"
Write-Log "Wrote manifest: $manifestPath"
