param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [string]$QcsubsysHint = "qcsubsys8250"
)

$ErrorActionPreference = "Continue"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $script:LogPath -Append
}

function Invoke-Captured {
    param(
        [string]$Name,
        [scriptblock]$Script
    )

    $path = Join-Path $script:OutDir ("{0}.txt" -f $Name)
    Write-Log "Running $Name"
    try {
        & $Script *>&1 | Out-File -LiteralPath $path -Encoding UTF8
        Write-Log "$Name completed"
    } catch {
        $_ | Out-File -LiteralPath $path -Append -Encoding UTF8
        Write-Log "$Name failed: $($_.Exception.Message)"
    }
}

function Get-FileBrief {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Path = $Path
            Present = $false
            Length = $null
            Sha256 = $null
            SignatureStatus = $null
            Signer = $null
            Issuer = $null
        }
    }

    $item = Get-Item -LiteralPath $Path
    $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
    $sig = Get-AuthenticodeSignature -LiteralPath $Path
    return [pscustomobject]@{
        Path = $Path
        Present = $true
        Length = $item.Length
        Sha256 = $hash.Hash
        SignatureStatus = [string]$sig.Status
        Signer = if ($sig.SignerCertificate) { [string]$sig.SignerCertificate.Subject } else { "" }
        Issuer = if ($sig.SignerCertificate) { [string]$sig.SignerCertificate.Issuer } else { "" }
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$script:OutDir = Join-Path $OutputRoot ("WdacRebuildability_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $script:OutDir | Out-Null
$script:LogPath = Join-Path $script:OutDir "00_trace.log"

Write-Log "WDAC rebuildability trace started."
Write-Log "Output: $script:OutDir"

Invoke-Captured "01_os_and_identity" {
    whoami /all
    Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsBuildNumber,OsArchitecture
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture
}

Invoke-Captured "02_configci_commands" {
    Get-Command -Module ConfigCI | Select-Object Name,CommandType | Sort-Object Name
    foreach ($cmd in "ConvertFrom-CIPolicy","New-CIPolicy","Merge-CIPolicy","Set-CIPolicyIdInfo","Get-CIPolicyIdInfo","Get-CIPolicyInfo") {
        "== $cmd =="
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            (Get-Command $cmd).Parameters.GetEnumerator() | Sort-Object Key | ForEach-Object {
                "{0} : {1}" -f $_.Key, $_.Value.ParameterType.FullName
            }
        } else {
            "missing"
        }
    }
}

Invoke-Captured "03_policy_locations" {
    $locations = @(
        "C:\Windows\System32\CodeIntegrity",
        "C:\Windows\System32\CodeIntegrity\CiPolicies\Active",
        "D:\EFI\Microsoft\Boot",
        "D:\EFI\Microsoft\Boot\CiPolicies\Active",
        "D:\EFI\Microsoft\Boot\SecureBootPolicy"
    )
    foreach ($loc in $locations) {
        "== $loc =="
        if (Test-Path -LiteralPath $loc) {
            Get-ChildItem -LiteralPath $loc -Force -ErrorAction SilentlyContinue |
                Select-Object FullName,Name,Length,LastWriteTime,Mode
        } else {
            "missing"
        }
        ""
    }
}

Invoke-Captured "04_policy_file_signatures" {
    $paths = @(
        "C:\Windows\System32\CodeIntegrity\driversipolicy.p7b",
        "C:\Windows\System32\CodeIntegrity\VbsSiPolicy.p7b",
        "C:\Windows\System32\CodeIntegrity\driver.stl",
        "D:\EFI\Microsoft\Boot\driversipolicy.p7b",
        "D:\EFI\Microsoft\Boot\SiPolicy.p7b"
    )
    $paths | ForEach-Object { Get-FileBrief -Path $_ } | Format-List
}

$driverPolicy = "C:\Windows\System32\CodeIntegrity\driversipolicy.p7b"
Invoke-Captured "05_driversipolicy_reverse_convert_note" {
    @(
        "driversipolicy=$driverPolicy",
        "ConvertFrom-CIPolicy compiles XML to binary policy; it does not reverse-convert an existing p7b back to XML.",
        "Windows built-in ConfigCI tools do not expose a supported driversipolicy.p7b to XML decompiler in this environment.",
        "Therefore base-policy merge requires an existing XML source, not only the deployed Microsoft p7b."
    )
}

Invoke-Captured "06_get_policy_id_info" {
    foreach ($p in @(
        "C:\Windows\System32\CodeIntegrity\driversipolicy.p7b",
        "C:\Windows\System32\CodeIntegrity\VbsSiPolicy.p7b"
    )) {
        "== $p =="
        if (Test-Path -LiteralPath $p) {
            Get-CIPolicyIdInfo -FilePath $p
        } else {
            "missing"
        }
    }
}

$qcCandidateDir = $null
Invoke-Captured "07_qcsubsys_driverstore_candidates" {
    $store = "C:\Windows\System32\DriverStore\FileRepository"
    Get-ChildItem -LiteralPath $store -Directory -Filter "$QcsubsysHint*" -ErrorAction SilentlyContinue |
        Select-Object FullName,Name,LastWriteTime
    $global:qcCandidateDir = (Get-ChildItem -LiteralPath $store -Directory -Filter "$QcsubsysHint*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    "Selected=$global:qcCandidateDir"
    if ($global:qcCandidateDir) {
        Get-ChildItem -LiteralPath $global:qcCandidateDir -File | Select-Object FullName,Name,Length,LastWriteTime
        Get-ChildItem -LiteralPath $global:qcCandidateDir -File -Include "*.sys","*.cat" | ForEach-Object {
            Get-FileBrief -Path $_.FullName
        } | Format-List
    }
}

$testXml = Join-Path $script:OutDir "qcsubsys-newcipolicy-test.xml"
Invoke-Captured "08_new_qcsubsys_policy_test" {
    $selected = (Get-ChildItem -LiteralPath "C:\Windows\System32\DriverStore\FileRepository" -Directory -Filter "$QcsubsysHint*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    if (-not $selected) {
        throw "No DriverStore directory found for $QcsubsysHint"
    }
    New-CIPolicy -FilePath $testXml -ScanPath $selected -Level FilePublisher -Fallback Hash -UserPEs -MultiplePolicyFormat -NoScript -ErrorAction Stop
    Get-Item -LiteralPath $testXml | Select-Object FullName,Length,LastWriteTime
    Select-String -LiteralPath $testXml -Pattern "PolicyID|BasePolicyID|qcsubsys|E33AB8|FileRules|Signers|SupplementalPolicySigners|UpdatePolicySigners" |
        Select-Object -First 160
}

$testBinary = Join-Path $script:OutDir "qcsubsys-newcipolicy-test.p7b"
Invoke-Captured "09_compile_qcsubsys_policy_binary" {
    if (-not (Test-Path -LiteralPath $testXml)) {
        throw "qcsubsys test XML missing; cannot compile."
    }
    ConvertFrom-CIPolicy -XmlFilePath $testXml -BinaryFilePath $testBinary -ErrorAction Stop
    Get-Item -LiteralPath $testBinary | Select-Object FullName,Length,LastWriteTime
    Get-FileHash -LiteralPath $testBinary -Algorithm SHA256
    Get-AuthenticodeSignature -LiteralPath $testBinary | Format-List *
}

$hashXml = Join-Path $script:OutDir "qcsubsys-hash-only-test.xml"
$hashBinary = Join-Path $script:OutDir "qcsubsys-hash-only-test.p7b"
Invoke-Captured "09b_new_qcsubsys_hash_only_policy" {
    $selected = (Get-ChildItem -LiteralPath "C:\Windows\System32\DriverStore\FileRepository" -Directory -Filter "$QcsubsysHint*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    if (-not $selected) {
        throw "No DriverStore directory found for $QcsubsysHint"
    }
    New-CIPolicy -FilePath $hashXml -ScanPath $selected -Level Hash -UserPEs -MultiplePolicyFormat -NoScript -ErrorAction Stop
    ConvertFrom-CIPolicy -XmlFilePath $hashXml -BinaryFilePath $hashBinary -ErrorAction Stop
    Get-Item -LiteralPath $hashXml,$hashBinary | Select-Object FullName,Length,LastWriteTime
    Get-FileHash -LiteralPath $hashBinary -Algorithm SHA256
    Select-String -LiteralPath $hashXml -Pattern "PolicyID|BasePolicyID|Hash|qcsubsys|E33AB8|FileRules|Signers|SigningScenario" |
        Select-Object -First 220
}

Invoke-Captured "10_driver_policy_official_guids" {
    $officialGuids = @(
        "784c4cbe-16a1-4caf-8a52-0c8eefd8f98c",
        "8f9d9f5b-1f20-44ea-8e41-9a8d95128c73",
        "d2bda982-ccf6-4344-ac5b-0b44427b6816"
    )
    $searchRoots = @(
        "C:\Windows\System32\CodeIntegrity",
        "D:\EFI\Microsoft\Boot"
    )
    foreach ($guid in $officialGuids) {
        "== $guid =="
        foreach ($root in $searchRoots) {
            if (Test-Path -LiteralPath $root) {
                Get-ChildItem -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match [regex]::Escape($guid) } |
                    Select-Object FullName,Length,LastWriteTime
            }
        }
    }
}

$verdict = Join-Path $script:OutDir "11_verdict.txt"
$newPolicyOk = Test-Path -LiteralPath $testXml
$binaryOk = Test-Path -LiteralPath $testBinary
$hashPolicyOk = Test-Path -LiteralPath $hashXml
$hashBinaryOk = Test-Path -LiteralPath $hashBinary
@(
    "DriversIpPolicyReverseConvertSupported=False",
    "NewQcsubsysPolicyXml=$newPolicyOk",
    "NewQcsubsysPolicyBinary=$binaryOk",
    "NewQcsubsysHashPolicyXml=$hashPolicyOk",
    "NewQcsubsysHashPolicyBinary=$hashBinaryOk",
    "MergeWithExistingDriversIpPolicySupported=False",
    "Existing deployed driversipolicy.p7b cannot be reverse-converted to XML with available ConfigCI tools.",
    "If official Driver Policy GUID files exist under ESP/CodeIntegrity, the next controlled experiment should target disabling/restoring those files, not editing driversipolicy.p7b content.",
    "If no official GUID files exist and only driversipolicy.p7b is active, replacing it with qcsubsys-newcipolicy-test.p7b remains a high-risk base-policy replacement experiment."
) | Set-Content -LiteralPath $verdict -Encoding UTF8

Write-Log "WDAC rebuildability trace completed."
Write-Log "Verdict: $verdict"
