param(
    [string]$WindowsDrive = "D",
    [string]$OutputRoot,
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

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

function Resolve-OfflineWindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . Use the Mass Storage drive letter, normally D:."
        }
    }

    $root = "${normalized}:\"
    $ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
    if (-not (Test-Path -LiteralPath $ciRoot)) {
        throw "Offline CodeIntegrity directory not found: $ciRoot"
    }
    return $root
}

function Add-Text {
    param(
        [string]$Path,
        [string]$Text
    )
    $Text | Out-File -LiteralPath $Path -Append -Encoding UTF8
}

$projectRoot = Get-ProjectRoot
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $projectRoot "Alioth-Engineering\logs"
}

$root = Resolve-OfflineWindowsRoot -Drive $WindowsDrive
$ciRoot = Join-Path $root "Windows\System32\CodeIntegrity"
$outDir = Join-Path $OutputRoot ("WdacBasePolicySource_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$summaryPath = Join-Path $outDir "00_summary.txt"
Add-Text $summaryPath "Offline Windows root: $root"
Add-Text $summaryPath "CodeIntegrity root: $ciRoot"
Add-Text $summaryPath ""

$policyNames = @(
    "driversipolicy.p7b",
    "VbsSiPolicy.p7b",
    "driver.stl",
    "SiPolicy.p7b"
)

foreach ($name in $policyNames) {
    $path = Join-Path $ciRoot $name
    Add-Text $summaryPath "== $name =="
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Text $summaryPath "missing"
        Add-Text $summaryPath ""
        continue
    }

    $item = Get-Item -LiteralPath $path
    $hash = Get-FileHash -LiteralPath $path -Algorithm SHA256
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    Add-Text $summaryPath ("Length: {0}" -f $item.Length)
    Add-Text $summaryPath ("LastWriteTime: {0:s}" -f $item.LastWriteTime)
    Add-Text $summaryPath ("SHA256: {0}" -f $hash.Hash)
    Add-Text $summaryPath ("SignatureStatus: {0}" -f $sig.Status)
    Add-Text $summaryPath ("Signer: {0}" -f $sig.SignerCertificate.Subject)
    Add-Text $summaryPath ("Issuer: {0}" -f $sig.SignerCertificate.Issuer)
    Add-Text $summaryPath ""

    Copy-Item -LiteralPath $path -Destination (Join-Path $outDir $name) -Force
    $dumpPath = Join-Path $outDir "$name.certutil.txt"
    & certutil.exe -dump $path *> $dumpPath
}

$activeDir = Join-Path $ciRoot "CiPolicies\Active"
$activeOut = Join-Path $outDir "CiPolicies_Active"
New-Item -ItemType Directory -Force -Path $activeOut | Out-Null
if (Test-Path -LiteralPath $activeDir) {
    Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $activeOut $_.Name) -Force
    }
}

Get-ChildItem -LiteralPath $activeOut -File -ErrorAction SilentlyContinue |
    Select-Object Name,Length,LastWriteTime |
    Format-List |
    Out-File -LiteralPath (Join-Path $outDir "01_active_policy_files.txt") -Encoding UTF8

Write-Host "WDAC base-policy source trace completed:"
Write-Host "  $outDir"
