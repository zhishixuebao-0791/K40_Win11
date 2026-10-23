param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a 恢复（电脑端管理员 PowerShell，手机处于 Mass Storage）：把 PEP0 退回"无驱动"状态，恢复开机。
#   背景：PEP0 绑定 pep0stub 后开机阶段驱动未加载，UFS0 等 _DEP 依赖 PEP0 → 0x7B（死路 16 及其后续）。
#   操作（以 SYSTEM 身份，经临时计划任务执行）：
#     1. Enum\ACPI\QCOM0519\<实例>：删除 Service / Driver / ClassGUID / Class，ConfigFlags=0（与 DISM 注入前一致）；
#     2. 删除指向 pep0stub 的 Control\Class\{4d36e97d-...}\NNNN 驱动键；
#     3. Services\pep0stub Start=4（禁用，开机不再加载；驱动包仍留在 DriverStore，以后可再用）。

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
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$log = Join-Path $logDir "restore-pep0-nodriver-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$classGuid = "{4d36e97d-e325-11ce-bfc1-08002be10318}"
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P19A_RS_$PID"
$task = "K40_Pep0Restore_$PID"
$cmdFile = Join-Path $env:TEMP "k40-pep0-restore-$PID.cmd"
$outFile = "$cmdFile.out"

function Show-State([string[]]$sets, [string]$tag) {
    foreach ($cs in $sets) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Enum\ACPI\QCOM0519")
        if ($k) {
            foreach ($sn in $k.GetSubKeyNames()) {
                $i = $k.OpenSubKey($sn)
                Log "$tag $cs 实例 ${sn}：ConfigFlags=$($i.GetValue('ConfigFlags')) Service=$($i.GetValue('Service')) Driver=$($i.GetValue('Driver')) ClassGUID=$($i.GetValue('ClassGUID'))"
                $i.Close()
            }
            $k.Close()
        } else { Log "$tag $cs\Enum\ACPI\QCOM0519 不存在" }
        $s = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Services\pep0stub")
        if ($s) { Log "$tag $cs\Services\pep0stub Start=$($s.GetValue('Start'))"; $s.Close() }
    }
}

& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败（如提示被占用，先执行 reg unload 卸载上次残留的 HKLM\ALIOTH_* 挂载）。" }
try {
    $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($name)
    $sets = @($root.GetSubKeyNames() | Where-Object { $_ -like 'ControlSet*' }); $root.Close()
    Show-State $sets "恢复前"

    $lines = @("@echo off")
    foreach ($cs in $sets) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Enum\ACPI\QCOM0519")
        if ($k) {
            foreach ($sn in $k.GetSubKeyNames()) {
                $ek = "HKLM\$name\$cs\Enum\ACPI\QCOM0519\$sn"
                foreach ($v in @("Service", "Driver", "ClassGUID", "Class")) { $lines += "reg.exe delete `"$ek`" /v $v /f" }
                $lines += "reg.exe add `"$ek`" /v ConfigFlags /t REG_DWORD /d 0 /f"
            }
            $k.Close()
        }
        # 指向 pep0stub 的驱动键（InfPath 为 pep0stub 对应的 oemNN.inf，或 DriverDesc 为桩驱动描述）
        $ck = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Control\Class\$classGuid")
        if ($ck) {
            foreach ($sn in @($ck.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' })) {
                try {
                    $sk = $ck.OpenSubKey($sn)
                    if ($sk -and $sk.GetValue('DriverDesc') -eq 'K40 PEP0 Stub (SM8250)') {
                        Log "$cs 将删除驱动键 Control\Class\$classGuid\$sn（InfPath=$($sk.GetValue('InfPath'))）"
                        $lines += "reg.exe delete `"HKLM\$name\$cs\Control\Class\$classGuid\$sn`" /f"
                    }
                    if ($sk) { $sk.Close() }
                } catch { }
            }
            $ck.Close()
        }
        $lines += "reg.exe add `"HKLM\$name\$cs\Services\pep0stub`" /v Start /t REG_DWORD /d 4 /f"
    }
    $lines += "echo done"
    [IO.File]::WriteAllLines($cmdFile, $lines, [Text.Encoding]::ASCII)
    Copy-Item -LiteralPath $cmdFile -Destination (Join-Path $logDir "restore-pep0-nodriver-$stamp.cmd")

    Log "以 SYSTEM 身份执行：$cmdFile（副本已存入 logs）"
    & schtasks.exe /Create /TN $task /TR "cmd.exe /c `"$cmdFile`" > `"$outFile`" 2>&1" /SC ONCE /ST 23:59 /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "创建计划任务失败。" }
    & schtasks.exe /Run /TN $task | Out-Null
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ((Test-Path -LiteralPath $outFile) -and (Select-String -LiteralPath $outFile -Pattern '^done' -Quiet)) { break }
    }
    & schtasks.exe /Delete /TN $task /F | Out-Null
    if (Test-Path -LiteralPath $outFile) { Get-Content -LiteralPath $outFile | ForEach-Object { Log "SYSTEM 输出：$_" } }

    Show-State $sets "恢复后"
} finally {
    Remove-Item -LiteralPath $cmdFile, $outFile -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Log "hive 卸载失败！请在本窗口手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Log "日志：$log"
