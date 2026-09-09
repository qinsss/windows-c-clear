param(
    [Parameter(Mandatory = $true)]
    [string]$ScreenshotPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\docs\images')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $ScreenshotPath)) { throw "找不到截图：$ScreenshotPath" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function New-RoundedRectanglePath {
    param([System.Drawing.RectangleF]$Rectangle, [float]$Radius)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $path.AddArc($Rectangle.X, $Rectangle.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rectangle.Right - $diameter, $Rectangle.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rectangle.X, $Rectangle.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$source = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $ScreenshotPath))
try {
    # 仅保留没有勾选状态的界面区域，避免公开截图造成“默认选择”的误解。
    $cropHeight = [Math]::Min(850, $source.Height)
    $overviewWidth = 1600
    $overviewHeight = [int]($cropHeight * $overviewWidth / $source.Width)
    $overview = [System.Drawing.Bitmap]::new($overviewWidth, $overviewHeight)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($overview)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, $overviewWidth, $overviewHeight), 0, 0, $source.Width, $cropHeight, [System.Drawing.GraphicsUnit]::Pixel)

            # 截图拍摄后页签名称曾调整；只替换页签文字，不改动任何扫描数据。
            $tabBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#E7EEF6'))
            $tabTextBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#38597A'))
            $tabFont = [System.Drawing.Font]::new('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
            $tabFormat = [System.Drawing.StringFormat]::new()
            try {
                $tabRect = [System.Drawing.RectangleF]::new(412, 312, 270, 50)
                $graphics.FillRectangle($tabBrush, $tabRect)
                $tabFormat.Alignment = [System.Drawing.StringAlignment]::Center
                $tabFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
                $graphics.DrawString('Windows 系统清理项', $tabFont, $tabTextBrush, $tabRect, $tabFormat)
            } finally {
                $tabBrush.Dispose(); $tabTextBrush.Dispose(); $tabFont.Dispose(); $tabFormat.Dispose()
            }
        } finally { $graphics.Dispose() }
        $overview.Save((Join-Path $OutputDirectory 'appdata-overview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $overview.Dispose() }
} finally { $source.Dispose() }

$canvas = [System.Drawing.Bitmap]::new(1280, 640)
try {
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml('#123B68'))

        $glow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(28, 87, 176, 255))
        $g.FillEllipse($glow, 850, -210, 620, 620)
        $glow.Dispose()

        $icon = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot '..\src\app-icon-preview.png'))
        try { $g.DrawImage($icon, 78, 137, 300, 300) } finally { $icon.Dispose() }

        $titleFont = [System.Drawing.Font]::new('Microsoft YaHei UI', 54, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $subFont = [System.Drawing.Font]::new('Microsoft YaHei UI', 28, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
        $chipFont = [System.Drawing.Font]::new('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
        $muted = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#C8DCF2'))
        try {
            $g.DrawString('C 盘清理助手', $titleFont, $white, 430, 132)
            $g.DrawString('先解释数据的作用，再由你决定是否删除', $subFont, $muted, 434, 225)

            $chips = @(
                @{ X=434; W=176; Text='默认不勾选' },
                @{ X=630; W=176; Text='删除到回收站' },
                @{ X=826; W=210; Text='AppData 精确扫描' }
            )
            foreach ($chip in $chips) {
                $rect = [System.Drawing.RectangleF]::new($chip.X, 315, $chip.W, 58)
                $path = New-RoundedRectanglePath -Rectangle $rect -Radius 18
                $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(42, 255, 255, 255))
                try { $g.FillPath($brush, $path) } finally { $brush.Dispose(); $path.Dispose() }
                $format = [System.Drawing.StringFormat]::new()
                $format.Alignment = [System.Drawing.StringAlignment]::Center
                $format.LineAlignment = [System.Drawing.StringAlignment]::Center
                try { $g.DrawString($chip.Text, $chipFont, $white, $rect, $format) } finally { $format.Dispose() }
            }

            $g.DrawString('Windows 10 / 11 · 开源 · 免安装', $subFont, $muted, 434, 430)
        } finally {
            $titleFont.Dispose(); $subFont.Dispose(); $chipFont.Dispose(); $white.Dispose(); $muted.Dispose()
        }
    } finally { $g.Dispose() }
    $canvas.Save((Join-Path $OutputDirectory 'social-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $canvas.Dispose() }

Write-Output "已生成推广图片：$OutputDirectory"
