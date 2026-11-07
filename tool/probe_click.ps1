param([int]$X, [int]$Y, [string]$Button = "left", [int]$Count = 1)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class M {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
[M]::SetProcessDPIAware() | Out-Null
[M]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 80
if ($Button -eq "move") {
  Start-Sleep -Milliseconds 250
  Write-Output "moved $X,$Y"
  exit
}
if ($Button -eq "right") {
  [M]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
  [M]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
} else {
  for ($i = 0; $i -lt $Count; $i++) {
    [M]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    [M]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 70
  }
}
Start-Sleep -Milliseconds 250
Write-Output "clicked $X,$Y $Button x$Count"
