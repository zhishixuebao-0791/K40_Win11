param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [string]$PolicyId = "86B04D39-E928-4F0F-937E-0F44B0909E79",
    [int]$MaxEvents = 500
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "WdacPolicyLoadState_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Write-Summary {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
}

function Save-Text {
    param(
        [string]$Name,
        [scriptblock]$Command
    )
    $path = Join-Path $outDir $Name
    try {
        & $Command *>&1 | Out-String -Width 8192 | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Try-CommandText {
    param(
        [string]$Title,
        [scriptblock]$Command
    )
    "==== $Title ===="
    try {
        & $Command *>&1 | Out-String -Width 8192
    } catch {
        "ERROR: $($_.Exception.Message)"
    }
}

Write-Summary "WDAC policy load trace started."
Write-Summary "Output: $outDir"
Write-Summary "Target policy id: $PolicyId"

$activeDir = Join-Path $env:SystemRoot "System32\CodeIntegrity\CiPolicies\Active"
$targetPolicyPath = Join-Path $activeDir ("{" + $PolicyId.Trim("{}") + "}.cip")

Save-Text "01_ActivePolicies.txt" {
    "SystemRoot: $env:SystemRoot"
    "ActiveDir: $activeDir"
    "TargetPolicyPath: $targetPolicyPath"
    "TargetPolicyExists: $(Test-Path -LiteralPath $targetPolicyPath)"
    if (Test-Path -LiteralPath $activeDir) {
        Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Select-Object Name, FullName, Length, LastWriteTime,
                @{Name="SHA256";Expression={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}} |
            Format-List
    } else {
        "Active policy directory not found."
    }
}

Save-Text "02_CiTool.txt" {
    $candidates = @(
        (Join-Path $env:SystemRoot "System32\CiTool.exe"),
        (Join-Path $env:SystemRoot "Sysnative\CiTool.exe"),
        "citool.exe"
    )

    foreach ($candidate in $candidates) {
        "Candidate: $candidate"
        try {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd) {
                "Resolved: $($cmd.Source)"
                Try-CommandText "citool -?" { & $cmd.Source -? }
                Try-CommandText "citool --help" { & $cmd.Source --help }
                Try-CommandText "citool -lp" { & $cmd.Source -lp }
                Try-CommandText "citool --list-policies" { & $cmd.Source --list-policies }
                Try-CommandText "citool -json -lp" { & $cmd.Source -json -lp }
                break
            }
        } catch {
            "ERROR: $($_.Exception.Message)"
        }
    }
}

Save-Text "03_CodeIntegrityPolicyEvents.txt" {
    $pattern = "Policy|$($PolicyId.Trim('{}'))|d2bda982|Driver Policy|Code Integrity|Status|supplement|Supplement|CIP|CiPolicies|activated|refreshed|failed|invalid|0x"
    Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $pattern -or $_.Id -in 3076,3077,3085,3089,3091,3095,3096,3099 } |
        Select-Object TimeCreated, Id, RecordId, LevelDisplayName, Message |
        Format-List
}

Save-Text "04_CodeIntegrityPolicyEventsXml.txt" {
    $pattern = "Policy|$($PolicyId.Trim('{}'))|d2bda982|Driver Policy|Code Integrity|Status|supplement|Supplement|CIP|CiPolicies|activated|refreshed|failed|invalid|0x"
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match $pattern -or $_.Id -in 3076,3077,3085,3089,3091,3095,3096,3099 }

    foreach ($event in $events) {
        "==== RecordId=$($event.RecordId) Id=$($event.Id) Time=$($event.TimeCreated) ===="
        $event.ToXml()
    }
}

Save-Text "05_CiRegistryAndDeviceGuard.txt" {
    Try-CommandText "CI registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI" /s }
    Try-CommandText "DeviceGuard SYSTEM registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /s }
    Try-CommandText "DeviceGuard policy registry" { reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /s }
    Try-CommandText "bcdedit current" { bcdedit /enum "{current}" }
    Try-CommandText "bcdedit all" { bcdedit /enum all }
}

Save-Text "06_QcsubsysState.txt" {
    Try-CommandText "pnputil QCOM2522" {
        pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers
    }
    Try-CommandText "Get-PnpDevice QCOM2522" {
        Get-PnpDevice -InstanceId "ACPI\QCOM2522\2&DABA3FF&0" -ErrorAction SilentlyContinue | Format-List *
    }
    Try-CommandText "Latest qcsubsys CI events" {
        Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "qcsubsys8250.sys|QCOM2522|hash could not be found|C0000428" } |
            Select-Object TimeCreated, Id, RecordId, LevelDisplayName, Message |
            Format-List
    }
}

Save-Text "07_AutoVerdict.txt" {
    $activeExists = Test-Path -LiteralPath $targetPolicyPath
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    $targetPolicyEvents = $events | Where-Object { $_.Message -match [regex]::Escape($PolicyId.Trim("{}")) }
    $baseEvents = $events | Where-Object { $_.Message -match "d2bda982-ccf6-4344-ac5b-0b44427b6816|Microsoft Windows Driver Policy" }
    $qcsubsysBlock = $events | Where-Object { $_.Message -match "qcsubsys8250.sys.*hash could not be found|hash could not be found.*qcsubsys8250.sys" }
    $pnp = pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers 2>&1 | Out-String

    "TargetPolicyExists=$activeExists"
    "TargetPolicyEvents=$($targetPolicyEvents.Count)"
    "BasePolicyEvents=$($baseEvents.Count)"
    "QcsubsysHashMissingEvents=$($qcsubsysBlock.Count)"
    "Qcom2522Code52=$([bool]($pnp -match '52|CM_PROB_UNSIGNED_DRIVER'))"

    if ($activeExists -and $targetPolicyEvents.Count -eq 0 -and $qcsubsysBlock.Count -gt 0) {
        "Verdict=Supplemental qcsubsys WDAC CIP exists on disk, but current Code Integrity events do not show it being loaded or used."
        "SuggestedNext=Do not keep editing INF. Determine whether this image requires signed supplemental policies or a base-policy merge path."
    } elseif ($activeExists -and $targetPolicyEvents.Count -gt 0 -and $qcsubsysBlock.Count -gt 0) {
        "Verdict=Supplemental policy appears in CI events but does not satisfy qcsubsys. Inspect policy format/hash rule coverage."
        "SuggestedNext=Regenerate with signer/certificate rule or merge hash rule into the active base policy candidate."
    } elseif ($activeExists -and $qcsubsysBlock.Count -eq 0) {
        "Verdict=No recent qcsubsys CI hash-missing block was found. Check QCOM2522 PnP status for the next dependency failure."
        "SuggestedNext=Continue with PILC/ADSP dependency chain."
    } else {
        "Verdict=Target policy is not present or evidence is incomplete."
        "SuggestedNext=Re-apply policy or collect logs immediately after boot."
    }
}

Write-Summary "Collection completed: $outDir"
Write-Host "WDAC policy load trace completed: $outDir"
