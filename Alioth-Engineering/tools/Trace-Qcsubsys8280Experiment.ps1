param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 400
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "Qcsubsys8280Experiment_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
if (-not $bootTime) {
    $bootTime = (Get-Date).AddHours(-2)
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

function Add-Summary {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
}

function Command-Text {
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

Add-Summary "qcsubsys8280 experiment trace started."
Add-Summary "Output: $outDir"

Save-Text "01_TargetDevices.txt" {
    Command-Text "pnputil QCOM0620" { pnputil /enum-devices /instanceid "ACPI\QCOM0620\*" /drivers }
    Command-Text "pnputil QCOM2522" { pnputil /enum-devices /instanceid "ACPI\QCOM2522\*" /drivers }
    Command-Text "pnputil QCOM0522" { pnputil /enum-devices /instanceid "ACPI\QCOM0522\*" /drivers }
    Command-Text "Get-PnpDevice selected" {
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'QCOM(0620|2522|0522)' } |
            Format-List *
    }
    Command-Text "Get-PnpDeviceProperty selected" {
        foreach ($id in @("ACPI\QCOM0620\2&DABA3FF&0", "ACPI\QCOM2522\2&DABA3FF&0", "ACPI\QCOM0522\2&DABA3FF&0")) {
            "---- $id ----"
            Get-PnpDeviceProperty -InstanceId $id -ErrorAction SilentlyContinue | Format-List *
        }
    }
}

Save-Text "02_DriverStore_Qcsubsys.txt" {
    Command-Text "pnputil enum-drivers qcsubsys" {
        pnputil /enum-drivers /files |
            Select-String -Pattern "qcsubsys8250|qcsubsys8280|oem[0-9]+\.inf|Provider|Signer|发布名称|原始名称|提供程序|签名者|目录文件|驱动程序文件" -Context 0,4
    }
    Command-Text "DriverStore qcsubsys directories" {
        Get-ChildItem "$env:SystemRoot\System32\DriverStore\FileRepository" -Directory -Filter "qcsubsys*.inf_arm64*" -ErrorAction SilentlyContinue |
            Sort-Object Name |
            ForEach-Object {
                "==== $($_.FullName) ===="
                Get-ChildItem -LiteralPath $_.FullName | Select-Object Name, Length, LastWriteTime
                Get-ChildItem -LiteralPath $_.FullName -Filter "*.cat" -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_.FullName -ErrorAction SilentlyContinue } |
                    Format-List *
                Get-ChildItem -LiteralPath $_.FullName -Filter "*.sys" -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-AuthenticodeSignature -LiteralPath $_.FullName -ErrorAction SilentlyContinue } |
                    Format-List *
            }
    }
}

Save-Text "03_Service_State.txt" {
    Command-Text "Win32_SystemDriver qcsubsys" {
        Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq "qcsubsys" -or $_.PathName -match "qcsubsys" } |
            Format-List *
    }
    Command-Text "Registry qcsubsys service" {
        reg query HKLM\SYSTEM\CurrentControlSet\Services\qcsubsys /s
    }
}

Save-Text "04_CodeIntegrity_Qcsubsys.txt" {
    Command-Text "Current boot CodeIntegrity events" {
        Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "qcsubsys|Code Integrity policy|Driver Policy|hash|signature|integrity" } |
            Select-Object TimeCreated, Id, ProviderName, Message |
            Format-List *
    }
}

Save-Text "05_SetupApi_Qcsubsys.txt" {
    Command-Text "setupapi.dev.log focused" {
        $setupApi = Join-Path $env:SystemRoot "INF\setupapi.dev.log"
        if (Test-Path -LiteralPath $setupApi) {
            Select-String -LiteralPath $setupApi -Pattern "qcsubsys8280|qcsubsys8250|QCOM0620|QCOM2522|QCOM0522|oem15.inf|oem5.inf|Driver Rank|Signer Score|Select Drivers|Exit status|0xC0000428|CM_PROB_UNSIGNED_DRIVER" -Context 2,5
        } else {
            "setupapi.dev.log not found: $setupApi"
        }
    }
}

$targetText = Get-Content -LiteralPath (Join-Path $outDir "01_TargetDevices.txt") -Raw -ErrorAction SilentlyContinue
$ciText = Get-Content -LiteralPath (Join-Path $outDir "04_CodeIntegrity_Qcsubsys.txt") -Raw -ErrorAction SilentlyContinue
$driverText = Get-Content -LiteralPath (Join-Path $outDir "02_DriverStore_Qcsubsys.txt") -Raw -ErrorAction SilentlyContinue
$serviceText = Get-Content -LiteralPath (Join-Path $outDir "03_Service_State.txt") -Raw -ErrorAction SilentlyContinue

$presentQcsubsysDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'QCOM(0620|2522|0522)' })
$qcom0620Present = @($presentQcsubsysDevices | Where-Object { $_.InstanceId -match 'QCOM0620' }).Count -gt 0
$qcom2522StillPresent = @($presentQcsubsysDevices | Where-Object { $_.InstanceId -match 'QCOM2522' }).Count -gt 0
$qcom0522StillPresent = @($presentQcsubsysDevices | Where-Object { $_.InstanceId -match 'QCOM0522' }).Count -gt 0
$qcom0620InfPath = ""
$qcom0620MatchingId = ""
$qcom0620Service = ""
if ($qcom0620Present) {
    $qcom0620Device = @($presentQcsubsysDevices | Where-Object { $_.InstanceId -match 'QCOM0620' } | Select-Object -First 1)
    $qcom0620InfPath = (Get-PnpDeviceProperty -InstanceId $qcom0620Device.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath" -ErrorAction SilentlyContinue).Data
    $qcom0620MatchingId = (Get-PnpDeviceProperty -InstanceId $qcom0620Device.InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId" -ErrorAction SilentlyContinue).Data
    $qcom0620Service = (Get-PnpDeviceProperty -InstanceId $qcom0620Device.InstanceId -KeyName "DEVPKEY_Device_Service" -ErrorAction SilentlyContinue).Data
}
$qcsubsys8280Staged = $driverText -match "qcsubsys8280"
$qcsubsys8280Selected = $qcom0620Present -and
    $qcom0620InfPath -match "oem\d+\.inf" -and
    $qcom0620MatchingId -eq "ACPI\QCOM0620" -and
    $qcom0620Service -eq "qcsubsys" -and
    ($targetText -match "qcsubsys8280\.inf_arm64" -or $serviceText -match "qcsubsys8280\.sys")
$qcsubsys8280CiBlocked = $ciText -match "qcsubsys8280.*hash could not be found|qcsubsys8280.*verify the image integrity|qcsubsys8280.*0xC0000428"
$qcsubsys8250CiBlocked = $ciText -match "qcsubsys8250.*hash could not be found|qcsubsys8250.*verify the image integrity|qcsubsys8250.*0xC0000428"

@"
QCOM0620Present=$qcom0620Present
QCOM2522StillPresent=$qcom2522StillPresent
QCOM0522StillPresent=$qcom0522StillPresent
QCOM0620InfPath=$qcom0620InfPath
QCOM0620MatchingDeviceId=$qcom0620MatchingId
QCOM0620Service=$qcom0620Service
Qcsubsys8280Staged=$qcsubsys8280Staged
Qcsubsys8280Selected=$qcsubsys8280Selected
Qcsubsys8280CiBlocked=$qcsubsys8280CiBlocked
Qcsubsys8250CiBlocked=$qcsubsys8250CiBlocked

Interpretation:
- If QCOM2522StillPresent=True and QCOM0620Present=False, Phase7 ACPI HID remap has not taken effect.
- If QCOM0620Present=True but qcsubsys8280 is not selected, inspect setupapi rank and matching ID.
- If QCOM0620Present=True, Qcsubsys8280Selected=True, and Qcsubsys8280CiBlocked=False, the WDAC/qcsubsys step is passed for the current boot.
- If QCOM0620Present=True and qcsubsys8280 is selected but Qcsubsys8280CiBlocked=True, WDAC/Microsoft Driver Policy is still blocking the official package.
- If QCOM0620Present=True, qcsubsys8280 is selected, and no CI block appears, move to functional dependency/audio root diagnostics.
"@ | Set-Content -LiteralPath (Join-Path $outDir "06_AutoVerdict.txt") -Encoding UTF8

Add-Summary "Collection completed: $outDir"
Write-Host "Qcsubsys8280 experiment trace completed: $outDir"
