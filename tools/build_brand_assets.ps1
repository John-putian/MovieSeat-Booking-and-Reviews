# Package the approved logo mark at each platform's required icon sizes.
# This resizes/pads the artwork without changing the design.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$source = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/branding/movieseat-mark.png'))
$wordmark = [System.Drawing.Image]::FromFile((Join-Path $projectRoot 'assets/branding/movieseat-logo.png'))
function Save-BrandImage([string]$relativePath, [int]$width, [int]$height, [bool]$opaque = $true, [double]$scale = 1, [bool]$useWordmark = $false) {
  $path = Join-Path $projectRoot $relativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $pixelFormat = if ($opaque) { [System.Drawing.Imaging.PixelFormat]::Format24bppRgb } else { [System.Drawing.Imaging.PixelFormat]::Format32bppArgb }
  $bitmap = New-Object System.Drawing.Bitmap($width, $height, $pixelFormat)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $background = if ($opaque) { [System.Drawing.Color]::FromArgb(244,241,255) } else { [System.Drawing.Color]::Transparent }
  $graphics.Clear($background)
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $inputImage = if ($useWordmark) { $wordmark } else { $source }
  $w = [int]($width * $scale)
  $h = [int]($height * $scale)
  $graphics.DrawImage($inputImage, [int](($width-$w)/2), [int](($height-$h)/2), $w, $h)
  $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose()
  $bitmap.Dispose()
}
try {
  $densities = @(@('mdpi',1),@('hdpi',1.5),@('xhdpi',2),@('xxhdpi',3),@('xxxhdpi',4))
  foreach ($entry in $densities) {
    $density = $entry[0]
    $factor = [double]$entry[1]
    Save-BrandImage "android/app/src/main/res/mipmap-$density/ic_launcher.png" ([int](48*$factor)) ([int](48*$factor))
    Save-BrandImage "android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png" ([int](108*$factor)) ([int](108*$factor)) $false 0.9
    Save-BrandImage "android/app/src/main/res/drawable-$density/brand_splash.png" ([int](128*$factor)) ([int](128*$factor)) $false
    Save-BrandImage "android/app/src/main/res/drawable-$density/brand_wordmark.png" ([int](192*$factor)) ([int](64*$factor)) $false 1 $true
  }
  foreach ($size in @(192,512)) {
    Save-BrandImage "web/icons/Icon-$size.png" $size $size
    Save-BrandImage "web/icons/Icon-maskable-$size.png" $size $size
  }
  Save-BrandImage 'web/favicon.png' 64 64
  foreach ($platform in @('ios','macos')) {
    $folder = "$platform/Runner/Assets.xcassets/AppIcon.appiconset"
    $manifest = Get-Content -Raw (Join-Path $projectRoot "$folder/Contents.json") | ConvertFrom-Json
    foreach ($entry in $manifest.images) {
      if ($entry.filename) {
        $base = [double]($entry.size.Split('x')[0])
        $factor = [double]($entry.scale.Replace('x',''))
        $size = [int]($base*$factor)
        Save-BrandImage "$folder/$($entry.filename)" $size $size
      }
    }
  }
  $launchNames = @('LaunchImage.png','LaunchImage@2x.png','LaunchImage@3x.png')
  for ($i=0; $i -lt 3; $i++) {
    Save-BrandImage "ios/Runner/Assets.xcassets/LaunchImage.imageset/$($launchNames[$i])" (192*($i+1)) (64*($i+1)) $false 1 $true
  }
  foreach ($size in @(16,32,48,64,128,256)) {
    Save-BrandImage ".tools/brand-icons/icon-$size.png" $size $size
  }
} finally {
  $source.Dispose()
  $wordmark.Dispose()
}
Write-Output 'Platform icon sizes and splash artwork generated.'
