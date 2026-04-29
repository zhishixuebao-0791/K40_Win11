param(
    [string]$MuRoot,
    [switch]$NoCompile
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
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
    $searchRoots = @($repoRoot, (Get-Location).Path) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($searchRoot in $searchRoots) {
        $candidate = Get-ChildItem -LiteralPath $searchRoot -Directory -Recurse -Filter "Mu-Silicium" -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "Silicium-ACPI\Platforms\Xiaomi\alioth\DSDT.asl") } |
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

$dsdtAsl = Join-Path $MuRoot "Silicium-ACPI\Platforms\Xiaomi\alioth\DSDT.asl"
$dsdtAml = Join-Path $MuRoot "Silicium-ACPI\Platforms\Xiaomi\alioth\DSDT.aml"
$compiler = Join-Path $MuRoot "Silicium-ACPI\Compiler\asl.exe"
$logRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$compileLog = Join-Path $logRoot "acpi-hid-phase3-compile-$timestamp.log"
$backupPath = Join-Path (Split-Path -Parent $dsdtAsl) "DSDT.asl.pre-phase3-$timestamp.bak"

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if (-not (Test-Path -LiteralPath $dsdtAsl)) {
    throw "Alioth DSDT source not found: $dsdtAsl"
}

$content = Get-Content -LiteralPath $dsdtAsl -Raw
$originalContent = $content

$replacements = @(
    [pscustomobject]@{
        Device = "PILC"
        Native = 'Name(_HID, "QCOM051B")'
        Kona = 'Name(_HID, "QCOM251B")'
    },
    [pscustomobject]@{
        Device = "RPEN"
        Native = 'Name(_HID, "QCOM0533")'
        Kona = 'Name(_HID, "QCOM2533")'
    }
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
    QCOM051B = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM051B"
    QCOM0533 = Test-AsciiInFile -Path $dsdtAml -Needle "QCOM0533"
}

foreach ($key in $checks.Keys) {
    Write-Log ("AML contains {0}: {1}" -f $key, $checks[$key])
}

if (-not $checks.QCOM251B -or -not $checks.QCOM2533 -or $checks.QCOM051B -or $checks.QCOM0533) {
    throw "Patched AML verification failed."
}

Write-Log "ACPI HID phase-3 source/AML patch is ready. Next step: rebuild Mu-alioth UEFI image."
