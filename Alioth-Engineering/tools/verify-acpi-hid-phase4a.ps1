param(
    [string]$MuRoot,
    [string]$ImagePath
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

function Join-RepoPath {
    param([string[]]$Parts)
    return [System.IO.Path]::Combine($Parts)
}

function Test-AsciiInFile {
    param(
        [string]$Path,
        [string]$Needle
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $needleBytes = [System.Text.Encoding]::ASCII.GetBytes($Needle)

    for ($i = 0; $i -le $bytes.Length - $needleBytes.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $needleBytes.Length; $j++) {
            if ($bytes[$i + $j] -ne $needleBytes[$j]) {
                $match = $false
                break
            }
        }
        if ($match) { return $true }
    }

    return $false
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($MuRoot)) { $MuRoot = $null }
if ([string]::IsNullOrWhiteSpace($ImagePath)) { $ImagePath = $null }

if (-not $MuRoot) {
    $preferred = Join-RepoPath @($repoRoot, "sound_code", "Mu-Silicium")
    if (Test-Path -LiteralPath $preferred) {
        $MuRoot = (Resolve-Path -LiteralPath $preferred).Path
    }
}

if (-not $MuRoot) {
    $searchRoots = @($repoRoot, (Get-Location).Path) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($searchRoot in $searchRoots) {
        $candidate = Get-ChildItem -LiteralPath $searchRoot -Directory -Recurse -Filter "Mu-Silicium" -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-RepoPath @($_.FullName, "Silicium-ACPI", "Platforms", "Xiaomi", "alioth", "DSDT.asl")) } |
            Select-Object -First 1
        if ($candidate) {
            $MuRoot = $candidate.FullName
            break
        }
    }
}

if (-not $MuRoot -or -not (Test-Path -LiteralPath $MuRoot)) {
    throw "Mu-Silicium root not found: $MuRoot"
}

$aliothDir = Join-RepoPath @($MuRoot, "Silicium-ACPI", "Platforms", "Xiaomi", "alioth")
$dsdtAsl = Join-RepoPath @($aliothDir, "DSDT.asl")
$dsdtAml = Join-RepoPath @($aliothDir, "DSDT.aml")

$source = Get-Content -LiteralPath $dsdtAsl -Raw
$sourceChecks = [ordered]@{
    "DSDT.asl QCOM251B" = $source.Contains("QCOM251B")
    "DSDT.asl QCOM2533" = $source.Contains("QCOM2533")
    "DSDT.asl QCOM250B" = $source.Contains("QCOM250B")
    "DSDT.asl QCOM258D" = $source.Contains("QCOM258D")
    "DSDT.asl QCOM051B" = $source.Contains("QCOM051B")
    "DSDT.asl QCOM0533" = $source.Contains("QCOM0533")
    "DSDT.asl QCOM050B" = $source.Contains("QCOM050B")
    "DSDT.asl QCOM058D" = $source.Contains("QCOM058D")
}

$amlChecks = [ordered]@{
    "DSDT.aml QCOM251B" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM251B"
    "DSDT.aml QCOM2533" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM2533"
    "DSDT.aml QCOM250B" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM250B"
    "DSDT.aml QCOM258D" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM258D"
    "DSDT.aml QCOM051B" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM051B"
    "DSDT.aml QCOM0533" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM0533"
    "DSDT.aml QCOM050B" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM050B"
    "DSDT.aml QCOM058D" = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM058D"
}

foreach ($entry in $sourceChecks.GetEnumerator()) {
    Write-Log ("{0}: {1}" -f $entry.Key, $entry.Value)
}

foreach ($entry in $amlChecks.GetEnumerator()) {
    Write-Log ("{0}: {1}" -f $entry.Key, $entry.Value)
}

if ($ImagePath) {
    if (-not (Test-Path -LiteralPath $ImagePath)) {
        throw "Image not found: $ImagePath"
    }

    Write-Log "Image size: $((Get-Item -LiteralPath $ImagePath).Length)"
    foreach ($needle in @("QCOM251B", "QCOM2533", "QCOM250B", "QCOM258D")) {
        Write-Log "Image contains $needle as plain ASCII: $(Test-AsciiInFile -Path $ImagePath -Needle $needle)"
    }
    Write-Log "Plain ASCII may be false for boot.img because the FV payload is compressed."
}

if (-not $sourceChecks["DSDT.asl QCOM251B"] -or -not $sourceChecks["DSDT.asl QCOM2533"] -or
    -not $sourceChecks["DSDT.asl QCOM250B"] -or -not $sourceChecks["DSDT.asl QCOM258D"] -or
    $sourceChecks["DSDT.asl QCOM051B"] -or $sourceChecks["DSDT.asl QCOM0533"] -or
    $sourceChecks["DSDT.asl QCOM050B"] -or $sourceChecks["DSDT.asl QCOM058D"] -or
    -not $amlChecks["DSDT.aml QCOM251B"] -or -not $amlChecks["DSDT.aml QCOM2533"] -or
    -not $amlChecks["DSDT.aml QCOM250B"] -or -not $amlChecks["DSDT.aml QCOM258D"] -or
    $amlChecks["DSDT.aml QCOM051B"] -or $amlChecks["DSDT.aml QCOM0533"] -or
    $amlChecks["DSDT.aml QCOM050B"] -or $amlChecks["DSDT.aml QCOM058D"]) {
    throw "ACPI HID phase-4a verification failed."
}

Write-Log "ACPI HID phase-4a verification passed."
