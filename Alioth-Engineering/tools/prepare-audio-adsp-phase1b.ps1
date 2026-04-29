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
    $ExperimentRoot = Join-Path $repoRoot "Alioth-Engineering\experiments\audio-adsp-phase1b"
}

if (-not (Test-Path -LiteralPath $SourceRoot)) {
    throw "Kona source root not found: $SourceRoot"
}

$sourceDir = Join-Path $SourceRoot "Drivers\Subsystems\CombinedSubsystem"
$packageRoot = Join-Path $ExperimentRoot "signed-driver-package"
$destDir = Join-Path $packageRoot "CombinedSubsystem"
$manifestPath = Join-Path $ExperimentRoot "manifest.json"

if (-not (Test-Path -LiteralPath (Join-Path $sourceDir "qcsubsys8250.inf"))) {
    throw "qcsubsys8250.inf not found: $sourceDir"
}

New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
if (Test-Path -LiteralPath $destDir) {
    Remove-Item -LiteralPath $destDir -Recurse -Force
}

Write-Log "Copying signed package: CombinedSubsystem"
Copy-Item -LiteralPath $sourceDir -Destination $destDir -Recurse -Force

$files = Get-ChildItem -LiteralPath $packageRoot -Recurse -File | Sort-Object FullName
$hashes = foreach ($file in $files) {
    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    [pscustomobject]@{
        RelativePath = $file.FullName.Substring($packageRoot.Length).TrimStart('\')
        Length = $file.Length
        SHA256 = $hash.Hash
    }
}

[ordered]@{
    Created = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    PackageRoot = $packageRoot
    SourceRoot = $SourceRoot
    Strategy = "Do not modify INF files. Add offline CompatibleID ACPI\QCOM251D to native ACPI\QCOM051D so signed qcsubsys8250 can bind only to ADSP."
    Aliases = @(
        [pscustomobject]@{
            Name = "ADSP CombinedSubsystem"
            NativeId = "ACPI\QCOM051D"
            DriverId = "ACPI\QCOM251D"
            Inf = "qcsubsys8250.inf"
        }
    )
    Files = $hashes
} | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Log "Prepared phase-1b signed package: $packageRoot"
Write-Log "Wrote manifest: $manifestPath"
