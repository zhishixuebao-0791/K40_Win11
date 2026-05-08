param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 500
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "PilcFailureTrace_$timestamp"
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

function Get-Prop {
    param(
        [string]$InstanceId,
        [string]$KeyName
    )

    try {
        return (Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $KeyName -ErrorAction Stop).Data
    } catch {
        return $null
    }
}

function Write-CommandText {
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

Save-Text "01_PilcDevices.txt" {
    Write-CommandText "Present PILC devices" {
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'QCOM(051B|251B|061B|06E0)' -or $_.FriendlyName -match 'Image Loader|PILC|ADSP|Subsystem' } |
            Sort-Object InstanceId |
            Format-List *
    }
    Write-CommandText "All PILC historical devices" {
        Get-PnpDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'QCOM(051B|251B|061B|06E0)' -or $_.FriendlyName -match 'Image Loader|PILC|ADSP|Subsystem' } |
            Sort-Object InstanceId |
            Format-List *
    }
    Write-CommandText "PILC device properties" {
        foreach ($id in @(
            "ACPI\QCOM251B\2&DABA3FF&0",
            "ACPI\QCOM051B\2&DABA3FF&0",
            "ACPI\QCOM06E0\2&DABA3FF&0",
            "ACPI\QCOM061B\2&DABA3FF&0",
            "ACPI\QCOM0620\2&DABA3FF&0"
        )) {
            "---- $id ----"
            Get-PnpDeviceProperty -InstanceId $id -ErrorAction SilentlyContinue |
                Sort-Object KeyName |
                Format-Table KeyName,Data -AutoSize
        }
    }
}

Save-Text "02_DependencyNeighbors.txt" {
    Write-CommandText "Likely dependency devices" {
        Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'QCOM(250B|251B|06E0|2533|258D|250E|057C|257C|058B|258B|0620|061B|06B0|068D|061F|05D2)' } |
            Sort-Object InstanceId |
            ForEach-Object {
                [pscustomobject]@{
                    InstanceId = $_.InstanceId
                    FriendlyName = $_.FriendlyName
                    Status = $_.Status
                    ProblemCode = Get-Prop -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_ProblemCode"
                    ProblemStatus = Get-Prop -InstanceId $_.InstanceId -KeyName "{4340A6C5-93FA-4706-972C-7B648008A5A7} 5"
                    Service = Get-Prop -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_Service"
                    DriverInfPath = Get-Prop -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
                    MatchingDeviceId = Get-Prop -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId"
                    IsPresent = Get-Prop -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_IsPresent"
                }
            } |
            Format-Table -AutoSize
    }
}

Save-Text "03_Services.txt" {
    foreach ($svcName in @("qcPILC", "qcPILFC", "qcsubsys", "qcscm", "qcGLINK", "QCIPC_ROUTER", "QCRPEN", "qcpdsr", "QcTftpKmdf")) {
        Write-CommandText "Service $svcName - Win32_SystemDriver" {
            Get-CimInstance Win32_SystemDriver -Filter "Name='$svcName'" -ErrorAction SilentlyContinue | Format-List *
        }
        Write-CommandText "Service $svcName - registry" {
            reg query "HKLM\SYSTEM\CurrentControlSet\Services\$svcName" /s
        }
    }
}

Save-Text "04_CodeIntegrity_CurrentBoot.txt" {
    Write-CommandText "Current boot CodeIntegrity focused" {
        Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "qcPILC|qcPILFC|pil|qcpil|qcsubsys|QCOM251B|QCOM06E0|QCOM061B|hash|signature|integrity|policy|0xC0000428" } |
            Select-Object TimeCreated, Id, ProviderName, Message |
            Format-List *
    }
}

Save-Text "05_KernelPnp_CurrentBoot.txt" {
    Write-CommandText "Current boot Kernel-PnP focused" {
        Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Microsoft-Windows-Kernel-PnP"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "QCOM251B|QCOM051B|QCOM06E0|QCOM061B|qcPILC|qcPILFC|Image Loader|QCOM0620|qcsubsys" } |
            Select-Object TimeCreated, Id, ProviderName, Message |
            Format-List *
    }
}

Save-Text "06_SetupApi_Pilc.txt" {
    Write-CommandText "setupapi.dev.log focused" {
        $setupApi = Join-Path $env:SystemRoot "INF\setupapi.dev.log"
        if (Test-Path -LiteralPath $setupApi) {
            Select-String -LiteralPath $setupApi -Pattern "QCOM251B|QCOM051B|QCOM06E0|QCOM061B|qcPILC|qcPILFC|qcpil|Image Loader|QCOM0620|qcsubsys8280" -Context 3,6
        } else {
            "setupapi.dev.log not found: $setupApi"
        }
    }
}

$summaryPath = Join-Path $outDir "00_Summary.txt"
$pilc = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'QCOM251B' } |
    Select-Object -First 1
$qcom0620 = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'QCOM0620' } |
    Select-Object -First 1
$qcom06e0 = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'QCOM06E0' } |
    Select-Object -First 1

$pilcProblem = if ($pilc) { Get-Prop -InstanceId $pilc.InstanceId -KeyName "DEVPKEY_Device_ProblemCode" } else { "" }
$pilcStatus = if ($pilc) { Get-Prop -InstanceId $pilc.InstanceId -KeyName "{4340A6C5-93FA-4706-972C-7B648008A5A7} 5" } else { "" }
$pilcService = if ($pilc) { Get-Prop -InstanceId $pilc.InstanceId -KeyName "DEVPKEY_Device_Service" } else { "" }
$pilcInf = if ($pilc) { Get-Prop -InstanceId $pilc.InstanceId -KeyName "DEVPKEY_Device_DriverInfPath" } else { "" }

@"
PilcPresent=$([bool]$pilc)
PilcInstanceId=$($pilc.InstanceId)
PilcProblemCode=$pilcProblem
PilcProblemStatus=$pilcStatus
PilcService=$pilcService
PilcDriverInfPath=$pilcInf
QCOM0620Present=$([bool]$qcom0620)
QCOM0620InstanceId=$($qcom0620.InstanceId)
QCOM06E0Present=$([bool]$qcom06e0)
QCOM06E0InstanceId=$($qcom06e0.InstanceId)
BootTime=$bootTime

Interpretation:
- If PilcPresent=True and PilcProblemCode=31, PILC is the current ADSP bring-up blocker.
- If CodeIntegrity has qcPILC blocks, fix signature/policy before ACPI changes.
- If CodeIntegrity is clean and PILC remains Code 31, compare PILC dependencies and AML resources before changing ADSP/qcsubsys HIDs.
"@ | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Host "PILC failure trace completed: $outDir"
