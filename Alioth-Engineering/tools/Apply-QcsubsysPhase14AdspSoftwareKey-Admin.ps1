param(
    [Parameter(Mandatory = $true)][string]$WindowsDrive,
    [string]$FirmwarePath = "",
    [switch]$AllowHostSystemDrive
)

# Phase14 步骤C：按 surfacepro_ext_adsp8280.inf 的 8280 形态，离线补齐 ADSP(QCOM061B) 缺失的运行参数。
#   1. 复制 alioth 自签名 ADSP 固件到手机 \Windows\System32\Drivers\Alioth\ADSP\qcadsp_alioth.mbn
#   2. 驱动软件键 Control\Class\<ADSP Driver>\ADSP：ImagePath/RPEC/Interfaces/MANU/...（INF 的 .NT AddReg）
#   3. ADSP 硬件键 Device Parameters：PDInfo(8280 的 ServiceName 形态，仅 audio_pd)、Mappings（INF 的 .NT.HW AddReg）
#   4. PILC(QCOM06E0) 硬件键 SubsystemLoad\ADSP：MemoryAlignment/MemoryReservation（INF 的 PIL_Device_Ext）
#   5. 清理 Phase13 写入的 Enum 残留（0\ADSP、Device Parameters\0\ADSP、PDInfo\0\GUID 由本脚本覆盖）
# 第一轮刻意不写：Desktop 子设备、FastRPC so 映射、WaitForVolStartupAppComplete、Resources\BinaryPath(RADS.bin)。
# 所有改动逐值备份，回滚用 Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1。

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
if (-not $FirmwarePath) {
    $FirmwarePath = Join-Path $projectRoot "Alioth-Engineering\components\Devices\Alioth\firmware-squashed\qcadsp_alioth.mbn"
}
if (-not (Test-Path -LiteralPath $FirmwarePath)) { throw "找不到 ADSP 固件: $FirmwarePath" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $projectRoot ("Alioth-Engineering\backups\qcsubsys-phase14-adsp-softwarekey-pre-apply-{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
$script:LogPath = Join-Path $projectRoot ("Alioth-Engineering\logs\apply-qcsubsys-phase14-adsp-softwarekey-{0}.log" -f $stamp)
$script:Backup = New-Object System.Collections.Generic.List[object]
$script:CreatedKeys = New-Object System.Collections.Generic.List[string]

Write-Log "Phase14 步骤C：ADSP 8280 软件键/硬件键/PIL 内存预留 离线写入开始。"
Write-Log "备份目录: $backupDir"

$drive = $WindowsDrive.TrimEnd(':', '\')
if ((-not $AllowHostSystemDrive) -and ($drive -ieq $env:SystemDrive.TrimEnd(':', '\'))) {
    throw "拒绝操作本机系统盘 ${drive}:。"
}
$systemHive = "${drive}:\Windows\System32\Config\SYSTEM"
if (-not (Test-Path -LiteralPath $systemHive)) { throw "找不到离线 SYSTEM hive: $systemHive（请确认手机 WIN 分区盘符）" }

# ---------- 1. 固件 ----------
$fwHash = (Get-FileHash -LiteralPath $FirmwarePath -Algorithm SHA256).Hash
Write-Log "固件: $FirmwarePath  SHA256=$fwHash"
$fwDirOnPhone = "${drive}:\Windows\System32\Drivers\Alioth\ADSP"
$fwOnPhone = Join-Path $fwDirOnPhone "qcadsp_alioth.mbn"
$fwExisted = Test-Path -LiteralPath $fwOnPhone
New-Item -ItemType Directory -Force -Path $fwDirOnPhone | Out-Null
Copy-Item -LiteralPath $FirmwarePath -Destination $fwOnPhone -Force
if ((Get-FileHash -LiteralPath $fwOnPhone -Algorithm SHA256).Hash -ne $fwHash) { throw "复制到手机后的固件哈希不一致。" }
Write-Log "固件已复制并校验: $fwOnPhone"
$imagePathOnPhone = "C:\Windows\System32\Drivers\Alioth\ADSP\qcadsp_alioth.mbn"

# ---------- 2~5. 注册表 ----------
$hiveName = "ALIOTH_PHASE14_APPLY_$PID"
$loaded = $false
try {
    Invoke-Reg -Arguments @("load", "HKLM\$hiveName", $systemHive)
    $loaded = $true

    $sel = Get-HklmSubKey -Path "$hiveName\Select"
    try { $current = [int]$sel.GetValue("Current") } finally { $sel.Dispose() }
    $cs = "$hiveName\ControlSet{0:D3}" -f $current
    Write-Log ("离线当前 ControlSet: ControlSet{0:D3}" -f $current)

    $adspInst = "$cs\Enum\ACPI\QCOM061B\2&daba3ff&0"
    $pilInst = "$cs\Enum\ACPI\QCOM06E0\2&daba3ff&0"
    $k = Get-HklmSubKey -Path $adspInst
    if (-not $k) { throw "找不到 ADSP 设备实例键: $adspInst" }
    try { $adspDriver = [string]$k.GetValue("Driver") } finally { $k.Dispose() }
    if (-not $adspDriver) { throw "ADSP 实例没有 Driver 值（未绑定驱动）。" }
    $k = Get-HklmSubKey -Path $pilInst
    if (-not $k) { throw "找不到 PILC 设备实例键: $pilInst" }
    $k.Dispose()
    $adspSw = "$cs\Control\Class\$adspDriver"
    Write-Log "ADSP 驱动软件键: Control\Class\$adspDriver"

    $pilTz = "{E2EB84C1-4068-4994-A48F-F3AC0D38DC29}"
    $fastRpc = "{E022FF1A-C06C-42D8-94FE-90D876FC0B75}"
    $glink = "{F9D15453-8335-434c-AA72-FCD925F135F3}"
    $adspGlink = "{99CA9C16-4E1E-4970-B49E-2CA56753588B}"
    $audioPd = "{0A35A787-A69F-4A90-8B78-0710BA7BB82C}"

    # 2. 软件键 [SUBSYSReg]（.NT）
    Set-Value "$adspSw\ADSP" "ImagePath" $imagePathOnPhone String
    Set-Value "$adspSw\ADSP" "RPEC" ([string[]]@($adspGlink)) MultiString
    Set-Value "$adspSw\ADSP" "Interfaces" ([string[]]@($pilTz, $fastRpc, $glink)) MultiString
    Set-Value "$adspSw\ADSP" "MANU" 0x06be0baf DWord
    Set-Value "$adspSw\ADSP" "IgnoreWdogEnabled" 1 DWord
    Set-Value "$adspSw\ADSP" "SubsysUefiLoadedImageAction" 2 DWord
    Set-Value "$adspSw\ADSP" "UefiLoadedImageTZProcID" 0x1F DWord
    Set-Value "$adspSw\ADSP" "UefiLoadedSubsysDetectionStatus" 0 DWord
    Set-Value "$adspSw\ADSP" "SpuAriFuseWorkAroundEnabled" 1 DWord

    # 3. 硬件键 [ADSP_PDInfo] / [SUBSYSReg_common]（.NT.HW）
    $adspHw = "$adspInst\Device Parameters"
    Set-Value "$adspHw\PDInfo" "NumPDs" 1 DWord
    Set-Value "$adspHw\PDInfo\0" "ServiceName" "msm/adsp/audio_pd" String
    Set-Value "$adspHw\PDInfo\0" "GUID" $audioPd String
    Set-Value "$adspHw\PDInfo\0" "FileNameWildCard" "pd_dump*audio*.elf" String
    Set-Value "$adspHw\PDInfo\0" "RootDirectory" "\DriverData\QUALCOMM\TFTP\rfs\msm\adsp\ramdumps\" String
    Set-Value "$adspHw\PDInfo\0" "CountFile" "pd_dump_audio_process.count" String
    Set-Value "$adspHw\Mappings" "PathMappingKeyName" "Default" String

    # 4. PILC [PIL_Reg_common]/[PIL_Reg_MSM]（.NT.HW）；实例级 SubsystemLoad 与现有 GFXSUC/VENUS 一致也写一份
    foreach ($base in @("$pilInst\Device Parameters\SubsystemLoad\ADSP", "$pilInst\SubsystemLoad\ADSP")) {
        Set-Value $base "MemoryAlignment" 0x00100000 DWord
        Set-Value $base "MemoryReservation" 0x02000000 DWord
    }

    # 5. Phase13 残留
    Remove-Value "$adspHw\0\ADSP" "Interfaces"
    Remove-Value "$adspHw\0\ADSP" "RPEC"
    Remove-Value "$adspInst\0\ADSP" "Interfaces"
    Remove-Value "$adspInst\0\ADSP" "RPEC"
    Remove-Value "$adspHw\PDInfo\0" "PDName"
} finally {
    Remove-Variable -Name k, sel -ErrorAction SilentlyContinue
    $manifest = [pscustomobject]@{
        CreatedAt = (Get-Date).ToString("s")
        WindowsDrive = $drive
        HiveNamePrefix = $hiveName
        FirmwareOnPhone = "\Windows\System32\Drivers\Alioth\ADSP\qcadsp_alioth.mbn"
        FirmwareExistedBefore = $fwExisted
        FirmwareSha256 = $fwHash
        # PS 5.1 对含 pscustomobject 的 List[object] 执行 @() 会抛 “参数类型不匹配”，必须用 ToArray()
        CreatedKeys = $script:CreatedKeys.ToArray()
        Values = $script:Backup.ToArray()
    }
    try {
        $manifest | ConvertTo-Json -Depth 6 | Out-File -FilePath (Join-Path $backupDir "manifest.json") -Encoding utf8
        Write-Log "备份清单已写入 manifest.json（$($script:Backup.Count) 个值，新建键 $($script:CreatedKeys.Count) 个）。"
    } catch {
        Write-Log "警告：写备份清单失败：$($_.Exception.Message)。仍继续卸载 hive。"
    }
    # 无论前面是否出错都必须卸载 hive，避免手机 SYSTEM hive 残留挂载
    if ($loaded) { Unload-HiveWithRetry -HiveName $hiveName }
}

Write-Log "Phase14 步骤C 写入完成。"
Write-Log ("回滚命令: powershell -NoProfile -ExecutionPolicy Bypass -File `"{0}`" -WindowsDrive {1} -BackupDir `"{2}`"" -f `
    (Join-Path $PSScriptRoot "Rollback-QcsubsysPhase14AdspSoftwareKey-Admin.ps1"), $drive, $backupDir)
