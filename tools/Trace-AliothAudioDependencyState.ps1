param(
    [string]$OutputRoot
)

$ErrorActionPreference = "Continue"

function Write-Section {
    param(
        [string]$Path,
        [string]$Title
    )

    "==== $Title ====" | Set-Content -LiteralPath $Path -Encoding UTF8
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -LiteralPath $Path -Encoding UTF8
    "" | Add-Content -LiteralPath $Path -Encoding UTF8
}

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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $scriptRoot ("AudioDependencyState_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$targets = @(
    [pscustomobject]@{ Name = "PILC"; Native = "QCOM051B"; Alias = "QCOM251B"; ExpectedService = "qcPILC"; Role = "ADSP dependency" },
    [pscustomobject]@{ Name = "RPEN"; Native = "QCOM0533"; Alias = "QCOM2533"; ExpectedService = "QCRPEN"; Role = "GLNK/ADSP dependency" },
    [pscustomobject]@{ Name = "MMU0"; Native = "QCOM0509"; Alias = "DEV_2509"; ExpectedService = "qcsmmu"; Role = "ARPC dependency" },
    [pscustomobject]@{ Name = "SCM0"; Native = "QCOM050B"; Alias = "QCOM250B"; ExpectedService = "qcscm"; Role = "ARPC dependency" },
    [pscustomobject]@{ Name = "GLNK"; Native = "QCOM058D"; Alias = "QCOM258D"; ExpectedService = "qcglink"; Role = "IPC0/SSDD/ARPC dependency" },
    [pscustomobject]@{ Name = "IPC0"; Native = "QCOM050E"; Alias = "QCOM250E"; ExpectedService = "qcipcrtr"; Role = "ADSP dependency" },
    [pscustomobject]@{ Name = "PDSR"; Native = "QCOM057C"; Alias = "QCOM257C"; ExpectedService = "qcpdsr"; Role = "SSDD dependency" },
    [pscustomobject]@{ Name = "TFTP"; Native = "QCOM058B"; Alias = "QCOM258B"; ExpectedService = "QcTftpKmdf"; Role = "SSDD dependency" },
    [pscustomobject]@{ Name = "SSDD"; Native = "QCOM0522"; Alias = "QCOM2522"; ExpectedService = "qcsubsys"; Role = "ADSP dependency" },
    [pscustomobject]@{ Name = "QSM"; Native = "QCOM0520"; Alias = "QCOM2520"; ExpectedService = "qcsubsys"; Role = "Subsystem service manager" },
    [pscustomobject]@{ Name = "ARPC"; Native = "QCOM0560"; Alias = "QCOM2560"; ExpectedService = "qcadsprpc"; Role = "ADSP FastRPC root" },
    [pscustomobject]@{ Name = "ARPD"; Native = "QCOM058A"; Alias = "QCOM258A"; ExpectedService = "qcadsprpcd"; Role = "Audio RPC daemon" },
    [pscustomobject]@{ Name = "ADSP"; Native = "QCOM051D"; Alias = "QCOM251D"; ExpectedService = "qcsubsys"; Role = "Target DSP root" },
    [pscustomobject]@{ Name = "AudioService"; Native = "QCOM05D2"; Alias = "QCOM25D2"; ExpectedService = "AudioService"; Role = "Known working phase1 alias" },
    [pscustomobject]@{ Name = "FSA4480"; Native = "FSA04480"; Alias = "FSA04480"; ExpectedService = "fsa4480"; Role = "Type-C analog switch" }
)

$summaryPath = Join-Path $OutputRoot "00_Summary.txt"
Write-Section -Path $summaryPath -Title "Summary"

$allPnp = @(Get-PnpDevice -PresentOnly:$false -ErrorAction SilentlyContinue)
$rows = foreach ($target in $targets) {
    $matches = @($allPnp | Where-Object {
        $_.InstanceId -match [regex]::Escape($target.Native) -or
        $_.InstanceId -match [regex]::Escape($target.Alias) -or
        $_.FriendlyName -match [regex]::Escape($target.Name)
<<<<<<< HEAD
    })
=======
    } | Sort-Object `
        @{ Expression = {
            $isPresent = Get-DevicePropertyValue -InstanceId $_.InstanceId -KeyName "DEVPKEY_Device_IsPresent"
            if ($isPresent) { 0 } else { 1 }
        } },
        @{ Expression = {
            if ($_.InstanceId -match [regex]::Escape($target.Alias)) { 0 } else { 1 }
        } },
        @{ Expression = {
            if ($_.Status -eq "OK") { 0 } elseif ($_.Status -eq "Error") { 1 } else { 2 }
        } },
        InstanceId)
>>>>>>> 997c2b364a3178ae7a9b408834e9221f675f1cdb

    foreach ($match in $matches) {
        [pscustomobject]@{
            Name = $target.Name
            Role = $target.Role
            InstanceId = $match.InstanceId
            FriendlyName = $match.FriendlyName
            Class = $match.Class
            Status = $match.Status
            ProblemCode = Get-DevicePropertyValue -InstanceId $match.InstanceId -KeyName "DEVPKEY_Device_ProblemCode"
            Service = Get-DevicePropertyValue -InstanceId $match.InstanceId -KeyName "DEVPKEY_Device_Service"
            Driver = Get-DevicePropertyValue -InstanceId $match.InstanceId -KeyName "DEVPKEY_Device_Driver"
            MatchingDeviceId = Get-DevicePropertyValue -InstanceId $match.InstanceId -KeyName "DEVPKEY_Device_MatchingDeviceId"
            CompatibleIds = (@(Get-DevicePropertyValue -InstanceId $match.InstanceId -KeyName "DEVPKEY_Device_CompatibleIds") -join ";")
        }
    }

    if (-not $matches) {
        [pscustomobject]@{
            Name = $target.Name
            Role = $target.Role
            InstanceId = "<not present>"
            FriendlyName = ""
            Class = ""
            Status = ""
            ProblemCode = ""
            Service = ""
            Driver = ""
            MatchingDeviceId = ""
            CompatibleIds = ""
        }
    }
}

Add-Text -Path $summaryPath -Value ($rows | Format-Table -AutoSize)

$pnpPath = Join-Path $OutputRoot "01_TargetPnpDetails.txt"
Write-Section -Path $pnpPath -Title "Target PnP Details"
foreach ($row in $rows | Where-Object { $_.InstanceId -ne "<not present>" }) {
    Add-Text -Path $pnpPath -Value "## $($row.Name) / $($row.InstanceId)"
    Add-Text -Path $pnpPath -Value ($row | Format-List)
    try {
        Add-Text -Path $pnpPath -Value (Get-PnpDeviceProperty -InstanceId $row.InstanceId -ErrorAction Stop | Sort-Object KeyName | Format-Table KeyName,Data -AutoSize)
    } catch {
        Add-Text -Path $pnpPath -Value $_
    }
}

$regPath = Join-Path $OutputRoot "02_RegistryEnumMatches.txt"
Write-Section -Path $regPath -Title "Registry Enum Matches"
$enumRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI"
foreach ($target in $targets) {
    Add-Text -Path $regPath -Value "## $($target.Name) native=$($target.Native) alias=$($target.Alias)"
    if (Test-Path -LiteralPath $enumRoot) {
        $matches = @(Get-ChildItem -LiteralPath $enumRoot -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match [regex]::Escape($target.Native) -or
            $_.Name -match [regex]::Escape($target.Alias)
        })
        if ($matches) {
            foreach ($match in $matches) {
                Add-Text -Path $regPath -Value $match.Name
                Add-Text -Path $regPath -Value (Get-ItemProperty -LiteralPath $match.PSPath | Select-Object HardwareID,CompatibleIDs,Service,ClassGUID,Driver,ConfigFlags,Problem,Status | Format-List)
            }
        } else {
            Add-Text -Path $regPath -Value "Not found"
        }
    }
}

$servicesPath = Join-Path $OutputRoot "03_Services.txt"
Write-Section -Path $servicesPath -Title "Services"
$serviceNames = $targets.ExpectedService | Sort-Object -Unique
foreach ($serviceName in $serviceNames) {
    Add-Text -Path $servicesPath -Value "## $serviceName"
    $svc = Get-CimInstance Win32_SystemDriver -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
    if ($svc) {
        Add-Text -Path $servicesPath -Value ($svc | Select-Object Name,State,StartMode,PathName,DisplayName | Format-List)
    } else {
        Add-Text -Path $servicesPath -Value "Not found"
    }
}

$setupApiPath = Join-Path $OutputRoot "04_SetupApiMatches.txt"
Write-Section -Path $setupApiPath -Title "SetupAPI Matches"
$setupApi = "C:\Windows\INF\setupapi.dev.log"
if (Test-Path -LiteralPath $setupApi) {
    $patterns = @()
    foreach ($target in $targets) {
        $patterns += $target.Native
        $patterns += $target.Alias
    }
    $patterns = $patterns | Sort-Object -Unique
    Select-String -LiteralPath $setupApi -Pattern $patterns -SimpleMatch -ErrorAction SilentlyContinue |
        Select-Object Path,LineNumber,Line |
        Format-Table -AutoSize |
        Out-String -Width 4096 |
        Add-Content -LiteralPath $setupApiPath -Encoding UTF8
} else {
    Add-Text -Path $setupApiPath -Value "setupapi.dev.log not found"
}

"Alioth audio dependency state collected to: $OutputRoot" | Tee-Object -FilePath (Join-Path $OutputRoot "README.txt")
