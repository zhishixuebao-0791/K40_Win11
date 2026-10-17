param(
    [string]$WindowsDrive = "E",
    [switch]$SkipModemFirmware,
    [switch]$AllowHostSystemDrive
)

# Phase14 步骤A：只读取证，不修改手机任何数据。
# 1. 离线加载手机 SYSTEM hive，导出 qcsubsys 各 DSP 设备的驱动软件键(Control\Class)和硬件键(Enum)，
#    以及 PILC(QCOM06E0) 的 SubsystemLoad 配置，用于确认 ADSP\ImagePath 等 8280 软件键值是否缺失。
# 2. 在 Mass Storage 暴露的分区中查找 modem(NON-HLOS) 分区，只读复制 image\adsp.* / cdsp.* / slpi.*，
#    供后续 pil-squasher 合并为 alioth 自签名固件 mbn。

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "必须在管理员 PowerShell 窗口中运行本脚本。"
    }
}

function Get-ProjectRoot {
    $scriptDir = $PSScriptRoot
    if ((Split-Path -Leaf (Split-Path -Parent $scriptDir)) -ieq "Alioth-Engineering") {
        return Split-Path -Parent (Split-Path -Parent $scriptDir)
    }
    return Split-Path -Parent $scriptDir
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Invoke-Captured {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    Write-Log ("执行: {0} {1}" -f $FilePath, ($Arguments -join " "))
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $script:LASTNATIVEEXITCODE = 0
        $ErrorActionPreference = "Continue"
        $output = & $FilePath @Arguments 2>&1
        $script:LASTNATIVEEXITCODE = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($output) {
        Add-Content -LiteralPath $script:LogPath -Value ($output | ForEach-Object { "$_" }) -Encoding UTF8
    }
    if (($script:LASTNATIVEEXITCODE -ne 0) -and (-not $IgnoreExitCode)) {
        throw "命令失败，退出码 $($script:LASTNATIVEEXITCODE): $FilePath"
    }
    return $output
}

function Unload-HiveWithRetry {
    param([string]$HiveName)

    for ($attempt = 1; $attempt -le 8; $attempt++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds (250 * $attempt)
        Invoke-Captured -FilePath reg.exe -Arguments @("unload", "HKLM\$HiveName") -IgnoreExitCode | Out-Null
        if ($script:LASTNATIVEEXITCODE -eq 0) {
            Write-Log "第 $attempt 次尝试成功卸载 HKLM\$HiveName。"
            return
        }
        Write-Log "第 $attempt 次卸载 hive 失败，退出码 $($script:LASTNATIVEEXITCODE)。"
    }
    throw "无法卸载 HKLM\$HiveName，请关闭其他 PowerShell/regedit 窗口后重试。"
}

function Export-RegKey {
    param(
        [string]$RegPath,
        [string]$FileName
    )

    $target = Join-Path $script:OutDir $FileName
    Invoke-Captured -FilePath reg.exe -Arguments @("export", $RegPath, $target, "/y") -IgnoreExitCode | Out-Null
    if ($script:LASTNATIVEEXITCODE -eq 0) {
        Write-Log "已导出: $RegPath -> $FileName"
    } else {
        Write-Log "键不存在或导出失败: $RegPath"
    }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:OutDir = Join-Path $projectRoot ("Alioth-Engineering\logs\QcsubsysPhase14Evidence_{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $script:OutDir | Out-Null
$script:LogPath = Join-Path $script:OutDir "00_Log.txt"

Write-Log "Phase14 步骤A：只读取证开始。"
Write-Log "输出目录: $script:OutDir"

# ---------- 1. 离线注册表 ----------
$normalized = $WindowsDrive.TrimEnd(':', '\')
if ((-not $AllowHostSystemDrive) -and ($normalized -ieq $env:SystemDrive.TrimEnd(':', '\'))) {
    throw "拒绝操作本机系统盘 ${normalized}:。Mass Storage 模式下手机 Windows 分区通常是 E: 或其他盘符。"
}
$systemHive = "${normalized}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) {
    throw "找不到离线 SYSTEM hive: $systemHive"
}

$hiveName = "ALIOTH_PHASE14_EVIDENCE_$PID"
$loaded = $false
$summary = New-Object System.Collections.Generic.List[string]

try {
    Invoke-Captured -FilePath reg.exe -Arguments @("load", "HKLM\$hiveName", $systemHive) | Out-Null
    $loaded = $true

    $current = (Get-ItemProperty -LiteralPath "Registry::HKEY_LOCAL_MACHINE\$hiveName\Select" -Name Current).Current
    $controlSet = "ControlSet{0:D3}" -f [int]$current
    Write-Log "离线当前 ControlSet: $controlSet"
    $regRoot = "HKLM\$hiveName\$controlSet"
    $psRoot = "Registry::HKEY_LOCAL_MACHINE\$hiveName\$controlSet"

    $devices = @(
        @{ Tag = "ADSP"; Id = "QCOM061B" },
        @{ Tag = "CDSP"; Id = "QCOM06B0" },
        @{ Tag = "SCSS"; Id = "QCOM061F" },
        @{ Tag = "SPSS"; Id = "QCOM068D" },
        @{ Tag = "SSDD"; Id = "QCOM0620" },
        @{ Tag = "PILC"; Id = "QCOM06E0" },
        @{ Tag = "PDSR"; Id = "QCOM06DF" }
    )

    foreach ($dev in $devices) {
        $enumKey = "Enum\ACPI\$($dev.Id)"
        if (-not (Test-Path -LiteralPath "$psRoot\$enumKey")) {
            Write-Log "$($dev.Tag) ($($dev.Id)) 在离线 Enum 中不存在。"
            $summary.Add(("{0,-5} {1,-9} Enum不存在" -f $dev.Tag, $dev.Id))
            continue
        }
        Export-RegKey -RegPath "$regRoot\$enumKey" -FileName ("10_Enum_{0}_{1}.reg" -f $dev.Tag, $dev.Id)

        foreach ($inst in Get-ChildItem -LiteralPath "$psRoot\$enumKey") {
            $props = Get-ItemProperty -LiteralPath $inst.PSPath
            $driver = $props.Driver
            if (-not $driver) {
                $summary.Add(("{0,-5} {1,-9} 无 Driver 值(未绑定)" -f $dev.Tag, $dev.Id))
                continue
            }
            $classKey = "Control\Class\$driver"
            Export-RegKey -RegPath "$regRoot\$classKey" -FileName ("20_Class_{0}_{1}.reg" -f $dev.Tag, ($driver -replace '[\\{}]', '_'))

            $classPs = "$psRoot\$classKey"
            $infPath = (Get-ItemProperty -LiteralPath $classPs -ErrorAction SilentlyContinue).InfPath
            $subKeys = @(Get-ChildItem -LiteralPath $classPs -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName })
            $imagePath = $null
            if (Test-Path -LiteralPath "$classPs\$($dev.Tag)") {
                $imagePath = (Get-ItemProperty -LiteralPath "$classPs\$($dev.Tag)" -ErrorAction SilentlyContinue).ImagePath
            }
            $summary.Add(("{0,-5} {1,-9} Driver={2} InfPath={3} 软件键子键=[{4}] {0}\ImagePath={5}" -f `
                $dev.Tag, $dev.Id, $driver, $infPath, ($subKeys -join ","), ($(if ($imagePath) { $imagePath } else { "<缺失>" }))))
        }
    }

    Export-RegKey -RegPath "$regRoot\Services\qcsubsys" -FileName "30_Service_qcsubsys.reg"
    Export-RegKey -RegPath "$regRoot\Services\qcPILC" -FileName "30_Service_qcPILC.reg"
} finally {
    # 释放对离线 hive 中注册表键对象的引用，否则 reg unload 会因句柄占用报“拒绝访问”。
    Remove-Variable -Name inst, props, dev -ErrorAction SilentlyContinue
    if ($loaded) {
        Unload-HiveWithRetry -HiveName $hiveName
    }
}

$summaryPath = Join-Path $script:OutDir "01_Summary.txt"
$summary | Out-File -FilePath $summaryPath -Encoding utf8
Write-Log "注册表摘要已写入 01_Summary.txt："
$summary | ForEach-Object { Write-Log "  $_" }

# ---------- 2. modem 分区固件（只读复制）----------
if ($SkipModemFirmware) {
    Write-Log "已指定 -SkipModemFirmware，跳过 modem 固件提取。"
    exit 0
}

$fwOut = Join-Path $script:OutDir "modem-firmware"
New-Item -ItemType Directory -Force -Path $fwOut | Out-Null

$candidates = Get-Volume | Where-Object { $_.FileSystemLabel -match '(?i)modem|non-hlos' -or $_.FileSystem -match 'FAT' }
Write-Log ("候选 FAT/modem 卷数量: {0}" -f @($candidates).Count)
$candidates | Select-Object DriveLetter, FileSystemLabel, FileSystem, Size, Path |
    Format-Table -AutoSize | Out-String -Width 300 | Out-File -FilePath (Join-Path $script:OutDir "40_Volumes.txt") -Encoding utf8

$found = $false
foreach ($vol in $candidates) {
    $root = if ($vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $vol.Path }
    $imageDir = Join-Path $root "image"
    $mdt = Join-Path $imageDir "adsp.mdt"
    try {
        $hasMdt = [System.IO.File]::Exists($mdt)
    } catch {
        $hasMdt = $false
    }
    if (-not $hasMdt) {
        continue
    }

    $found = $true
    Write-Log "在卷 $root (标签: $($vol.FileSystemLabel)) 找到 image\adsp.mdt，开始只读复制。"
    foreach ($name in [System.IO.Directory]::GetFiles($imageDir)) {
        $leaf = [System.IO.Path]::GetFileName($name)
        if ($leaf -match '^(?i)(adsp|cdsp|slpi)\.(mdt|b\d\d|mbn)$') {
            [System.IO.File]::Copy($name, (Join-Path $fwOut $leaf), $true)
        }
    }
    Get-ChildItem -LiteralPath $fwOut | Get-FileHash -Algorithm SHA256 |
        Select-Object @{ n = "File"; e = { Split-Path -Leaf $_.Path } }, Hash |
        Format-Table -AutoSize | Out-String -Width 200 |
        Out-File -FilePath (Join-Path $script:OutDir "41_ModemFirmwareHashes.txt") -Encoding utf8
    Write-Log ("已复制 {0} 个固件分段文件到 modem-firmware。" -f (Get-ChildItem -LiteralPath $fwOut).Count)
    break
}

if (-not $found) {
    Write-Log "未在任何可访问的 FAT 卷中找到 image\adsp.mdt。请查看 40_Volumes.txt；如 modem 分区无盘符，可用 diskpart 临时分配盘符后用 -SkipModemFirmware 以外的方式重跑。"
}

Write-Log "Phase14 步骤A 完成，手机数据未做任何修改。"
