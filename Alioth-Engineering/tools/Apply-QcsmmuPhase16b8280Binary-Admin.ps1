param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [switch]$AllowHostSystemDrive
)

# Phase16b：让 SMMU(MMU1, ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1) 用 WHQL 签名的 qcsmmu8280.sys 运行，
# 但保留 qcsmmu8250.inf(oem9) 安装时已写入驱动软件键的 8250v2 硬件配置（ChipSetVersion/CTXI/S2CB/Resources\SMMU）。
#   背景：qcsmmu8250.sys/.cat 由 "Windows On Andromeda KMCI Codesigning" 签名，CI 3004 拒绝（Code 52）；
#         qcsmmu8280.cat 为 Microsoft WHQL 签名；两者 SMMC.bin 字节相同、配置结构相同，但 8280 INF 的流映射表是 SC8280XP 的，不能用。
#   步骤：1) dism /Add-Driver 离线注入 Surface qcsmmu8280 包（注册其 WHQL catalog）
#         2) 校验 MMU1 软件键已有 8250v2 配置，否则中止
#         3) 备份并把 Services\qcsmmu\ImagePath 指向 DriverStore 中的 qcsmmu8280.sys
# 回滚：Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1 -WindowsDrive <盘符> -BackupDir <本次备份目录>（恢复 ImagePath；DISM 注入的包保留在驱动库，不影响任何设备匹配）

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
$pkgDir = Join-Path $projectRoot "sound_code\driver_candidates\surfacepro9_5g_22621_25.070.2191.0\extracted\SurfaceUpdate\qcsmmu8280"
$pkgInf = Join-Path $pkgDir "qcsmmu8280.inf"
if (-not (Test-Path -LiteralPath $pkgInf)) { throw "找不到 Surface qcsmmu8280 驱动包: $pkgInf" }
$catSig = Get-AuthenticodeSignature -FilePath (Join-Path $pkgDir "qcsmmu8280.cat")
if ($catSig.Status -ne "Valid") { throw "qcsmmu8280.cat 签名无效: $($catSig.Status)" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $projectRoot ("Alioth-Engineering\backups\qcsmmu-phase16b-imagepath-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$script:LogPath = Join-Path $projectRoot ("Alioth-Engineering\logs\apply-qcsmmu-phase16b-8280-binary-{0}.log" -f $stamp)
$script:Backup = New-Object System.Collections.Generic.List[object]
$script:CreatedKeys = New-Object System.Collections.Generic.List[string]

Write-Log "Phase16b：qcsmmu 使用 WHQL 签名的 8280 驱动程序 + 保留 8250v2 硬件配置。"
Write-Log "备份目录: $backupDir"
Write-Log "qcsmmu8280.cat 签名者: $($catSig.SignerCertificate.Subject)"

$drive = $WindowsDrive.TrimEnd(':', '\')
if ((-not $AllowHostSystemDrive) -and ($drive -ieq $env:SystemDrive.TrimEnd(':', '\'))) { throw "拒绝操作本机系统盘 ${drive}:。" }
$root = "${drive}:\"
$systemHive = "${drive}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) { throw "找不到离线 SYSTEM hive: $systemHive（请确认手机 WIN 分区盘符）" }
$repo = "${drive}:\Windows\System32\DriverStore\FileRepository"

# ---------- 1. 先只读校验注册表，确认 8250v2 配置在位 ----------
$hiveName = "ALIOTH_PHASE16B_APPLY_$PID"
$loaded = $false
$mmuDriver = $null
try {
    Invoke-Reg -Arguments @("load", "HKLM\$hiveName", $systemHive)
    $loaded = $true
    $sel = Get-HklmSubKey -Path "$hiveName\Select"
    try { $current = [int]$sel.GetValue("Current") } finally { $sel.Dispose() }
    $cs = "$hiveName\ControlSet{0:D3}" -f $current
    Write-Log ("离线当前 ControlSet: ControlSet{0:D3}" -f $current)

    $mmuInst = "$cs\Enum\ACPI\VEN_QCOM&DEV_2509&SUBSYS_MTP08250&REV_0002\1"
    $k = Get-HklmSubKey -Path $mmuInst
    if (-not $k) { throw "找不到 MMU1 设备实例键: $mmuInst（Phase16 UEFI 是否已刷入？）" }
    try {
        $mmuDriver = [string]$k.GetValue("Driver")
        $mmuService = [string]$k.GetValue("Service")
        $mmuFlags = $k.GetValue("ConfigFlags")
    } finally { $k.Dispose() }
    Write-Log "MMU1: Service=$mmuService Driver=$mmuDriver ConfigFlags=$mmuFlags"
    if ($mmuService -ne "qcsmmu" -or -not $mmuDriver) { throw "MMU1 尚未绑定 qcsmmu 服务，无法沿用 8250v2 配置。" }

    $cls = "$cs\Control\Class\$mmuDriver"
    $k = Get-HklmSubKey -Path $cls
    if (-not $k) { throw "找不到 MMU1 驱动软件键: $cls" }
    try {
        $infPath = [string]$k.GetValue("InfPath"); $infSection = [string]$k.GetValue("InfSection"); $chip = $k.GetValue("ChipSetVersion")
    } finally { $k.Dispose() }
    $res = Get-HklmSubKey -Path "$cls\Resources"
    $smmcPath = $null
    if ($res) { try { $smmcPath = [string]$res.GetValue("SMMU") } finally { $res.Dispose() } }
    $s2cb0 = Get-HklmSubKey -Path "$cls\0\S2CB"
    $s2cbCount = 0
    if ($s2cb0) { try { $s2cbCount = $s2cb0.SubKeyCount } finally { $s2cb0.Dispose() } }
    $ctxi = Get-HklmSubKey -Path "$cls\0\CTXI"
    $hasCtxi = $null -ne $ctxi
    if ($ctxi) { $ctxi.Dispose() }
    Write-Log "MMU1 软件键: InfPath=$infPath InfSection=$infSection ChipSetVersion=$chip CTXI=$hasCtxi 0\S2CB 一级子键=$s2cbCount Resources\SMMU=$smmcPath"
    if ($infSection -notmatch '8250v2' -or $chip -ne 2 -or -not $hasCtxi -or $s2cbCount -lt 1 -or -not $smmcPath) {
        throw "MMU1 软件键中的 8250v2 配置不完整，中止（未做任何修改）。"
    }
    $svc = Get-HklmSubKey -Path "$cs\Services\qcsmmu"
    try { $oldImage = [string]$svc.GetValue("ImagePath", $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $oldKind = $svc.GetValueKind("ImagePath") } finally { $svc.Dispose() }
    Write-Log "当前 Services\qcsmmu\ImagePath ($oldKind) = $oldImage"
} finally {
    Remove-Variable -Name k, sel, res, s2cb0, ctxi, svc -ErrorAction SilentlyContinue
    if ($loaded) { Unload-HiveWithRetry -HiveName $hiveName; $loaded = $false }
}

$smmcOnPhone = $smmcPath -replace '^(?i)C:', "${drive}:"
$smmcOnPhone = $smmcOnPhone -replace '^(?i)\\SystemRoot', "${drive}:\Windows"
if (-not (Test-Path -LiteralPath $smmcOnPhone)) { throw "Resources\SMMU 指向的 SMMC.bin 在手机上不存在: $smmcOnPhone" }
Write-Log "SMMC.bin 存在: $smmcOnPhone"

# ---------- 2. DISM 离线注入 qcsmmu8280 包 ----------
$existing = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "qcsmmu8280.inf_arm64_*" -ErrorAction SilentlyContinue)
if ($existing.Count -eq 0) {
    Write-Log "执行: dism.exe /Image:$root /Add-Driver /Driver:$pkgInf"
    $out = & dism.exe "/Image:$root" "/Add-Driver" "/Driver:$pkgInf" 2>&1
    $code = $LASTEXITCODE
    Add-Content -LiteralPath $script:LogPath -Value ($out | ForEach-Object { "$_" }) -Encoding UTF8
    if ($code -ne 0) { throw "DISM 注入 qcsmmu8280 失败，退出码 $code（详见日志）" }
    $existing = @(Get-ChildItem -LiteralPath $repo -Directory -Filter "qcsmmu8280.inf_arm64_*")
} else {
    Write-Log "驱动库中已存在 qcsmmu8280 包，跳过 DISM 注入。"
}
if ($existing.Count -ne 1) { throw "驱动库中 qcsmmu8280 包目录数量为 $($existing.Count)，需人工确认。" }
$sys = Join-Path $existing[0].FullName "qcsmmu8280.sys"
if (-not (Test-Path -LiteralPath $sys)) { throw "找不到 $sys" }
$srcHash = (Get-FileHash -LiteralPath (Join-Path $pkgDir "qcsmmu8280.sys")).Hash
if ((Get-FileHash -LiteralPath $sys).Hash -ne $srcHash) { throw "驱动库中的 qcsmmu8280.sys 与源包哈希不一致。" }
$newImage = "\SystemRoot\System32\DriverStore\FileRepository\$($existing[0].Name)\qcsmmu8280.sys"
Write-Log "目标 ImagePath = $newImage"

# ---------- 3. 修改 ImagePath ----------
try {
    Invoke-Reg -Arguments @("load", "HKLM\$hiveName", $systemHive)
    $loaded = $true
    Set-Value "$cs\Services\qcsmmu" "ImagePath" $newImage $oldKind
} finally {
    $manifest = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString("s")
        WindowsDrive = $drive
        HiveNamePrefix = $hiveName
        FirmwareOnPhone = ""
        FirmwareExistedBefore = $true
        FirmwareSha256 = ""
        Note = "Phase16b 只改 Services\qcsmmu\ImagePath；DISM 注入的 qcsmmu8280 包不随回滚删除"
        CreatedKeys = $script:CreatedKeys.ToArray()
        Values = $script:Backup.ToArray()
    }
    try {
        $manifest | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $backupDir "manifest.json") -Encoding utf8
        Write-Log "备份清单已写入 manifest.json（$($script:Backup.Count) 个值）。"
    } catch {
        Write-Log "警告：写备份清单失败：$($_.Exception.Message)。仍继续卸载 hive。"
    }
    if ($loaded) { Unload-HiveWithRetry -HiveName $hiveName }
}

Write-Log "Phase16b 写入完成。"
Write-Log ("回滚命令: powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -WindowsDrive {1} -BackupDir `"{2}`"" -f `
    (Join-Path $PSScriptRoot "Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1"), $drive, $backupDir)