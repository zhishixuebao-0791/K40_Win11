param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [switch]$AllowHostSystemDrive
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Rollback-Qcpil8280Candidate-Admin.ps1"
& $script -WindowsDrive $WindowsDrive -BackupDir $BackupDir -AllowHostSystemDrive:$AllowHostSystemDrive
