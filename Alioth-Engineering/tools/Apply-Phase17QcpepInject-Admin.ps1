param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase17b 前置步骤（电脑端管理员 PowerShell，手机处于 Mass Storage）：离线把 Kona PEP 驱动包 qcpep.wd8250.inf 注入手机驱动库。
#   背景：当初 apply-alioth-offline-fixes-admin.ps1 把 Kona 的 Drivers\SOC 整个排除了，所以手机上从来没有 qcpep。
#   安全性：当前 UEFI 中 PEP0 的 HID 是 QCOM0519，这个 INF 只认 QCOM2519，注入后不会匹配任何设备，开机行为不变。
#           只有用 Phase17 UEFI（PEP0 → QCOM2519）启动时才会生效。
#   签名：Andromeda 证书（需要手机开启 testsigning，Phase17a 已开启）。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$inf = Join-Path $projectRoot "sound_code\windows_silicon_qcom_kona\Drivers\SOC\PowerManagement\qcpep.wd8250.inf"
if (-not (Test-Path -LiteralPath $inf)) { throw "找不到 $inf" }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $projectRoot "Alioth-Engineering\logs\apply-phase17-qcpep-inject-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$repo = "${drive}:\Windows\System32\DriverStore\FileRepository"
$before = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "qcpep*" -ErrorAction SilentlyContinue)
Log "注入前驱动库中的 qcpep* 目录：$($before.Count) 个"
if ($before.Count -gt 0) { $before | ForEach-Object { Log "  $($_.Name)" } }

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
if ($code -ne 0 -or $after.Count -eq 0) {
    Log "注入失败。如果 DISM 报签名错误，请把日志发给电脑端：$log"
} else {
    Log "注入成功。下一步：用 Phase17 UEFI（PEP0 → QCOM2519）fastboot boot 启动手机。"
}
Log "日志：$log"
