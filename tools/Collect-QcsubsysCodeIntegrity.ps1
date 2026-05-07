param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11"
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "QcsubsysCodeIntegrity_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Write-Section {
    param([string]$Name)
    "`r`n==== $Name ====" | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
}

function Save-Text {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    $path = Join-Path $outDir $Name
    try {
        & $Command *>&1 | Out-String -Width 4096 | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Save-EventLog {
    param(
        [string]$Name,
        [string]$LogName,
        [string[]]$Patterns
    )

    $path = Join-Path $outDir $Name
    try {
        $events = Get-WinEvent -LogName $LogName -MaxEvents 250 -ErrorAction Stop
        if ($Patterns -and $Patterns.Count -gt 0) {
            $events = $events | Where-Object {
                $message = $_.Message
                foreach ($pattern in $Patterns) {
                    if ($message -match $pattern -or $_.ProviderName -match $pattern) {
                        return $true
                    }
                }
                return $false
            }
        }

        $events |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Format-List |
            Out-String -Width 4096 |
            Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        "ERROR: $($_.Exception.Message)" | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

Write-Section "Qcsubsys Code Integrity collection"
"Time: $(Get-Date -Format s)" | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
"Output: $outDir" | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append

Save-Text "01_Pnp_QCOM2522.txt" {
    pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers
    pnputil /enum-devices /class System | Select-String -Pattern "QCOM2522|qcsubsys|Subsystem Dependency|Problem|Status|Driver"
}

Save-Text "02_Qcsubsys_Service.txt" {
    Get-CimInstance Win32_SystemDriver |
        Where-Object { $_.Name -match "qcsubsys|qcPILC|QCRPEN|qcGLINK|QCIPC_ROUTER|qcpdsr|QcTftpKmdf|qcscm" } |
        Select-Object Name, State, StartMode, PathName, DisplayName |
        Format-List
}

Save-Text "03_Qcsubsys_DriverStore_Signatures.txt" {
    $drivers = Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -eq "qcsubsys" }
    foreach ($driver in $drivers) {
        "Service: $($driver.Name)"
        "PathName: $($driver.PathName)"
        $sysPath = $driver.PathName -replace '^\\??\\', ''
        if ($sysPath -match '^\\SystemRoot\\') {
            $sysPath = $sysPath -replace '^\\SystemRoot\\', $env:SystemRoot
        }
        if ($sysPath -and (Test-Path -LiteralPath $sysPath)) {
            "ResolvedSys: $sysPath"
            Get-AuthenticodeSignature -LiteralPath $sysPath | Format-List *
            $repoDir = Split-Path -Parent $sysPath
            Get-ChildItem -LiteralPath $repoDir -Filter "*.cat" -ErrorAction SilentlyContinue | ForEach-Object {
                "Catalog: $($_.FullName)"
                Get-AuthenticodeSignature -LiteralPath $_.FullName | Format-List *
            }
            Get-ChildItem -LiteralPath $repoDir -Filter "*.inf" -ErrorAction SilentlyContinue | ForEach-Object {
                "INF: $($_.FullName)"
                Get-Content -LiteralPath $_.FullName | Select-String -Pattern "QCOM2522|qcsubsys|CatalogFile|Provider|DriverVer|KMCI|Andromeda"
            }
        } else {
            "Resolved sys path not found: $sysPath"
        }
    }
}

Save-Text "04_Certificate_Stores.txt" {
    "=== certutil Root filtered ==="
    certutil -store Root | Select-String -Pattern "Andromeda|D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627|KMCI|Production PCA|Root Platform"
    "=== certutil TrustedPublisher filtered ==="
    certutil -store TrustedPublisher | Select-String -Pattern "Andromeda|D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627|KMCI|Production PCA|Root Platform"
    "=== PowerShell cert view ==="
    Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match "Andromeda|KMCI|Production PCA|Root Platform" -or $_.Thumbprint -match "D9254DAC570E3D582B429B162A70E7AD23FC5736|C767958C1A48D3831DB3FF69AA45083CB8397627" } |
        Select-Object PSParentPath, Subject, Issuer, Thumbprint, NotBefore, NotAfter |
        Format-List
}

Save-Text "05_Boot_CI_Settings.txt" {
    bcdedit /enum "{current}"
    bcdedit /enum "{default}"
    reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI" /s
}

Save-EventLog "06_CodeIntegrity_Operational.txt" "Microsoft-Windows-CodeIntegrity/Operational" @("qcsubsys", "qcpil", "QCOM2522", "C0000428", "0xC0000428", "Andromeda", "KMCI", "signature", "certificate", "integrity")
Save-EventLog "07_System_CI_PnP_Service.txt" "System" @("CodeIntegrity", "Kernel-PnP", "Service Control Manager", "qcsubsys", "qcpil", "QCOM2522", "C0000428", "0xC0000428")

Save-Text "08_SetupApi_Qcsubsys.txt" {
    $setupLog = Join-Path $env:windir "INF\setupapi.dev.log"
    if (Test-Path -LiteralPath $setupLog) {
        Select-String -LiteralPath $setupLog -Pattern "QCOM2522|qcsubsys|qcsubsys8250|C0000428|signature|certificate|Code 52" -Context 6,12
    } else {
        "setupapi.dev.log not found"
    }
}

Write-Section "Completed"
"Collection completed: $outDir" | Tee-Object -FilePath (Join-Path $outDir "00_Summary.txt") -Append
Write-Host "Qcsubsys Code Integrity collection completed: $outDir"
