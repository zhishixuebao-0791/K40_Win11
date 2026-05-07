param(
    [string]$WindowsDrive = "D",
    [Parameter(Mandatory = $true)]
    [string]$BackupDir,
    [switch]$RemoveDriverPackage,
    [switch]$AllowHostSystemDrive
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Rollback-Qcsubsys8280Candidate-Admin.ps1"
& $script -WindowsDrive $WindowsDrive -BackupDir $BackupDir -RemoveDriverPackage:$RemoveDriverPackage -AllowHostSystemDrive:$AllowHostSystemDrive
