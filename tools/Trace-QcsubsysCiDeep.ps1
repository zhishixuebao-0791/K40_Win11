param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [int]$MaxEvents = 400
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "QcsubsysCiDeep_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Write-Summary {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
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

function Try-CommandText {
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

function Get-QcsubsysPaths {
    $service = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "qcsubsys" } |
        Select-Object -First 1

    $sysPath = $null
    if ($service) {
        $sysPath = $service.PathName -replace '^\\??\\', ''
        if ($sysPath -match '^\\SystemRoot\\') {
            $sysPath = $sysPath -replace '^\\SystemRoot\\', $env:SystemRoot
        }
    }

    $driverDir = $null
    if ($sysPath -and (Test-Path -LiteralPath $sysPath)) {
        $driverDir = Split-Path -Parent $sysPath
    } else {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot "System32\DriverStore\FileRepository") -Directory -Filter "qcsubsys8250.inf_arm64*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            $driverDir = $candidate.FullName
            $sysPath = Join-Path $driverDir "qcsubsys8250.sys"
        }
    }

    $catPath = $null
    $infPath = $null
    if ($driverDir) {
        $cat = Get-ChildItem -LiteralPath $driverDir -Filter "*.cat" -ErrorAction SilentlyContinue | Select-Object -First 1
        $inf = Get-ChildItem -LiteralPath $driverDir -Filter "*.inf" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cat) { $catPath = $cat.FullName }
        if ($inf) { $infPath = $inf.FullName }
    }

    [pscustomobject]@{
        Service = $service
        SysPath = $sysPath
        CatPath = $catPath
        InfPath = $infPath
        DriverDir = $driverDir
    }
}

Write-Summary "Qcsubsys deep Code Integrity trace started."
Write-Summary "Output: $outDir"

$paths = Get-QcsubsysPaths
Write-Summary "DriverDir: $($paths.DriverDir)"
Write-Summary "SysPath: $($paths.SysPath)"
Write-Summary "CatPath: $($paths.CatPath)"
Write-Summary "InfPath: $($paths.InfPath)"

Save-Text "01_QCOM2522_PnP_Extended.txt" {
    Try-CommandText "pnputil QCOM2522 with drivers" {
        pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers
    }
    Try-CommandText "pnputil System filtered" {
        pnputil /enum-devices /class System |
            Select-String -Pattern "QCOM2522|qcsubsys|Subsystem Dependency|Problem|Status|Driver|Signer"
    }
    Try-CommandText "Get-PnpDevice QCOM2522" {
        Get-PnpDevice -InstanceId "ACPI\QCOM2522\2&DABA3FF&0" -ErrorAction SilentlyContinue | Format-List *
    }
    Try-CommandText "Get-PnpDeviceProperty QCOM2522" {
        Get-PnpDeviceProperty -InstanceId "ACPI\QCOM2522\2&DABA3FF&0" -ErrorAction SilentlyContinue |
            Sort-Object KeyName |
            Format-List KeyName, Type, Data
    }
    Try-CommandText "CIM PnPEntity QCOM2522" {
        Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.PNPDeviceID -match "QCOM2522|qcsubsys|Subsystem Dependency" } |
            Format-List *
    }
}

Save-Text "02_DriverStore_Catalog_Hash.txt" {
    "Resolved paths:"
    $paths | Format-List *

    foreach ($file in @($paths.SysPath, $paths.CatPath, $paths.InfPath)) {
        if ($file -and (Test-Path -LiteralPath $file)) {
            "==== File: $file ===="
            Get-Item -LiteralPath $file | Format-List FullName, Length, CreationTime, LastWriteTime
            Get-FileHash -LiteralPath $file -Algorithm SHA1 | Format-List
            Get-FileHash -LiteralPath $file -Algorithm SHA256 | Format-List
            Get-AuthenticodeSignature -LiteralPath $file | Format-List *
        } else {
            "Missing file: $file"
        }
    }

    if ($paths.CatPath -and (Test-Path -LiteralPath $paths.CatPath)) {
        Try-CommandText "certutil dump catalog" { certutil -dump $paths.CatPath }
        Try-CommandText "certutil verify catalog" { certutil -verify $paths.CatPath }
    }

    Try-CommandText "pnputil enum-drivers filtered" {
        pnputil /enum-drivers |
            Select-String -Pattern "oem5.inf|qcsubsys8250|Qualcomm|Andromeda|Signer|Class|Provider" -Context 1,4
    }

    Try-CommandText "pnputil enum-drivers files if supported" {
        pnputil /enum-drivers /files |
            Select-String -Pattern "oem5.inf|qcsubsys8250|qcsubsys8250.sys|qcsubsys8250.cat|FileRepository" -Context 2,4
    }

    Try-CommandText "CatRoot qcsubsys/oem catalog search" {
        $roots = @(
            (Join-Path $env:SystemRoot "System32\catroot"),
            (Join-Path $env:SystemRoot "System32\catroot2")
        )
        foreach ($root in $roots) {
            if (Test-Path -LiteralPath $root) {
                "Root: $root"
                Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "qcsubsys|oem5|ssde" } |
                    Select-Object FullName, Length, LastWriteTime
            }
        }
    }
}

Save-Text "03_CodeIntegrity_Events_Parsed.txt" {
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    $events |
        Where-Object { $_.Message -match "qcsubsys|QCOM2522|C0000428|0xC0000428|hash could not be found|file hash|Driver Policy|WHQL|Andromeda|KMCI" } |
        Select-Object TimeCreated, Id, RecordId, LevelDisplayName, ProviderName, Message |
        Format-List
}

Save-Text "04_CodeIntegrity_Events_Xml.txt" {
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    $filtered = $events | Where-Object { $_.Message -match "qcsubsys|QCOM2522|C0000428|0xC0000428|hash could not be found|file hash|Driver Policy|WHQL|Andromeda|KMCI" }
    foreach ($event in $filtered) {
        "==== RecordId=$($event.RecordId) Id=$($event.Id) Time=$($event.TimeCreated) ===="
        $event.ToXml()
    }
}

Save-Text "05_System_KernelPnp_Service_Events.txt" {
    Get-WinEvent -LogName "System" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "QCOM2522|qcsubsys|CodeIntegrity|blocked|Driver|Kernel-PnP|Service Control Manager" } |
        Select-Object TimeCreated, Id, RecordId, ProviderName, LevelDisplayName, Message |
        Format-List
}

Save-Text "06_CI_BCD_DeviceGuard_State.txt" {
    Try-CommandText "bcdedit current" { bcdedit /enum "{current}" }
    Try-CommandText "bcdedit all" { bcdedit /enum all }
    Try-CommandText "SecureBoot" { Confirm-SecureBootUEFI }
    Try-CommandText "CI registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI" /s }
    Try-CommandText "DeviceGuard SYSTEM registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /s }
    Try-CommandText "DeviceGuard SOFTWARE policy registry" { reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /s }
    Try-CommandText "CodeIntegrity directory" {
        Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot "System32\CodeIntegrity") -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object FullName, Length, LastWriteTime
    }
    Try-CommandText "Active CI policies" {
        $active = Join-Path $env:SystemRoot "System32\CodeIntegrity\CiPolicies\Active"
        if (Test-Path -LiteralPath $active) {
            Get-ChildItem -LiteralPath $active -File -ErrorAction SilentlyContinue |
                Select-Object FullName, Length, LastWriteTime
        } else {
            "Active CI policy directory not found: $active"
        }
    }
}

Save-Text "07_CertStores_Andromeda.txt" {
    Try-CommandText "certutil Root filtered" {
        certutil -store Root |
            Select-String -Pattern "Andromeda|D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627|KMCI|Production PCA|Root Platform" -Context 1,3
    }
    Try-CommandText "certutil TrustedPublisher filtered" {
        certutil -store TrustedPublisher |
            Select-String -Pattern "Andromeda|D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627|KMCI|Production PCA|Root Platform" -Context 1,3
    }
    Try-CommandText "PowerShell certificate view" {
        Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Subject -match "Andromeda|KMCI|Production PCA|Root Platform" -or
                $_.Thumbprint -match "D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627|946CF507369A80E65F2B58BEBF5D02CC159A484D"
            } |
            Select-Object PSParentPath, Subject, Issuer, Thumbprint, NotBefore, NotAfter |
            Format-List
    }
}

Save-Text "08_SetupApi_Qcsubsys_Focused.txt" {
    $setupLog = Join-Path $env:windir "INF\setupapi.dev.log"
    if (Test-Path -LiteralPath $setupLog) {
        Select-String -LiteralPath $setupLog -Pattern "QCOM2522|qcsubsys|qcsubsys8250|oem5.inf|C0000428|Code 52|signature|certificate|catalog|Signer Score|Signer Name|rank" -Context 10,18
    } else {
        "setupapi.dev.log not found: $setupLog"
    }
}

Save-Text "09_Ssde_Rollback_State.txt" {
    Try-CommandText "SSDE service" { reg query "HKLM\SYSTEM\CurrentControlSet\Services\ssde" /s }
    Try-CommandText "SSDE INF search" {
        Get-ChildItem -LiteralPath (Join-Path $env:windir "INF") -Filter "oem*.inf" -File -ErrorAction SilentlyContinue |
            Select-String -Pattern "ssde.inf|ssde.sys|Root\\SSDE|ACPI\\SSDE|Self-Signed Driver Enabler" -SimpleMatch |
            Select-Object Path, LineNumber, Line
    }
    Try-CommandText "SSDE DriverStore search" {
        Get-ChildItem -LiteralPath (Join-Path $env:windir "System32\DriverStore\FileRepository") -Filter "ssde.inf_arm64*" -Directory -ErrorAction SilentlyContinue |
            Select-Object FullName, LastWriteTime
    }
}

Save-Text "10_AutoVerdict.txt" {
    $pnp = pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers 2>&1 | Out-String
    $ci = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match "qcsubsys8250.sys|hash could not be found|file hash" } |
        Select-Object -First 5
    $sig = $null
    if ($paths.SysPath -and (Test-Path -LiteralPath $paths.SysPath)) {
        $sig = Get-AuthenticodeSignature -LiteralPath $paths.SysPath
    }

    "ProblemCode52Present=" + [bool]($pnp -match "52|CM_PROB_UNSIGNED_DRIVER")
    "ProblemStatusC0000428Present=" + [bool]($pnp -match "C0000428")
    "SysSignatureStatus=" + $(if ($sig) { $sig.Status } else { "<missing>" })
    "CiHashMissingEventPresent=" + [bool]($ci)
    if (($pnp -match "52|CM_PROB_UNSIGNED_DRIVER") -and ($sig.Status -eq "Valid") -and $ci) {
        "Verdict=Catalog/authenticode signature is valid, but kernel Code Integrity policy does not have an accepted hash/policy entry for qcsubsys8250.sys."
        "SuggestedNext=Try a qcsubsys-only WDAC hash allow policy, not SSDE. Keep rollback ready."
    } else {
        "Verdict=Evidence is incomplete or points to a different failure. Review detailed files."
    }
}

Write-Summary "Collection completed: $outDir"
Write-Host "Qcsubsys deep Code Integrity trace completed: $outDir"
