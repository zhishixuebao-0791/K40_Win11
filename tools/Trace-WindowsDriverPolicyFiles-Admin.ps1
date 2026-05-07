$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Trace-WindowsDriverPolicyFiles-Admin.ps1"
& $script @args
exit $LASTEXITCODE
