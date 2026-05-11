param(
    [string]$WindowsDrive = "D",
    [switch]$AllowHostSystemDrive
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Apply-Qcpil8280ExtensionRegistryExperiment-Admin.ps1"
& $script -WindowsDrive $WindowsDrive -AllowHostSystemDrive:$AllowHostSystemDrive
