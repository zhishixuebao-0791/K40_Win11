param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [Parameter(Mandatory = $true)][string]$OutFile
)

# Phase17f（电脑端管理员 PowerShell，手机处于 Mass Storage）：只读导出 KDNET 相关状态，定位 USB EEM 调试为什么没连上。
# 内容：Services\kdnet / kdnic（KdInitStatus、KdInitResultString）、Control\SystemStartOptions、Synopsys 控制器 / URS0 的 Enum 项、
# System.evtx 最近 3 小时中与调试相关的事件。不修改任何东西。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$out = New-Object System.Collections.Generic.List[string]
function Add([string]$s) { $out.Add($s) }
# 由 cmd 完成重定向，避免 PowerShell 5.1 把 reg.exe 的 stderr 包成 ErrorRecord 后中止脚本
function RegQ([string]$cmdArgs) { & cmd.exe /c "reg.exe query $cmdArgs 2>&1" }

$hive = "${drive}:\Windows\System32\Config\SYSTEM"
Add ("SYSTEM hive 修改时间：{0}" -f (Get-Item -LiteralPath $hive).LastWriteTime)
$name = "ALIOTH_P17F_KD_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sel = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Select")
    $cs = "ControlSet{0:D3}" -f [int]$sel.GetValue("Current"); $sel.Dispose()
    Add "当前控制集：$cs"
    foreach ($sub in @("Services\kdnet", "Services\kdnic", "Services\kdnet\Parameters")) {
        Add "==== $cs\$sub"
        $o = RegQ "`"HKLM\$name\$cs\$sub`""
        $o | ForEach-Object { Add "$_" }
    }
    Add "==== $cs\Control SystemStartOptions"
    RegQ "`"HKLM\$name\$cs\Control`" /v SystemStartOptions" | ForEach-Object { Add "$_" }
    foreach ($e in @("ACPI\QCOM0597", "URS")) {
        Add "==== $cs\Enum\$e（递归）"
        RegQ "`"HKLM\$name\$cs\Enum\$e`" /s" | Where-Object { $_ -match 'HKEY|Service|ConfigFlags|DeviceDesc|Driver|Problem|Capabilities' } | ForEach-Object { Add "$_" }
    }
} finally {
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Add "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Add "卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}

$evtx = "${drive}:\Windows\System32\winevt\Logs\System.evtx"
Add ("==== System.evtx（修改时间 {0}），最近 3 小时内与调试相关或级别≤3 的事件" -f (Get-Item -LiteralPath $evtx).LastWriteTime)
try {
    $since = (Get-Date).AddHours(-3)
    Get-WinEvent -Path $evtx -MaxEvents 3000 -ErrorAction Stop | Where-Object {
        $_.TimeCreated -ge $since -and ($_.Level -le 3 -or $_.ProviderName -match 'Kernel-Boot|Kernel-General|kdnic|Debug' -or $_.Message -match '调试|debug|KDNET|kdnic')
    } | Select-Object -First 80 | ForEach-Object {
        Add ("{0:yyyy-MM-dd HH:mm:ss} [{1}] {2} #{3}: {4}" -f $_.TimeCreated, $_.LevelDisplayName, $_.ProviderName, $_.Id, (($_.Message -split "`r?`n")[0]))
    }
} catch { Add "读取 System.evtx 失败：$($_.Exception.Message)" }

$out | Set-Content -LiteralPath $OutFile -Encoding UTF8
Write-Host "已写入 $OutFile"
