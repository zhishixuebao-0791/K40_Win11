param(
    [string]$OutputRoot = "C:\Code\REDMIK40_Win11",
    [guid]$BasePolicyId = "{d2bda982-ccf6-4344-ac5b-0b44427b6816}",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $OutputRoot "QcsubsysWdacHash_$timestamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logPath = Join-Path $outDir "00_PrepareLog.txt"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $logPath -Append
}

function Resolve-QcsubsysSys {
    $service = Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "qcsubsys" } |
        Select-Object -First 1

    if ($service) {
        $path = $service.PathName -replace '^\\??\\', ''
        if ($path -match '^\\SystemRoot\\') {
            $path = $path -replace '^\\SystemRoot\\', $env:SystemRoot
        }
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $driverStore = Join-Path $env:SystemRoot "System32\DriverStore\FileRepository"
    $candidate = Get-ChildItem -LiteralPath $driverStore -Directory -Filter "qcsubsys8250.inf_arm64*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($candidate) {
        $sys = Join-Path $candidate.FullName "qcsubsys8250.sys"
        if (Test-Path -LiteralPath $sys) {
            return $sys
        }
    }

    throw "qcsubsys8250.sys was not found in the live Windows DriverStore."
}

function Assert-ConfigCi {
    $required = @("New-CIPolicyRule", "New-CIPolicy", "Set-CIPolicyIdInfo", "ConvertFrom-CIPolicy")
    foreach ($name in $required) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "Required ConfigCI cmdlet missing: $name"
        }
    }
}

Write-Log "Preparing qcsubsys-only WDAC hash policy."
Write-Log "Output: $outDir"
Write-Log "Apply: $Apply"
Write-Log "Supplements base policy: $BasePolicyId"

Assert-ConfigCi

$sysPath = Resolve-QcsubsysSys
$sysHash = Get-FileHash -LiteralPath $sysPath -Algorithm SHA256
$sysSig = Get-AuthenticodeSignature -LiteralPath $sysPath

Write-Log "Target sys: $sysPath"
Write-Log "Target SHA256: $($sysHash.Hash)"
Write-Log "Target signature status: $($sysSig.Status)"

$xmlPath = Join-Path $outDir "Alioth-Qcsubsys8250-Hash-Allow.xml"
$cipPath = Join-Path $outDir "Alioth-Qcsubsys8250-Hash-Allow.cip"
$infoPath = Join-Path $outDir "policy-info.txt"

Write-Log "Generating hash rule."
$rules = New-CIPolicyRule -DriverFilePath $sysPath -Level Hash
if (-not $rules) {
    throw "New-CIPolicyRule returned no rules."
}

Write-Log "Generating multiple-policy-format XML."
New-CIPolicy -FilePath $xmlPath -Rules $rules -MultiplePolicyFormat -NoScript | Out-Null

Write-Log "Removing Audit Mode from generated supplemental policy."
Set-RuleOption -FilePath $xmlPath -Option 3 -Delete | Out-Null

Write-Log "Setting supplemental policy metadata."
Set-CIPolicyIdInfo -FilePath $xmlPath -PolicyName "Alioth qcsubsys8250 hash allow" -SupplementsBasePolicyID $BasePolicyId -ResetPolicyID | Out-Null

Write-Log "Converting XML policy to CIP."
ConvertFrom-CIPolicy -XmlFilePath $xmlPath -BinaryFilePath $cipPath | Out-Null

$policyInfo = Get-CIPolicyIdInfo -FilePath $xmlPath
$policyInfo | Format-List * | Out-String -Width 4096 | Set-Content -LiteralPath $infoPath -Encoding UTF8

$policyId = $null
$policyIdLine = (Get-Content -LiteralPath $infoPath | Select-String -Pattern "PolicyID|PolicyId" | Select-Object -First 1)
if ($policyIdLine -and $policyIdLine.Line -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
    $policyId = $Matches[1]
}

if (-not $policyId) {
    $xml = Get-Content -LiteralPath $xmlPath -Raw
    if ($xml -match "<PolicyID>\{?([0-9a-fA-F-]{36})\}?</PolicyID>") {
        $policyId = $Matches[1]
    }
}

if (-not $policyId) {
    throw "Could not determine generated policy ID from $xmlPath"
}

$activeName = "{$policyId}.cip"
$activeTarget = Join-Path $env:SystemRoot "System32\CodeIntegrity\CiPolicies\Active\$activeName"

"PolicyId=$policyId" | Set-Content -LiteralPath (Join-Path $outDir "policy-id.txt") -Encoding UTF8
"ActiveTarget=$activeTarget" | Add-Content -LiteralPath (Join-Path $outDir "policy-id.txt") -Encoding UTF8
"TargetSys=$sysPath" | Add-Content -LiteralPath (Join-Path $outDir "policy-id.txt") -Encoding UTF8
"TargetSha256=$($sysHash.Hash)" | Add-Content -LiteralPath (Join-Path $outDir "policy-id.txt") -Encoding UTF8

Write-Log "Generated policy ID: $policyId"
Write-Log "Generated CIP: $cipPath"
Write-Log "Expected active target: $activeTarget"

if ($Apply) {
    $activeDir = Split-Path -Parent $activeTarget
    New-Item -ItemType Directory -Force -Path $activeDir | Out-Null
    Copy-Item -LiteralPath $cipPath -Destination $activeTarget -Force
    Write-Log "Applied CIP to active policy directory. Reboot is required."
} else {
    Write-Log "Generate-only mode. Policy was not installed. Re-run with -Apply only after review."
}

Write-Log "Completed."
Write-Host "Qcsubsys WDAC hash policy preparation completed: $outDir"
