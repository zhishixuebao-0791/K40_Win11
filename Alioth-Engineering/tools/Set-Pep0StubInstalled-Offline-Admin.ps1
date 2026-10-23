param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a 修正（电脑端管理员 PowerShell，手机处于 Mass Storage）：离线把 PEP0 写成"已安装 pep0stub"的完整状态。
#   背景：ConfigFlags=0x20（重新安装）会让内核在开机阶段不启动 PEP0，UFS0 等 _DEP 依赖 PEP0 → 0x7B（Phase19a 第二次开机，kd 证实
#         PEP0 ServiceName=pep0stub 但停在 DeviceNodeInitialized）。
#   做法：Enum\ACPI\QCOM0519\<实例> 写 Service/ClassGUID/Class/Driver/DeviceDesc/Mfg，ConfigFlags=0；
#         新建 Control\Class\{4d36e97d-...}\NNNN 驱动键（InfPath 指向 DISM 注入生成的 oemNN.inf）。
#   Enum 键只有 SYSTEM 可写：生成 .reg 文件，用临时计划任务以 SYSTEM 身份 reg import，执行完立即删除任务。

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
$log = Join-Path $logDir "set-pep0stub-installed-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

# 1. 找 DISM 注入生成的 oemNN.inf
$oem = Get-ChildItem -LiteralPath "${drive}:\Windows\INF" -Filter "oem*.inf" | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'pep0stub.sys' -SimpleMatch -Quiet } | Select-Object -First 1
if (-not $oem) { throw "在 ${drive}:\Windows\INF 中找不到 pep0stub 的 oemNN.inf，请先运行 Apply-Pep0Stub-Offline-Admin.ps1" }
Log "pep0stub 对应的 INF：$($oem.Name)"

$classGuid = "{4d36e97d-e325-11ce-bfc1-08002be10318}"
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P19A_IN_$PID"
$task = "K40_Pep0Installed_$PID"
$regFile = Join-Path $env:TEMP "k40-pep0stub-installed-$PID.reg"
$cmdFile = Join-Path $env:TEMP "k40-pep0stub-installed-$PID.cmd"

& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    $sets = Get-ChildItem "Registry::HKEY_LOCAL_MACHINE\$name" | Where-Object { $_.PSChildName -like 'ControlSet*' } | ForEach-Object { $_.PSChildName }
    $reg = @("Windows Registry Editor Version 5.00", "")
    foreach ($cs in $sets) {
        $enumPath = "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519"
        if (-not (Test-Path -LiteralPath $enumPath)) { Log "$cs\Enum\ACPI\QCOM0519 不存在"; continue }

        # 已有指向 pep0stub 的 Class 键就复用，否则取下一个空闲编号
        # 不能用 Get-ChildItem：类键下的 Properties 子键管理员无权打开，会直接报错
        $classKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$cs\Control\Class\$classGuid")
        $names = @($classKey.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' })
        $idx = $null
        foreach ($sn in $names) {
            try { $sk = $classKey.OpenSubKey($sn); if ($sk) { if ($sk.GetValue('InfPath') -eq $oem.Name) { $idx = $sn }; $sk.Close() } } catch { }
        }
        $classKey.Close()
        if (-not $idx) {
            $used = $names | ForEach-Object { [int]$_ }
            $n = 0; while ($used -contains $n) { $n++ }
            $idx = "{0:D4}" -f $n
        }
        Log "$cs 驱动键：Control\Class\$classGuid\$idx"
        $ck = "HKEY_LOCAL_MACHINE\$name\$cs\Control\Class\$classGuid\$idx"
        $reg += "[$ck]"
        $reg += '"DriverDesc"="K40 PEP0 Stub (SM8250)"'
        $reg += '"ProviderName"="K40 Alioth Engineering"'
        $reg += '"DriverVersion"="1.0.0.1"'
        $reg += '"DriverDate"="10-23-2026"'
        $reg += "`"InfPath`"=`"$($oem.Name)`""
        $reg += '"InfSection"="Pep0Stub_Device"'
        $reg += '"MatchingDeviceId"="acpi\\qcom0519"'
        $reg += ""

        foreach ($inst in Get-ChildItem -LiteralPath $enumPath) {
            Log "修改前 $cs 实例 $($inst.PSChildName)：ConfigFlags=$($inst.GetValue('ConfigFlags')) Service=$($inst.GetValue('Service')) Driver=$($inst.GetValue('Driver')) ClassGUID=$($inst.GetValue('ClassGUID'))"
            $ek = "HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519\$($inst.PSChildName)"
            $reg += "[$ek]"
            $reg += '"Service"="pep0stub"'
            $reg += "`"ClassGUID`"=`"$classGuid`""
            $reg += '"Class"="System"'
            $reg += "`"Driver`"=`"$classGuid\\$idx`""
            $reg += '"DeviceDesc"="K40 PEP0 Stub (SM8250)"'
            $reg += '"Mfg"="K40 Alioth Engineering"'
            $reg += '"ConfigFlags"=dword:00000000'
            $reg += ""
            $inst.Close()   # 不关闭句柄会导致最后 reg unload 拒绝访问
        }
    }
    [IO.File]::WriteAllLines($regFile, $reg, [Text.Encoding]::Unicode)
    Copy-Item -LiteralPath $regFile -Destination (Join-Path $logDir "set-pep0stub-installed-$stamp.reg")
    [IO.File]::WriteAllLines($cmdFile, @("@echo off", "reg.exe import `"$regFile`" > `"$regFile.out`" 2>&1"), [Text.Encoding]::ASCII)

    Log "以 SYSTEM 身份导入：$regFile（副本已存入 logs）"
    & schtasks.exe /Create /TN $task /TR "cmd.exe /c `"$cmdFile`"" /SC ONCE /ST 23:59 /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "创建计划任务失败。" }
    & schtasks.exe /Run /TN $task | Out-Null
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (Test-Path -LiteralPath "$regFile.out") { Start-Sleep -Seconds 1; break } }
    & schtasks.exe /Delete /TN $task /F | Out-Null
    if (Test-Path -LiteralPath "$regFile.out") { Get-Content -LiteralPath "$regFile.out" | ForEach-Object { Log "reg import：$_" } }

    $ok = $true
    foreach ($cs in $sets) {
        $enumPath = "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Enum\ACPI\QCOM0519"
        if (-not (Test-Path -LiteralPath $enumPath)) { continue }
        foreach ($inst in Get-ChildItem -LiteralPath $enumPath) {
            $cf = $inst.GetValue('ConfigFlags'); $svc = $inst.GetValue('Service'); $drv = $inst.GetValue('Driver')
            Log "修改后 $cs 实例 $($inst.PSChildName)：ConfigFlags=$cf Service=$svc Driver=$drv"
            if ($cf -ne 0 -or $svc -ne 'pep0stub' -or -not $drv) { $ok = $false }
            $inst.Close()
        }
        $svcKey = Get-Item -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$name\$cs\Services\pep0stub" -ErrorAction SilentlyContinue
        if ($svcKey) { Log "$cs\Services\pep0stub：Start=$($svcKey.GetValue('Start')) ImagePath=$($svcKey.GetValue('ImagePath')) Group=$($svcKey.GetValue('Group'))"; $svcKey.Close() }
        else { Log "$cs\Services\pep0stub 不存在！"; $ok = $false }
    }
    if ($ok) { Log "写入全部生效。" } else { Log "写入未全部生效，请把日志发给电脑端。" }
} finally {
    Remove-Item -LiteralPath $regFile, "$regFile.out", $cmdFile -ErrorAction SilentlyContinue
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { Log "hive 卸载失败！请在本窗口手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机。" }
    }
}
Log "日志：$log"
