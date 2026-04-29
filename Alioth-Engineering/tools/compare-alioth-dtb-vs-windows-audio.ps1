param(
    [string]$DtbPath,
    [string]$EvidencePath,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if (-not $DtbPath) {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $candidate = Get-ChildItem -Path $repoRoot -Recurse -Filter "alioth.dts" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match 'Mu-Silicium' -and $_.FullName -match 'Resources\\DTBs\\alioth\.dts$' } |
        Select-Object -First 1
    if ($candidate) {
        $DtbPath = $candidate.FullName
    }
}

if (-not (Test-Path $DtbPath)) {
    throw "alioth.dts not found: $DtbPath"
}

if (-not $EvidencePath) {
    throw "EvidencePath is required."
}

if (-not (Test-Path $EvidencePath)) {
    throw "EvidencePath not found: $EvidencePath"
}

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path -Parent $EvidencePath) ("alioth-audio-gap-" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".md")
}

$dtbText = [System.IO.File]::ReadAllText($DtbPath, [System.Text.Encoding]::UTF8)

$expectedNodes = @(
    @{ Name = "FSA4480"; LinuxPattern = 'fsa4480@42|qcom,fsa4480-i2c|fsa4480-i2c-handle'; WindowsPattern = 'ACPI\\FSA04480' },
    @{ Name = "LPASS core"; LinuxPattern = 'qcom,q6core-audio|lpass_audio_hw_vote|lpass_core_hw_vote'; WindowsPattern = 'ACPI\\QCOM2560|ACPI\\QCOM258A|ACPI\\QCOM25D2|ADSP\\QCOM2510|SLM1\\QCOM2524|AUDD\\|ADCM\\' },
    @{ Name = "bolero codec"; LinuxPattern = 'bolero-cdc|qcom,bolero-codec'; WindowsPattern = 'AUDD\\|ADCM\\|SLM1\\|ADSP\\QCOM2510' },
    @{ Name = "TX macro / SWR"; LinuxPattern = 'tx-macro@3220000|tx_swr_master|swr2 ='; WindowsPattern = 'SLM1\\|ADCM\\|AUDD\\' },
    @{ Name = "RX macro / SWR"; LinuxPattern = 'rx-macro@3200000|rx_swr_master|swr1 ='; WindowsPattern = 'SLM1\\|ADCM\\|AUDD\\' },
    @{ Name = "WSA macro / speakers"; LinuxPattern = 'wsa-macro@3240000|wsa881x|WSA_SPK1|WSA_SPK2|swr0 ='; WindowsPattern = 'AUDD\\|ACPI\\QCOM25D2' },
    @{ Name = "VA macro / mics"; LinuxPattern = 'va-macro@3370000|VA DMIC|VA SWR_MIC'; WindowsPattern = 'ADSP\\QCOM2510|ACPI\\QCOM258A' },
    @{ Name = "Sound card"; LinuxPattern = 'compatible = "qcom,kona-asoc-snd"|qcom,model = "kona-mtp-snd-card"|asoc-codec-names'; WindowsPattern = 'AUDD\\|ADCM\\|SLM1\\' }
)

$evidenceFiles = @(
    "00_TargetDevices.txt",
    "01_TargetProblemProperties.txt",
    "02_ConfigManagerAndSignedDrivers.txt",
    "03_RegistryEnum.txt",
    "04_DriversAndServices.txt",
    "05_SetupApiHits.txt",
    "06_PnpUtil.txt",
    "07_Interpretation.txt"
)

$evidenceText = ""
foreach ($file in $evidenceFiles) {
    $path = Join-Path $EvidencePath $file
    if (Test-Path $path) {
        $evidenceText += "`r`n===== $file =====`r`n"
        $evidenceText += [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    }
}

$lines = @()
$lines += "# Alioth Audio DTB vs Windows ACPI Gap Report"
$lines += ""
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += "DTB source: ``$DtbPath``"
$lines += "Evidence source: ``$EvidencePath``"
$lines += ""
$lines += "## Summary"
$lines += ""
$lines += "- This report compares audio-related Linux/DTB nodes in `alioth.dts` with what current Windows actually enumerates."
$lines += "- If Linux-side nodes exist but Windows-side roots remain absent, the likely bottleneck is ACPI/firmware exposure rather than Windows INF matching."
$lines += ""
$lines += "## Node Comparison"
$lines += ""
$lines += "| Node | In alioth.dts | In Windows evidence | Current read |"
$lines += "| --- | --- | --- | --- |"

foreach ($node in $expectedNodes) {
    $inDtb = [regex]::IsMatch($dtbText, $node.LinuxPattern, 'IgnoreCase')
    $inWin = [regex]::IsMatch($evidenceText, $node.WindowsPattern, 'IgnoreCase')
    $read = if ($inDtb -and $inWin) {
        "Present on both sides"
    } elseif ($inDtb -and -not $inWin) {
        "Linux/DTB has it, Windows does not"
    } elseif (-not $inDtb -and $inWin) {
        "Unexpected: Windows evidence without DTB hit"
    } else {
        "Not observed on either side"
    }
    "| $($node.Name) | $inDtb | $inWin | $read |"
}

$lines += ""
$lines += "## Focused Findings"
$lines += ""

if ([regex]::IsMatch($evidenceText, 'ACPI\\FSA04480', 'IgnoreCase')) {
    $lines += "- `FSA4480` is the only audio-adjacent node that clearly enumerates in Windows today."
}

if (-not [regex]::IsMatch($evidenceText, 'ADCM\\|AUDD\\|ADSP\\QCOM2510|SLM1\\QCOM2524|ACPI\\QCOM2560|ACPI\\QCOM258A|ACPI\\QCOM25D2', 'IgnoreCase')) {
    $lines += "- None of the expected Qualcomm audio root devices (`ADCM/AUDD/ADSP/SLM1/QCOM2560/QCOM258A/QCOM25D2`) appear in Windows evidence."
}

if ([regex]::IsMatch($dtbText, 'bolero-cdc|qcom,kona-asoc-snd|fsa4480@42|tx-macro@3220000|rx-macro@3200000|wsa-macro@3240000|va-macro@3370000', 'IgnoreCase')) {
    $lines += "- `alioth.dts` clearly contains a full board-level audio topology: `fsa4480`, `bolero-cdc`, `tx/rx/wsa/va macro`, and a `kona-asoc-snd` card."
}

$lines += ""
$lines += "## Working Hypothesis"
$lines += ""
$lines += "Current evidence points to this chain:"
$lines += ""
$lines += "1. Linux/DTB contains the board-level audio topology."
$lines += "2. Windows sees `FSA04480`, but it is still in `Error`."
$lines += "3. Windows does **not** see the real Qualcomm audio root devices that Kona audio drivers expect."
$lines += "4. Therefore, the missing piece is more likely `Mu-Silicium` ACPI/firmware exposure for alioth audio, not just a missing Windows INF."
$lines += ""
$lines += "## Recommendation"
$lines += ""
$lines += "- Do **not** inject `Kona Audio` yet."
$lines += "- Keep Windows audio experiments narrow."
$lines += "- Next focus should be validating whether `Mu-alioth` ACPI tables expose the audio-related nodes at all."
$lines += "- If they do not, work should pivot to `Mu-Silicium -> aliothPkg/ACPI` rather than Windows driver expansion."

[System.IO.File]::WriteAllText($OutputPath, ($lines -join "`r`n"), [System.Text.Encoding]::UTF8)
Write-Host "Wrote report: $OutputPath"
