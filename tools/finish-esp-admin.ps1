$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'finish-esp-admin.log'
$diskpartScript = Join-Path $root '_diskpart_assign_esp_admin.txt'
$windowsDrive = $null

function Write-Log {
    param([string]$Message)
    $parent = Split-Path -Parent $log
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

function Get-OfflineWindowsDrive {
    $candidates = Get-CimInstance Win32_LogicalDisk |
        Where-Object { $_.DriveType -eq 3 } |
        ForEach-Object { $_.DeviceID } |
        Where-Object { $_ -and $_ -ne 'C:' }

    foreach ($drive in $candidates) {
        if (Test-Path "$drive\Windows\System32") {
            return $drive
        }
    }

    throw 'Could not locate offline Windows drive automatically.'
}

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
Write-Log 'Admin finisher started.'

@'
select disk 1
select partition 36
assign letter=S
list volume
'@ | Set-Content -LiteralPath $diskpartScript -Encoding ASCII

Write-Log 'Assigning S: to target ESP with diskpart.'
$diskpartOutput = & diskpart /s $diskpartScript 2>&1
$diskpartOutput | ForEach-Object { Write-Log $_ }

if (-not (Test-Path 'S:\')) {
    throw 'S: was not mounted after diskpart.'
}

$windowsDrive = Get-OfflineWindowsDrive
Write-Log ("Detected offline Windows drive: {0}" -f $windowsDrive)

Write-Log 'Running BCDBoot for offline Windows.'
$bcdbootOutput = & bcdboot "$windowsDrive\Windows" /s S: /f UEFI /v 2>&1
$bcdbootOutput | ForEach-Object { Write-Log $_ }

Write-Log 'Listing EFI tree.'
Get-ChildItem -Recurse -LiteralPath 'S:\EFI' -ErrorAction Stop |
    Select-Object FullName, Length |
    ForEach-Object { Write-Log ("EFI {0}" -f $_.FullName) }

Write-Log 'Admin finisher completed.'
