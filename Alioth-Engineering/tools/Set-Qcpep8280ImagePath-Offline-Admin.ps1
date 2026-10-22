param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [switch]$Revert
)

# Phase17h 修正（电脑端管理员 PowerShell，手机处于 Mass Storage）：
# 8250 与 8280 INF 共用服务名 qcpep（BOOT_START），离线 DISM 注入不会改 Services\qcpep\ImagePath，
# 导致首测时实际加载的仍是 qcpep8250.sys（kd: lm m qcpep* 只有 qcpep8250）。
# 本脚本把 ImagePath 指向 DriverStore 里的 qcpep8280.sys；-Revert 改回 qcpep8250.sys。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }
$hive = "${drive}:\Windows\System32\Config\SYSTEM"

# 按目录名通配查找，不写死哈希后缀
$pattern = if ($Revert) { 'qcpep.wd8250.inf_arm64_*' } else { 'qcpep.wd8280.inf_arm64_*' }
$sys = if ($Revert) { 'qcpep8250.sys' } else { 'qcpep8280.sys' }
$dirs = @(Get-ChildItem -LiteralPath "${drive}:\Windows\System32\DriverStore\FileRepository" -Directory -Filter $pattern |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $sys) })
if ($dirs.Count -ne 1) { throw "DriverStore 中匹配 $pattern 且含 $sys 的目录有 $($dirs.Count) 个（应为 1 个）。" }
$target = "\SystemRoot\System32\DriverStore\FileRepository\$($dirs[0].Name)\$sys"

$name = "ALIOTH_P17H_IMG_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sel = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Select")
    $cur = [int]$sel.GetValue("Current"); $sel.Dispose()
    foreach ($cs in @(("ControlSet{0:D3}" -f $cur)) + @("ControlSet001", "ControlSet002") | Select-Object -Unique) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Services\qcpep", $true)
        if (-not $k) { continue }
        try {
            $old = $k.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $k.SetValue("ImagePath", $target, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            Write-Host "$cs\Services\qcpep\ImagePath：$old"
            Write-Host "    改为 → $target"
            Write-Host "    Start = $($k.GetValue('Start'))"
        } finally { $k.Dispose() }
    }
} finally {
    Remove-Variable k, sel -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Write-Host "卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Write-Host "完成。下一步：电脑端先启动 kd 桥接，再 fastboot boot Phase17h 镜像；连上后先执行 lm m qcpep* 确认加载的是 $sys。"
