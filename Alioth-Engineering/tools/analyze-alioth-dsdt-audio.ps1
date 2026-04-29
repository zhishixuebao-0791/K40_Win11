param(
    [string]$RawAcpiRoot = "D:\Code\REDMIK40_Win11\RawAcpiTables_20260423_161309",
    [string]$IaslPath,
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
}

function Find-DsdtBinary {
    param([string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        throw "Raw ACPI root not found: $Root"
    }

    $candidate = Get-ChildItem -LiteralPath $Root -Recurse -Filter "*.bin" -File |
        Where-Object { $_.FullName -match '\\DSDT\\' } |
        Sort-Object FullName |
        Select-Object -First 1

    if (-not $candidate) {
        throw "DSDT binary not found under: $Root"
    }

    return $candidate.FullName
}

function Get-LineContext {
    param(
        [string[]]$Lines,
        [string]$Pattern,
        [int]$Before = 8,
        [int]$After = 25
    )

    $hits = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) {
            $start = [Math]::Max(0, $i - $Before)
            $end = [Math]::Min($Lines.Count - 1, $i + $After)
            $block = for ($j = $start; $j -le $end; $j++) {
                "{0}: {1}" -f ($j + 1), $Lines[$j]
            }
            $hits += [pscustomobject]@{
                Pattern = $Pattern
                Line = $i + 1
                Context = ($block -join "`r`n")
            }
        }
    }

    return $hits
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

if (-not $IaslPath) {
    $IaslPath = Join-Path $repoRoot "tools\acpica\iasl.exe"
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot ("analysis\dsdt-audio-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
}

if (-not (Test-Path -LiteralPath $IaslPath)) {
    throw "iasl.exe not found: $IaslPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$dsdtBin = Find-DsdtBinary -Root $RawAcpiRoot
$amlPath = Join-Path $OutputDir "DSDT.aml"
$dslPath = Join-Path $OutputDir "DSDT.dsl"
$decompileLog = Join-Path $OutputDir "iasl-decompile.log"
$contextPath = Join-Path $OutputDir "audio-target-context.txt"
$reportPath = Join-Path $OutputDir "audio-dsdt-target-report.md"

Write-Log "Using DSDT binary: $dsdtBin"
Copy-Item -LiteralPath $dsdtBin -Destination $amlPath -Force

Write-Log "Decompiling DSDT with iasl."
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$iaslOutput = & $IaslPath -d $amlPath 2>&1
$iaslExitCode = $LASTEXITCODE
$ErrorActionPreference = $oldErrorActionPreference
$iaslOutput | Set-Content -Path $decompileLog -Encoding UTF8

if ($iaslExitCode -ne 0) {
    throw "iasl.exe failed with exit code $iaslExitCode. See: $decompileLog"
}

if (-not (Test-Path -LiteralPath $dslPath)) {
    throw "DSDT decompile did not produce: $dslPath"
}

$lines = Get-Content -LiteralPath $dslPath
$targets = @(
    @{ Name = "AUDS AudioService"; Pattern = 'Device \(AUDS\)|QCOM05D2'; ExpectedKonaId = 'ACPI\QCOM25D2' },
    @{ Name = "ADSP"; Pattern = 'Device \(ADSP\)|QCOM051D'; ExpectedKonaId = 'ADSP core dependency root' },
    @{ Name = "SLM1"; Pattern = 'Device \(SLM1\)'; ExpectedKonaId = 'SLM1\QCOM2524' },
    @{ Name = "ADCM"; Pattern = 'Device \(ADCM\)|ADCM\\\\QCOM0525'; ExpectedKonaId = 'ADCM\QCOM2525' },
    @{ Name = "AUDD"; Pattern = 'Device \(AUDD\)|AUDD\\\\QCOM052C|AUDD\\\\QCOM0537'; ExpectedKonaId = 'AUDD\QCOM252C / AUDD\QCOM2537' },
    @{ Name = "ADSPRPC"; Pattern = 'Device \(ARPC\)|QCOM0560'; ExpectedKonaId = 'ACPI\QCOM2560' },
    @{ Name = "ADSPRPCD"; Pattern = 'Device \(ARPD\)|QCOM058A'; ExpectedKonaId = 'ACPI\QCOM258A' },
    @{ Name = "FSA4480"; Pattern = 'FSA04480'; ExpectedKonaId = 'ACPI\FSA04480' }
)

$allContexts = @()
foreach ($target in $targets) {
    $contexts = @(Get-LineContext -Lines $lines -Pattern $target.Pattern)
    foreach ($context in $contexts) {
        $allContexts += [pscustomobject]@{
            Name = $target.Name
            ExpectedKonaId = $target.ExpectedKonaId
            Line = $context.Line
            Context = $context.Context
        }
    }
}

$contextText = foreach ($item in $allContexts) {
    "==== $($item.Name) | expected: $($item.ExpectedKonaId) | line $($item.Line) ===="
    $item.Context
    ""
}
$contextText | Set-Content -Path $contextPath -Encoding UTF8

$summaryRows = @(
    [pscustomobject]@{
        Target = "AUDS"
        DSDT = "Device(AUDS), _HID QCOM05D2, _UID 0"
        Status = "No _STA in device block; default is present/enabled if parent is active"
        Dependencies = "No _DEP"
        DriverGap = "Kona AudioService INF expects ACPI\QCOM25D2"
    },
    [pscustomobject]@{
        Target = "ADSP"
        DSDT = "Device(ADSP), _HID QCOM051D"
        Status = "_STA returns 0x0F"
        Dependencies = "_DEP: PEP0, PILC, GLNK, IPC0, RPEN, SSDD, ARPC"
        DriverGap = "Not hidden; dependent children use 05xx IDs"
    },
    [pscustomobject]@{
        Target = "SLM1"
        DSDT = "Device(SLM1) under ADSP"
        Status = "No _STA in device block"
        Dependencies = "No _DEP; has _CRS"
        DriverGap = "Kona ADCM INF expects SLM1\QCOM2524; no explicit QCOM0524 observed in DSDT"
    },
    [pscustomobject]@{
        Target = "ADCM"
        DSDT = "Device(ADCM), CHLD returns ADCM\QCOM0525"
        Status = "No _STA in device block"
        Dependencies = "_DEP: MMU0, IMM0"
        DriverGap = "Kona qcauddev INF expects ADCM\QCOM2525"
    },
    [pscustomobject]@{
        Target = "AUDD"
        DSDT = "Device(AUDD), CHLD returns AUDD\QCOM0537 and AUDD\QCOM052C"
        Status = "No _STA in device block"
        Dependencies = "No _DEP; has SPI4 _CRS"
        DriverGap = "Kona miniport/MBHC INFs expect AUDD\QCOM252C and AUDD\QCOM2537"
    },
    [pscustomobject]@{
        Target = "ARPC"
        DSDT = "Device(ARPC), _HID QCOM0560"
        Status = "No _STA in device block"
        Dependencies = "_DEP: MMU0, GLNK, SCM0"
        DriverGap = "Kona ADSPRPC INF expects ACPI\QCOM2560"
    },
    [pscustomobject]@{
        Target = "ARPD"
        DSDT = "Device(ARPD), _HID QCOM058A"
        Status = "No _STA in device block"
        Dependencies = "_DEP: ADSP, ARPC"
        DriverGap = "Kona ADSPRPCD INF expects ACPI\QCOM258A"
    },
    [pscustomobject]@{
        Target = "CFSA"
        DSDT = "Device(CFSA), _HID FSA04480"
        Status = "No _STA in device block"
        Dependencies = "No _DEP; _CRS references I2C5"
        DriverGap = "ID matches FSA4480 driver; prior runtime issue is dependency/I2C stack, not ID alias"
    }
)

$report = @()
$report += "# Alioth DSDT Audio Target Report"
$report += ""
$report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$report += "Raw ACPI root: ``$RawAcpiRoot``"
$report += "DSDT binary: ``$dsdtBin``"
$report += "Decompiled DSL: ``$dslPath``"
$report += "Context dump: ``$contextPath``"
$report += ""
$report += "## Result"
$report += ""
$report += "The current Mu-alioth DSDT does expose an audio topology to Windows. The important devices are not broadly hidden by _STA; the main mismatch is that this DSDT exposes Qualcomm audio child IDs in the 05xx family while the local Kona Windows audio INFs mostly match 25xx IDs."
$report += ""
$report += "Because the devices are present in DSDT and ADSP._STA returns 0x0F, the next low-risk direction is a narrow INF alias experiment. Do not pivot to Mu-Silicium ACPI edits yet, and do not broad-inject Kona/SOC/USBFn packages."
$report += ""
$report += "## Target Table"
$report += ""
$report += "| Target | DSDT evidence | _STA result | _DEP / dependency | Driver gap |"
$report += "| --- | --- | --- | --- | --- |"
foreach ($row in $summaryRows) {
    $report += "| $($row.Target) | $($row.DSDT) | $($row.Status) | $($row.Dependencies) | $($row.DriverGap) |"
}
$report += ""
$report += "## Narrow Alias Candidates"
$report += ""
$report += "| DSDT/runtime ID | Candidate source INF | Existing INF match | Experiment action |"
$report += "| --- | --- | --- | --- |"
$report += "| ACPI\QCOM05D2 | Drivers\Audio\Orientation\AudioService8250.inf | ACPI\QCOM25D2 | Add alias only in copied INF package |"
$report += "| ACPI\QCOM0560 | Drivers\Audio\RPC\ADSPRPC\qcadsprpc8250.inf | ACPI\QCOM2560 | Add alias only in copied INF package |"
$report += "| ACPI\QCOM058A | Drivers\Audio\RPC\ADSPRPCD\qcadsprpcd8250.inf | ACPI\QCOM258A | Add alias only in copied INF package |"
$report += "| ADCM\QCOM0525 | Drivers\Audio\Device\qcauddev8250.inf / Extensions\Audio\Device\qcauddev_ext8250.inf | ADCM\QCOM2525 | Add alias only after RPC/AudioService test |"
$report += "| AUDD\QCOM052C | Drivers\Audio\AudMiniport\qcaudminiport_Base8250.inf | AUDD\QCOM252C | Add alias only after ADCM appears stable |"
$report += "| AUDD\QCOM0537 | Drivers\Audio\Device\qcauddev8250.inf | AUDD\QCOM2537 | Add alias only after ADCM appears stable |"
$report += "| ACPI\FSA04480 | windows_qcom_platforms\components\ANYSOC\Hardware\HARDWARE.USB.FSA4480\fsa4480.inf | ACPI\FSA04480 | No alias needed; debug I2C5/dependency instead |"
$report += ""
$report += "## Decision"
$report += ""
$report += "Proceed with an extremely narrow INF alias package, staged and reversible. First pass should cover only `ACPI\QCOM05D2`, `ACPI\QCOM0560`, and `ACPI\QCOM058A`. Do not touch SOC, USBFn, PMIC, PCIe, storage, or broad Qualcomm class packages."
$report += ""
$report += "If the alias pass produces new ADCM/AUDD devices without boot regression, then test ADCM\QCOM0525, AUDD\QCOM052C, and AUDD\QCOM0537 in a second pass. If these nodes fail because _DEP objects are unavailable or drivers cannot start despite ID match, then pivot to Mu-Silicium aliothPkg/ACPI work."

$report | Set-Content -Path $reportPath -Encoding UTF8

Write-Log "Wrote context: $contextPath"
Write-Log "Wrote report: $reportPath"
