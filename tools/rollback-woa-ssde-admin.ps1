param(
    [string]$WindowsDrive = "D",
    [switch]$SkipDismRemove,
    [switch]$AllowHostSystemDrive
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$inner = Join-Path $repoRoot "Alioth-Engineering\tools\rollback-woa-ssde-admin.ps1"

if (-not (Test-Path -LiteralPath $inner)) {
    throw "Inner rollback script not found: $inner"
}

& $inner -WindowsDrive $WindowsDrive -SkipDismRemove:$SkipDismRemove -AllowHostSystemDrive:$AllowHostSystemDrive
