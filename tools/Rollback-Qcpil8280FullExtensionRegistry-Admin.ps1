param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [switch]$AllowHostSystemDrive
)

$script = "C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Rollback-Qcpil8280FullExtensionRegistry-Admin.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Implementation script not found: $script"
}

& $script -WindowsDrive $WindowsDrive -BackupDir $BackupDir -AllowHostSystemDrive:$AllowHostSystemDrive
