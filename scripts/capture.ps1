# Launches Fiend and saves a PNG of its window only (PrintWindow, so nothing else on screen is captured).
#   .\scripts\capture.ps1 -Out shot.png -AppArgs "--demo --section=shield"
param(
    [Parameter(Mandatory)] [string] $Out,
    [string] $AppArgs = "",
    [string] $Exe = "$PSScriptRoot\..\app\build\windows\x64\runner\Release\Fiend.exe",
    [int] $WaitSeconds = 6,
    [switch] $Keep
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class FiendWin {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
Add-Type -AssemblyName System.Drawing
[FiendWin]::SetProcessDPIAware() | Out-Null

$start = @{ FilePath = (Resolve-Path $Exe).Path; PassThru = $true }
if ($AppArgs) { $start.ArgumentList = $AppArgs }
$p = Start-Process @start
for ($i = 0; $i -lt 50 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
if ($p.MainWindowHandle -eq 0) { throw "Fiend's window didn't appear" }
Start-Sleep -Seconds $WaitSeconds

$h = $p.MainWindowHandle
$r = New-Object FiendWin+RECT
[FiendWin]::GetWindowRect($h, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[FiendWin]::PrintWindow($h, $hdc, 2) | Out-Null   # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
if (-not $Keep) { $p.Kill() }
"Saved $Out ($($r.Right - $r.Left)x$($r.Bottom - $r.Top))"
