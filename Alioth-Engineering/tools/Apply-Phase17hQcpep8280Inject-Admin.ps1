param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase17h 前置步骤（电脑端管理员 PowerShell，手机处于 Mass Storage）：离线把 Surface 的 qcpep.wd8280.inf（WHQL）注入手机驱动库。
#   背景：qcpep8250.sys（内部名 qcpep8180.sys）在 AddDevice 中写 SM8150 的 LMH 寄存器 0x18350800/0x18358800，SM8250 上没有该硬件，
#         CPU7 卡死（Phase17g 内核调试现场确认）。qcpep8280.sys 不含 SM8150 LMH/OSM 地址，CPU 调频用 EPSS 0x18591000/0x18592000，与 SM8250 一致。
#   绑定：INF 认 ACPI\QCOM0617，需配合 Phase17h UEFI（PEP0 _HID 与 PEPH → 0617）。用其他镜像启动时不会匹配任何设备，开机行为不变。
#   注意：8280 INF 的服务名同样是 qcpep，会覆盖手机上现有的 Services\qcpep（ImagePath、Parameters），所以注入前先完整导出备份。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$inf = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\qcpepwd8280\qcpep.wd8280.inf"
if (-not (Test-Path -LiteralPath $inf)) { throw "找不到 $inf" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$log = Join-Path $logDir "apply-phase17h-qcpep8280-inject-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

# 1. 备份 Services\qcpep（所有控制集）
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P17H_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    foreach ($cs in @("ControlSet001", "ControlSet002")) {
        $exists = & cmd.exe /c "reg.exe query `"HKLM\$name\$cs\Services\qcpep`" >nul 2>&1 && echo yes"
        if ($exists -ne 'yes') { Log "$cs\Services\qcpep 不存在，跳过备份"; continue }
        $bak = Join-Path $logDir "qcpep-service-backup-$cs-pre-phase17h-$stamp.reg"
        & cmd.exe /c "reg.exe export `"HKLM\$name\$cs\Services\qcpep`" `"$bak`" /y >nul 2>&1"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bak)) { throw "导出 $cs\Services\qcpep 失败" }
        Log "已备份 $cs\Services\qcpep → $bak（注意：导出文件里的键路径是临时挂载名 $name，恢复时要替换成 HKLM\SYSTEM）"
        $img = & cmd.exe /c "reg.exe query `"HKLM\$name\$cs\Services\qcpep`" /v ImagePath 2>&1"
        $img | Where-Object { $_ -match 'ImagePath' } | ForEach-Object { Log "  注入前 ImagePath：$($_.Trim())" }
    }
} finally {
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { throw "hive 卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机，也不要继续注入。" }
    }
}

# 2. DISM 注入
$repo = "${drive}:\Windows\System32\DriverStore\FileRepository"
$before = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "qcpep*" -ErrorAction SilentlyContinue)
Log "注入前驱动库中的 qcpep* 目录：$($before.Count) 个"
$before | ForEach-Object { Log "  $($_.Name)" }

Log "执行: dism.exe /Image:${drive}:\ /Add-Driver /Driver:$inf"
$out = & dism.exe "/Image:${drive}:\" "/Add-Driver" "/Driver:$inf" 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Add-Content -LiteralPath $log -Value "$_" -Encoding UTF8 }
$out | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" }
Log "DISM 退出码：$code"

$after = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "qcpep*" -ErrorAction SilentlyContinue)
Log "注入后驱动库中的 qcpep* 目录：$($after.Count) 个"
foreach ($d in $after) {
    Log "  $($d.Name)"
    Get-ChildItem -LiteralPath $d.FullName | ForEach-Object { Log ("     {0}  {1:N0} 字节" -f $_.Name, $_.Length) }
}
if ($code -ne 0 -or -not ($after | Where-Object { $_.Name -like 'qcpep.wd8280.inf_*' })) {
    Log "注入失败，请把日志发给电脑端：$log"
    exit 1
}
Log "注入成功。下一步：电脑端先启动 kd 监听，再用 Phase17h UEFI（PEP0 → QCOM0617）fastboot boot。"
Log "日志：$log"
