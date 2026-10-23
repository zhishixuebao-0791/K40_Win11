param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive
)

# Phase19a 只读核查：确认 pep0stub 的自签名测试证书（指纹 7151DDBE...）是否已在手机的
#   「受信任根」/「受信任发布者」证书库里。若不在，则 testsigning 下 winload 校验 pep0stub.sys
#   会因 UntrustedRoot 被剔除出引导驱动列表（当前 0x7B 的根因假设）。
#   本脚本不修改任何内容：只 reg load SOFTWARE hive、reg query、reg unload。

$ErrorActionPreference = "Stop"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 中运行。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\config\SOFTWARE")) { throw "${drive}: 下找不到 SOFTWARE hive。" }

$thumb = "7151DDBEB8836BE0D0733A53B1B5700C787E1FF7"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $logDir "check-pep0stub-trust-$stamp.log"
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$name = "ALIOTH_P19A_CHK_$PID"
$hive = "${drive}:\Windows\System32\config\SOFTWARE"

Log "挂载 SOFTWARE hive：$hive"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败（残留挂载先 reg unload HKLM\ALIOTH_*）。" }
try {
    # 机器级证书库（SOFTWARE hive 内）+ 组策略库
    $stores = @(
        "Microsoft\SystemCertificates\ROOT\Certificates",
        "Microsoft\SystemCertificates\TrustedPublisher\Certificates",
        "Microsoft\SystemCertificates\CA\Certificates",
        "Policies\Microsoft\SystemCertificates\ROOT\Certificates",
        "Policies\Microsoft\SystemCertificates\TrustedPublisher\Certificates"
    )
    $found = $false
    foreach ($s in $stores) {
        $base = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\$s")
        if (-not $base) { Log "库不存在: $s"; continue }
        $subs = $base.GetSubKeyNames()
        $hit = $subs | Where-Object { $_ -ieq $thumb }
        if ($hit) { Log ">>> 命中: $s 下存在 $thumb （证书已受信任）"; $found = $true }
        else { Log "未命中: $s （共 $($subs.Count) 张证书，无 $thumb）" }
        $base.Close()
    }
    Log "================================================"
    if ($found) { Log "结论：K40 测试证书已在受信任库 → 根因不是证书信任，需另查。" }
    else { Log "结论：K40 测试证书【不在】任何受信任根/发布者库 → 证实假设：winload 因 UntrustedRoot 剔除 pep0stub，这就是 0x7B 的根因。" }
}
finally {
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    for ($i = 1; $i -le 8; $i++) {
        Start-Sleep -Milliseconds (200 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "hive 已卸载。"; break }
        if ($i -eq 8) { Log "hive 卸载失败！手动执行：reg unload HKLM\$name" }
    }
}
Log "日志：$log"
