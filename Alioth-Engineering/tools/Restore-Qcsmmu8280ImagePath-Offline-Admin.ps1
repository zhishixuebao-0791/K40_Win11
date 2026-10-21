param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# 离线救砖（电脑端管理员 PowerShell，手机处于 Mass Storage）：把 Services\qcsmmu\ImagePath 恢复为 WHQL 的 qcsmmu8280.sys。
# 用于 Phase17a（testsigning + qcsmmu8250.sys）开机卡在 Silicium 启动画面的情况。
# 只改这一个值，BCD 中的 testsigning 保留不动，用来区分"8250 驱动卡死"和"testsigning 本身导致卡死"。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$target = '\SystemRoot\System32\DriverStore\FileRepository\qcsmmu8280.inf_arm64_1d80adabc6ef3b6d\qcsmmu8280.sys'
if (-not (Test-Path -LiteralPath ($target -replace '^\\SystemRoot', "${drive}:\Windows"))) { throw "手机上找不到 qcsmmu8280.sys。" }

$name = "ALIOTH_P17A_RESTORE_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sel = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Select")
    $cur = [int]$sel.GetValue("Current"); $sel.Dispose()
    foreach ($cs in @(("ControlSet{0:D3}" -f $cur)) + @("ControlSet001", "ControlSet002") | Select-Object -Unique) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Services\qcsmmu", $true)
        if (-not $k) { continue }
        try {
            $old = $k.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $k.SetValue("ImagePath", $target, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            Write-Host "$cs\Services\qcsmmu\ImagePath：$old"
            Write-Host "    改为 → $target"
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
Write-Host "完成。现在可以退出 Mass Storage，重启手机。"
