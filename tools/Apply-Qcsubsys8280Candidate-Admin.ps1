param(
    [string]$WindowsDrive = "D",
    [string]$CandidateDir,
    [switch]$AllowHostSystemDrive
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Apply-Qcsubsys8280Candidate-Admin.ps1"
& $script -WindowsDrive $WindowsDrive -CandidateDir $CandidateDir -AllowHostSystemDrive:$AllowHostSystemDrive
