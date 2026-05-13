param(
    [string]$OutputRoot
)

$ErrorActionPreference = "Continue"

function Write-Section {
    param([string]$Path, [string]$Title)
    "==== $Title ====" | Set-Content -LiteralPath $Path -Encoding UTF8
    "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content -LiteralPath $Path -Encoding UTF8
    "" | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Add-Text {
    param([string]$Path, [object]$Value)
    if ($null -eq $Value) {
        "<null>" | Add-Content -LiteralPath $Path -Encoding UTF8
        return
    }
    $Value | Out-String -Width 4096 | Add-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DeviceByAcpiId {
    param([string]$AcpiId)
    $devices = @()

    try {
        $devices += Get-PnpDevice -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -like "ACPI\$AcpiId\*" } |
            Select-Object @{ Name = "InstanceId"; Expression = { $_.InstanceId } },
                @{ Name = "FriendlyName"; Expression = { $_.FriendlyName } },
                @{ Name = "Status"; Expression = { $_.Status } },
                @{ Name = "ProblemCode"; Expression = { $_.ProblemCode } },
                @{ Name = "Source"; Expression = { "Get-PnpDevice" } }
    } catch {
        # Fall back below. Some recovery/phone builds expose registry state but not PnP cmdlet state.
    }

    if ($devices.Count -eq 0) {
        try {
            $devices += Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
                Where-Object { $_.PNPDeviceID -like "ACPI\$AcpiId\*" } |
                Select-Object @{ Name = "InstanceId"; Expression = { $_.PNPDeviceID } },
                    @{ Name = "FriendlyName"; Expression = { $_.Name } },
                    @{ Name = "Status"; Expression = { $_.Status } },
                    @{ Name = "ProblemCode"; Expression = { $_.ConfigManagerErrorCode } },
                    @{ Name = "Source"; Expression = { "Win32_PnPEntity" } }
        } catch {
        }
    }

    $devices | Sort-Object InstanceId -Unique
}

function Get-RegDeviceByAcpiId {
    param([string]$AcpiId)
    $base = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\$AcpiId"
    if (-not (Test-Path -LiteralPath $base)) {
        return @()
    }

    Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -notmatch '^(Properties|Device Parameters|Control|LogConf)$' } |
        ForEach-Object {
            $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            [pscustomobject]@{
                InstanceId = "ACPI\$AcpiId\$($_.PSChildName)"
                FriendlyName = $item.DeviceDesc
                Status = "<registry-only>"
                ProblemCode = ""
                Source = "EnumRegistry"
                HardwareID = (@($item.HardwareID) -join ";")
                CompatibleIDs = (@($item.CompatibleIDs) -join ";")
                Service = $item.Service
                Driver = $item.Driver
                ConfigFlags = $item.ConfigFlags
                Mfg = $item.Mfg
                PsPath = $_.PSPath
            }
        } |
        Sort-Object InstanceId -Unique
}

function Get-PnpPropMap {
    param([string]$InstanceId)
    $map = [ordered]@{}
    try {
        foreach ($prop in Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop) {
            $map[$prop.KeyName] = $prop.Data
        }
    } catch {
        $map["__ERROR__"] = $_.Exception.Message
    }
    return $map
}

function Export-RegKeyText {
    param([string]$RegPath, [string]$OutFile)
    if (Test-Path -LiteralPath $RegPath) {
        "## $RegPath" | Add-Content -LiteralPath $OutFile -Encoding UTF8
        Get-Item -LiteralPath $RegPath -ErrorAction SilentlyContinue |
            Format-List * |
            Out-String -Width 4096 |
            Add-Content -LiteralPath $OutFile -Encoding UTF8

        Get-ChildItem -LiteralPath $RegPath -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object {
                ""
                "### $($_.Name)"
                Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue |
                    Format-List *
            } |
            Out-String -Width 4096 |
            Add-Content -LiteralPath $OutFile -Encoding UTF8
    } else {
        "## Missing: $RegPath" | Add-Content -LiteralPath $OutFile -Encoding UTF8
    }
}

function Add-SetupApiContext {
    param(
        [string]$SetupApiLog,
        [string[]]$Tokens,
        [string]$OutFile,
        [int]$Context = 28
    )

    if (-not (Test-Path -LiteralPath $SetupApiLog)) {
        "Missing setupapi log: $SetupApiLog" | Add-Content -LiteralPath $OutFile -Encoding UTF8
        return
    }

    $lines = Get-Content -LiteralPath $SetupApiLog -ErrorAction SilentlyContinue
    $contextText = foreach ($token in $Tokens) {
        ""
        "==== SetupAPI context for $token ===="
        $hits = for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match [regex]::Escape($token)) { $i }
        }
        if (-not $hits -or $hits.Count -eq 0) {
            "No matches."
            continue
        }

        $selected = New-Object System.Collections.Generic.HashSet[int]
        foreach ($hit in $hits) {
            $start = [Math]::Max(0, $hit - $Context)
            $end = [Math]::Min($lines.Count - 1, $hit + $Context)
            for ($j = $start; $j -le $end; $j++) {
                [void]$selected.Add($j)
            }
        }

        foreach ($idx in ($selected | Sort-Object)) {
            "{0:D7}: {1}" -f ($idx + 1), $lines[$idx]
        }
    }

    $contextText | Add-Content -LiteralPath $OutFile -Encoding UTF8
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $scriptRoot ("QcsubsysAcpiShape_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$targets = @(
    [pscustomobject]@{ Name = "SSDD working"; AcpiId = "QCOM0620"; Expected = "qcsubsys"; Role = "Known working qcsubsys parent/dependency" },
    [pscustomobject]@{ Name = "ADSP failing"; AcpiId = "QCOM061B"; Expected = "qcsubsys"; Role = "Audio DSP root, Phase11 now enumerates" },
    [pscustomobject]@{ Name = "CDSP failing"; AcpiId = "QCOM06B0"; Expected = "qcsubsys"; Role = "Compute DSP root, Phase11 now enumerates" },
    [pscustomobject]@{ Name = "SCSS failing"; AcpiId = "QCOM061F"; Expected = "qcsubsys"; Role = "Sensor DSP root, Phase11 now enumerates" },
    [pscustomobject]@{ Name = "SPSS failing"; AcpiId = "QCOM068D"; Expected = "qcsubsys"; Role = "Secure processor DSP root" },
    [pscustomobject]@{ Name = "CDI unbound"; AcpiId = "QCOM0532"; Expected = ""; Role = "Native PIL dependent node, still Code 28" },
    [pscustomobject]@{ Name = "QSM unbound"; AcpiId = "QCOM0520"; Expected = ""; Role = "Subsystem service manager, still Code 28" },
    [pscustomobject]@{ Name = "PILC working"; AcpiId = "QCOM06E0"; Expected = "qcPILC"; Role = "Working PIL dependency" },
    [pscustomobject]@{ Name = "RPEN working"; AcpiId = "QCOM2533"; Expected = "QCRPEN"; Role = "Working reset/power dependency" }
)

$summaryFile = Join-Path $OutputRoot "00_Summary.txt"
Write-Section $summaryFile "Qcsubsys ACPI shape summary"

$rows = foreach ($target in $targets) {
    $devices = @(Get-DeviceByAcpiId -AcpiId $target.AcpiId)
    $regDevices = @(Get-RegDeviceByAcpiId -AcpiId $target.AcpiId)
    if ($devices.Count -eq 0) {
        if ($regDevices.Count -gt 0) {
            foreach ($regDev in $regDevices) {
                [pscustomobject]@{
                    Name = $target.Name
                    Role = $target.Role
                    AcpiId = $target.AcpiId
                    InstanceId = $regDev.InstanceId
                    FriendlyName = $regDev.FriendlyName
                    Status = $regDev.Status
                    ProblemCode = $regDev.ProblemCode
                    ProblemStatus = ""
                    Service = $regDev.Service
                    MatchingDeviceId = ""
                    CompatibleIds = $regDev.CompatibleIDs
                    LocationPaths = ""
                    Source = $regDev.Source
                }
            }
            continue
        }

        [pscustomobject]@{
            Name = $target.Name
            Role = $target.Role
            AcpiId = $target.AcpiId
            InstanceId = "<not present>"
            FriendlyName = ""
            Status = ""
            ProblemCode = ""
            ProblemStatus = ""
            Service = ""
            MatchingDeviceId = ""
            CompatibleIds = ""
            LocationPaths = ""
            Source = ""
        }
        continue
    }

    foreach ($dev in $devices) {
        $props = Get-PnpPropMap -InstanceId $dev.InstanceId
        [pscustomobject]@{
            Name = $target.Name
            Role = $target.Role
            AcpiId = $target.AcpiId
            InstanceId = $dev.InstanceId
            FriendlyName = $dev.FriendlyName
            Status = $dev.Status
            ProblemCode = $dev.ProblemCode
            ProblemStatus = $props["DEVPKEY_Device_ProblemStatus"]
            Service = $props["DEVPKEY_Device_Service"]
            MatchingDeviceId = $props["DEVPKEY_Device_MatchingDeviceId"]
            CompatibleIds = (@($props["DEVPKEY_Device_CompatibleIds"]) -join ";")
            LocationPaths = (@($props["DEVPKEY_Device_LocationPaths"]) -join ";")
            Source = $dev.Source
        }
    }
}

Add-Text $summaryFile ($rows | Format-Table -AutoSize)
"" | Add-Content -LiteralPath $summaryFile -Encoding UTF8
"PnP row count: $(@($rows | Where-Object { $_.Source -and $_.Source -ne 'EnumRegistry' }).Count)" | Add-Content -LiteralPath $summaryFile -Encoding UTF8
"Registry fallback row count: $(@($rows | Where-Object { $_.Source -eq 'EnumRegistry' }).Count)" | Add-Content -LiteralPath $summaryFile -Encoding UTF8

$detailsFile = Join-Path $OutputRoot "01_PnpProperties.txt"
Write-Section $detailsFile "Target PnP properties"
foreach ($target in $targets) {
    foreach ($dev in @(Get-DeviceByAcpiId -AcpiId $target.AcpiId)) {
        "## $($target.Name) / $($dev.InstanceId)" | Add-Content -LiteralPath $detailsFile -Encoding UTF8
        Add-Text $detailsFile $dev
        Add-Text $detailsFile (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -ErrorAction SilentlyContinue | Sort-Object KeyName | Format-Table KeyName,Type,Data -AutoSize)
    }

    foreach ($regDev in @(Get-RegDeviceByAcpiId -AcpiId $target.AcpiId)) {
        "## Registry fallback: $($target.Name) / $($regDev.InstanceId)" | Add-Content -LiteralPath $detailsFile -Encoding UTF8
        Add-Text $detailsFile $regDev
    }
}

$regFile = Join-Path $OutputRoot "02_EnumRegistry.txt"
Write-Section $regFile "Enum ACPI registry keys"
foreach ($target in $targets) {
    Export-RegKeyText -RegPath ("HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\" + $target.AcpiId) -OutFile $regFile
}

$serviceFile = Join-Path $OutputRoot "03_ServiceAndDriverStore.txt"
Write-Section $serviceFile "Service and driver store state"
$serviceNames = @("qcsubsys", "qcPILC", "QCRPEN", "qcGLINK", "QCIPC_ROUTER", "qcpdsr", "QcTftpKmdf", "qcscm", "qcsmmu", "qcadsprpc", "qcadsprpcd")
foreach ($svcName in $serviceNames) {
    "## $svcName" | Add-Content -LiteralPath $serviceFile -Encoding UTF8
    $svc = Get-CimInstance Win32_SystemDriver -Filter "Name='$svcName'" -ErrorAction SilentlyContinue
    Add-Text $serviceFile $svc
    if ($svc -and $svc.PathName) {
        $sysPath = $svc.PathName -replace '^\\??\\',''
        if (Test-Path -LiteralPath $sysPath) {
            Add-Text $serviceFile (Get-Item -LiteralPath $sysPath | Select-Object FullName,Length,CreationTime,LastWriteTime,VersionInfo)
            try {
                Add-Text $serviceFile (Get-AuthenticodeSignature -LiteralPath $sysPath | Format-List *)
            } catch {
                Add-Text $serviceFile "Signature query failed: $($_.Exception.Message)"
            }
        }
    }
}

$setupFile = Join-Path $OutputRoot "04_SetupApiContext.txt"
Write-Section $setupFile "SetupAPI context"
Add-SetupApiContext -SetupApiLog "$env:windir\INF\setupapi.dev.log" -Tokens @("QCOM0620", "QCOM061B", "QCOM06B0", "QCOM061F", "QCOM068D", "QCOM0532", "QCOM0520") -OutFile $setupFile

$eventFile = Join-Path $OutputRoot "05_KernelPnpAndCodeIntegrityEvents.txt"
Write-Section $eventFile "Recent Kernel-PnP and CodeIntegrity events"
$start = (Get-Date).AddDays(-3)
foreach ($logName in @("System", "Microsoft-Windows-CodeIntegrity/Operational", "Microsoft-Windows-Kernel-PnP/Configuration")) {
    "## $logName" | Add-Content -LiteralPath $eventFile -Encoding UTF8
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = $logName; StartTime = $start } -ErrorAction Stop |
            Where-Object { $_.Message -match "QCOM061B|QCOM06B0|QCOM061F|QCOM068D|QCOM0620|qcsubsys|qcpil|Code Integrity|driver" } |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message
        Add-Text $eventFile $events
    } catch {
        Add-Text $eventFile "Event query failed for ${logName}: $($_.Exception.Message)"
    }
}

$readme = Join-Path $OutputRoot "README.txt"
@"
Qcsubsys ACPI shape trace completed.
Output: $OutputRoot

Send this folder back after booting with Phase11:
$OutputRoot
"@ | Set-Content -LiteralPath $readme -Encoding UTF8

Write-Host "Qcsubsys ACPI shape trace completed:"
Write-Host $OutputRoot
