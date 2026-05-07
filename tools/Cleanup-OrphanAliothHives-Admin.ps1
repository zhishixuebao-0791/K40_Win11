param(
    [switch]$WhatIfOnly
)

$script = Join-Path (Split-Path -Parent $PSScriptRoot) "Alioth-Engineering\tools\Cleanup-OrphanAliothHives-Admin.ps1"
& $script -WhatIfOnly:$WhatIfOnly
