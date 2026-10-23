param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a 补充（电脑端管理员 PowerShell，手机处于 Mass Storage）：给 PEP0（Enum\ACPI\QCOM0519\*）设置 ConfigFlags=0x20（CONFIGFLAG_REINSTALL）。
#   背景：DISM 离线注入 pep0stub 后，服务在开机时已加载（kd 看到 DriverEntry），但 PEP0 实例早已存在且 ConfigFlags=0、没有 Driver 值，
#         PnP 不会主动给它重新匹配驱动。设置重新安装标志后，下次开机 PnP 会为它选择最佳驱动（pep0stub）。
#   Enum 键默认只有 SYSTEM 可写，所以通过一个临时计划任务以 SYSTEM 身份执行 reg.exe，执行完立即删除任务。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $projectRoot "Alioth-Engineering\logs\set-pep0-reinstall-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P19A_RI_$PID"
$task = "K40_Pep0Reinstall_$PID"
$cmdFile = Join-Path $env:TEMP "k40-pep0-reinstall-$PID.cmd"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sets = Get-ChildItem "Registry::HKEY_LOCAL_MACHINE\$name" | Where-Object { $_.PSChildName -like 'ControlSet*' } | ForEach-Object { $_.PSChildName }
    $keys = @()
    foreach ($cs in $sets) {
        $enumPath = "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519"
        if (-not (Test-Path -LiteralPath $enumPath)) { Log "$cs\Enum\ACPI\QCOM0519 不存在"; continue }
        foreach ($inst in Get-ChildItem -LiteralPath $enumPath) {
            $k = "HKLM\$name\$cs\Enum\ACPI\QCOM0519\$($inst.PSChildName)"
            Log "修改前 $cs 实例 $($inst.PSChildName)：ConfigFlags=$($inst.GetValue('ConfigFlags')) Service=$($inst.GetValue('Service')) Driver=$($inst.GetValue('Driver'))"
            $keys += $k
            $inst.Close()   # 不关闭句柄会导致最后 reg unload 拒绝访问
        }
    }
    if ($keys.Count -eq 0) { throw "没有找到 PEP0 实例。" }

    $lines = @("@echo off") + ($keys | ForEach-Object { "reg.exe add `"$_`" /v ConfigFlags /t REG_DWORD /d 0x20 /f" })
    [IO.File]::WriteAllLines($cmdFile, $lines, [Text.Encoding]::ASCII)
    Log "以 SYSTEM 身份执行：$cmdFile"
    & schtasks.exe /Create /TN $task /TR "cmd.exe /c `"$cmdFile`"" /SC ONCE /ST 23:59 /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "创建计划任务失败。" }
    & schtasks.exe /Run /TN $task | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $st = (& schtasks.exe /Query /TN $task /FO CSV /NH) -split '","'
        if ($st[-1] -notmatch 'Running|正在运行') { break }
    }
    & schtasks.exe /Delete /TN $task /F | Out-Null

    $ok = $true
    foreach ($cs in $sets) {
        $enumPath = "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519"
        if (-not (Test-Path -LiteralPath $enumPath)) { continue }
        foreach ($inst in Get-ChildItem -LiteralPath $enumPath) {
            $v = $inst.GetValue('ConfigFlags')
            Log "修改后 $cs 实例 $($inst.PSChildName)：ConfigFlags=$v"
            if ($v -ne 0x20) { $ok = $false }
            $inst.Close()
        }
    }
    if (-not $ok) { Log "写入未全部生效，请把日志发给电脑端。" }
} finally {
    Remove-Item -LiteralPath $cmdFile -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { throw "hive 卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Log "完成。下一步：kd 保持监听，fastboot boot phase17g-base，观察 pep0stub: AddDevice。日志：$log"
