param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [switch]$Disable
)

# Phase17i（电脑端管理员 PowerShell，手机处于 Mass Storage）：
# 离线写入 Services\qcpep\Parameters\EnableStubbedPepForPresilicon = 1（REG_DWORD）。
# 依据：qcpep8280 在该值非 0 时，AddDevice 链上的 0x239d20 直接返回，跳过 TSENS 初始化（Phase17h 卡死点），
#       且提供给 qcsmmu 的接口 {a0e1dd36-dfb9-4c0e-bbaa-78f0746be181} 的功能函数直接返回成功。
# 只对 qcpep8280.sys 有效（qcpep8250 没有这个值），脚本会检查 ImagePath。
# -Disable：删除该值，恢复默认行为。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$valueName = "EnableStubbedPepForPresilicon"

$name = "ALIOTH_P17I_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sel = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Select")
    $cur = [int]$sel.GetValue("Current"); $sel.Dispose()
    foreach ($cs in @(("ControlSet{0:D3}" -f $cur)) + @("ControlSet001", "ControlSet002") | Select-Object -Unique) {
        $svc = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Services\qcpep", $true)
        if (-not $svc) { continue }
        try {
            $img = $svc.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Write-Host "$cs\Services\qcpep\ImagePath：$img"
            if (-not $Disable -and $img -notmatch 'qcpep8280\.sys$') {
                Write-Host "    警告：ImagePath 不是 qcpep8280.sys，该值对其他版本无效。请先运行 Set-Qcpep8280ImagePath-Offline-Admin.ps1。"
            }
            $p = $svc.CreateSubKey("Parameters")
            try {
                $old = $p.GetValue($valueName)
                if ($Disable) {
                    if ($null -ne $old) { $p.DeleteValue($valueName) }
                    Write-Host "    Parameters\$valueName：$old → 已删除（恢复默认 0）"
                } else {
                    $p.SetValue($valueName, 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                    Write-Host "    Parameters\$valueName：$old → 1（REG_DWORD）"
                }
            } finally { $p.Dispose() }
        } finally { $svc.Dispose() }
        # PEP0 安装状态：INF 的 AddReg 会把该值写回 0，只有安装已完成（ConfigFlags=0 且有 Driver）时，下次开机才不会重新安装覆盖
        $enum = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Enum\ACPI\QCOM0617")
        if (-not $enum) { Write-Host "    Enum\ACPI\QCOM0617 不存在：PEP0 尚未枚举，下次开机会首次安装并把该值覆盖为 0。"; continue }
        try {
            foreach ($inst in $enum.GetSubKeyNames()) {
                $ik = $enum.OpenSubKey($inst)
                try {
                    $cf = $ik.GetValue("ConfigFlags"); $drv = $ik.GetValue("Driver"); $sv = $ik.GetValue("Service")
                    Write-Host ("    Enum\ACPI\QCOM0617\{0}：ConfigFlags={1} Driver={2} Service={3}" -f $inst, $cf, $drv, $sv)
                    if ($cf -eq 0 -and $drv) {
                        Write-Host "    → 安装已完成，下次开机不会重新执行 AddReg，写入的值能保留。"
                    } else {
                        Write-Host "    → 安装未完成，下次开机会重新安装并把该值覆盖为 0！"
                    }
                } finally { $ik.Dispose() }
            }
        } finally { $enum.Dispose() }
    }
} finally {
    Remove-Variable svc, p, sel -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Write-Host "卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Write-Host "完成。下一步：电脑端先启动 kd 桥接，再 fastboot boot Phase17h 镜像。"
