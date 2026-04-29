param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "AudioRootCause_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$targets = @(
    '^ACPI\\FSA04480',
    '^SLM1\\QCOM2524',
    '^ADCM\\',
    '^AUDD\\',
    '^ADSP\\QCOM2510',
    '^ACPI\\QCOM2560$',
    '^ACPI\\QCOM258A$',
    '^ACPI\\QCOM25D2$',
    '^ACPI\\VEN_QCOM&DEV_25'
)

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

function Get-MatchingPnp {
    $all = Get-PnpDevice -ErrorAction SilentlyContinue
    $all | Where-Object {
        $id = $_.InstanceId
        foreach ($pattern in $targets) {
            if ($id -match $pattern) { return $true }
        }
        return $false
    }
}

$matches = @(Get-MatchingPnp)

Write-Section -Name "00_TargetDevices" -Script {
    $matches | Sort-Object Class, FriendlyName, InstanceId |
        Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
}

Write-Section -Name "01_TargetProblemProperties" -Script {
    foreach ($dev in $matches) {
        "## $($dev.InstanceId)"
        "FriendlyName: $($dev.FriendlyName)"
        "Class: $($dev.Class)"
        "Status: $($dev.Status)"
        foreach ($key in @(
            'DEVPKEY_Device_ProblemCode',
            'DEVPKEY_Device_ProblemStatus',
            'DEVPKEY_Device_Driver',
            'DEVPKEY_Device_Service',
            'DEVPKEY_Device_ClassGuid',
            'DEVPKEY_Device_Manufacturer',
            'DEVPKEY_Device_MatchingDeviceId',
            'DEVPKEY_Device_CompatibleIds',
            'DEVPKEY_Device_DriverVersion',
            'DEVPKEY_Device_DriverProvider'
        )) {
            try {
                $prop = Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName $key -ErrorAction Stop
                "{0}: {1}" -f $key, $prop.Data
            } catch {
                "{0}: <not available>" -f $key
            }
        }
        ""
    }
}

Write-Section -Name "02_ConfigManagerAndSignedDrivers" -Script {
    foreach ($dev in $matches) {
        "## $($dev.InstanceId)"
        $signed = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.DeviceID -eq $dev.InstanceId }
        if ($signed) {
            $signed | Select-Object DeviceName, DeviceClass, DriverName, InfName, DriverProviderName, DriverVersion, IsSigned
        } else {
            "No Win32_PnPSignedDriver entry"
        }
        ""
    }
}

Write-Section -Name "03_SetupApi_TargetMatches" -Script {
    $log = 'C:\Windows\INF\setupapi.dev.log'
    if (Test-Path $log) {
        Select-String -Path $log -Pattern 'FSA04480|fsa4480|QCOM2524|ADCM|AUDD|ADSP|QCOM2560|QCOM258A|QCOM25D2|QCOM25' -CaseSensitive:$false |
            Select-Object -Last 800
    } else {
        "setupapi.dev.log not found"
    }
}

Write-Section -Name "04_ServicesAndFiles" -Script {
    Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'fsa4480|qcaud|qcadcm|qcslim|adsp|audio' } |
        Sort-Object Name |
        Select-Object Name, State, StartMode, PathName, DisplayName
    ""
    "DriverStore candidates:"
    Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'fsa4480|qcaud|qcadcm|qcslim|adsp|audio' } |
        Select-Object Name, FullName
}

Write-Section -Name "05_Registry_EnumTargets" -Script {
    foreach ($root in @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADCM',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\AUDD',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADSP',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SLM1'
    )) {
        "## $root"
        if (Test-Path $root) {
            Get-ChildItem $root -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.PSChildName -match '^FSA04480$|^QCOM25|^VEN_QCOM&DEV_25|^ADCM|^AUDD|^ADSP|^QCOM2524'
                } |
                Select-Object PSChildName, Name
        } else {
            "Not found"
        }
        ""
    }
}

"Output directory: $outDir" | Set-Content -Path (Join-Path $outDir "README.txt") -Encoding UTF8
"Done. Audio root cause trace saved to: $outDir" | Write-Output
