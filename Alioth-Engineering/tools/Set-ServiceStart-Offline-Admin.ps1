param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [Parameter(Mandatory = $true)][string]$Service,
    [Parameter(Mandatory = $true)][ValidateRange(0, 4)][int]$Start
)

# 离线修改手机 Windows 中某个服务的 Start 值（电脑端管理员 PowerShell，手机处于 Mass Storage）。
# 例：Phase17j 验证 IoGetIommuInterface 时，把 qcsmmu 从 4（禁用）改回 3（按需启动）。
# 只改 Start，其他值不动；会打印修改前后的值和 ImagePath。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }
$hive = "${drive}:\Windows\System32\Config\SYSTEM"

$name = "ALIOTH_SVCSTART_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sel = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Select")
    $cur = [int]$sel.GetValue("Current"); $sel.Dispose()
    $found = $false
    foreach ($cs in @(("ControlSet{0:D3}" -f $cur)) + @("ControlSet001", "ControlSet002") | Select-Object -Unique) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Services\$Service", $true)
        if (-not $k) { continue }
        $found = $true
        try {
            $old = $k.GetValue("Start")
            $img = $k.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $k.SetValue("Start", $Start, [Microsoft.Win32.RegistryValueKind]::DWord)
            Write-Host "$cs\Services\$Service：Start $old → $Start"
            Write-Host "    ImagePath：$img"
        } finally { $k.Dispose() }
    }
    if (-not $found) { Write-Host "没有找到服务 $Service，未做任何修改。" }
} finally {
    Remove-Variable k, sel -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Host "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Write-Host "卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Write-Host "完成。"
