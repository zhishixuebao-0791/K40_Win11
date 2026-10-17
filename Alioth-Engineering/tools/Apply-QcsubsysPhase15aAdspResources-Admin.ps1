param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [string]$ResourceBinPath = "",
    [switch]$AllowHostSystemDrive
)

# Phase15A：验证 ADSP 当前 0xC000003B 是否由缺少 Resources\BinaryPath（AeoB 电源资源文件）引起。
#   只做一件事：把 AeoB 资源文件复制到手机 \Windows\System32\Drivers\Alioth\ADSP\RADS.bin，
#   并在 ADSP 硬件键 Device Parameters\Resources 写 BinaryPath（对应 surfacepro_ext_adsp8280.inf 的 [SUBSYSReg_ADSP_HW]）。
#   默认使用 Surface 原版 RADS.bin（含 8250 PEP 可能不支持的 rail_lpicx/rail_lpimx，这是本实验要观察的下一个故障点）。
# 回滚：Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1 -WindowsDrive <盘符> -BackupDir <本次备份目录>（按 manifest 通用回滚）

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

function Invoke-Reg {
    param([string[]]$Arguments, [switch]$IgnoreExitCode)
    Write-Log ("执行: reg.exe {0}" -f ($Arguments -join " "))
    $oldPref = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & reg.exe @Arguments 2>&1
        $script:RegExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPref
    }
    if ($output) { Add-Content -LiteralPath $script:LogPath -Value ($output | ForEach-Object { "$_" }) -Encoding UTF8 }
    if (($script:RegExit -ne 0) -and (-not $IgnoreExitCode)) {
        throw "reg.exe 失败，退出码 $($script:RegExit)"
    }
}

function Unload-HiveWithRetry {
    param([string]$HiveName)
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds (250 * $attempt)
        Invoke-Reg -Arguments @("unload", "HKLM\$HiveName") -IgnoreExitCode
        if ($script:RegExit -eq 0) {
            Write-Log "第 $attempt 次尝试成功卸载 HKLM\$HiveName。"
            return
        }
    }
    throw "无法卸载 HKLM\$HiveName。请关闭 regedit/其他 PowerShell 后执行: reg.exe unload HKLM\$HiveName ；在卸载成功前不要断开手机。"
}

# 使用 .NET RegistryKey 并及时 Dispose，避免句柄残留导致 hive 无法卸载
function Get-HklmSubKey {
    param([string]$Path, [switch]$Create)
    $hklm = [Microsoft.Win32.Registry]::LocalMachine
    if ($Create) { return $hklm.CreateSubKey($Path) }
    return $hklm.OpenSubKey($Path, $true)
}

function Backup-Value {
    param([string]$Path, [string]$Name)
    $key = Get-HklmSubKey -Path $Path
    $entry = [ordered]@{ Path = $Path; Name = $Name; KeyExisted = ($null -ne $key); Existed = $false; Kind = $null; Value = $null }
    if ($key) {
        try {
            if ($key.GetValueNames() -contains $Name) {
                $entry.Existed = $true
                $entry.Kind = $key.GetValueKind($Name).ToString()
                $entry.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
        } finally { $key.Dispose() }
    }
    $script:Backup.Add([pscustomobject]$entry)
}

function Set-Value {
    param([string]$Path, [string]$Name, $Value, [Microsoft.Win32.RegistryValueKind]$Kind)
    Backup-Value -Path $Path -Name $Name
    $probe = Get-HklmSubKey -Path $Path
    if ($probe) { $probe.Dispose() } else { $script:CreatedKeys.Add($Path) }
    $key = Get-HklmSubKey -Path $Path -Create
    try { $key.SetValue($Name, $Value, $Kind) } finally { $key.Dispose() }
    $text = if ($Value -is [array]) { $Value -join ", " } elseif ($Kind -eq "DWord") { "0x{0:x8}" -f [int]$Value } else { [string]$Value }
    Write-Log ("设置 {0}\{1} ({2}) = {3}" -f ($Path -replace '^[^\\]+\\[^\\]+\\', ''), $Name, $Kind, $text)
}

function Remove-Value {
    param([string]$Path, [string]$Name)
    Backup-Value -Path $Path -Name $Name
    $key = Get-HklmSubKey -Path $Path
    if (-not $key) { return }
    try {
        if ($key.GetValueNames() -contains $Name) {
            $key.DeleteValue($Name)
            Write-Log ("删除 Phase13 残留 {0}\{1}" -f ($Path -replace '^[^\\]+\\[^\\]+\\', ''), $Name)
        }
    } finally { $key.Dispose() }
}

Assert-Administrator

$projectRoot = Get-ProjectRoot
if (-not $ResourceBinPath) {
    $ResourceBinPath = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\surfaceproextadsp8280\RADS.bin"
}
if (-not (Test-Path -LiteralPath $ResourceBinPath)) { throw "找不到 AeoB 资源文件: $ResourceBinPath" }
$magic = [System.Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($ResourceBinPath), 0, 4)
if ($magic -ne "AeoB") { throw "资源文件不是 AeoB 格式（文件头为 '$magic'）: $ResourceBinPath" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $projectRoot ("Alioth-Engineering\backups\qcsubsys-phase15a-adsp-resources-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$script:LogPath = Join-Path $projectRoot ("Alioth-Engineering\logs\apply-qcsubsys-phase15a-adsp-resources-{0}.log" -f $stamp)
$script:Backup = New-Object System.Collections.Generic.List[object]
$script:CreatedKeys = New-Object System.Collections.Generic.List[string]

Write-Log "Phase15A：ADSP Resources\BinaryPath 离线写入开始。"
Write-Log "备份目录: $backupDir"

$drive = $WindowsDrive.TrimEnd(':', '\')
if ((-not $AllowHostSystemDrive) -and ($drive -ieq $env:SystemDrive.TrimEnd(':', '\'))) { throw "拒绝操作本机系统盘 ${drive}:。" }
$systemHive = "${drive}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) { throw "找不到离线 SYSTEM hive: $systemHive（请确认手机 WIN 分区盘符）" }

# ---------- 1. 资源文件 ----------
$binHash = (Get-FileHash -LiteralPath $ResourceBinPath -Algorithm SHA256).Hash
Write-Log "AeoB 资源文件: $ResourceBinPath  SHA256=$binHash"
$binDirOnPhone = "${drive}:\Windows\System32\Drivers\Alioth\ADSP"
$binOnPhone = Join-Path $binDirOnPhone "RADS.bin"
$binExisted = Test-Path -LiteralPath $binOnPhone
New-Item -ItemType Directory -Force -Path $binDirOnPhone | Out-Null
Copy-Item -LiteralPath $ResourceBinPath -Destination $binOnPhone -Force
if ((Get-FileHash -LiteralPath $binOnPhone -Algorithm SHA256).Hash -ne $binHash) { throw "复制到手机后的资源文件哈希不一致。" }
Write-Log "资源文件已复制并校验: $binOnPhone"

# ---------- 2. 注册表 ----------
$hiveName = "ALIOTH_PHASE15A_APPLY_$PID"
$loaded = $false
try {
    Invoke-Reg -Arguments @("load", "HKLM\$hiveName", $systemHive)
    $loaded = $true

    $sel = Get-HklmSubKey -Path "$hiveName\Select"
    try { $current = [int]$sel.GetValue("Current") } finally { $sel.Dispose() }
    $cs = "$hiveName\ControlSet{0:D3}" -f $current
    Write-Log ("离线当前 ControlSet: ControlSet{0:D3}" -f $current)

    $adspInst = "$cs\Enum\ACPI\QCOM061B\2&daba3ff&0"
    $k = Get-HklmSubKey -Path $adspInst
    if (-not $k) { throw "找不到 ADSP 设备实例键: $adspInst" }
    $k.Dispose()

    Set-Value "$adspInst\Device Parameters\Resources" "BinaryPath" "C:\Windows\System32\Drivers\Alioth\ADSP\RADS.bin" String
} finally {
    Remove-Variable -Name k, sel -ErrorAction SilentlyContinue
    $manifest = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString("s")
        WindowsDrive = $drive
        HiveNamePrefix = $hiveName
        FirmwareOnPhone = "\Windows\System32\Drivers\Alioth\ADSP\RADS.bin"
        FirmwareExistedBefore = $binExisted
        FirmwareSha256 = $binHash
        CreatedKeys = $script:CreatedKeys.ToArray()
        Values = $script:Backup.ToArray()
    }
    try {
        $manifest | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $backupDir "manifest.json") -Encoding utf8
        Write-Log "备份清单已写入 manifest.json（$($script:Backup.Count) 个值，新建键 $($script:CreatedKeys.Count) 个）。"
    } catch {
        Write-Log "警告：写备份清单失败：$($_.Exception.Message)。仍继续卸载 hive。"
    }
    if ($loaded) { Unload-HiveWithRetry -HiveName $hiveName }
}

Write-Log "Phase15A 写入完成。"
Write-Log ("回滚命令: powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -WindowsDrive {1} -BackupDir `"{2}`"" -f `
    (Join-Path $PSScriptRoot "Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1"), $drive, $backupDir)