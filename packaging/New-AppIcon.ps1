param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\src\app.ico'),
    [string]$PreviewPath = (Join-Path $PSScriptRoot '..\src\app-icon-preview.png')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$bitmap = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

$path = [System.Drawing.Drawing2D.GraphicsPath]::new()
$radius = 44
$path.AddArc(22, 22, $radius, $radius, 180, 90)
$path.AddArc(190, 22, $radius, $radius, 270, 90)
$path.AddArc(190, 190, $radius, $radius, 0, 90)
$path.AddArc(22, 190, $radius, $radius, 90, 90)
$path.CloseFigure()

$background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.Point]::new(30, 24), [System.Drawing.Point]::new(220, 232),
    [System.Drawing.Color]::FromArgb(255, 34, 107, 224), [System.Drawing.Color]::FromArgb(255, 18, 59, 112))
$graphics.FillPath($background, $path)

$innerPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(75, 255, 255, 255), 5)
$graphics.DrawLine($innerPen, 44, 183, 194, 183)
$graphics.FillEllipse([System.Drawing.Brushes]::White, 53, 198, 14, 14)
$graphics.FillEllipse([System.Drawing.Brushes]::White, 77, 198, 14, 14)

$font = [System.Drawing.Font]::new('Segoe UI', 102, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$textFormat = [System.Drawing.StringFormat]::new()
$textFormat.Alignment = [System.Drawing.StringAlignment]::Center
$textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
$graphics.DrawString('C', $font, [System.Drawing.Brushes]::White, [System.Drawing.RectangleF]::new(20, 30, 196, 145), $textFormat)

$sparkle = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 83, 232, 210))
$sparklePoints = @(
    [System.Drawing.PointF]::new(202, 20), [System.Drawing.PointF]::new(211, 46),
    [System.Drawing.PointF]::new(237, 55), [System.Drawing.PointF]::new(211, 64),
    [System.Drawing.PointF]::new(202, 90), [System.Drawing.PointF]::new(193, 64),
    [System.Drawing.PointF]::new(167, 55), [System.Drawing.PointF]::new(193, 46)
)
$graphics.FillPolygon($sparkle, $sparklePoints)

$pngStream = [System.IO.MemoryStream]::new()
$bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Save([System.IO.Path]::GetFullPath($PreviewPath), [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $pngStream.ToArray()

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$parent = [System.IO.Path]::GetDirectoryName($resolvedOutput)
[System.IO.Directory]::CreateDirectory($parent) | Out-Null
$fileStream = [System.IO.File]::Create($resolvedOutput)
$writer = [System.IO.BinaryWriter]::new($fileStream)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
    $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$pngBytes.Length); $writer.Write([uint32]22)
    $writer.Write($pngBytes)
} finally {
    $writer.Dispose(); $fileStream.Dispose(); $pngStream.Dispose()
    $sparkle.Dispose(); $textFormat.Dispose(); $font.Dispose(); $innerPen.Dispose()
    $background.Dispose(); $path.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}

Write-Output "已生成图标：$resolvedOutput"
Write-Output "预览文件：$([System.IO.Path]::GetFullPath($PreviewPath))"
