param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 800
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "PilcAcpiShape_$timestamp"
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

function Get-DeviceRow {
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
        Driver = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Driver"
        DriverInfPath = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_DriverInfPath"
        MatchingDeviceId = Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId"
        HardwareIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_HardwareIds") -join ";")
        CompatibleIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_CompatibleIds") -join ";")
        LowerFilters = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_LowerFilters") -join ";")
        UpperFilters = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_UpperFilters") -join ";")
        ExtendedConfigurationIds = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_ExtendedConfigurationIds") -join ";")
        LocationPaths = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_LocationPaths") -join ";")
        DeviceStack = (@(Get-Prop -InstanceId $InstanceId -KeyName "DEVPKEY_Device_Stack") -join ";")
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
    "ACPI\QCOM258B\2&DABA3FF&0"
)

Save-Text "00_Summary.txt" {
    "Alioth PILC ACPI shape trace"
    "Time=$timestamp"
    "BootTime=$bootTime"
    ""
    $targetIds | ForEach-Object { Get-DeviceRow -InstanceId $_ } | Format-Table -AutoSize
    ""
    "Interpretation:"
    "- QCOM06E0 Code 31 with clean CodeIntegrity means qcPILC loaded but failed AddDevice/start."
    "- If QCOM06E0 DeviceStack only contains ACPI, qcPILC/qcPILFC did not attach successfully."
    "- Compare QCOM06E0 resources and registry values against a known Surface qcpil8280 device before further UEFI changes."
}

Save-Text "01_PnpDeviceProperties.txt" {
    foreach ($id in $targetIds) {
        "==== $id ===="
        Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue | Format-List *
        ""
        Get-PnpDeviceProperty -InstanceId $id -ErrorAction SilentlyContinue |
            Sort-Object KeyName |
            Format-Table KeyName,Type,Data -AutoSize
        ""
    }
}

Save-Text "02_PnpUtilPropertiesAndResources.txt" {
    foreach ($id in $targetIds) {
        "==== pnputil properties/resources: $id ===="
        Run-Cmd -FilePath "pnputil.exe" -Arguments @("/enum-devices", "/instanceid", $id, "/properties", "/resources")
        ""
        "==== pnputil properties only fallback: $id ===="
        Run-Cmd -FilePath "pnputil.exe" -Arguments @("/enum-devices", "/instanceid", $id, "/properties")
        ""
    }
}

Save-Text "03_WmiAllocatedResources.txt" {
    $resources = @(Get-CimInstance Win32_PnPAllocatedResource -ErrorAction SilentlyContinue)
    foreach ($id in $targetIds) {
        "==== $id ===="
        $escaped = $id.Replace("\", "\\")
        $resources |
            Where-Object { $_.Dependent -match [regex]::Escape($escaped) -or $_.Dependent -match [regex]::Escape($id) } |
            Format-List *
        ""
    }
}

Save-Text "04_RegistryRaw_QCOM06E0.txt" {
    Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM06E0", "/s")
}

Save-Text "05_RegistryRaw_QCOM251B.txt" {
    Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI\QCOM251B", "/s")
}

Save-Text "06_ServiceRegistry.txt" {
    foreach ($svc in @("qcPILC", "qcPILFC", "qcsubsys", "qcscm", "qcGLINK", "QCIPC_ROUTER", "QCRPEN", "qcpdsr", "QcTftpKmdf")) {
        "==== $svc ===="
        Run-Cmd -FilePath "reg.exe" -Arguments @("query", "HKLM\SYSTEM\CurrentControlSet\Services\$svc", "/s")
        ""
    }
}

Save-Text "07_DriverStoreInfCopies.txt" {
    $infNames = @()
    foreach ($id in $targetIds) {
        $inf = Get-Prop -InstanceId $id -KeyName "DEVPKEY_Device_DriverInfPath"
        if ($inf) { $infNames += $inf }
    }
    $infNames += @("oem16.inf", "oem17.inf", "oem15.inf")
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

Save-Text "08_SetupApi_QCOM06E0.txt" {
    $setupApi = Join-Path $env:SystemRoot "INF\setupapi.dev.log"
    if (Test-Path -LiteralPath $setupApi) {
        Select-String -LiteralPath $setupApi -Pattern "QCOM06E0", "qcpil", "qcPILC", "qcPILFC", "PIL_Device_Ext", "CM_PROB_FAILED_ADD", "0xc0000001" -SimpleMatch -Context 6,12
    } else {
        "setupapi.dev.log not found: $setupApi"
    }
}

Save-Text "09_CurrentBootEvents.txt" {
    "==== CodeIntegrity current boot ===="
    Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcPILC|qcPILFC|qcpil|QCOM06E0|QCOM251B|signature|integrity|policy|0xC0000428" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
    ""
    "==== Kernel-PnP current boot ===="
    Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Microsoft-Windows-Kernel-PnP"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcPILC|qcPILFC|qcpil|QCOM06E0|QCOM251B|QCOM0620|Image Loader|Subsystem" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
    ""
    "==== System current boot service failures ===="
    Get-WinEvent -FilterHashtable @{ LogName = "System"; StartTime = $bootTime } -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcPILC|qcPILFC|qcpil|QCOM06E0|QCOM251B|failed|error|无法|失败" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
}

Save-Text "10_CandidateVerdict.txt" {
    $row = Get-DeviceRow -InstanceId "ACPI\QCOM06E0\2&DABA3FF&0"
    $row | Format-List *
    ""
    if ($row.Present -and $row.ProblemCode -eq 31 -and $row.Service -eq "qcPILC") {
        "Verdict=QCOM06E0_qcPILC_Code31"
        "Next=Do not continue qcsubsys or WDAC work. Compare PILC ACPI resources/_DSD against Surface, or try a UEFI Phase9 ACPI shape change for PILC."
    } elseif ($row.Present -and $row.ProblemCode -eq 0) {
        "Verdict=QCOM06E0_qcPILC_started"
        "Next=Move downstream to ADSP/qcsubsys roots and audio endpoint enumeration."
    } else {
        "Verdict=Unexpected"
        "Next=Inspect 00_Summary and 09_CurrentBootEvents."
    }
}

"Alioth PILC ACPI shape trace completed: $outDir" | Tee-Object -FilePath (Join-Path $outDir "README.txt")
