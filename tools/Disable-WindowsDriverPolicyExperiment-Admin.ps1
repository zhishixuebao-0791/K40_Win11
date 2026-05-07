$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Disable-WindowsDriverPolicyExperiment-Admin.ps1"
& $script @args
exit $LASTEXITCODE
