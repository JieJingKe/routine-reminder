param([int]$X1, [int]$Y1, [int]$X2, [int]$Y2)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class D {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
}
"@
[D]::SetProcessDPIAware() | Out-Null
[D]::SetCursorPos($X1, $Y1) | Out-Null
Start-Sleep -Milliseconds 120
[D]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
for ($i = 1; $i -le 30; $i++) {
  $x = [int]($X1 + ($X2 - $X1) * $i / 30)
  $y = [int]($Y1 + ($Y2 - $Y1) * $i / 30)
  [D]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 40
}
[D]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 200
Write-Output "dragged $X1,$Y1 -> $X2,$Y2"
