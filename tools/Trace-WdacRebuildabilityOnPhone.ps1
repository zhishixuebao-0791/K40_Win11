$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Trace-WdacRebuildabilityOnPhone.ps1"
& $script @args
exit $LASTEXITCODE
