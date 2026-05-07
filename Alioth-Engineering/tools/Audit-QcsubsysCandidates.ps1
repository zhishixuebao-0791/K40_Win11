param(
    [string]$ProjectRoot,
    [string]$OutputRoot
)

$ErrorActionPreference = "Stop"

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

if (-not $ProjectRoot) {
    $ProjectRoot = Get-ProjectRoot
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $ProjectRoot "Alioth-Engineering\logs"
}

$roots = @(
    (Join-Path $ProjectRoot "sound_code"),
    (Join-Path $ProjectRoot "Alioth-Engineering\experiments")
) | Where-Object { Test-Path -LiteralPath $_ }

$outDir = Join-Path $OutputRoot ("QcsubsysCandidateAudit_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$files = Get-ChildItem -LiteralPath $roots -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'qcsubsys.*\.(inf|sys|cat)$|subsystem.*\.(inf|sys|cat)$' } |
    Sort-Object FullName

$records = foreach ($file in $files) {
    $sig = $null
    $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
    if ($file.Extension -in @(".sys", ".cat")) {
        $sig = Get-AuthenticodeSignature -LiteralPath $file.FullName
    }
    [pscustomobject]@{
        Path = $file.FullName
        Name = $file.Name
        Length = $file.Length
        Sha256 = $hash.Hash
        SignatureStatus = if ($sig) { [string]$sig.Status } else { "" }
        Signer = if ($sig -and $sig.SignerCertificate) { [string]$sig.SignerCertificate.Subject } else { "" }
        Issuer = if ($sig -and $sig.SignerCertificate) { [string]$sig.SignerCertificate.Issuer } else { "" }
    }
}

$records | Export-Csv -LiteralPath (Join-Path $outDir "qcsubsys-candidates.csv") -NoTypeInformation -Encoding UTF8
$records | Format-List | Out-File -LiteralPath (Join-Path $outDir "qcsubsys-candidates.txt") -Encoding UTF8

$infSummaryPath = Join-Path $outDir "inf-hardware-ids.txt"
foreach ($inf in ($files | Where-Object Extension -eq ".inf")) {
    "== $($inf.FullName) ==" | Out-File -LiteralPath $infSummaryPath -Append -Encoding UTF8
    Select-String -LiteralPath $inf.FullName -Pattern 'DriverVer|CatalogFile|Provider|ACPI\\QCOM|ACPI\\VEN_QCOM|SSDD.DeviceDesc|ServiceBinary' |
        ForEach-Object { "{0}:{1}" -f $_.LineNumber, $_.Line.Trim() } |
        Out-File -LiteralPath $infSummaryPath -Append -Encoding UTF8
    "" | Out-File -LiteralPath $infSummaryPath -Append -Encoding UTF8
}

Write-Host "Qcsubsys candidate audit completed:"
Write-Host "  $outDir"
