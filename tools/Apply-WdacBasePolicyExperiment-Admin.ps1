$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Apply-WdacBasePolicyExperiment-Admin.ps1"
& $script @args
exit $LASTEXITCODE
