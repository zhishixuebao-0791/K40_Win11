$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Backup-WdacBasePolicy-Admin.ps1"
& $script @args
exit $LASTEXITCODE
