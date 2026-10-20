# Draws the 1280x640 social preview / banner for the GitHub repo from the app icon and a
# demo screenshot: .github/assets/social-preview.png
#   node scripts/make-icon.mjs --preview <dir>   (makes the icon PNG first)
#   .\scripts\make-banner.ps1
param(
    [string] $Icon = "$PSScriptRoot\..\.github\assets\icon.png",
    [string] $Screen = "$PSScriptRoot\..\web\assets\overview.png",
    [string] $Out = "$PSScriptRoot\..\.github\assets\social-preview.png"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function C([string] $hex, [int] $a = 255) {
    [System.Drawing.Color]::FromArgb($a, [Convert]::ToInt32($hex.Substring(1, 2), 16), [Convert]::ToInt32($hex.Substring(3, 2), 16), [Convert]::ToInt32($hex.Substring(5, 2), 16))
}
function RoundRect([float] $x, [float] $y, [float] $w, [float] $h, [float] $r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90)
    $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90)
    $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure()
    $p
}
$dot = [char]0x00B7   # middle dot, kept out of the source so the script stays ASCII

$W = 1280; $H = 640
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.InterpolationMode = 'HighQualityBicubic'
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear((C '#0B0A10'))

# Accent glow behind the screenshot.
$glow = New-Object System.Drawing.Drawing2D.GraphicsPath
$glow.AddEllipse(560, -260, 980, 900)
$pg = New-Object System.Drawing.Drawing2D.PathGradientBrush $glow
$pg.CenterColor = (C '#FF3B4E' 70)
$pg.SurroundColors = @((C '#0B0A10' 0))
$g.FillPath($pg, $glow)

# Screenshot, cropped by the right edge, in a rounded frame.
$shot = [System.Drawing.Image]::FromFile((Resolve-Path $Screen))
$sw = 760; $sh = [int]($shot.Height * $sw / $shot.Width)
$sx = 600; $sy = 112
$frame = RoundRect $sx $sy $sw $sh 18
$g.SetClip($frame)
$g.DrawImage([System.Drawing.Image] $shot, (New-Object System.Drawing.Rectangle $sx, $sy, $sw, $sh))
$g.ResetClip()
$g.DrawPath((New-Object System.Drawing.Pen (C '#2E2A3B'), 2), $frame)
$shot.Dispose()

# Fade the screenshot's lower edge into the background.
$fade = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Rectangle 0, 470, $W, 170), (C '#0B0A10' 0), (C '#0B0A10' 255), 90
$g.FillRectangle($fade, 0, 470, $W, 171)

# Icon and words.
$iconImage = [System.Drawing.Image]::FromFile((Resolve-Path $Icon))
$g.DrawImage([System.Drawing.Image] $iconImage, (New-Object System.Drawing.Rectangle 80, 128, 112, 112))
$iconImage.Dispose()

$x = 80
$wordmark = New-Object System.Drawing.Font 'Segoe UI', 54, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$bone = New-Object System.Drawing.SolidBrush (C '#EDEAF4')
foreach ($ch in 'FIEND'.ToCharArray()) {
    $g.DrawString([string] $ch, $wordmark, $bone, $x - 6, 262)
    $x += $g.MeasureString([string] $ch, $wordmark, 200, [System.Drawing.StringFormat]::GenericTypographic).Width + 16
}

$tag = New-Object System.Drawing.Font 'Segoe UI Semibold', 34, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString("It hunts what`nhides on your PC.", $tag, $bone, 74, 344)

$small = New-Object System.Drawing.Font 'Segoe UI', 20, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
$g.DrawString("Cleaner $dot Disk $dot Shield for Windows 10 & 11", $small, (New-Object System.Drawing.SolidBrush (C '#9690A8')), 78, 452)
$g.DrawString("Rust engine $dot Flutter interface", $small, (New-Object System.Drawing.SolidBrush (C '#5F5A70')), 78, 560)

$accentBar = New-Object System.Drawing.SolidBrush (C '#FF3B4E')
$g.FillPath($accentBar, (RoundRect 80 512 56 6 3))

$g.Dispose()
New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
"Saved $Out"
