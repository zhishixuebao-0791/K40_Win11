param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 1200
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "PilcStartFailureDeep_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
if (-not $bootTime) {
    $bootTime = (Get-Date).AddHours(-3)
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

function Run-Cmd {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    "Running: $FilePath $($Arguments -join ' ')"
    try {
        & $FilePath @Arguments *>&1 | Out-String -Width 8192
    } catch {
        "ERROR: $($_.Exception.Message)"
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

function Get-DeviceSnapshot {
    param([string]$InstanceId)

    $dev = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
    [pscustomobject]@{
        InstanceId = $InstanceId
        Present = [bool]$dev
        FriendlyName = if ($dev) { $dev.FriendlyName } else { "" }
        Class = if ($dev) { $dev.Class } else { "" }
        Status = if ($dev) { $dev.Status } else { "" }
        ProblemCode = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_ProblemCode"
        ProblemStatus = Get-Prop -InstanceId $InstanceId -KeyName "{4340A6C5-93FA-4706-972C-7B648008A5A7} 5"
        Service = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Service"
        DriverInfPath = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
        MatchingDeviceId = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId"
        HardwareIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_HardwareIds") -join ";")
        CompatibleIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_CompatibleIds") -join ";")
        ExtendedConfigurationIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_ExtendedConfigurationIds") -join ";")
        DependencyProviders = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DependencyProviders") -join ";")
        DependencyDependents = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DependencyDependents") -join ";")
        DeviceStack = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Stack") -join ";")
        UpperFilters = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_UpperFilters") -join ";")
        LowerFilters = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_LowerFilters") -join ";")
        BiosDeviceName = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_BiosDeviceName"
        LocationPaths = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_LocationPaths") -join ";")
    }
}

$targetIds = @(
    "ACPI\QCOM06E0\2&DABA3FF&0",
    "ACPI\QCOM251B\2&DABA3FF&0",
    "ACPI\QCOM0620\2&DABA3FF&0",
    "ACPI\QCOM2533\2&DABA3FF&0",
    "ACPI\QCOM250B\0",
    "ACPI\QCOM258D\0",
    "ACPI\QCOM250E\2&DABA3FF&0",
    "ACPI\QCOM257C\2&DABA3FF&0",
    "ACPI\QCOM258B\2&DABA3FF&0",
    "ACPI\QCOM05D2\0",
    "ACPI\FSA04480\2&DABA3FF&0"
)

Save-Text "00_Verdict.txt" {
    $pilc = Get-DeviceSnapshot -InstanceId "ACPI\QCOM06E0\2&DABA3FF&0"
    $subsys = Get-DeviceSnapshot -InstanceId "ACPI\QCOM0620\2&DABA3FF&0"
    "Alioth PILC start failure deep trace"
    "Time=$timestamp"
    "BootTime=$bootTime"
    ""
    "PILC:"
    $pilc | Format-List *
    ""
    "QCSUBSYS:"
    $subsys | Format-List *
    ""
    "Decision:"
    if ($pilc.Present -and $pilc.ProblemCode -eq 31 -and $pilc.HardwareIds -match "SUBSYS_MTP08280") {
        "Phase9A_SubsystemId=Effective"
        "Blocker=qcPILC_AddDevice_StartFailure"
        "Next=Do not change WDAC/qcsubsys. Compare PILC ACPI/runtime shape and qcpil extension binding."
    } elseif ($pilc.Present -and $pilc.ProblemCode -eq 0) {
        "Phase9A_Result=qcPILCStarted"
        "Next=Move to ADSP/qcsubsys/audio root enumeration."
    } else {
        "Phase9A_Result=Unexpected"
        "Next=Inspect 01_DeviceSnapshots and 08_SetupApiPilc."
    }
}

Save-Text "01_DeviceSnapshots.txt" {
    $targetIds | ForEach-Object { Get-DeviceSnapshot -InstanceId $_ } | Format-Table -AutoSize
    ""
    $targetIds | ForEach-Object {
        "==== $_ ===="
        Get-DeviceSnapshot -InstanceId $_ | Format-List *
        ""
    }
}

Save-Text "02_PnpUtilResources.txt" {
    foreach ($id in $targetIds) {
        "==== $id ===="
        Run-Cmd -FilePath "pnputil.exe" -Arguments @("/enum-devices", "/instanceid", $id, "/properties", "/resources")
        ""
    }
}

Save-Text "03_PilcRegistry.txt" {
    Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM06E0", "/s")
    ""
    Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM251B", "/s")
}

Save-Text "04_ServiceRegistry.txt" {
    foreach ($svc in @("qcPILC", "qcPILFC", "qcsubsys", "qcscm", "qcGLINK", "QCIPC_ROUTER", "QCRPEN", "qcpdsr", "QcTftpKmdf")) {
        "==== $svc ===="
        Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Services\$svc", "/s")
        ""
        Get-CimInstance Win32_SystemDriver -Filter "Name='$svc'" -ErrorAction SilentlyContinue | Format-List *
        ""
    }
}

Save-Text "05_DriverStorePilcInf.txt" {
    $infNames = @()
    foreach ($id in $targetIds) {
        $inf = Get-Prop -InstanceId $id -KeyName "DEVPKEY_Device_DriverInfPath"
        if ($inf) { $infNames += $inf }
        $ext = @(Get-Prop -InstanceId $id -KeyName "DEVPKEY_Device_ExtendedConfigurationIds")
        foreach ($item in $ext) {
            if ($item -match "^(oem\d+\.inf):") { $infNames += $Matches[1] }
        }
    }
    $infNames += @("oem16.inf", "oem17.inf")

    foreach ($inf in ($infNames | Sort-Object -Unique)) {
        $infPath = Join-Path $env:SystemRoot "INF\$inf"
        "==== $infPath ===="
        if (Test-Path -LiteralPath $infPath) {
            Get-AuthenticodeSignature -LiteralPath $infPath | Format-List *
            ""
            Get-Content -LiteralPath $infPath -ErrorAction SilentlyContinue
        } else {
            "Not found"
        }
        ""
    }
}

Save-Text "06_CodeIntegrityCurrentBoot.txt" {
    Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcpil|qcPIL|QCOM06E0|QCOM251B|qcsubsys|signature|integrity|policy|0xC0000428" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
}

Save-Text "07_KernelPnpCurrentBoot.txt" {
    Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Microsoft-Windows-Kernel-PnP"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "QCOM06E0|QCOM251B|QCOM0620|qcpil|qcPIL|Image Loader|Subsystem" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
}

Save-Text "08_SetupApiPilc.txt" {
    $setupApi = Join-Path $env:SystemRoot "INF\setupapi.dev.log"
    if (Test-Path -LiteralPath $setupApi) {
        Select-String -LiteralPath $setupApi -Pattern "QCOM06E0", "QCOM251B", "qcpil", "qcPILC", "qcPILFC", "PIL_Device_Ext", "MTP08280", "CM_PROB_FAILED_ADD", "0xc0000001" -SimpleMatch -Context 8,16
    } else {
        "setupapi.dev.log not found: $setupApi"
    }
}

Save-Text "09_WdfAndPnPLogsAvailable.txt" {
    "==== Logs matching WDF/KMDF/PNP/ACPI ===="
    wevtutil.exe el |
        Where-Object { $_ -match "WDF|Kernel-PnP|PnP|ACPI|CodeIntegrity|DriverFrameworks" } |
        Sort-Object
    ""
    foreach ($log in @(
        "Microsoft-Windows-DriverFrameworks-KernelMode/Operational",
        "Microsoft-Windows-Kernel-PnP/Configuration",
        "Microsoft-Windows-CodeIntegrity/Operational"
    )) {
        "==== $log ===="
        try {
            Get-WinEvent -LogName $log -MaxEvents 80 -ErrorAction Stop |
                Where-Object { $_.TimeCreated -ge $bootTime } |
                Select-Object TimeCreated, Id, ProviderName, Message |
                Format-List *
        } catch {
            "ERROR: $($_.Exception.Message)"
        }
        ""
    }
}

Write-Host "PILC start failure deep trace completed: $outDir"
