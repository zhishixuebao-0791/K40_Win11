param(
    [ValidateSet("Live", "BootEnable", "BootCollect")][string]$Mode = "Live",
    [int]$Seconds = 30
)

# 在手机 Windows 上运行（管理员 PowerShell），抓取 qcsmmu8280 的内核调试输出（DbgPrintEx），定位 MMU1 Code 31 的失败点。
#   -Mode Live        默认。开始抓取 → 重启 MMU1 设备（触发 AddDevice 重试）→ 保存日志。不需要重启手机。
#   -Mode BootEnable  Live 抓不到输出时使用：开启开机内核调试日志，然后重启手机。
#   -Mode BootCollect 开机后运行，保存开机阶段的调试输出。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cli = Join-Path $here "dbgviewcli64a.exe"
$mmu = 'ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
if (-not (Test-Path -LiteralPath $cli)) { throw "找不到 $cli" }

# 打开所有组件、所有级别的 DbgPrintEx 输出（只影响调试输出，不影响系统行为）
$filter = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Debug Print Filter"
New-Item -Path $filter -Force | Out-Null
foreach ($n in "DEFAULT", "IHVDRIVER", "IHVBUS") { New-ItemProperty -Path $filter -Name $n -Value 0xFFFFFFFF -PropertyType DWord -Force | Out-Null }

if ($Mode -eq "BootEnable") {
    & $cli --accepteula --no-banner --boot-enable
    Write-Host "已开启开机内核调试日志。请重启手机，进入 Windows 后等 1 分钟，再运行："
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Mode BootCollect"
    return
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $here "QcsmmuDebug_${Mode}_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$log = Join-Path $outDir "dbgview.log"

function Save-MmuStatus([string]$Name) {
    Get-PnpDevice -InstanceId $mmu -ErrorAction SilentlyContinue | ForEach-Object {
        $ps = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue).Data
        "{0} Status={1} Problem={2} ProblemStatus=0x{3:X8}" -f $Name, $_.Status, $_.Problem, [uint32]$ps
    } | Tee-Object -FilePath (Join-Path $outDir "mmu1_status.txt") -Append
}

Save-MmuStatus "抓取前"
$p = Start-Process -FilePath $cli -ArgumentList @("--accepteula", "--no-banner", "-k", "-v", "--clock-ms", "--duration", "$Seconds", "-l", "`"$log`"") -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3

if ($Mode -eq "Live") {
    Write-Host "正在重启 MMU1 设备，触发 qcsmmu 重新执行 AddDevice……"
    $out = & pnputil.exe /restart-device "$mmu" 2>&1
    $out | Out-File -FilePath (Join-Path $outDir "pnputil.txt") -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        Write-Host "pnputil 重启失败，改用禁用再启用。"
        Disable-PnpDevice -InstanceId $mmu -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Enable-PnpDevice -InstanceId $mmu -Confirm:$false -ErrorAction SilentlyContinue
    }
}

Write-Host "正在抓取调试输出，约 $Seconds 秒……"
$p.WaitForExit(($Seconds + 15) * 1000) | Out-Null
if (-not $p.HasExited) { & $cli --stop | Out-Null; Start-Sleep -Seconds 2 }
Save-MmuStatus "抓取后"

if ($Mode -eq "BootCollect") { & $cli --accepteula --no-banner --boot-disable | Out-Null }

if (Test-Path -LiteralPath $log) {
    $all = @(Get-Content -LiteralPath $log)
    # 匹配 0 行时管道为空，Set-Content 不会建文件，所以先收集到数组再写
    $hits = @($all | Select-String -Pattern "smmu|qcsmmu|XBL|Acpi|Sid" | ForEach-Object { $_.Line })
    Set-Content -LiteralPath (Join-Path $outDir "smmu_lines.txt") -Value $hits -Encoding UTF8
    Write-Host ("调试输出共 {0} 行，其中与 SMMU 相关 {1} 行。" -f $all.Count, $hits.Count)
    Write-Host "调试输出前 20 行："
    $all | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "没有生成 $log 。"
}
Write-Host "完成。请回到 Mass Storage 模式，把目录 $outDir 告诉电脑端。"
