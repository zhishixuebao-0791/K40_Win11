# 安装自写 KMDF 驱动（PEP0 桩驱动）所需的工具链。必须在管理员 PowerShell 中运行。
# 1) 给已有的 VS 生成工具 2026 补 ARM64 交叉编译组件
# 2) 用 winget 安装 WDK 10.0.26100（km / wdf 头文件与内核库）
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot "..\logs\install-driver-toolchain-$(Get-Date -Format yyyyMMdd-HHmmss).log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
Start-Transcript -Path $log | Out-Null

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "错误：请在管理员 PowerShell 中运行本脚本。" -ForegroundColor Red
    Stop-Transcript | Out-Null; exit 1
}

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -products * -latest -property installationPath
Write-Host "VS 生成工具位置：$vsPath"

Write-Host "`n[1/2] 修改 VS 生成工具：添加 ARM64 编译器与 Spectre 库（约 2~4GB，需数分钟）..." -ForegroundColor Cyan
$setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
$vsArgs = @('modify', '--installPath', "`"$vsPath`"",
    '--add', 'Microsoft.VisualStudio.Component.VC.Tools.ARM64',
    '--add', 'Microsoft.VisualStudio.Component.VC.Runtimes.ARM64.Spectre',
    '--add', 'Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre',
    '--quiet', '--norestart')
$p = Start-Process -FilePath $setup -ArgumentList $vsArgs -Wait -PassThru
Write-Host "VS 安装器退出码：$($p.ExitCode)（0 或 3010 为成功）"

Write-Host "`n[2/2] 安装 WDK 10.0.26100 ..." -ForegroundColor Cyan
if (Test-Path "${env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.26100.0\km\wdm.h") {
    Write-Host "WDK 已安装，跳过。"
} else {
    winget install --id Microsoft.WindowsWDK.10.0.26100 -e --silent --accept-package-agreements --accept-source-agreements
    Write-Host "winget 退出码：$LASTEXITCODE"
}

Write-Host "`n===== 安装后检查 =====" -ForegroundColor Cyan
$msvc = Get-ChildItem "$vsPath\VC\Tools\MSVC" | Sort-Object Name | Select-Object -Last 1
$checks = [ordered]@{
    'ARM64 交叉编译器 cl.exe' = "$($msvc.FullName)\bin\Hostx64\arm64\cl.exe"
    'WDK km 头文件 wdm.h'     = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.26100.0\km\wdm.h"
    'KMDF 头文件目录'          = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\wdf\kmdf"
    'ARM64 内核库 ntoskrnl.lib' = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib\10.0.26100.0\km\arm64\ntoskrnl.lib"
    'ARM64 KMDF 库目录'        = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib\wdf\kmdf\arm64"
}
foreach ($k in $checks.Keys) {
    $ok = Test-Path $checks[$k]
    Write-Host ("{0,-28} {1}  {2}" -f $k, $(if ($ok) { '有' } else { '缺失' }), $checks[$k]) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
Write-Host "`n日志：$log"
Stop-Transcript | Out-Null
