$ErrorActionPreference = 'Stop'

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

Add-Type -TypeDefinition $src

$sb = New-Object System.Text.StringBuilder 4096
$ret = [Win32.DosDevice]::QueryDosDevice('S:', $sb, $sb.Capacity)
if ($ret -eq 0) {
    throw ('QueryDosDevice failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
}

$target = $sb.ToString().Split([char]0)[0]
Write-Output ('S: -> ' + $target)

$DDD_REMOVE_DEFINITION = 0x00000002
$DDD_EXACT_MATCH_ON_REMOVE = 0x00000004
$DDD_NO_BROADCAST_SYSTEM = 0x00000008

$ok = [Win32.DosDevice]::DefineDosDevice(
    $DDD_REMOVE_DEFINITION -bor $DDD_EXACT_MATCH_ON_REMOVE -bor $DDD_NO_BROADCAST_SYSTEM,
    'S:',
    $target
)

if (-not $ok) {
    throw ('DefineDosDevice remove failed: ' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
}

Write-Output 'Removed orphaned S: mapping.'
