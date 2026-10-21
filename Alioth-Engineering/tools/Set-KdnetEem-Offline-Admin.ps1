param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [int]$BusParams = 1,
    [int]$Port = 50005,
    [string]$Key = "1.2.3.4",
    [switch]$Disable,
    [string]$LogFile
)

# Phase17f（电脑端管理员 PowerShell，手机处于 Mass Storage）：离线修改手机 ESP 中的 BCD，开启 KDNET over USB EEM 内核调试。
# 依据：alioth UEFI 自带 Kona/DBG2.aml（端口类型 0x8003、子类型 0x5143、基址 0x0a600000、\_SB.URS0），手机系统中有 kd_8003_5143.dll。
# -Disable：关闭 debug（dbgsettings 保留，不影响开机）。每次修改前都会备份 BCD 到 logs\。

$ErrorActionPreference = "Stop"
if ($LogFile) { Start-Transcript -LiteralPath $LogFile -Append | Out-Null }
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "必须在管理员 PowerShell 窗口中运行本脚本。"
    }
    $drive = $WindowsDrive.TrimEnd(':', '\')
    if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
    if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }
    if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\kd_8003_5143.dll")) { throw "手机系统中缺少 kd_8003_5143.dll。" }

    $winPart = Get-Partition -DriveLetter $drive
    $esp = Get-Partition -DiskNumber $winPart.DiskNumber | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } | Select-Object -First 1
    if (-not $esp) { throw "手机磁盘 $($winPart.DiskNumber) 上找不到 ESP。" }
    Write-Host "手机磁盘 $($winPart.DiskNumber)，ESP 为分区 $($esp.PartitionNumber)（$([math]::Round($esp.Size/1MB)) MB）"

    $letter = $esp.DriveLetter
    $assigned = $false
    if (-not $letter) {
        $letter = (69..90 | ForEach-Object { [char]$_ } | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1)
        Add-PartitionAccessPath -DiskNumber $winPart.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:\"
        $assigned = $true
        Start-Sleep -Seconds 2
    }
    try {
        $bcd = "${letter}:\EFI\Microsoft\Boot\BCD"
        if (-not (Test-Path -LiteralPath $bcd)) { throw "ESP 中找不到 $bcd" }
        $logs = Join-Path $PSScriptRoot "..\logs"
        $bak = Join-Path $logs ("BCD-backup-phase17f-{0}.bin" -f (Get-Date -Format yyyyMMdd-HHmmss))
        Copy-Item -LiteralPath $bcd -Destination $bak
        Write-Host "BCD 已备份到 $bak"

        function Invoke-Bcd([string[]]$a) {
            $out = & bcdedit.exe /store $bcd @a 2>&1
            Write-Host ("bcdedit {0} → {1}" -f ($a -join ' '), ($out -join ' '))
            if ($LASTEXITCODE -ne 0) { throw "bcdedit 执行失败。" }
        }
        if ($Disable) {
            Invoke-Bcd @('/set', '{default}', 'debug', 'off')
        } else {
            Invoke-Bcd @('/dbgsettings', 'net', "hostip:169.254.255.255", "port:$Port", "key:$Key", "busparams:$BusParams")
            Invoke-Bcd @('/set', '{dbgsettings}', 'dhcp', 'no')
            Invoke-Bcd @('/set', '{default}', 'debug', 'on')
        }
        Write-Host "---- 当前 {dbgsettings} ----"
        & bcdedit.exe /store $bcd /enum '{dbgsettings}' | Write-Host
        Write-Host "---- 当前 {default} ----"
        & bcdedit.exe /store $bcd /enum '{default}' | Write-Host
    } finally {
        if ($assigned) {
            Remove-PartitionAccessPath -DiskNumber $winPart.DiskNumber -PartitionNumber $esp.PartitionNumber -AccessPath "${letter}:\"
            Write-Host "已移除 ESP 的临时盘符 ${letter}:"
        }
    }
    Write-Host "完成。"
} catch {
    Write-Host "出错：$($_.Exception.Message)"
    throw
} finally {
    if ($LogFile) { Stop-Transcript | Out-Null }
}
