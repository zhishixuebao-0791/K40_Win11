$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Disable-DriversIpPolicyExperiment-Admin.ps1"
& $script @args
exit $LASTEXITCODE
