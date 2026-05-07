$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Rollback-WdacBasePolicy-Admin.ps1"
& $script @args
exit $LASTEXITCODE
