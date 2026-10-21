param(
    [Parameter(Mandatory = $true)][ValidateSet("Enable", "Collect")][string]$Mode
)

# 在手机 Windows 上运行（管理员 PowerShell）。
#   第一步：-Mode Enable  开启 Procmon 开机日志，然后重启手机。
#   第二步：开机后 -Mode Collect  把开机日志保存为 PML，供电脑端分析 qcsubsys/ADSP 的注册表与文件操作。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$procmon = Join-Path $here "Procmon64a.exe"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
if (-not (Test-Path -LiteralPath $procmon)) { throw "找不到 $procmon" }

if ($Mode -eq "Enable") {
    & $procmon /AcceptEula /EnableBootLogging
    Write-Host "已请求开启 Procmon 开机日志。如果弹出确认窗口请点“确定”。"
    Write-Host "现在请重启手机，进入 Windows 后不要做其他操作，等 1~2 分钟后运行："
    Write-Host "  powershell -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Mode Collect"
    return
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $here "ProcmonBoot_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pml = Join-Path $outDir "boot.pml"

Write-Host "正在把开机日志转换保存为 $pml ，可能需要几分钟，请等待 Procmon 窗口自行结束……"
$p = Start-Process -FilePath $procmon -ArgumentList @("/AcceptEula", "/ConvertBootLog", "`"$pml`"") -PassThru -Wait
if (-not (Test-Path -LiteralPath $pml)) {
    throw "没有生成 $pml 。可能开机日志未启用成功，或 Procmon 弹出了需要手动确认的窗口。"
}
$size = (Get-Item -LiteralPath $pml).Length
Write-Host ("开机日志已保存：{0}（{1:N0} 字节）" -f $pml, $size)

# 记录本次开机 ADSP 状态，方便对照
Get-PnpDevice -InstanceId 'ACPI\QCOM061B\2&DABA3FF&0' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $ps = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue).Data
        "ADSP Status={0} ProblemStatus=0x{1:X8}" -f $_.Status, [uint32]$ps
    } | Tee-Object -FilePath (Join-Path $outDir "adsp_status.txt")

# 记录 SMMU（MMU1）状态，Phase16b 之后用于对照
Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'ACPI\VEN_QCOM&DEV_?509*' } |
    ForEach-Object {
        $ps = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue).Data
        "SMMU {0} Status={1} ProblemCode={2} ProblemStatus=0x{3:X8}" -f $_.InstanceId, $_.Status, $_.Problem, [uint32]$ps
    } | Tee-Object -FilePath (Join-Path $outDir "smmu_status.txt")

Write-Host "完成。请回到 Mass Storage 模式，把目录 $outDir 告诉电脑端。"
