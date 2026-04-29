param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$stamp] $Message"
}

function Save-Text {
    param(
        [string]$Path,
        [string]$Text
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.Encoding]::UTF8)
}

function Run-And-Save {
    param(
        [string]$Title,
        [string]$Path,
        [scriptblock]$Script
    )

    Write-Log $Title
    try {
        $content = & $Script | Out-String -Width 500
    } catch {
        $content = "ERROR:`r`n$($_ | Out-String)"
    }
    Save-Text -Path $Path -Text $content
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "AcpiAudioEvidence_$timestamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$targets = @(
    "ACPI\FSA04480",
    "ACPI\QCOM2560",
    "ACPI\QCOM258A",
    "ACPI\QCOM25D2",
    "ADSP\QCOM2510",
    "SLM1\QCOM2524",
    "AUDD\VEN_QCOM&DEV_252C&SUBSYS_MTP08250",
    "ADCM\QCOM2525"
)

Run-And-Save -Title "Summary" -Path (Join-Path $outDir "00_Summary.txt") -Script {
    $lines = @()
    $lines += "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "ComputerName: $env:COMPUTERNAME"
    $lines += "UserName: $env:USERNAME"
    $lines += ""
    $lines += "Targets:"
    $lines += $targets
    $lines += ""
    $lines += "Sound devices:"
    try {
        $snd = Get-CimInstance Win32_SoundDevice | Select-Object Name, Manufacturer, Status, PNPDeviceID
        if ($snd) { $lines += ($snd | Format-Table -AutoSize | Out-String -Width 500) } else { $lines += "None" }
    } catch {
        $lines += "Failed to query Win32_SoundDevice"
    }
    $lines -join "`r`n"
}

Run-And-Save -Title "PnP full snapshot for audio-related classes" -Path (Join-Path $outDir "01_Pnp_AudioRelated.txt") -Script {
    Get-PnpDevice |
        Where-Object {
            $_.InstanceId -match '^ACPI\\' -or
            $_.InstanceId -match '^ADSP\\' -or
            $_.InstanceId -match '^ADCM\\' -or
            $_.InstanceId -match '^AUDD\\' -or
            $_.InstanceId -match '^SLM1\\' -or
            $_.Class -in @('MEDIA','AudioEndpoint','USBDevice','SoftwareComponent')
        } |
        Sort-Object Class, InstanceId |
        Select-Object Class, FriendlyName, InstanceId, Status, Problem, Present
}

Run-And-Save -Title "Target device properties" -Path (Join-Path $outDir "02_TargetProperties.txt") -Script {
    $props = @(
        'DEVPKEY_Device_ProblemCode',
        'DEVPKEY_Device_ProblemStatus',
        'DEVPKEY_Device_Service',
        'DEVPKEY_Device_MatchingDeviceId',
        'DEVPKEY_Device_CompatibleIds',
        'DEVPKEY_Device_DriverVersion',
        'DEVPKEY_Device_DriverProvider',
        'DEVPKEY_Device_DriverInfPath',
        'DEVPKEY_Device_Class',
        'DEVPKEY_Device_ClassGuid',
        'DEVPKEY_Device_Manufacturer'
    )

    foreach ($target in $targets) {
        "## $target"
        $devices = Get-PnpDevice | Where-Object { $_.InstanceId -like "$target*" }
        if (-not $devices) {
            "Not present"
            ""
            continue
        }
        foreach ($dev in $devices) {
            "FriendlyName: $($dev.FriendlyName)"
            "InstanceId: $($dev.InstanceId)"
            "Status: $($dev.Status)"
            "Problem: $($dev.Problem)"
            foreach ($prop in $props) {
                try {
                    $value = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName $prop -ErrorAction Stop
                    "${prop}: $($value.Data)"
                } catch {
                    "${prop}: <missing>"
                }
            }
            ""
        }
    }
}

Run-And-Save -Title "Registry enum targets" -Path (Join-Path $outDir "03_RegistryEnum.txt") -Script {
    $roots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADSP',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADCM',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\AUDD',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SLM1'
    )

    foreach ($root in $roots) {
        "## $root"
        if (Test-Path $root) {
            Get-ChildItem -LiteralPath $root |
                Select-Object PSChildName, Name |
                Format-Table -AutoSize
        } else {
            "Not found"
        }
        ""
    }
}

Run-And-Save -Title "Signed drivers and services" -Path (Join-Path $outDir "04_DriversAndServices.txt") -Script {
    $targetsRegex = 'fsa4480|qcadcm|qcauddev|qcslimbus|qcadsprpc|AudioService|usbaudio|hdaudio'
    "## Win32_PnPSignedDriver"
    Get-CimInstance Win32_PnPSignedDriver |
        Where-Object {
            $_.DriverName -match $targetsRegex -or
            $_.DeviceName -match 'Audio|FSA4480|Qualcomm'
        } |
        Sort-Object DeviceName |
        Select-Object DeviceName, DriverProviderName, DriverVersion, InfName, IsSigned

    ""
    "## Services"
    Get-CimInstance Win32_Service |
        Where-Object { $_.Name -match $targetsRegex } |
        Sort-Object Name |
        Select-Object Name, State, StartMode, PathName, DisplayName
}

Run-And-Save -Title "SetupAPI log hits" -Path (Join-Path $outDir "05_SetupApiHits.txt") -Script {
    $logPath = Join-Path $env:windir 'INF\setupapi.dev.log'
    if (-not (Test-Path $logPath)) {
        "setupapi.dev.log not found"
        return
    }

    Select-String -Path $logPath -Pattern 'FSA04480|QCOM2560|QCOM258A|QCOM25D2|QCOM2510|QCOM2524|QCOM252C|ADCM|AUDD|SLM1|fsa4480|qcadcm|qcauddev|qcslimbus|qcadsprpc|AudioService' |
        Select-Object LineNumber, Line
}

Run-And-Save -Title "PnPUtil snapshots" -Path (Join-Path $outDir "06_PnpUtil.txt") -Script {
    $cmds = @(
        'pnputil /enum-devices /class MEDIA',
        'pnputil /enum-devices /class AudioEndpoint',
        'pnputil /enum-devices /problem',
        'pnputil /enum-drivers'
    )
    foreach ($cmd in $cmds) {
        "## $cmd"
        cmd /c $cmd 2>&1
        ""
    }
}

Run-And-Save -Title "Interpretation" -Path (Join-Path $outDir "07_Interpretation.txt") -Script {
    $lines = @()
    $lines += "Initial interpretation:"
    $lines += "- If FSA04480 is present with Status=Error, FSA4480 is no longer missing but still not starting cleanly."
    $lines += "- If ADCM/AUDD/ADSP/SLM1/QCOM2560/QCOM258A/QCOM25D2 remain absent, the bottleneck is likely ACPI/firmware exposure rather than simple Windows INF absence."
    $lines += "- This package is meant to be compared with alioth.dts on the host."
    $lines -join "`r`n"
}

Write-Log "ACPI audio evidence exported to: $outDir"
