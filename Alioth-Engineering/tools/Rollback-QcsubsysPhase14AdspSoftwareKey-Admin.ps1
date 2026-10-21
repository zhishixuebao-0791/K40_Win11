param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [Parameter(Mandatory = $true)][string]$BackupDir,
    [switch]$AllowHostSystemDrive
)

# 回滚 Apply-QcsubsysPhase14AdspSoftwareKey-Admin.ps1：按 manifest.json 逐值恢复，删除脚本新建的空键和复制的固件。

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "必须在管理员 PowerShell 窗口中运行本脚本。"
    }
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
    if (($script:RegExit -ne 0) -and (-not $IgnoreExitCode)) { throw "reg.exe 失败，退出码 $($script:RegExit)" }
}

function Unload-HiveWithRetry {
    param([string]$HiveName)
    for ($attempt = 1; $attempt -le 8; $attempt++) {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds (250 * $attempt)
        Invoke-Reg -Arguments @("unload", "HKLM\$HiveName") -IgnoreExitCode
        if ($script:RegExit -eq 0) { Write-Log "第 $attempt 次尝试成功卸载 HKLM\$HiveName。"; return }
    }
    throw "无法卸载 HKLM\$HiveName。卸载成功前不要断开手机。"
}

Assert-Administrator

$manifestPath = Join-Path $BackupDir "manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "找不到备份清单: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:LogPath = Join-Path $BackupDir ("rollback-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

$drive = $WindowsDrive.TrimEnd(':', '\')
if ((-not $AllowHostSystemDrive) -and ($drive -ieq $env:SystemDrive.TrimEnd(':', '\'))) { throw "拒绝操作本机系统盘 ${drive}:。" }
$systemHive = "${drive}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) { throw "找不到离线 SYSTEM hive: $systemHive" }

Write-Log "Phase14 步骤C 回滚开始，备份: $BackupDir"

# 备份记录的路径以原 hive 挂载名开头，回滚时换成新挂载名
$oldPrefix = $manifest.HiveNamePrefix
$hiveName = "ALIOTH_PHASE14_ROLLBACK_$PID"
$loaded = $false
try {
    Invoke-Reg -Arguments @("load", "HKLM\$hiveName", $systemHive)
    $loaded = $true
    $hklm = [Microsoft.Win32.Registry]::LocalMachine

    # 逆序恢复，保证同一个值多次记录时恢复到最早的状态
    $values = @($manifest.Values)
    [array]::Reverse($values)
    foreach ($v in $values) {
        $path = $v.Path -replace ('^' + [regex]::Escape($oldPrefix)), $hiveName
        $key = $hklm.OpenSubKey($path, $true)
        if (-not $key) { continue }
        try {
            if ($v.Existed) {
                $kind = [Microsoft.Win32.RegistryValueKind]$v.Kind
                $data = if ($kind -eq "MultiString") { [string[]]@($v.Value) } elseif ($kind -eq "DWord") { [int]$v.Value } else { $v.Value }
                $key.SetValue($v.Name, $data, $kind)
                Write-Log "恢复 $($v.Name) @ $($path.Substring($hiveName.Length))"
            } elseif ($key.GetValueNames() -contains $v.Name) {
                $key.DeleteValue($v.Name)
                Write-Log "删除 $($v.Name) @ $($path.Substring($hiveName.Length))"
            }
        } finally { $key.Dispose() }
    }

    # 删除脚本新建且已为空的键（深的先删）
    $created = @($manifest.CreatedKeys | ForEach-Object { $_ -replace ('^' + [regex]::Escape($oldPrefix)), $hiveName } | Sort-Object Length -Descending)
    foreach ($path in $created) {
        $key = $hklm.OpenSubKey($path)
        if (-not $key) { continue }
        $empty = ($key.ValueCount -eq 0) -and ($key.SubKeyCount -eq 0)
        $key.Dispose()
        if ($empty) {
            $parent = Split-Path -Parent $path
            $leaf = Split-Path -Leaf $path
            $pk = $hklm.OpenSubKey($parent, $true)
            try { $pk.DeleteSubKey($leaf) } finally { $pk.Dispose() }
            Write-Log "删除新建空键 $($path.Substring($hiveName.Length))"
        }
    }
} finally {
    Remove-Variable -Name key, pk, hklm -ErrorAction SilentlyContinue
    if ($loaded) { Unload-HiveWithRetry -HiveName $hiveName }
}

if ((-not $manifest.FirmwareExistedBefore) -and ([string]$manifest.FirmwareOnPhone) -match '^\\Windows\\.+\.\w+$') {
    $fw = "${drive}:$($manifest.FirmwareOnPhone)"
    if (Test-Path -LiteralPath $fw) {
        Remove-Item -LiteralPath $fw -Force
        Write-Log "已删除手机上的固件 $fw"
    }
}

Write-Log "Phase14 步骤C 回滚完成。"
