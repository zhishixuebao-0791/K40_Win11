param(
    [string]$MuRoot,
    [string]$OutputDir,
    [switch]$Clean,
    [switch]$SetupApt
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
}

function Quote-Bash {
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($MuRoot)) { $MuRoot = $null }
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = $null }

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

if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot "UEFI-Images"
}

if (-not $MuRoot -or -not (Test-Path -LiteralPath $MuRoot)) {
    throw "Mu-Silicium root not found: $MuRoot"
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    throw "wsl.exe was not found. Install WSL with Ubuntu 24.04 first, then rerun this script."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$wslMuRoot = (& wsl.exe wslpath -a "$MuRoot").Trim()
if (-not $wslMuRoot) {
    throw "Failed to convert MuRoot to WSL path: $MuRoot"
}

$buildArgs = "-d alioth -m 1 -i"
if ($Clean) {
    $buildArgs += " -c"
}

$commands = @(
    "set -e",
    "cd $(Quote-Bash $wslMuRoot)",
    "git submodule update --init --recursive",
    "./Silicium-ACPI/Compiler/asl.exe ./Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.asl >/tmp/alioth-acpi-phase3-asl.log",
    "grep -a QCOM251B ./Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.aml >/dev/null",
    "grep -a QCOM2533 ./Silicium-ACPI/Platforms/Xiaomi/alioth/DSDT.aml >/dev/null"
)

if ($SetupApt) {
    $commands += "./setup_env.sh -p apt"
}

$commands += "./build_uefi.sh $buildArgs"

$bashCommand = $commands -join " && "
Write-Log "Running WSL build for alioth model 1."
& wsl.exe bash -lc $bashCommand
if ($LASTEXITCODE -ne 0) {
    throw "WSL build failed with exit code $LASTEXITCODE."
}

$builtImage = Join-Path $MuRoot "Mu-alioth-1.img"
if (-not (Test-Path -LiteralPath $builtImage)) {
    throw "Expected build output not found: $builtImage"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = Join-Path $OutputDir "Mu-alioth-1-acpi-hid-phase3-$timestamp.img"
Copy-Item -LiteralPath $builtImage -Destination $dest -Force

Write-Log "Copied patched UEFI image to: $dest"
Write-Log "Test with fastboot boot first. Do not flash persistently until boot behavior is confirmed."
