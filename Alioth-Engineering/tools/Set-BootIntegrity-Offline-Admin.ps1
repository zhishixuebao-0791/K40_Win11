param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [ValidateSet("on", "off")][string]$NoIntegrityChecks = "on",
    [ValidateSet("on", "off")][string]$TestSigning = "on"
)

# Phase19a：离线改手机 ESP 的 BCD，设置 {default} 的 nointegritychecks / testsigning
#   （电脑端管理员 PowerShell，手机处于 Mass Storage）。
#   背景：winload 对 boot-critical 驱动按 Secure Boot 链校验，testsigning 不放行自签 boot 驱动；
#         本机 Secure Boot 关，用 nointegritychecks 跳过 winload 的签名校验，放行自签 pep0stub。
#   ESP 与 WIN 同盘：按 win 盘号找 GptType c12a7328... 的 ESP，临时挂盘符，改完移除。每次先备份 BCD。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $logDir "set-bootintegrity-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$winPart = Get-Partition -DriveLetter $drive
$esp = Get-Partition -DiskNumber $winPart.DiskNumber | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } | Select-Object -First 1
if (-not $esp) { throw "手机磁盘 $($winPart.DiskNumber) 上找不到 ESP。" }
Log "手机磁盘 $($winPart.DiskNumber)，ESP 为分区 $($esp.PartitionNumber)（$([math]::Round($esp.Size/1MB)) MB）"

$letter = $esp.DriveLetter; $assigned = $false
if (-not $letter) {
    $letter = (69..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1)
    Add-PartitionAccessPath -DiskNumber $winPart.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:\"
    $assigned = $true; Start-Sleep -Seconds 2
}
try {
    $bcd = "${letter}:\EFI\Microsoft\Boot\BCD"
    if (-not (Test-Path -LiteralPath $bcd)) { throw "ESP 中找不到 $bcd" }
    $bak = Join-Path $logDir ("BCD-backup-bootintegrity-$stamp.bin")
    Copy-Item -LiteralPath $bcd -Destination $bak
    Log "BCD 已备份到 $bak"

    Log "---- 改前 {default} ----"
    (& bcdedit.exe /store $bcd /enum '{default}') | ForEach-Object { if ($_ -match 'testsigning|nointegritychecks|identifier|description') { Log ("  " + $_.Trim()) } }

    function Invoke-Bcd([string[]]$a) {
        $out = & bcdedit.exe /store $bcd @a 2>&1
        Log ("bcdedit {0} → {1}" -f ($a -join ' '), ($out -join ' '))
        if ($LASTEXITCODE -ne 0) { throw "bcdedit 执行失败。" }
    }
    Invoke-Bcd @('/set', '{default}', 'testsigning', $TestSigning)
    Invoke-Bcd @('/set', '{default}', 'nointegritychecks', $NoIntegrityChecks)

    Log "---- 改后 {default} ----"
    (& bcdedit.exe /store $bcd /enum '{default}') | ForEach-Object { if ($_ -match 'testsigning|nointegritychecks|identifier|description') { Log ("  " + $_.Trim()) } }
    Log "完成：testsigning=$TestSigning nointegritychecks=$NoIntegrityChecks"
} finally {
    if ($assigned) {
        Remove-PartitionAccessPath -DiskNumber $winPart.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:\"
        Log "已移除 ESP 临时盘符 ${letter}:"
    }
}
Log "日志：$log"
