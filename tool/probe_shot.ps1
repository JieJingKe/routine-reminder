param(
  [string]$Out = "build\_probe\screen.png",
  [int]$X = -1, [int]$Y = -1, [int]$W = 0, [int]$H = 0
)
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class C { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[C]::SetProcessDPIAware() | Out-Null
Add-Type -AssemblyName System.Windows.Forms
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
if ($W -le 0) { $W = $bounds.Width }
if ($H -le 0) { $H = $bounds.Height }
if ($X -lt 0) { $X = $bounds.X }
if ($Y -lt 0) { $Y = $bounds.Y }
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($X, $Y, 0, 0, $bmp.Size)
$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$bmp.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "$X,$Y ${W}x${H}"
