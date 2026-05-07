param(
    [string]$WindowsDrive = "D",
    [switch]$SkipDismRemove,
    [switch]$AllowHostSystemDrive
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run from an elevated Administrator PowerShell window."
    }
}

function Write-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    if ($script:LogPath) {
        $line | Add-Content -LiteralPath $script:LogPath -Encoding UTF8
    }
}

function Invoke-Native {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    Write-Log ("Running: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldErrorActionPreference

    if ($output) {
        $output | ForEach-Object { Write-Log ([string]$_) }
    }

    if (($exitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Command failed with exit code $exitCode`: $FilePath"
    }

    return $exitCode
}

function Get-WindowsRoot {
    param([string]$Drive)

    $normalized = $Drive.TrimEnd(':', '\')
    if (-not $AllowHostSystemDrive) {
        $hostDrive = $env:SystemDrive.TrimEnd(':', '\')
        if ($normalized -ieq $hostDrive) {
            throw "Refusing to operate on host system drive ${normalized}: . In Mass Storage mode the phone Windows partition should be D: or another removable drive. Use -AllowHostSystemDrive only if you intentionally target this PC."
        }
    }

    $root = "${normalized}:\"
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\System32\Config\SYSTEM"))) {
        throw "Offline Windows SYSTEM hive not found under $root"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root "Windows\INF"))) {
        throw "Offline Windows INF directory not found under $root"
    }
    return $root
}

function Get-ActiveControlSet {
    param([string]$HiveName)

    $controlSet = "ControlSet001"
    $selectOutput = & reg.exe query "HKLM\$HiveName\Select" /v Current 2>&1
    if ($LASTEXITCODE -eq 0) {
        $currentLine = $selectOutput | Where-Object { $_ -match "\s+Current\s+REG_DWORD\s+" } | Select-Object -First 1
        if ($currentLine) {
            $currentRaw = ($currentLine -split "\s+")[-1]
            $current = [Convert]::ToInt32(($currentRaw -replace "^0x", ""), 16)
            $controlSet = "ControlSet{0:D3}" -f $current
        }
    }

    return $controlSet
}

function Find-SsdeOemInfs {
    param([string]$WindowsRoot)

    $infRoot = Join-Path $WindowsRoot "Windows\INF"
    $matches = New-Object System.Collections.Generic.List[string]
    $patterns = @(
        "ssde.inf",
        "ssde.sys",
        "Root\\SSDE",
        "ACPI\\SSDE",
        "Self-Signed Driver Enabler"
    )

    foreach ($inf in Get-ChildItem -LiteralPath $infRoot -Filter "oem*.inf" -File) {
        $hit = Select-String -LiteralPath $inf.FullName -Pattern $patterns -SimpleMatch -Quiet -ErrorAction SilentlyContinue
        if ($hit) {
            $matches.Add($inf.Name)
            Write-Log "Matched SSDE OEM INF: $($inf.FullName)"
        }
    }

    return @($matches)
}

function Export-KeyIfExists {
    param(
        [string]$KeyPath,
        [string]$ExportPath
    )

    $null = & reg.exe query $KeyPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Registry key absent, skip export: $KeyPath"
        return
    }

    Invoke-Native -FilePath "reg.exe" -Arguments @("export", $KeyPath, $ExportPath, "/y") -AllowFailure | Out-Null
}

function Disable-OfflineSsde {
    param([string]$WindowsRoot)

    $hiveName = "ALIOTH_SSDE_ROLLBACK_SYSTEM_{0}" -f (Get-Random)
    $hivePath = Join-Path $WindowsRoot "Windows\System32\Config\SYSTEM"
    $loaded = $false

    try {
        Invoke-Native -FilePath "reg.exe" -Arguments @("load", "HKLM\$hiveName", $hivePath) | Out-Null
        $loaded = $true

        $activeControlSet = Get-ActiveControlSet -HiveName $hiveName
        Write-Log "Offline active control set: $activeControlSet"

        $controlSets = @()
        $controlSetOutput = & reg.exe query "HKLM\$hiveName" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $controlSets = $controlSetOutput |
                Where-Object { $_ -match "\\ControlSet\d{3}$" } |
                ForEach-Object { Split-Path $_ -Leaf } |
                Sort-Object -Unique
        }
        if (-not $controlSets) {
            $controlSets = @($activeControlSet)
        }
        Write-Log ("Control sets selected for rollback: {0}" -f ($controlSets -join ", "))

        $backupRoot = Join-Path $script:LogRoot ("woa-ssde-rollback-reg-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
        New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

        foreach ($controlSet in $controlSets) {
            Export-KeyIfExists -KeyPath "HKLM\$hiveName\$controlSet\Services\ssde" -ExportPath (Join-Path $backupRoot "$controlSet-services-ssde.reg")
            Export-KeyIfExists -KeyPath "HKLM\$hiveName\$controlSet\Control\CI" -ExportPath (Join-Path $backupRoot "$controlSet-control-ci.reg")
        }
        Write-Log "Registry backup directory: $backupRoot"

        foreach ($controlSet in $controlSets) {
            $serviceKey = "HKLM\$hiveName\$controlSet\Services\ssde"
            $null = & reg.exe query $serviceKey 2>&1
            if ($LASTEXITCODE -eq 0) {
                Invoke-Native -FilePath "reg.exe" -Arguments @("add", $serviceKey, "/v", "Start", "/t", "REG_DWORD", "/d", "4", "/f") | Out-Null
                Write-Log "Disabled offline ssde service Start=4 under $controlSet."
            } else {
                Write-Log "ssde service key was not present under $controlSet."
            }

            $ciProtected = "HKLM\$hiveName\$controlSet\Control\CI\Protected"
            Invoke-Native -FilePath "reg.exe" -Arguments @("add", $ciProtected, "/v", "Licensed", "/t", "REG_DWORD", "/d", "0", "/f") -AllowFailure | Out-Null

            $ciPolicy = "HKLM\$hiveName\$controlSet\Control\CI\Policy"
            $null = & reg.exe query $ciPolicy /v WhqlSettings 2>&1
            if ($LASTEXITCODE -eq 0) {
                Invoke-Native -FilePath "reg.exe" -Arguments @("add", $ciPolicy, "/v", "WhqlSettings", "/t", "REG_DWORD", "/d", "0", "/f") -AllowFailure | Out-Null
            } else {
                Write-Log "CI Policy WhqlSettings was absent under $controlSet."
            }
        }
    } finally {
        if ($loaded) {
            [gc]::Collect()
            Start-Sleep -Milliseconds 300
            Invoke-Native -FilePath "reg.exe" -Arguments @("unload", "HKLM\$hiveName") -AllowFailure | Out-Null
        }
    }
}

function Remove-SsdeDriverPackages {
    param(
        [string]$WindowsRoot,
        [string[]]$OemInfs
    )

    if ($SkipDismRemove) {
        Write-Log "SkipDismRemove was set; not removing SSDE driver packages."
        return
    }

    foreach ($oemInf in $OemInfs) {
        Invoke-Native -FilePath "dism.exe" -Arguments @("/Image:$WindowsRoot", "/Remove-Driver", "/Driver:$oemInf") -AllowFailure | Out-Null
    }
}

function Write-RemainingSsdeState {
    param([string]$WindowsRoot)

    $driverStore = Join-Path $WindowsRoot "Windows\System32\DriverStore\FileRepository"
    $leftovers = Get-ChildItem -LiteralPath $driverStore -Filter "ssde.inf_arm64*" -Directory -ErrorAction SilentlyContinue
    foreach ($leftover in $leftovers) {
        Write-Log "Remaining SSDE DriverStore directory: $($leftover.FullName)"
    }

    $oemInfs = Find-SsdeOemInfs -WindowsRoot $WindowsRoot
    if ($oemInfs.Count -eq 0) {
        Write-Log "No remaining SSDE OEM INF matched."
    } else {
        Write-Log ("Remaining SSDE OEM INF(s): {0}" -f ($oemInfs -join ", "))
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Assert-Administrator

$script:LogRoot = Join-Path $repoRoot "Alioth-Engineering\logs"
New-Item -ItemType Directory -Force -Path $script:LogRoot | Out-Null
$script:LogPath = Join-Path $script:LogRoot ("woa-ssde-rollback-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Log "Rolling back WOA SSDE package from offline Alioth Windows image."
Write-Log "WindowsDrive=$WindowsDrive"

$windowsRoot = Get-WindowsRoot -Drive $WindowsDrive
$oemInfs = Find-SsdeOemInfs -WindowsRoot $windowsRoot

Disable-OfflineSsde -WindowsRoot $windowsRoot
Remove-SsdeDriverPackages -WindowsRoot $windowsRoot -OemInfs $oemInfs
Write-RemainingSsdeState -WindowsRoot $windowsRoot

Write-Log "WOA SSDE rollback completed. Boot Phase6 UEFI again. Expected result: system should no longer fail on ssde.sys; qcsubsys may return to Code 52 until we choose a safer signing path."
