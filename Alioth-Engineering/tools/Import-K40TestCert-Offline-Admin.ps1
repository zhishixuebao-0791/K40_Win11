param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [switch]$Remove   # 带此开关则从手机受信任库删除该证书（回滚）
)

# Phase19a 修复：把 K40 测试签名证书（指纹 7151DDBE...）离线导入手机的
#   Trusted Root + Trusted Publisher，使 testsigning 下 winload 信任 pep0stub.sys 的签名根，
#   允许它作为 boot 驱动加载（根因见 dead-ends-and-breakthroughs.md 突破14）。
#   证书库键 ACL 不给普通管理员写，故与项目其它离线脚本一致，经临时计划任务以 SYSTEM 身份用 reg.exe 写。
#   只写 SOFTWARE hive 的证书库，不动其它。-Remove 可回滚。

$ErrorActionPreference = "Stop"
$thumb = "7151DDBEB8836BE0D0733A53B1B5700C787E1FF7"
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "必须在管理员 PowerShell 中运行。"
}
$drive = $WindowsDrive.TrimEnd(':', '\')
if ($drive -ieq $env:SystemDrive.TrimEnd(':', '\')) { throw "拒绝操作本机系统盘 ${drive}:。" }
if (-not (Test-Path -LiteralPath "${drive}:\Windows\System32\config\SOFTWARE")) { throw "${drive}: 下找不到 SOFTWARE hive。" }

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logDir = Join-Path $projectRoot "Alioth-Engineering\logs"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $logDir ("import-k40cert-" + $(if ($Remove) { "remove-" } else { "" }) + "$stamp.log")
function Log([string]$m) { $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

$stores = @("ROOT", "TrustedPublisher")
$name = "ALIOTH_P19A_IMP_$PID"
$hive = "${drive}:\Windows\System32\config\SOFTWARE"
$task = "K40_Pep0CertImp_$PID"
$cmdFile = Join-Path $env:TEMP "k40-cert-imp-$PID.cmd"
$outFile = "$cmdFile.out"

# 证书 Blob（Windows 原生序列化格式）→ 连续大写 hex
function Get-CertBlobHex {
    $src = Get-Item "Cert:\CurrentUser\My\$thumb" -ErrorAction SilentlyContinue
    if (-not $src) { throw "本机 CurrentUser\My 没有证书 $thumb，无法导出。" }
    $tmpName = "ALIOTHTMP$PID"
    $st = New-Object System.Security.Cryptography.X509Certificates.X509Store($tmpName, "CurrentUser")
    $st.Open("ReadWrite")
    $pub = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, $src.RawData)  # 仅公钥
    $st.Add($pub); $st.Close()
    $blob = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\SystemCertificates\$tmpName\Certificates\$thumb" -Name Blob).Blob
    Remove-Item -Path "HKCU:\Software\Microsoft\SystemCertificates\$tmpName" -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $blob -or $blob.Length -lt 100) { throw "读取 Blob 失败。" }
    return (($blob | ForEach-Object { $_.ToString("X2") }) -join "")
}

$hex = $null
if (-not $Remove) { $hex = Get-CertBlobHex; Log ("已生成证书 Blob hex，" + ($hex.Length / 2) + " 字节") }

Log "挂载 SOFTWARE hive：$hive"
& reg.exe load "HKLM\$name" $hive | Out-Null
if ($LASTEXITCODE -ne 0) { throw "reg load 失败（残留先 reg unload HKLM\ALIOTH_*）。" }
try {
    # 挂载前状态
    foreach ($s in $stores) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Microsoft\SystemCertificates\$s\Certificates\$thumb")
        Log ("改前 $s：" + $(if ($k) { "已存在该证书" } else { "无该证书" })); if ($k) { $k.Close() }
    }

    $lines = @("@echo off")
    foreach ($s in $stores) {
        $key = "HKLM\$name\Microsoft\SystemCertificates\$s\Certificates\$thumb"
        if ($Remove) { $lines += "reg.exe delete `"$key`" /f" }
        else { $lines += "reg.exe add `"$key`" /v Blob /t REG_BINARY /d $hex /f" }
    }
    $lines += "echo done"
    [IO.File]::WriteAllLines($cmdFile, $lines, [Text.Encoding]::ASCII)
    Copy-Item -LiteralPath $cmdFile -Destination (Join-Path $logDir ("import-k40cert-$stamp.cmd")) -ErrorAction SilentlyContinue

    Log "以 SYSTEM 身份执行 reg 写入（临时计划任务）"
    & schtasks.exe /Create /TN $task /TR "cmd.exe /c `"$cmdFile`" > `"$outFile`" 2>&1" /SC ONCE /ST 23:59 /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "创建计划任务失败。" }
    & schtasks.exe /Run /TN $task | Out-Null
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if ((Test-Path $outFile) -and (Select-String -LiteralPath $outFile -Pattern '^done' -Quiet)) { break } }
    & schtasks.exe /Delete /TN $task /F | Out-Null
    if (Test-Path $outFile) { Get-Content -LiteralPath $outFile | ForEach-Object { if ($_ -and $_.Trim()) { Log "SYSTEM 输出：$_" } } }

    # 复核
    foreach ($s in $stores) {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$name\Microsoft\SystemCertificates\$s\Certificates\$thumb")
        if ($Remove) { Log ("改后 $s：" + $(if ($k) { "!! 仍存在（删除失败）" } else { "已删除 OK" })) }
        else {
            if ($k) { Log ("改后 $s：证书已写入，Blob $((($k.GetValue('Blob'))).Length) 字节 OK") }
            else { Log "改后 $s：!! 仍无该证书（写入失败，查 SYSTEM 输出）" }
        }
        if ($k) { $k.Close() }
    }
    Log "================================================"
    if ($Remove) { Log "回滚完成。" } else { Log "导入完成：下一步 Set-Pep0StubInstalled-Offline-Admin.ps1 -WindowsDrive D，再 kd 重启验证。" }
}
finally {
    Remove-Item -LiteralPath $cmdFile, $outFile -ErrorAction SilentlyContinue
    [gc]::Collect(); [gc]::WaitForPendingFinalizers()
    for ($i = 1; $i -le 8; $i++) {
        Start-Sleep -Milliseconds (200 * $i)
        & reg.exe unload "HKLM\$name" | Out-Null
        if ($LASTEXITCODE -eq 0) { Log "hive 已卸载。"; break }
        if ($i -eq 8) { Log "hive 卸载失败！手动执行：reg unload HKLM\$name" }
    }
}
Log "日志：$log"
