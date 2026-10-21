param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# 只读：离线导出手机 SYSTEM hive 中所有 ACPI 设备实例的绑定情况（Service/Driver/ConfigFlags）以及相关服务的 Start/ImagePath。
# 电脑端管理员 PowerShell，手机处于 Mass Storage。用于 Phase17d 开机卡死时，判断有哪些设备驱动会在 PEP 启动后被放行。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$out = Join-Path $projectRoot ("Alioth-Engineering\logs\OfflineDeviceState_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$name = "ALIOTH_DEVSTATE_$PID"
& reg.exe load "HKLM\$name" "${drive}:\Windows\System32\Config\SYSTEM" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
$lines = New-Object System.Collections.Generic.List[string]
try {
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    $sel = $hklm.OpenSubKey("$name\Select"); $cur = [int]$sel.GetValue("Current"); $sel.Dispose()
    $cs = "$name\ControlSet{0:D3}" -f $cur
    $lines.Add("ControlSet{0:D3}" -f $cur)
    $services = New-Object System.Collections.Generic.HashSet[string]
    $acpi = $hklm.OpenSubKey("$cs\Enum\ACPI")
    foreach ($dev in $acpi.GetSubKeyNames()) {
        $dk = $acpi.OpenSubKey($dev)
        foreach ($inst in $dk.GetSubKeyNames()) {
            $ik = $dk.OpenSubKey($inst)
            if (-not $ik) { continue }
            $svc = [string]$ik.GetValue("Service"); $drv = [string]$ik.GetValue("Driver"); $cf = $ik.GetValue("ConfigFlags")
            $hw = @($ik.GetValue("HardwareID")) | Select-Object -First 1
            $lines.Add(("DEV {0}\{1} | Service={2} | Driver={3} | ConfigFlags={4} | HWID={5}" -f $dev, $inst, $svc, $drv, $cf, $hw))
            if ($svc) { [void]$services.Add($svc) }
            $ik.Dispose()
        }
        $dk.Dispose()
    }
    $acpi.Dispose()
    foreach ($s in ($services | Sort-Object)) {
        $sk = $hklm.OpenSubKey("$cs\Services\$s")
        if ($sk) {
            $lines.Add(("SVC {0} | Start={1} | Type={2} | Group={3} | ImagePath={4}" -f $s, $sk.GetValue("Start"), $sk.GetValue("Type"), $sk.GetValue("Group"), $sk.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)))
            $sk.Dispose()
        } else { $lines.Add("SVC $s | (服务键不存在)") }
    }
    $pp = $hklm.OpenSubKey("$cs\Services\qcpep\Parameters")
    if ($pp) { foreach ($v in $pp.GetValueNames()) { $lines.Add(("QCPEP_PARAM {0}={1}" -f $v, $pp.GetValue($v))) }; $pp.Dispose() }
} finally {
    Remove-Variable hklm, sel, acpi, dk, ik, sk, pp -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        if ($i -eq 8) { Write-Host "卸载失败！请手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
$lines | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ("已导出 {0} 行到 {1}" -f $lines.Count, $out)
