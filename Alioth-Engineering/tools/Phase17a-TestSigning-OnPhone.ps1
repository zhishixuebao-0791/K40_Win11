param(
    [Parameter(Mandatory = $true)][ValidateSet("Apply", "Check", "Rollback")][string]$Mode
)

# Phase17a：验证"测试签名模式下 Andromeda 签名的 Kona 驱动能否加载"。在手机 Windows 上运行（管理员 PowerShell）。
#   -Mode Apply     开启 testsigning，把 qcsmmu 的 ImagePath 改回 qcsmmu8250.sys（Andromeda 签名），然后重启手机。
#   -Mode Check     重启后运行：记录 testsigning 状态、MMU1 状态和 CodeIntegrity 事件。
#                   判断：MMU1 由 Code 52 / CI 3004 变为 Code 31（或更好），说明测试签名有效。
#   -Mode Rollback  恢复 ImagePath 为 qcsmmu8280.sys，并关闭 testsigning，然后重启手机。

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$svc = "HKLM:\SYSTEM\CurrentControlSet\Services\qcsmmu"
$mmu = 'ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1'
$img8250 = '\SystemRoot\System32\DriverStore\FileRepository\qcsmmu8250.inf_arm64_326da5121bfa3145\qcsmmu8250.sys'
$img8280 = '\SystemRoot\System32\DriverStore\FileRepository\qcsmmu8280.inf_arm64_1d80adabc6ef3b6d\qcsmmu8280.sys'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $here "Phase17a_${Mode}_$stamp"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$log = Join-Path $outDir "phase17a.txt"
function Log([string]$m) { $m | Tee-Object -FilePath $log -Append }

function Set-ImagePath([string]$path) {
    $sys = $path -replace '^\\SystemRoot', $env:SystemRoot
    if (-not (Test-Path -LiteralPath $sys)) { throw "驱动文件不存在：$sys" }
    $old = (Get-ItemProperty -Path $svc -Name ImagePath).ImagePath
    Log "原 ImagePath = $old"
    New-ItemProperty -Path $svc -Name ImagePath -Value $path -PropertyType ExpandString -Force | Out-Null
    Log "新 ImagePath = $((Get-ItemProperty -Path $svc -Name ImagePath).ImagePath)"
}

if ($Mode -eq "Apply") {
    Log "== Phase17a Apply =="
    $o = & bcdedit.exe /set "{current}" testsigning on 2>&1
    Log "bcdedit testsigning on: $o"
    if ($LASTEXITCODE -ne 0) { throw "bcdedit 设置失败，没有修改 ImagePath。" }
    Set-ImagePath $img8250
    Log "完成。请重启手机，进入 Windows 后运行："
    Log "  powershell -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" -Mode Check"
    return
}

if ($Mode -eq "Rollback") {
    Log "== Phase17a Rollback =="
    Set-ImagePath $img8280
    $o = & bcdedit.exe /set "{current}" testsigning off 2>&1
    Log "bcdedit testsigning off: $o"
    Log "完成。请重启手机。"
    return
}

# Check
Log "== Phase17a Check =="
& bcdedit.exe /enum "{current}" 2>&1 | Out-File (Join-Path $outDir "bcdedit.txt") -Encoding utf8
$ts = Select-String -Path (Join-Path $outDir "bcdedit.txt") -Pattern "testsigning"
Log ("BCD testsigning: " + $(if ($ts) { $ts.Line.Trim() } else { "未设置" }))
Log ("ImagePath = " + (Get-ItemProperty -Path $svc -Name ImagePath).ImagePath)

Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'ACPI\VEN_QCOM&DEV_?509*' -or $_.InstanceId -like 'ACPI\QCOM0519*' -or $_.InstanceId -like 'ACPI\QCOM061B*' } | ForEach-Object {
    $ps = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemStatus -ErrorAction SilentlyContinue).Data
    $pc = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data
    Log ("{0} Status={1} ProblemCode={2} ProblemStatus=0x{3:X8}" -f $_.InstanceId, $_.Status, $pc, [uint32]$ps)
}

$drv = Get-CimInstance Win32_SystemDriver -Filter "Name='qcsmmu'" -ErrorAction SilentlyContinue
if ($drv) { Log ("qcsmmu 服务: State={0} PathName={1}" -f $drv.State, $drv.PathName) }

try {
    $ev = Get-WinEvent -LogName "Microsoft-Windows-CodeIntegrity/Operational" -MaxEvents 300 -ErrorAction Stop |
        Where-Object { $_.TimeCreated -gt (Get-Date).AddHours(-2) -and $_.Message -match "qcsmmu|qcpep|Andromeda" }
    $ev | Select-Object TimeCreated, Id, Message | Format-List | Out-File (Join-Path $outDir "ci_events.txt") -Encoding utf8
    Log ("最近 2 小时与 qcsmmu/qcpep 相关的 CodeIntegrity 事件：{0} 条（详见 ci_events.txt）" -f @($ev).Count)
    @($ev) | Group-Object Id | ForEach-Object { Log ("  事件 {0}: {1} 条" -f $_.Name, $_.Count) }
} catch {
    Log "读取 CodeIntegrity 日志失败：$_"
}
Log "完成。请回到 Mass Storage 模式，把目录 $outDir 告诉电脑端。"
