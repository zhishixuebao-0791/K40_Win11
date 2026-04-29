param(
    [string]$MuRoot,
    [switch]$NoCompile
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
$compiler = Join-RepoPath @($MuRoot, "Silicium-ACPI", "Compiler", "asl.exe")
$logRoot = Join-RepoPath @($repoRoot, "Alioth-Engineering", "logs")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$compileLog = Join-RepoPath @($logRoot, "acpi-hid-phase4a-compile-$timestamp.log")
$backupPath = Join-RepoPath @($aliothDir, "DSDT.asl.pre-phase4a-$timestamp.bak")

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if (-not (Test-Path -LiteralPath $dsdtAsl)) {
    throw "Alioth DSDT source not found: $dsdtAsl"
}

$content = Get-Content -LiteralPath $dsdtAsl -Raw
$originalContent = $content

$replacements = @(
    [pscustomobject]@{ Device = "PILC"; Native = 'Name(_HID, "QCOM051B")'; Kona = 'Name(_HID, "QCOM251B")' },
    [pscustomobject]@{ Device = "RPEN"; Native = 'Name(_HID, "QCOM0533")'; Kona = 'Name(_HID, "QCOM2533")' },
    [pscustomobject]@{ Device = "SCM0"; Native = 'Name(_HID, "QCOM050B")'; Kona = 'Name(_HID, "QCOM250B")' },
    [pscustomobject]@{ Device = "GLNK"; Native = 'Name(_HID, "QCOM058D")'; Kona = 'Name(_HID, "QCOM258D")' }
)

foreach ($replacement in $replacements) {
    if ($content.Contains($replacement.Native)) {
        Write-Log "Patching $($replacement.Device): $($replacement.Native) -> $($replacement.Kona)"
        $content = $content.Replace($replacement.Native, $replacement.Kona)
    } elseif ($content.Contains($replacement.Kona)) {
        Write-Log "$($replacement.Device) is already patched: $($replacement.Kona)"
    } else {
        throw "Could not find either native or Kona HID for $($replacement.Device)."
    }
}

if ($content -ne $originalContent) {
    Copy-Item -LiteralPath $dsdtAsl -Destination $backupPath -Force
    [System.IO.File]::WriteAllText($dsdtAsl, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Log "Wrote patched DSDT.asl. Backup: $backupPath"
} else {
    Write-Log "No DSDT.asl changes needed."
}

if (-not $NoCompile) {
    if (-not (Test-Path -LiteralPath $compiler)) {
        throw "ASL compiler not found: $compiler"
    }

    Write-Log "Compiling patched alioth DSDT."
    $output = & $compiler $dsdtAsl 2>&1
    $exitCode = $LASTEXITCODE
    $output | Set-Content -Path $compileLog -Encoding UTF8

    if ($exitCode -ne 0) {
        throw "ASL compile failed with exit code $exitCode. Log: $compileLog"
    }

    Write-Log "Compiled DSDT.aml: $dsdtAml"
    Write-Log "Compile log: $compileLog"
}

if (-not (Test-Path -LiteralPath $dsdtAml)) {
    throw "DSDT.aml not found after compile: $dsdtAml"
}

$checks = [ordered]@{
    QCOM251B = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM251B"
    QCOM2533 = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM2533"
    QCOM250B = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM250B"
    QCOM258D = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM258D"
    QCOM051B = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM051B"
    QCOM0533 = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM0533"
    QCOM050B = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM050B"
    QCOM058D = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM058D"
}

foreach ($key in $checks.Keys) {
    Write-Log ("AML contains {0}: {1}" -f $key, $checks[$key])
}

if (-not $checks.QCOM251B -or -not $checks.QCOM2533 -or -not $checks.QCOM250B -or -not $checks.QCOM258D -or
    $checks.QCOM051B -or $checks.QCOM0533 -or $checks.QCOM050B -or $checks.QCOM058D) {
    throw "Patched AML verification failed."
}

Write-Log "ACPI HID phase-4a source/AML patch is ready. Next step: rebuild Mu-alioth UEFI image."
