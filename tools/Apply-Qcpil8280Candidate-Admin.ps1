param(
    [string]$WindowsDrive = "D",
    [string]$CandidateRoot,
    [switch]$IncludeSubsystemExtensions,
    [switch]$AllowHostSystemDrive
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Apply-Qcpil8280Candidate-Admin.ps1"
& $script -WindowsDrive $WindowsDrive -CandidateRoot $CandidateRoot -IncludeSubsystemExtensions:$IncludeSubsystemExtensions -AllowHostSystemDrive:$AllowHostSystemDrive
