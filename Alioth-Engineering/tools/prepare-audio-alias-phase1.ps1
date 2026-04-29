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
    $ExperimentRoot = Join-Path $repoRoot "Alioth-Engineering\experiments\audio-alias-phase1"
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Kona source root not found: $SourceRoot"
}

$packageRoot = Join-Path $ExperimentRoot "signed-driver-package"
$manifestPath = Join-Path $ExperimentRoot "manifest.json"

$items = @(
    [pscustomobject]@{
        Name = "AudioService"
        Source = Join-Path $SourceRoot "Drivers\Audio\Orientation"
        Destination = Join-Path $packageRoot "AudioService"
        Inf = "AudioService8250.inf"
        NativeId = "ACPI\QCOM05D2"
        DriverId = "ACPI\QCOM25D2"
    },
    [pscustomobject]@{
        Name = "ADSPRPC"
        Source = Join-Path $SourceRoot "Drivers\Audio\RPC\ADSPRPC"
        Destination = Join-Path $packageRoot "ADSPRPC"
        Inf = "qcadsprpc8250.inf"
        NativeId = "ACPI\QCOM0560"
        DriverId = "ACPI\QCOM2560"
    },
    [pscustomobject]@{
        Name = "ADSPRPCD"
        Source = Join-Path $SourceRoot "Drivers\Audio\RPC\ADSPRPCD"
        Destination = Join-Path $packageRoot "ADSPRPCD"
        Inf = "qcadsprpcd8250.inf"
        NativeId = "ACPI\QCOM058A"
        DriverId = "ACPI\QCOM258A"
    }
)

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

foreach ($item in $items) {
    if (-not (Test-Path -LiteralPath $item.Source)) {
        throw "Source driver directory not found: $($item.Source)"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $item.Source $item.Inf))) {
        throw "Source INF not found: $(Join-Path $item.Source $item.Inf)"
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
    Strategy = "Do not modify INF files. Add offline CompatibleIDs for 05xx ACPI devices, then add original signed driver packages to DriverStore."
    Aliases = $items | Select-Object Name, NativeId, DriverId, Inf
    Files = $hashes
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Log "Prepared phase-1 signed package: $packageRoot"
Write-Log "Wrote manifest: $manifestPath"
