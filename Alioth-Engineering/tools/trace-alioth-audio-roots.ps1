param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "AudioRootTrace_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$expectedRoots = @(
    [pscustomobject]@{ Name = "FSA4480"; Pattern = '^ACPI\\FSA04480'; Why = "Type-C analog audio switch candidate" },
    [pscustomobject]@{ Name = "ADCM root"; Pattern = '^SLM1\\QCOM2524|^ADCM\\'; Why = "Audio DSP and calibration manager entry" },
    [pscustomobject]@{ Name = "AUDD root"; Pattern = '^AUDD\\'; Why = "Audio device / MBHC entry" },
    [pscustomobject]@{ Name = "ADSP Slimbus"; Pattern = '^ADSP\\QCOM2510'; Why = "Slimbus audio root" },
    [pscustomobject]@{ Name = "ADSPRPC"; Pattern = '^ACPI\\QCOM2560$|^ACPI\\VEN_QCOM&DEV_2560'; Why = "ADSP RPC endpoint expected by Kona audio" },
    [pscustomobject]@{ Name = "ADSPRPCD"; Pattern = '^ACPI\\QCOM258A$|^ACPI\\VEN_QCOM&DEV_258A'; Why = "ADSP RPCD endpoint expected by Kona audio" },
    [pscustomobject]@{ Name = "AudioService"; Pattern = '^ACPI\\QCOM25D2$|^ACPI\\VEN_QCOM&DEV_25D2'; Why = "Audio orientation/service companion endpoint" }
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

$allPnp = @(Get-PnpDevice -ErrorAction SilentlyContinue)
$allSignedDrivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
$problemPnp = $allPnp | Where-Object { $_.Status -ne 'OK' }
$audioLikePnp = $allPnp | Where-Object {
    $_.InstanceId -match '^ACPI\\FSA04480|^SLM1\\QCOM2524|^ADCM\\|^AUDD\\|^ADSP\\QCOM2510|^ACPI\\QCOM25|^ACPI\\VEN_QCOM&DEV_25' -or
    $_.FriendlyName -match 'Audio|音频|Speaker|Microphone|耳机|麦克风|Endpoint|Slimbus|Codec|ADSP'
}

Write-Section -Name "00_Summary" -Script {
    foreach ($item in $expectedRoots) {
        $presentPnp = $allPnp | Where-Object { $_.InstanceId -match $item.Pattern }
        $presentProblem = $problemPnp | Where-Object { $_.InstanceId -match $item.Pattern }
        $presentReg = @()
        foreach ($root in @(
            'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI',
            'HKLM:\SYSTEM\CurrentControlSet\Enum\ADCM',
            'HKLM:\SYSTEM\CurrentControlSet\Enum\AUDD',
            'HKLM:\SYSTEM\CurrentControlSet\Enum\ADSP',
            'HKLM:\SYSTEM\CurrentControlSet\Enum\SLM1'
        )) {
            if (Test-Path $root) {
                $presentReg += Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match $item.Pattern }
            }
        }
        [pscustomobject]@{
            Name = $item.Name
            WhyItMatters = $item.Why
            PnpPresent = [bool]($presentPnp.Count)
            ProblemPresent = [bool]($presentProblem.Count)
            RegistryPresent = [bool]($presentReg.Count)
        }
    }
}

Write-Section -Name "01_ExpectedRoots_PnpMatches" -Script {
    foreach ($item in $expectedRoots) {
        "## $($item.Name)"
        $matches = $allPnp | Where-Object { $_.InstanceId -match $item.Pattern }
        if ($matches) {
            $matches | Sort-Object Class, FriendlyName | Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
        } else {
            "No PnP matches"
        }
        ""
    }
}

Write-Section -Name "02_ExpectedRoots_RegistryMatches" -Script {
    $roots = @(
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADCM',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\AUDD',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\ADSP',
        'HKLM:\SYSTEM\CurrentControlSet\Enum\SLM1'
    )
    foreach ($root in $roots) {
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

Write-Section -Name "03_CurrentAudioLikePnp" -Script {
    $audioLikePnp | Sort-Object Status, Class, FriendlyName |
        Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
}

Write-Section -Name "04_ProblemAudioLikePnp" -Script {
    $problemPnp |
        Where-Object {
            $_.InstanceId -match '^ACPI\\FSA04480|^SLM1\\QCOM2524|^ADCM\\|^AUDD\\|^ADSP\\QCOM2510|^ACPI\\QCOM25|^ACPI\\VEN_QCOM&DEV_25' -or
            $_.FriendlyName -match 'Audio|音频|Speaker|Microphone|耳机|麦克风|Endpoint|Slimbus|Codec|ADSP'
        } |
        Sort-Object Class, FriendlyName, InstanceId |
        Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
}

Write-Section -Name "05_SignedDrivers_Related" -Script {
    $allSignedDrivers |
        Where-Object {
            $_.DriverName -match 'fsa4480|qcaud|qcadcm|qcslim|adsp|audio|codec' -or
            $_.InfName -match 'fsa4480|qcaud|qcadcm|qcslim|adsp|audio'
        } |
        Sort-Object DeviceName, DriverName |
        Select-Object DeviceName, DeviceClass, DriverName, InfName, DriverProviderName, DriverVersion, IsSigned
}

Write-Section -Name "06_SystemDrivers_Related" -Script {
    Get-CimInstance Win32_SystemDriver |
        Where-Object { $_.Name -match 'fsa4480|qcaud|qcadcm|qcslim|adsp|audio' } |
        Sort-Object Name |
        Select-Object Name, State, StartMode, PathName, DisplayName
}

Write-Section -Name "07_SetupApi_Related" -Script {
    $log = 'C:\Windows\INF\setupapi.dev.log'
    if (Test-Path $log) {
        Select-String -Path $log -Pattern 'FSA04480|QCOM2524|ADCM|AUDD|ADSP|QCOM2560|QCOM258A|QCOM25D2|qcaud|qcadcm|qcslim|audio' -CaseSensitive:$false |
            Select-Object -Last 500
    } else {
        "setupapi.dev.log not found"
    }
}

Write-Section -Name "08_MediaAndEndpoints" -Script {
    "Win32_SoundDevice:"
    Get-CimInstance Win32_SoundDevice | Select-Object Name, Manufacturer, Status, PNPDeviceID
    ""
    "MEDIA class PnP:"
    Get-PnpDevice -Class MEDIA | Format-Table -AutoSize Class, FriendlyName, InstanceId, Status
    ""
    "MMDevices Render:"
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render') {
        Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render' | Select-Object PSChildName, Name
    }
    ""
    "MMDevices Capture:"
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture') {
        Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture' | Select-Object PSChildName, Name
    }
}

Write-Section -Name "09_Interpretation" -Script {
    $presentNames = foreach ($item in $expectedRoots) {
        if ($allPnp | Where-Object { $_.InstanceId -match $item.Pattern }) { $item.Name }
    }

    if (-not $presentNames) {
        "No expected audio-root devices are currently enumerated."
        "This usually means the next step should NOT be direct Kona Audio injection."
        "Prefer exact-match single-point candidates first, especially FSA4480 if still present as a problem device."
    } else {
        "Some expected audio-root devices are present:"
        $presentNames
    }
}

"Output directory: $outDir" | Set-Content -Path (Join-Path $outDir "README.txt") -Encoding UTF8
"Done. Audio root trace saved to: $outDir" | Write-Output
