$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $scriptRoot
$log = Join-Path $root 'cleanup-orphan-driveletters-admin.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    Write-Output $line
}

$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace Win32 {
  public static class DosDevice {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint QueryDosDevice(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool DefineDosDevice(uint flags, string lpDeviceName, string lpTargetPath);
  }
}
"@

Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
Add-Type -TypeDefinition $src

$DDD_REMOVE_DEFINITION = 0x00000002
$DDD_EXACT_MATCH_ON_REMOVE = 0x00000004
$DDD_NO_BROADCAST_SYSTEM = 0x00000008

foreach ($letter in 'R:','S:') {
    $sb = New-Object System.Text.StringBuilder 4096
    $ret = [Win32.DosDevice]::QueryDosDevice($letter, $sb, $sb.Capacity)
    if ($ret -eq 0) {
        Write-Log ("{0} not present. Win32={1}" -f $letter, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        continue
    }

    $target = $sb.ToString().Split([char]0)[0]
    Write-Log ("{0} -> {1}" -f $letter, $target)

    $ok = [Win32.DosDevice]::DefineDosDevice(
        $DDD_REMOVE_DEFINITION -bor $DDD_EXACT_MATCH_ON_REMOVE -bor $DDD_NO_BROADCAST_SYSTEM,
        $letter,
        $target
    )

    if ($ok) {
        Write-Log ("Removed orphan mapping {0}" -f $letter)
    } else {
        Write-Log ("Failed to remove {0}. Win32={1}" -f $letter, [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}
