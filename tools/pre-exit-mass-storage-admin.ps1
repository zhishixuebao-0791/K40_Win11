$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'pre-exit-mass-storage-admin.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
Write-Log 'Pre-exit Mass Storage cleanup started.'

foreach ($letter in 'R:','S:') {
    try {
        $out = cmd /c "mountvol $letter /D" 2>&1
        foreach ($line in $out) {
            Write-Log ("{0} {1}" -f $letter, $line)
        }
    } catch {
        Write-Log ("{0} cleanup exception: {1}" -f $letter, $_.Exception.Message)
    }
}

Write-Log 'Pre-exit Mass Storage cleanup completed.'
