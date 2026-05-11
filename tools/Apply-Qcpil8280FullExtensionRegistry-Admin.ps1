param(
    [string]$WindowsDrive = "D",
    [switch]$AllowHostSystemDrive
)

$script = "C:\yjc_code\K40_Win11\Alioth-Engineering\tools\Apply-Qcpil8280FullExtensionRegistry-Admin.ps1"
if (-not (Test-Path -LiteralPath $script)) {
    throw "Implementation script not found: $script"
}

& $script -WindowsDrive $WindowsDrive -AllowHostSystemDrive:$AllowHostSystemDrive
