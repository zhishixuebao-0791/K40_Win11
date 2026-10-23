param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a 回滚（电脑端管理员 PowerShell，手机处于 Mass Storage）：停用 PEP0 桩驱动。
#   1. 所有控制集 Services\pep0stub\Start = 4（禁用）；
#   2. 尝试删除 Enum\ACPI\QCOM0519\* 下的 Service / Driver 值，让 PEP0 回到"没有驱动"的状态（与 Phase16 一致）。
#      原因：UFS0 等设备的 _DEP 依赖 PEP0，PEP0 绑定了驱动却没启动时可能 0x7B（Phase17b 教训）。

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
$log = Join-Path $projectRoot "Alioth-Engineering\logs\disable-pep0stub-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P19A_RB_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sets = Get-ChildItem "Registry::HKEY_LOCAL_MACHINE\$name" | Where-Object { $_.PSChildName -like 'ControlSet*' } | ForEach-Object { $_.PSChildName }
    foreach ($cs in $sets) {
        $svc = "HKLM\$name\$cs\Services\pep0stub"
        & cmd.exe /c "reg.exe query `"$svc`" >nul 2>&1"
        if ($LASTEXITCODE -eq 0) {
            & reg.exe add $svc /v Start /t REG_DWORD /d 4 /f | Out-Null
            Log "$cs\Services\pep0stub Start=4（退出码 $LASTEXITCODE）"
        } else { Log "$cs\Services\pep0stub 不存在" }

        $enumPath = "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519"
        if (-not (Test-Path -LiteralPath $enumPath)) { Log "$cs\Enum\ACPI\QCOM0519 不存在"; continue }
        foreach ($inst in Get-ChildItem -LiteralPath $enumPath) {
            $k = "HKLM\$name\$cs\Enum\ACPI\QCOM0519\$($inst.PSChildName)"
            foreach ($v in @("Service", "Driver")) {
                & cmd.exe /c "reg.exe delete `"$k`" /v $v /f >nul 2>&1"
                Log "  删除 $k 的 $v 值（退出码 $LASTEXITCODE；1 表示值不存在或无权限）"
            }
        }
    }
} finally {
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { throw "hive 卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name" }
    }
}
Log "回滚完成。日志：$log"
