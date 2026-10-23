param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a（电脑端管理员 PowerShell，手机处于 Mass Storage）：离线注入 PEP0 桩驱动 pep0stub。
#   驱动：drivers\pep0_stub\pkg（测试签名），绑定 ACPI\QCOM0519（Phase16 / phase17g-base 镜像中 PEP0 的原始 HID）。
#   作用：只提供 {55beca03} 设备接口和 {a0e1dd36} QueryInterface，供 qcsmmu8280 / qcsubsys8280 使用，不访问硬件。
#   本脚本还会把注入前的相关注册表状态记入日志：qcsmmu / qcsubsys / qcpep 服务，Enum\ACPI\QCOM0519。
#   不修改 qcsmmu / qcsubsys 的 Start（首测期望：qcsmmu=3，qcsubsys=4）。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 窗口中运行本脚本。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\Drivers\Alioth\ADSP")) { throw "${drive}: 看起来不是手机的 Windows 分区。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pkg = Join-Path $projectRoot "Alioth-Engineering\drivers\pep0_stub\pkg"
$inf = Join-Path $pkg "pep0stub.inf"
foreach ($f in @("pep0stub.inf", "pep0stub.sys", "pep0stub.cat")) {
    if (-not (Test-Path -LiteralPath (Join-Path $pkg $f))) { throw "驱动包缺少 $f，请先运行 drivers\pep0_stub\build-pkg.sh" }
}
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$log = Join-Path $logDir "apply-pep0stub-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

Get-ChildItem -LiteralPath $pkg | ForEach-Object { Log ("驱动包文件 {0}  SHA256 {1}" -f $_.Name, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash) }

# 1. 记录注入前状态
$hive = "${drive}:\Windows\System32\Config\SYSTEM"
$name = "ALIOTH_P19A_$PID"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败。" }
try {
    foreach ($cs in @("ControlSet001")) {
        foreach ($svc in @("qcsmmu", "qcsubsys", "qcpep", "pep0stub")) {
            $out = & cmd.exe /c "reg.exe query `"HKLM\$name\$cs\Services\$svc`" 2>&1"
            if ($LASTEXITCODE -ne 0) { Log "$cs\Services\$svc 不存在"; continue }
            $out | Where-Object { $_ -match '\s(Start|ImagePath)\s' } | ForEach-Object { Log "  $cs\Services\$svc  $($_.Trim())" }
        }
        $out = & cmd.exe /c "reg.exe query `"HKLM\$name\$cs\Enum\ACPI\QCOM0519`" /s 2>&1"
        if ($LASTEXITCODE -ne 0) { Log "$cs\Enum\ACPI\QCOM0519 不存在" }
        else { $out | Where-Object { $_ -match '\s(Service|Driver|ConfigFlags|ClassGUID)\s' } | ForEach-Object { Log "  Enum\ACPI\QCOM0519  $($_.Trim())" } }
    }
} finally {
    for ($i = 1; $i -le 8; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds (250 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "注册表 hive 已卸载。"; break }
        if ($i -eq 8) { throw "hive 卸载失败！请关闭 regedit 后手动执行：reg unload HKLM\$name ，卸载成功前不要断开手机，也不要继续注入。" }
    }
}

# 2. DISM 注入（测试签名包，需要 /ForceUnsigned）
$repo = "${drive}:\Windows\System32\DriverStore\FileRepository"
Log "执行: dism.exe /Image:${drive}:\ /Add-Driver /Driver:$inf /ForceUnsigned"
$out = & dism.exe "/Image:${drive}:\" "/Add-Driver" "/Driver:$inf" "/ForceUnsigned" 2>&1
$code = $LASTEXITCODE
$out | ForEach-Object { Add-Content -LiteralPath $log -Value "$_" -Encoding UTF8 }
$out | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" }
Log "DISM 退出码：$code"

$after = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "pep0stub.inf_*" -ErrorAction SilentlyContinue)
foreach ($d in $after) {
    Log "驱动库目录：$($d.Name)"
    Get-ChildItem -LiteralPath $d.FullName | ForEach-Object { Log ("     {0}  {1:N0} 字节" -f $_.Name, $_.Length) }
}
if ($code -ne 0 -or $after.Count -eq 0) {
    Log "注入失败，请把日志发给电脑端：$log"
    exit 1
}
Log "注入成功。下一步：电脑端先启动 kd 监听，再 fastboot boot phase17g-base 镜像（PEP0 = QCOM0519）。"
Log "日志：$log"
