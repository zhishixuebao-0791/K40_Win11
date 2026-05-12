param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [string]$DriverDir = "C:\Code\REDMIK40_Win11\drivers\qcpilext8280",
    [string]$PilcInstanceId = "ACPI\QCOM06E0\2&DABA3FF&0"
)

$ErrorActionPreference = "Continue"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "QcpilExt8280Rebind_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir "00_rebind.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $logPath -Append
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

function Invoke-Captured {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $global:LASTEXITCODE = 0
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    $output | Tee-Object -FilePath $logPath -Append
    if (($exitCode -ne 0) -and (-not $IgnoreExitCode)) {
        Write-Log "Command exit code: $exitCode"
    }
    return $output
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

function Save-PilcState {
    param([string]$Prefix)

    Save-Text "${Prefix}_pilc_pnp.txt" {
        Get-PnpDevice -InstanceId $PilcInstanceId -ErrorAction SilentlyContinue | Format-List *
        ""
        $propertyRows = foreach ($key in @(
            "DEVPKEY_Device_ProblemCode",
            "{4340A6C5-93FA-4706-972C-7B648008A5A7} 5",
            "DEVPKEY_Device_Service",
            "DEVPKEY_Device_DriverInfPath",
            "DEVPKEY_Device_MatchingDeviceId",
            "DEVPKEY_Device_HardwareIds",
            "DEVPKEY_Device_CompatibleIds",
            "DEVPKEY_Device_ExtendedConfigurationIds",
            "DEVPKEY_Device_Stack",
            "DEVPKEY_Device_UpperFilters",
            "DEVPKEY_Device_LowerFilters"
        )) {
            [pscustomobject]@{
                Key = $key
                Data = @(Get-Prop -InstanceId $PilcInstanceId -KeyName $key) -join ";"
            }
        }
        $propertyRows | Format-Table -AutoSize
    }

    Save-Text "${Prefix}_pnputil_device.txt" {
        Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/enum-devices", "/instanceid", $PilcInstanceId, "/properties", "/resources") -IgnoreExitCode
    }
}

Write-Log "Starting qcpilEXT8280 online rebind."
Write-Log "OutputRoot: $OutputRoot"
Write-Log "DriverDir: $DriverDir"
Write-Log "PilcInstanceId: $PilcInstanceId"

$infPath = Join-Path $DriverDir "qcpilEXT8280.inf"
if (-not (Test-Path -LiteralPath $infPath)) {
    Write-Log "Driver INF missing: $infPath"
    throw "Driver INF missing: $infPath"
}

Save-Text "01_driverstore_before.txt" {
    Get-ChildItem -LiteralPath "$env:windir\System32\DriverStore\FileRepository" -Directory -Filter "qcpilext8280.inf_*" -ErrorAction SilentlyContinue |
        Select-Object FullName, LastWriteTime |
        Format-List
    ""
    Get-ChildItem -LiteralPath "$env:windir\INF" -Filter "oem*.inf" -ErrorAction SilentlyContinue |
        Select-String -Pattern "qcpilEXT8280", "8AB9D1D1-199E-482C-A2C9-C11F660260E6", "ACPI\VEN_QCOM&DEV_06E0&SUBSYS_MTP08280" -SimpleMatch |
        Select-Object Path, LineNumber, Line |
        Format-Table -AutoSize
}

Save-PilcState -Prefix "02_before"

Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/add-driver", $infPath, "/install") -IgnoreExitCode | Out-Null
Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/scan-devices") -IgnoreExitCode | Out-Null

Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/restart-device", $PilcInstanceId) -IgnoreExitCode | Out-Null
Start-Sleep -Seconds 3
Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/disable-device", $PilcInstanceId) -IgnoreExitCode | Out-Null
Start-Sleep -Seconds 2
Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/enable-device", $PilcInstanceId) -IgnoreExitCode | Out-Null
Start-Sleep -Seconds 5
Invoke-Captured -FilePath "pnputil.exe" -Arguments @("/scan-devices") -IgnoreExitCode | Out-Null

Save-Text "03_setupapi_recent.txt" {
    $setupApi = Join-Path $env:windir "INF\setupapi.dev.log"
    if (Test-Path -LiteralPath $setupApi) {
        Select-String -LiteralPath $setupApi -Pattern "QCOM06E0", "qcpilEXT8280", "qcpilext8280", "oem18.inf", "CM_PROB_FAILED_ADD", "0xc0000001" -SimpleMatch -Context 6,14 |
            Select-Object -Last 220
    } else {
        "setupapi.dev.log not found: $setupApi"
    }
}

Save-PilcState -Prefix "04_after"

Save-Text "05_codeintegrity_kernelpnp_recent.txt" {
    $bootTime = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
    if (-not $bootTime) {
        $bootTime = (Get-Date).AddHours(-3)
    }
    "BootTime=$bootTime"
    ""
    "==== CodeIntegrity ===="
    Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-CodeIntegrity/Operational"; StartTime = $bootTime } -MaxEvents 1000 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcpil|qcPIL|qcpilext|QCOM06E0|signature|policy|integrity|0xC0000428" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
    ""
    "==== Kernel-PnP ===="
    Get-WinEvent -FilterHashtable @{ LogName = "System"; ProviderName = "Microsoft-Windows-Kernel-PnP"; StartTime = $bootTime } -MaxEvents 1000 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "QCOM06E0|qcpil|qcPIL|Image Loader" } |
        Select-Object TimeCreated, Id, ProviderName, Message |
        Format-List *
}

Write-Log "qcpilEXT8280 online rebind completed."
Write-Host "qcpilEXT8280 online rebind completed."
Write-Host "Output: $outDir"
