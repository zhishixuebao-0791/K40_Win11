param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    }
}

function Get-RegistryChildNameSafe {
    param([string]$Name)
    return (($Name -replace '[\\/:*?"<>|]', '_').Trim())
}

function Get-ValueBytes {
    param(
        [Microsoft.Win32.RegistryKey]$Key,
        [string]$ValueName
    )
    return [byte[]]$Key.GetValue($ValueName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
}

function Save-RegistryTree {
    param(
        [Microsoft.Win32.RegistryKey]$Key,
        [string]$RelativePath,
        [string]$BaseDir
    )

    $safeDir = Join-Path $BaseDir $RelativePath
    New-Item -ItemType Directory -Path $safeDir -Force | Out-Null

    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add("Key: $($Key.Name)")

    foreach ($valueName in $Key.GetValueNames()) {
        $displayName = if ([string]::IsNullOrEmpty($valueName)) { "(Default)" } else { $valueName }
        $kind = $Key.GetValueKind($valueName)
        $summary.Add("Value: $displayName [$kind]")

        $bytes = Get-ValueBytes -Key $Key -ValueName $valueName
        if ($bytes -and $bytes.Length -gt 0) {
            $safeName = Get-RegistryChildNameSafe $displayName
            $binPath = Join-Path $safeDir ($safeName + ".bin")
            [System.IO.File]::WriteAllBytes($binPath, $bytes)
            $summary.Add("SavedBinary: $(Split-Path $binPath -Leaf) ($($bytes.Length) bytes)")
        }
    }

    Set-Content -LiteralPath (Join-Path $safeDir "_key.txt") -Value $summary -Encoding UTF8

    foreach ($subKeyName in $Key.GetSubKeyNames()) {
        $subKey = $Key.OpenSubKey($subKeyName)
        if ($null -ne $subKey) {
            try {
                Save-RegistryTree -Key $subKey -RelativePath (Join-Path $RelativePath (Get-RegistryChildNameSafe $subKeyName)) -BaseDir $BaseDir
            } finally {
                $subKey.Close()
            }
        }
    }
}

function Find-NeedlesInBinaries {
    param(
        [string]$BaseDir,
        [string[]]$Needles
    )

    $results = New-Object System.Collections.Generic.List[string]
    $binFiles = Get-ChildItem -LiteralPath $BaseDir -Recurse -Filter *.bin -File -ErrorAction SilentlyContinue
    foreach ($file in $binFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        $unicode = [System.Text.Encoding]::Unicode.GetString($bytes)
        foreach ($needle in $Needles) {
            if ($ascii -match [regex]::Escape($needle) -or $unicode -match [regex]::Escape($needle)) {
                $results.Add(("{0}: {1}" -f $file.FullName, $needle))
            }
        }
    }

    if ($results.Count -eq 0) {
        $results.Add("No target strings found in exported ACPI binaries.")
    }

    return $results
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot ("RawAcpiTables_{0}" -f $timestamp)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$script:LogPath = Join-Path $outDir "00_Log.txt"
Write-Log "Exporting raw ACPI registry-backed tables to $outDir"

$hardwareAcpi = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("HARDWARE\ACPI")
if ($null -eq $hardwareAcpi) {
    throw "HKLM\HARDWARE\ACPI not found."
}

try {
    $rootSummary = New-Object System.Collections.Generic.List[string]
    $rootSummary.Add("HKLM\\HARDWARE\\ACPI child keys:")
    foreach ($name in $hardwareAcpi.GetSubKeyNames()) {
        $rootSummary.Add($name)
    }
    Set-Content -LiteralPath (Join-Path $outDir "01_AcpiRootKeys.txt") -Value $rootSummary -Encoding UTF8

    foreach ($topKeyName in $hardwareAcpi.GetSubKeyNames()) {
        $topKey = $hardwareAcpi.OpenSubKey($topKeyName)
        if ($null -ne $topKey) {
            try {
                Write-Log "Saving ACPI subtree $topKeyName"
                Save-RegistryTree -Key $topKey -RelativePath (Get-RegistryChildNameSafe $topKeyName) -BaseDir $outDir
            } finally {
                $topKey.Close()
            }
        }
    }
} finally {
    $hardwareAcpi.Close()
}

$interestingStrings = @(
    "FSA04480",
    "QCOM05D2",
    "QCOM25D2",
    "QCOM2560",
    "QCOM258A",
    "QCOM2524",
    "QCOM2525",
    "QCOM252C",
    "QCOM2510",
    "ADCM",
    "AUDD",
    "ADSP",
    "SLM1",
    "bolero",
    "lpass",
    "swr",
    "kona-asoc-snd",
    "msm-audio-apr",
    "fsa4480"
)

$needleResults = Find-NeedlesInBinaries -BaseDir $outDir -Needles $interestingStrings
Set-Content -LiteralPath (Join-Path $outDir "02_StringHits.txt") -Value $needleResults -Encoding UTF8

Write-Log "Raw ACPI export completed."
Write-Host $outDir
