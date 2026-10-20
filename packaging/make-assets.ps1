# Sinh bộ icon/tile cho gói MSIX từ Themes/Logo.xaml (cùng nguồn với logo trong app và app.ico).
# Chạy: powershell -STA -File packaging\make-assets.ps1
param([string]$OutDir = (Join-Path $PSScriptRoot "Assets"))

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$logoXaml = Join-Path $PSScriptRoot "..\Themes\Logo.xaml"
$stream = [IO.File]::OpenRead($logoXaml)
try { $img = ([System.Windows.Markup.XamlReader]::Load($stream))["LogoImage"] } finally { $stream.Close() }

New-Item -ItemType Directory -Force $OutDir | Out-Null
Get-ChildItem $OutDir -Filter *.png | Remove-Item

# Vẽ logo cỡ $logo px, căn giữa trên khung $w x $h trong suốt
function Save-Png([string]$name, [int]$w, [int]$h, [double]$logo) {
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.DrawImage($img, (New-Object System.Windows.Rect (($w - $logo) / 2), (($h - $logo) / 2), $logo, $logo))
    $dc.Close()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $OutDir $name))
    try { $enc.Save($fs) } finally { $fs.Close() }
}

foreach ($scale in 100, 125, 150, 200, 400) {
    $k = $scale / 100.0
    # Logo ứng dụng (danh sách Start, thanh tác vụ): logo gần kín khung
    Save-Png "Square44x44Logo.scale-$scale.png" ([int](44 * $k)) ([int](44 * $k)) (40 * $k)
    # Tile vuông vừa / nhỏ / lớn và tile ngang: logo ở giữa, chừa lề
    Save-Png "Square150x150Logo.scale-$scale.png" ([int](150 * $k)) ([int](150 * $k)) (84 * $k)
    Save-Png "SmallTile.scale-$scale.png" ([int](71 * $k)) ([int](71 * $k)) (46 * $k)
    Save-Png "LargeTile.scale-$scale.png" ([int](310 * $k)) ([int](310 * $k)) (160 * $k)
    Save-Png "Wide310x150Logo.scale-$scale.png" ([int](310 * $k)) ([int](150 * $k)) (84 * $k)
    # Logo trên trang Store
    Save-Png "StoreLogo.scale-$scale.png" ([int](50 * $k)) ([int](50 * $k)) (50 * $k)
}

# Icon thanh tác vụ / File Explorer theo kích thước tuyệt đối (không có nền "plate")
foreach ($size in 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 256) {
    Save-Png "Square44x44Logo.targetsize-$size.png" $size $size $size
    Save-Png "Square44x44Logo.targetsize-${size}_altform-unplated.png" $size $size $size
    Save-Png "Square44x44Logo.targetsize-${size}_altform-lightunplated.png" $size $size $size
}

"Assets: " + (Get-ChildItem $OutDir -Filter *.png).Count + " files -> $OutDir"
