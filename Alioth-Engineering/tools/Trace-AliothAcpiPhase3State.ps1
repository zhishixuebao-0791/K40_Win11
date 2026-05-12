param(
    [string]$OutputRoot
)

$ErrorActionPreference = "Continue"

function Add-Text {
    param(
        [string]$Path,
        [object]$Value
    )

    if ($null -eq $Value) {
        "<null>" | Add-Content -LiteralPath $Path -Encoding UTF8
        return
    }

    $Value | Out-String -Width 4096 | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Write-Section {
    param(
        [string]$Path,
        [string]$Title
    )

    "==== $Title ====" | Set-Content -LiteralPath $Path -Encoding UTF8
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -LiteralPath $Path -Encoding UTF8
    "" | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DevicePropertyValue {
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

function Get-DevicesByAcpiId {
    param([string]$AcpiId)

    $pattern = "ACPI\$AcpiId\*"
    return @(Get-PnpDevice -InstanceId $pattern -ErrorAction SilentlyContinue)
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $scriptRoot ("AcpiPhase3State_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$targets = @(
    [pscustomobject]@{ Name = "PILC native stale"; AcpiId = "QCOM051B"; ExpectedService = "" },
    [pscustomobject]@{ Name = "PILC phase3"; AcpiId = "QCOM251B"; ExpectedService = "qcPILC" },
    [pscustomobject]@{ Name = "RPEN native stale"; AcpiId = "QCOM0533"; ExpectedService = "" },
    [pscustomobject]@{ Name = "RPEN phase3"; AcpiId = "QCOM2533"; ExpectedService = "QCRPEN" },
    [pscustomobject]@{ Name = "AudioService"; AcpiId = "QCOM05D2"; ExpectedService = "AudioService" },
    [pscustomobject]@{ Name = "FSA4480"; AcpiId = "FSA04480"; ExpectedService = "fsa4480" },
    [pscustomobject]@{ Name = "PEP0 native"; AcpiId = "QCOM0519"; ExpectedService = "" },
    [pscustomobject]@{ Name = "MMU0 native"; AcpiId = "QCOM0509"; ExpectedService = "qcsmmu" },
    [pscustomobject]@{ Name = "MMU0 kona"; AcpiId = "QCOM2509"; ExpectedService = "qcsmmu" },
    [pscustomobject]@{ Name = "SCM0 native"; AcpiId = "QCOM050B"; ExpectedService = "qcscm" },
    [pscustomobject]@{ Name = "SCM0 kona"; AcpiId = "QCOM250B"; ExpectedService = "qcscm" },
    [pscustomobject]@{ Name = "GLNK native"; AcpiId = "QCOM058D"; ExpectedService = "qcglink" },
    [pscustomobject]@{ Name = "GLNK kona"; AcpiId = "QCOM258D"; ExpectedService = "qcglink" },
    [pscustomobject]@{ Name = "IPC0 native"; AcpiId = "QCOM050E"; ExpectedService = "QCIPC_ROUTER" },
    [pscustomobject]@{ Name = "IPC0 kona"; AcpiId = "QCOM250E"; ExpectedService = "QCIPC_ROUTER" },
    [pscustomobject]@{ Name = "SSDD native"; AcpiId = "QCOM0522"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SSDD kona old"; AcpiId = "QCOM2522"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SSDD phase7 8280"; AcpiId = "QCOM0620"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "CDI native"; AcpiId = "QCOM0532"; ExpectedService = "" },
    [pscustomobject]@{ Name = "QSM native"; AcpiId = "QCOM0520"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "QSM kona"; AcpiId = "QCOM2520"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SCSS native"; AcpiId = "QCOM0521"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SCSS phase10 8280"; AcpiId = "QCOM061F"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "ADSP native"; AcpiId = "QCOM051D"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "ADSP kona"; AcpiId = "QCOM251D"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "ADSP phase10 8280"; AcpiId = "QCOM061B"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "CDSP native"; AcpiId = "QCOM0523"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "CDSP phase10 8280"; AcpiId = "QCOM06B0"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SPSS native"; AcpiId = "QCOM0599"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "SPSS phase10 8280"; AcpiId = "QCOM068D"; ExpectedService = "qcsubsys" },
    [pscustomobject]@{ Name = "ARPC native"; AcpiId = "QCOM0560"; ExpectedService = "qcadsprpc" },
    [pscustomobject]@{ Name = "ARPC kona"; AcpiId = "QCOM2560"; ExpectedService = "qcadsprpc" },
    [pscustomobject]@{ Name = "ARPD native"; AcpiId = "QCOM058A"; ExpectedService = "qcadsprpcd" },
    [pscustomobject]@{ Name = "ARPD kona"; AcpiId = "QCOM258A"; ExpectedService = "qcadsprpcd" }
)

$summaryPath = Join-Path $OutputRoot "00_Phase3Summary.txt"
Write-Section -Path $summaryPath -Title "Alioth ACPI phase3/phase4 state summary"

$rows = foreach ($target in $targets) {
    $devices = Get-DevicesByAcpiId -AcpiId $target.AcpiId
    if (-not $devices) {
        [pscustomobject]@{
            Name = $target.Name
            AcpiId = $target.AcpiId
            InstanceId = "<not present>"
            FriendlyName = ""
            Class = ""
            Status = ""
            ProblemCode = ""
            ProblemStatus = ""
            Service = ""
            Driver = ""
            IsPresent = ""
            MatchingDeviceId = ""
            CompatibleIds = ""
        }
        continue
    }

    foreach ($device in $devices) {
        [pscustomobject]@{
            Name = $target.Name
            AcpiId = $target.AcpiId
            InstanceId = $device.InstanceId
            FriendlyName = $device.FriendlyName
            Class = $device.Class
            Status = $device.Status
            ProblemCode = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_ProblemCode"
            ProblemStatus = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_ProblemStatus"
            Service = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_Service"
            Driver = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_Driver"
            IsPresent = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_IsPresent"
            MatchingDeviceId = Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId"
            CompatibleIds = (@(Get-DevicePropertyValue -InstanceId $device.InstanceId -KeyName "DEVPKEY_Device_CompatibleIds") -join ";")
        }
    }
}

Add-Text -Path $summaryPath -Value ($rows | Format-Table -AutoSize)

$detailsPath = Join-Path $OutputRoot "01_DeviceProperties.txt"
Write-Section -Path $detailsPath -Title "Target device properties"
foreach ($row in $rows | Where-Object { $_.InstanceId -ne "<not present>" }) {
    Add-Text -Path $detailsPath -Value "## $($row.Name) / $($row.InstanceId)"
    Add-Text -Path $detailsPath -Value ($row | Format-List)
    try {
        Add-Text -Path $detailsPath -Value (Get-PnpDeviceProperty -InstanceId $row.InstanceId -ErrorAction Stop | Sort-Object KeyName | Format-Table KeyName,Data -AutoSize)
    } catch {
        Add-Text -Path $detailsPath -Value $_
    }
}

$regPath = Join-Path $OutputRoot "02_EnumRegistry.txt"
Write-Section -Path $regPath -Title "Enum registry for target IDs"
foreach ($target in $targets) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\$($target.AcpiId)"
    Add-Text -Path $regPath -Value "## $($target.Name) / $path"
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            Add-Text -Path $regPath -Value $_.Name
            Add-Text -Path $regPath -Value (Get-ItemProperty -LiteralPath $_.PSPath | Format-List)
        }
    } else {
        Add-Text -Path $regPath -Value "Not found"
    }
}

$servicePath = Join-Path $OutputRoot "03_ServiceState.txt"
Write-Section -Path $servicePath -Title "Related service state"
$services = $targets.ExpectedService | Where-Object { $_ } | Sort-Object -Unique
foreach ($service in $services) {
    Add-Text -Path $servicePath -Value "## $service"
    $svc = Get-CimInstance Win32_SystemDriver -Filter "Name='$service'" -ErrorAction SilentlyContinue
    if ($svc) {
        Add-Text -Path $servicePath -Value ($svc | Select-Object Name,State,StartMode,PathName,DisplayName | Format-List)
        $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$service"
        if (Test-Path -LiteralPath $svcReg) {
            Add-Text -Path $servicePath -Value (Get-ItemProperty -LiteralPath $svcReg | Format-List)
        }
    } else {
        Add-Text -Path $servicePath -Value "Not found"
    }
}

$setupApiPath = Join-Path $OutputRoot "04_SetupApiTargetLines.txt"
Write-Section -Path $setupApiPath -Title "SetupAPI target lines"
$setupApi = "C:\Windows\INF\setupapi.dev.log"
if (Test-Path -LiteralPath $setupApi) {
    $patterns = $targets.AcpiId | Sort-Object -Unique
    Select-String -LiteralPath $setupApi -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue |
        Select-Object Path,LineNumber,Line |
        Format-Table -AutoSize |
        Out-String -Width 4096 |
        Add-Content -LiteralPath $setupApiPath -Encoding UTF8
} else {
    Add-Text -Path $setupApiPath -Value "setupapi.dev.log not found"
}

$readme = Join-Path $OutputRoot "README.txt"
"Alioth ACPI phase3 diagnostic collected to: $OutputRoot" | Tee-Object -FilePath $readme
