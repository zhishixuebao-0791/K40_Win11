param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [string[]]$PolicyIds = @(
        "d2bda982-ccf6-4344-ac5b-0b44427b6816",
        "86B04D39-E928-4F0F-937E-0F44B0909E79",
        "1283ac0f-fff1-49ae-ada1-8a933130cad6",
        "2678656c-05ef-481f-bc5b-ebd8c991502d"
    ),
    [int]$MaxEvents = 800
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "WdacPolicyChain_$timestamp"
$policyCopyDir = Join-Path $outDir "ActivePolicyCopies"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
New-Item -ItemType Directory -Force -Path $policyCopyDir | Out-Null

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

function ConvertTo-SafeName {
    param([string]$Name)
    return ($Name -replace '[^0-9A-Za-z_.{}-]', '_')
}

function Get-PrintableStrings {
    param(
        [string]$Path,
        [int]$MinLength = 4
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $ascii = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder

    foreach ($byte in $bytes) {
        if ($byte -ge 32 -and $byte -le 126) {
            [void]$builder.Append([char]$byte)
        } else {
            if ($builder.Length -ge $MinLength) {
                $ascii.Add($builder.ToString())
            }
            [void]$builder.Clear()
        }
    }
    if ($builder.Length -ge $MinLength) {
        $ascii.Add($builder.ToString())
    }

    $unicode = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt ($bytes.Length - 1); $i += 2) {
        $lo = $bytes[$i]
        $hi = $bytes[$i + 1]
        if ($hi -eq 0 -and $lo -ge 32 -and $lo -le 126) {
            [void]$builder.Append([char]$lo)
        } else {
            if ($builder.Length -ge $MinLength) {
                $unicode.Add($builder.ToString())
            }
            [void]$builder.Clear()
        }
    }
    if ($builder.Length -ge $MinLength) {
        $unicode.Add($builder.ToString())
    }

    "==== ASCII strings ===="
    $ascii | Sort-Object -Unique
    "==== UTF-16LE-like strings ===="
    $unicode | Sort-Object -Unique
}

function Get-PolicyEventObjects {
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    $idPattern = (($PolicyIds | ForEach-Object { [regex]::Escape($_.Trim("{}")) }) -join "|")
    $pattern = "Policy|policy|CIP|CiPolicies|Code Integrity|Driver Policy|VerifiedAndReputable|Supplement|supplement|Signer|signer|WDAC|AppControl|Status|0x|failed|invalid|activated|refreshed|$idPattern"
    $events | Where-Object { $_.Message -match $pattern -or $_.Id -in 3004,3076,3077,3085,3089,3091,3095,3096,3099,3116 }
}

Write-Summary "WDAC policy chain trace started."
Write-Summary "Output: $outDir"
Write-Summary "PolicyIds: $($PolicyIds -join ', ')"

$activeDir = Join-Path $env:SystemRoot "System32\CodeIntegrity\CiPolicies\Active"

Save-Text "01_ActivePolicies.txt" {
    "ComputerName: $env:COMPUTERNAME"
    "SystemRoot: $env:SystemRoot"
    "ActiveDir: $activeDir"
    "ActiveDirExists: $(Test-Path -LiteralPath $activeDir)"
    foreach ($id in $PolicyIds) {
        $candidate = Join-Path $activeDir ("{" + $id.Trim("{}") + "}.cip")
        "PolicyId=$id Exists=$(Test-Path -LiteralPath $candidate) Path=$candidate"
    }
    if (Test-Path -LiteralPath $activeDir) {
        Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue |
            Sort-Object Name |
            Select-Object Name, FullName, Length, LastWriteTime,
                @{Name="SHA1";Expression={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA1).Hash}},
                @{Name="SHA256";Expression={(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}} |
            Format-List
    }
}

Save-Text "02_ActivePolicyCopies.txt" {
    if (Test-Path -LiteralPath $activeDir) {
        Get-ChildItem -LiteralPath $activeDir -File -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $policyCopyDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
            "Copied: $($_.FullName) -> $dest"
        }
    } else {
        "Active policy directory not found."
    }
}

Save-Text "03_ActivePolicyMetadataAndStrings.txt" {
    $files = Get-ChildItem -LiteralPath $policyCopyDir -File -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($file in $files) {
        "==== Policy copy: $($file.Name) ===="
        $file | Select-Object FullName, Length, LastWriteTime | Format-List
        Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 | Format-List

        Try-CommandText "Get-CIPolicyIdInfo $($file.Name)" {
            if (Get-Command Get-CIPolicyIdInfo -ErrorAction SilentlyContinue) {
                Get-CIPolicyIdInfo -FilePath $file.FullName | Format-List *
            } else {
                "Get-CIPolicyIdInfo is not available."
            }
        }

        $safeName = ConvertTo-SafeName $file.Name
        $stringsPath = Join-Path $outDir ("policy-strings-$safeName.txt")
        try {
            Get-PrintableStrings -Path $file.FullName | Set-Content -LiteralPath $stringsPath -Encoding UTF8
            "Extracted strings: $stringsPath"
            Select-String -LiteralPath $stringsPath -Pattern "Policy|Base|Supplement|Signer|Update|d2bda982|86B04D39|Andromeda|KMCI|Qualcomm|Microsoft|Driver" -CaseSensitive:$false -ErrorAction SilentlyContinue |
                Select-Object LineNumber, Line |
                Format-Table -AutoSize
        } catch {
            "String extraction failed: $($_.Exception.Message)"
        }
    }
}

Save-Text "04_ConfigCiCapability.txt" {
    "PowerShellVersion: $($PSVersionTable.PSVersion)"
    "ProcessArchitecture: $([System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture)"
    Get-Command -Module ConfigCI -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object Name, Source, Version | Format-Table -AutoSize
    foreach ($cmdName in @("New-CIPolicy", "New-CIPolicyRule", "Set-CIPolicyIdInfo", "Get-CIPolicyIdInfo", "ConvertFrom-CIPolicy", "Merge-CIPolicy", "Add-SignerRule", "Set-RuleOption")) {
        Try-CommandText "Help $cmdName" {
            if (Get-Command $cmdName -ErrorAction SilentlyContinue) {
                Get-Help $cmdName -Detailed | Select-Object -First 80
            } else {
                "$cmdName is not available."
            }
        }
    }
}

Save-Text "05_CiToolCapability.txt" {
    $candidates = @(
        (Join-Path $env:SystemRoot "System32\CiTool.exe"),
        (Join-Path $env:SystemRoot "Sysnative\CiTool.exe"),
        "citool.exe"
    )

    foreach ($candidate in $candidates) {
        "Candidate: $candidate"
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) {
            "Not found."
            continue
        }

        "Resolved: $($cmd.Source)"
        foreach ($args in @(
            @("-?"),
            @("--help"),
            @("-lp"),
            @("--list-policies"),
            @("-json", "-lp"),
            @("-lp", "-json"),
            @("policy", "list"),
            @("policy", "list", "-json"),
            @("--list-policies", "-json")
        )) {
            Try-CommandText ("citool " + ($args -join " ")) {
                & $cmd.Source @args
            }
        }
        break
    }
}

Save-Text "06_CodeIntegrityPolicyEvents.txt" {
    Get-PolicyEventObjects |
        Select-Object TimeCreated, Id, RecordId, LevelDisplayName, ProviderName, Message |
        Format-List
}

Save-Text "07_CodeIntegrityPolicyEventsXml.txt" {
    foreach ($event in (Get-PolicyEventObjects)) {
        "==== RecordId=$($event.RecordId) Id=$($event.Id) Time=$($event.TimeCreated) ===="
        $event.ToXml()
    }
}

Save-Text "08_CiRegistryAndBoot.txt" {
    Try-CommandText "CI registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI" /s }
    Try-CommandText "DeviceGuard SYSTEM registry" { reg query "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /s }
    Try-CommandText "DeviceGuard policy registry" { reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /s }
    Try-CommandText "CodeIntegrity services" { reg query "HKLM\SYSTEM\CurrentControlSet\Services" /f "CodeIntegrity" /s }
    Try-CommandText "bcdedit current" { bcdedit /enum "{current}" }
    Try-CommandText "bcdedit bootmgr" { bcdedit /enum "{bootmgr}" }
    Try-CommandText "bcdedit all" { bcdedit /enum all }
}

Save-Text "09_QcsubsysCurrentState.txt" {
    Try-CommandText "pnputil QCOM2522" {
        pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers
    }
    Try-CommandText "Get-PnpDevice QCOM2522" {
        Get-PnpDevice -InstanceId "ACPI\QCOM2522\2&DABA3FF&0" -ErrorAction SilentlyContinue | Format-List *
    }
    Try-CommandText "Latest qcsubsys Code Integrity events" {
        Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match "qcsubsys8250.sys|QCOM2522|hash could not be found|C0000428|0xC0000428" } |
            Select-Object TimeCreated, Id, RecordId, LevelDisplayName, Message |
            Format-List
    }
}

Save-Text "10_CertificateStores.txt" {
    foreach ($storeName in @("Root", "TrustedPublisher", "CA", "My")) {
        "==== Cert:\LocalMachine\$storeName ===="
        Get-ChildItem -LiteralPath "Cert:\LocalMachine\$storeName" -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match "Andromeda|Qualcomm|Microsoft|Windows" -or $_.Issuer -match "Andromeda|Qualcomm|Microsoft|Windows" } |
            Select-Object Subject, Issuer, Thumbprint, NotBefore, NotAfter, HasPrivateKey |
            Format-List
    }
}

Save-Text "11_AutoVerdict.txt" {
    $events = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents $MaxEvents -ErrorAction SilentlyContinue
    $basePolicyId = "d2bda982-ccf6-4344-ac5b-0b44427b6816"
    $oldSupplementalId = "86B04D39-E928-4F0F-937E-0F44B0909E79"
    $baseEvents = $events | Where-Object { $_.Message -match $basePolicyId -or $_.Message -match "Microsoft Windows Driver Policy" }
    $oldSupplementalEvents = $events | Where-Object { $_.Message -match $oldSupplementalId }
    $qcsubsysBlocks = $events | Where-Object { $_.Message -match "qcsubsys8250.sys.*hash could not be found|hash could not be found.*qcsubsys8250.sys" }
    $basePath = Join-Path $activeDir "{$basePolicyId}.cip"
    $oldSupplementalPath = Join-Path $activeDir "{$oldSupplementalId}.cip"
    $pnp = pnputil /enum-devices /instanceid "ACPI\QCOM2522\2&DABA3FF&0" /drivers 2>&1 | Out-String

    "BasePolicyExists=$(Test-Path -LiteralPath $basePath)"
    "OldSupplementalPolicyExists=$(Test-Path -LiteralPath $oldSupplementalPath)"
    "BasePolicyEvents=$($baseEvents.Count)"
    "OldSupplementalPolicyEvents=$($oldSupplementalEvents.Count)"
    "QcsubsysHashMissingEvents=$($qcsubsysBlocks.Count)"
    "Qcom2522Code52=$([bool]($pnp -match '52|CM_PROB_UNSIGNED_DRIVER'))"
    "RequireMicrosoftSignedBootChain=$((reg query 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' /v RequireMicrosoftSignedBootChain 2>&1 | Out-String).Trim())"

    if ((Test-Path -LiteralPath $basePath) -and $baseEvents.Count -gt 0 -and $qcsubsysBlocks.Count -gt 0) {
        "Verdict=The Microsoft Windows Driver Policy is active and qcsubsys is still blocked by CI."
    }
    if (-not (Test-Path -LiteralPath $oldSupplementalPath)) {
        "VerdictDetail=The previous qcsubsys hash supplemental policy has been removed from Active; this is the clean state needed for the next experiment."
    }
    "SuggestedNext=Inspect active base policy acceptance/signing constraints. If unsigned supplemental policy is not loaded, choose either signed supplemental policy with an accepted signer or a controlled base-policy merge/replacement experiment."
}

Write-Summary "Collection completed: $outDir"
Write-Host "WDAC policy chain trace completed: $outDir"

