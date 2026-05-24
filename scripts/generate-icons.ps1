# Generiert die für Tauri/Windows benötigten Icons unter src-tauri/icons/.
# Erzeugt ein lila Hexagon mit "R" — passend zum App-Logo.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts/generate-icons.ps1

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$iconDir = Join-Path $root "src-tauri\icons"
New-Item -ItemType Directory -Force -Path $iconDir | Out-Null

function New-LogoBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    # Transparenter Hintergrund
    $g.Clear([System.Drawing.Color]::Transparent)

    $center = $size / 2.0
    $radius = $size * 0.42

    # Hexagon-Punkte (vertikale Ausrichtung)
    $points = New-Object System.Drawing.PointF[] 6
    for ($i = 0; $i -lt 6; $i++) {
        $angle = ([Math]::PI / 3.0) * $i - ([Math]::PI / 2.0)
        $points[$i] = New-Object System.Drawing.PointF(
            ($center + $radius * [Math]::Cos($angle)),
            ($center + $radius * [Math]::Sin($angle))
        )
    }

    # Hex-Füllung: dunkler Lila-Gradient
    $bgRect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $bgRect,
        [System.Drawing.Color]::FromArgb(240, 30, 16, 56),
        [System.Drawing.Color]::FromArgb(240, 60, 22, 92),
        45.0
    )
    $g.FillPolygon($bgBrush, $points)
    $bgBrush.Dispose()

    # Hex-Rand: lila → magenta Gradient
    $rimBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $bgRect,
        [System.Drawing.Color]::FromArgb(255, 192, 132, 252),
        [System.Drawing.Color]::FromArgb(255, 124, 58, 237),
        45.0
    )
    $rimPen = New-Object System.Drawing.Pen($rimBrush, [single]([Math]::Max(2, $size * 0.04)))
    $rimPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPolygon($rimPen, $points)
    $rimPen.Dispose()
    $rimBrush.Dispose()

    # "R" zentriert (so groß wie möglich)
    $fontSize = [single]($size * 0.55)
    $fontFamily = $null
    foreach ($candidate in @("Inter", "Segoe UI", "Arial")) {
        try {
            $fontFamily = New-Object System.Drawing.FontFamily($candidate)
            break
        } catch {}
    }
    if (-not $fontFamily) { $fontFamily = New-Object System.Drawing.FontFamily([System.Drawing.Text.GenericFontFamilies]::SansSerif) }
    $font = New-Object System.Drawing.Font($fontFamily, $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center

    $textBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $bgRect,
        [System.Drawing.Color]::FromArgb(255, 233, 213, 255),
        [System.Drawing.Color]::FromArgb(255, 168, 85, 247),
        90.0
    )
    # Leichtes Nudging um optisches Zentrum
    $textRect = New-Object System.Drawing.RectangleF(0, ($size * -0.04), $size, $size)
    $g.DrawString("R", $font, $textBrush, $textRect, $fmt)

    $textBrush.Dispose()
    $font.Dispose()
    $fontFamily.Dispose()
    $g.Dispose()
    return $bmp
}

function Save-Png($bmp, $path) {
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "  $path" -ForegroundColor DarkGray
}

# ICO-Schreiber: PNG-eingebettete Multi-Resolution-ICO (Vista+ kompatibel)
function Save-Ico([int[]]$sizes, [string]$outPath) {
    $tempPngs = @()
    foreach ($s in $sizes) {
        $bmp = New-LogoBitmap $s
        $tmp = [System.IO.Path]::Combine($env:TEMP, "revideo-icon-$s.png")
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $tempPngs += $tmp
    }

    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    # ICONDIR header
    $bw.Write([UInt16]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]$sizes.Count)

    $pngBlobs = @()
    foreach ($p in $tempPngs) {
        $pngBlobs += ,([System.IO.File]::ReadAllBytes($p))
    }

    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $w = $sizes[$i]; $h = $sizes[$i]
        $size = $pngBlobs[$i].Length
        $bw.Write([byte]($(if ($w -ge 256) { 0 } else { $w })))
        $bw.Write([byte]($(if ($h -ge 256) { 0 } else { $h })))
        $bw.Write([byte]0)        # palette
        $bw.Write([byte]0)        # reserved
        $bw.Write([UInt16]1)      # planes
        $bw.Write([UInt16]32)     # bpp
        $bw.Write([UInt32]$size)  # image size
        $bw.Write([UInt32]$offset)
        $offset += $size
    }

    foreach ($blob in $pngBlobs) { $bw.Write($blob) }

    [System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
    $bw.Close()
    foreach ($p in $tempPngs) { Remove-Item -Force -ErrorAction SilentlyContinue $p }
    Write-Host "  $outPath" -ForegroundColor DarkGray
}

Write-Host "Generating icons..." -ForegroundColor Cyan

# PNG-Größen, die Tauri direkt referenziert
$b32  = New-LogoBitmap 32
Save-Png $b32  (Join-Path $iconDir "32x32.png");           $b32.Dispose()
$b128 = New-LogoBitmap 128
Save-Png $b128 (Join-Path $iconDir "128x128.png");         $b128.Dispose()
$b256 = New-LogoBitmap 256
Save-Png $b256 (Join-Path $iconDir "128x128@2x.png");      $b256.Dispose()

# Multi-Resolution ICO
Save-Ico @(16, 32, 48, 64, 128, 256) (Join-Path $iconDir "icon.ico")

Write-Host "Done." -ForegroundColor Green
