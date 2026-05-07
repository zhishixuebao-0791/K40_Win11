$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Rollback-WindowsDriverPolicyExperiment-Admin.ps1"
& $script @args
exit $LASTEXITCODE
