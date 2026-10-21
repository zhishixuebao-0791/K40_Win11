param(
    [ValidateSet("Live", "BootEnable", "BootCollect")][string]$Mode = "Live",
    [int]$Seconds = 15
)

# 在手机 Windows 上运行（管理员 PowerShell），用 ETW 抓取 qcsmmu8280 的 WPP 跟踪（DebugView 抓不到它）。
# 不需要 TMF：电脑端从 ETL 中解析出消息 GUID + 消息编号，对照反汇编即可知道 AddDevice 失败在哪个分支。
#   -Mode Live        默认。开 ETW 会话 → 重启 MMU1（触发 AddDevice）→ 停止会话。不需要重启手机。
#   -Mode BootEnable  Live 抓不到事件时使用：写入开机 AutoLogger，然后重启手机。
#   -Mode BootCollect 开机后运行，收集 AutoLogger 的 ETL 并删除 AutoLogger。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mmu = 'ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1'
$wppGuid = '{cf6bfd48-e161-4949-96d5-8647cfc488c8}'   # qcsmmu8280.sys 的 WPP 控制 GUID（反汇编得到）
$session = "QcsmmuWpp"
$autoKey = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$session"
$bootEtl = "C:\Windows\Temp\QcsmmuWppBoot.etl"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}

if ($Mode -eq "BootEnable") {
    New-Item -Path $autoKey -Force | Out-Null
    New-ItemProperty -Path $autoKey -Name Start -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $autoKey -Name Guid -Value ("{" + [guid]::NewGuid().ToString() + "}") -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $autoKey -Name FileName -Value $bootEtl -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $autoKey -Name LogFileMode -Value 0x00000002 -PropertyType DWord -Force | Out-Null   # 顺序文件
    New-ItemProperty -Path $autoKey -Name BufferSize -Value 64 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $autoKey -Name MaxFileSize -Value 64 -PropertyType DWord -Force | Out-Null
    $pk = Join-Path $autoKey $wppGuid
    New-Item -Path $pk -Force | Out-Null
    New-ItemProperty -Path $pk -Name Enabled -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $pk -Name EnableLevel -Value 0xFF -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $pk -Name EnableFlags -Value 0xFFFFFFFF -PropertyType DWord -Force | Out-Null
    Write-Host "已写入开机 AutoLogger。请重启手机，进入 Windows 后等 1 分钟，再运行："
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Mode BootCollect"
    return
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $here "QcsmmuWpp_${Mode}_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$etl = Join-Path $outDir "qcsmmu_wpp.etl"

function Save-MmuStatus([string]$Name) {
    Get-PnpDevice -InstanceId $mmu -ErrorAction SilentlyContinue | ForEach-Object {
        $ps = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue).Data
        "{0} Status={1} Problem={2} ProblemStatus=0x{3:X8}" -f $Name, $_.Status, $_.Problem, [uint32]$ps
    } | Tee-Object -FilePath (Join-Path $outDir "mmu1_status.txt") -Append
}

if ($Mode -eq "BootCollect") {
    & logman.exe stop $session -ets 2>&1 | Out-File (Join-Path $outDir "logman.txt") -Encoding utf8
    Start-Sleep -Seconds 2
    Remove-Item -Path $autoKey -Recurse -Force -ErrorAction SilentlyContinue
    Save-MmuStatus "开机后"
    if (Test-Path -LiteralPath $bootEtl) { Copy-Item -LiteralPath $bootEtl -Destination $etl -Force }
} else {
    Save-MmuStatus "抓取前"
    & logman.exe stop $session -ets 2>&1 | Out-Null
    $o = & logman.exe start $session -p $wppGuid 0xFFFFFFFF 0xFF -o "$etl" -ets 2>&1
    $o | Out-File (Join-Path $outDir "logman.txt") -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "logman 启动 ETW 会话失败：$o" }

    Write-Host "正在重启 MMU1 设备，触发 qcsmmu 重新执行 AddDevice……"
    $out = & pnputil.exe /restart-device "$mmu" 2>&1
    $out | Out-File -FilePath (Join-Path $outDir "pnputil.txt") -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pnputil 重启失败，改用禁用再启用。"
        Disable-PnpDevice -InstanceId $mmu -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $mmu -Confirm:$false -ErrorAction SilentlyContinue
    }
    Write-Host "等待 $Seconds 秒……"
    Start-Sleep -Seconds $Seconds
    & logman.exe stop $session -ets 2>&1 | Out-File (Join-Path $outDir "logman.txt") -Append -Encoding utf8
    Save-MmuStatus "抓取后"
}

if (Test-Path -LiteralPath $etl) {
    Write-Host ("ETL 已保存：{0}（{1:N0} 字节）" -f $etl, (Get-Item -LiteralPath $etl).Length)
} else {
    Write-Host "没有生成 ETL 文件，请把 $outDir\logman.txt 的内容告诉电脑端。"
}
Write-Host "完成。请回到 Mass Storage 模式，把目录 $outDir 告诉电脑端。"
