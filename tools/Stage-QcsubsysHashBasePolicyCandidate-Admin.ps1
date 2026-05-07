$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Stage-QcsubsysHashBasePolicyCandidate-Admin.ps1"
& $script @args
exit $LASTEXITCODE
