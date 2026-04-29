param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "AudioAliasState_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Write-Section {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    $path = Join-Path $outDir ($Name + ".txt")
    "==== $Name ====" | Set-Content -Path $path -Encoding UTF8
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -Path $path -Encoding UTF8
    "" | Add-Content -Path $path -Encoding UTF8
    try {
        & $Script | Out-String -Width 4096 | Add-Content -Path $path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Add-Content -Path $path -Encoding UTF8
    }
}

$ids = @(
    'QCOM05D2', 'QCOM25D2',
    'QCOM051D', 'QCOM251D',
    'QCOM0560', 'QCOM2560',
    'QCOM058A', 'QCOM258A',
    'QCOM2510',
    'QCOM0524', 'QCOM2524',
    'QCOM0525', 'QCOM2525',
    'QCOM052C', 'QCOM252C',
    'QCOM0537', 'QCOM2537',
    'FSA04480'
)

$pattern = ($ids | ForEach-Object { [regex]::Escape($_) }) -join '|'
$allPnp = @(Get-PnpDevice -ErrorAction SilentlyContinue)

Write-Section -Name "00_QcomAudioAliasPnp" -Script {
    $allPnp |
        Where-Object { $_.InstanceId -match $pattern -or $_.FriendlyName -match 'Audio|Aqstic|FastRPC|RPC|Slimbus|FSA4480|ADSP|Qualcomm' } |
        Sort-Object Class, FriendlyName, InstanceId |
        Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
}

Write-Section -Name "01_QcomAudioAliasProperties" -Script {
    $targets = $allPnp | Where-Object { $_.InstanceId -match $pattern -or $_.FriendlyName -match 'Audio|Aqstic|FastRPC|RPC|Slimbus|FSA4480|ADSP|Qualcomm' }
    foreach ($target in $targets) {
        "## $($target.InstanceId)"
        "FriendlyName: $($target.FriendlyName)"
        "Class: $($target.Class)"
        "Status: $($target.Status)"
        foreach ($key in @(
            'DEVPKEY_Device_ProblemCode',
            'DEVPKEY_Device_ProblemStatus',
            'DEVPKEY_Device_Service',
            'DEVPKEY_Device_MatchingDeviceId',
            'DEVPKEY_Device_CompatibleIds',
            'DEVPKEY_Device_DriverInfPath',
            'DEVPKEY_Device_DriverProvider',
            'DEVPKEY_Device_DriverVersion'
        )) {
            try {
                $prop = Get-PnpDeviceProperty -InstanceId $target.InstanceId -KeyName $key -ErrorAction Stop
                "{0}: {1}" -f $key, $prop.Data
            } catch {
                "{0}: <missing>" -f $key
            }
        }
        ""
    }
}

Write-Section -Name "02_RegistryEnumExact" -Script {
    foreach ($root in @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADSP',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SLM1',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADCM',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\AUDD'
    )) {
        "## $root"
        if (Test-Path $root) {
            Get-ChildItem $root -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match $pattern } |
                Select-Object PSChildName, Name
        } else {
            "Not found"
        }
        ""
    }
}

Write-Section -Name "03_RelatedServices" -Script {
    Get-CimInstance Win32_SystemDriver |
        Where-Object { $_.Name -match 'qcsubsys|qcadsprpc|qcadsprpcd|qcslimbus|qcadcm|qcaud|fsa4480|AudioService' -or $_.DisplayName -match 'Aqstic|Audio|FastRPC|Subsystem|Slimbus|FSA4480' } |
        Sort-Object Name |
        Select-Object Name, State, StartMode, PathName, DisplayName
}

Write-Section -Name "04_DriverStoreRelated" -Script {
    Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'qcsubsys|qcadsprpc|qcadsprpcd|qcslimbus|qcadcm|qcaud|audioservice|fsa4480' } |
        Sort-Object Name |
        Select-Object Name, FullName
}

Write-Section -Name "05_SetupApiAliasHits" -Script {
    $log = 'C:\Windows\INF\setupapi.dev.log'
    if (Test-Path $log) {
        Select-String -Path $log -Pattern ($pattern + '|qcsubsys|qcadsprpc|qcadsprpcd|AudioService|Slimbus|Aqstic') -CaseSensitive:$false |
            Select-Object -Last 800
    } else {
        "setupapi.dev.log not found"
    }
}

"Output directory: $outDir" | Set-Content -Path (Join-Path $outDir "README.txt") -Encoding UTF8
"Done. Audio alias state saved to: $outDir" | Write-Output
