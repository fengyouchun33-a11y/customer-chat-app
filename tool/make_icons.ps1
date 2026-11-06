# 从 design/app-icon-source.png 生成 Android / iOS 的桌面启动图标。
# 换 logo 时只需覆盖源文件再重跑本脚本，不要手改生成物。
#
#   powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1
#   powershell -ExecutionPolicy Bypass -File tool/make_icons.ps1 -SourcePath C:\path\to\logo.png
#
# 源图要求：正方形、满幅出血（自带背景色/渐变）、不要透明圆角。
# Android 自适应图标是 108dp 画布，启动器只显示中心 72dp 并套各种遮罩形状，
# 关键图形必须落在 66dp 安全圆内。前景层按 84dp 铺：画满 108dp 会把耳机耳罩
# 切掉（源图耳机横跨约 2/3 幅面），只画 72dp 又显得比别的 App 小一圈。
param(
    [string]$SourcePath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($SourcePath)) {
    $SourcePath = Join-Path $ProjectRoot 'design/app-icon-source.png'
}
if (-not (Test-Path $SourcePath)) {
    throw "找不到图标源文件：$SourcePath"
}
$SourcePath = (Resolve-Path $SourcePath).Path
Write-Output "source: $SourcePath"

$src = [System.Drawing.Image]::FromFile($SourcePath)
if ($src.Width -ne $src.Height) {
    $src.Dispose()
    throw "图标源文件必须是正方形，当前 $($src.Width)x$($src.Height)"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false

# mode: square = 满幅（老式图标 / iOS）；circle = 满幅后裁圆；inset = 画进 108dp 画布中心
function Save-Icon {
    param(
        [int]$Size,
        [string]$OutFile,
        [ValidateSet('square', 'circle', 'inset')]
        [string]$Mode
    )
    $withAlpha = ($Mode -ne 'square')
    $format = if ($withAlpha) {
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    } else {
        # iOS 的 AppIcon 不允许带 alpha（App Store 校验会拒），统一拍平成 RGB
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    }
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, $format)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($(if ($withAlpha) { [System.Drawing.Color]::Transparent } else { [System.Drawing.Color]::Black }))

    if ($Mode -eq 'inset') {
        # 108dp 画布，图形占中心 84dp（可见区仍是 72dp，多出的一圈给遮罩留余量）
        $inner = [int][Math]::Round($Size * 84 / 108)
        $pad = [int](($Size - $inner) / 2)
        $g.DrawImage($script:src, $pad, $pad, $inner, $inner)
    } elseif ($Mode -eq 'circle') {
        $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
        $clip.AddEllipse(0, 0, $Size, $Size)
        $g.SetClip($clip)
        $g.DrawImage($script:src, 0, 0, $Size, $Size)
        $clip.Dispose()
    } else {
        $g.DrawImage($script:src, 0, 0, $Size, $Size)
    }

    $g.Dispose()
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("  {0} ({1}px, {2})" -f $OutFile.Replace($ProjectRoot + '\', ''), $Size, $Mode)
}

function Save-Text {
    param([string]$OutFile, [string]$Content)
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # here-string 的换行跟随源文件，统一成 CRLF 再落盘（先归一再展开，避免 CRLF 变成 CR CR LF）
    $text = $Content.Replace("`r`n", "`n").Replace("`n", "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($OutFile, $text, $utf8NoBom)
    Write-Output ("  {0}" -f $OutFile.Replace($ProjectRoot + '\', ''))
}

# ---------------------------------------------------------------- Android
# 老式图标（API 25 及以下、以及不认自适应图标的启动器）按密度五档出图；
# 自适应图标 = 满幅渐变背景层 + 中心 72dp 前景层，启动器自己裁形状。
Write-Output '--- android ---'
$densities = [ordered]@{ mdpi = 1.0; hdpi = 1.5; xhdpi = 2.0; xxhdpi = 3.0; xxxhdpi = 4.0 }
foreach ($name in $densities.Keys) {
    $d = $densities[$name]
    $dir = Join-Path $ProjectRoot "android/app/src/main/res/mipmap-$name"
    Save-Icon -Size ([int][Math]::Round(48 * $d)) -OutFile (Join-Path $dir 'ic_launcher.png') -Mode 'square'
    Save-Icon -Size ([int][Math]::Round(48 * $d)) -OutFile (Join-Path $dir 'ic_launcher_round.png') -Mode 'circle'
    Save-Icon -Size ([int][Math]::Round(108 * $d)) -OutFile (Join-Path $dir 'ic_launcher_foreground.png') -Mode 'inset'
}

$res = Join-Path $ProjectRoot 'android/app/src/main/res'

# 背景层跟着源图的对角走势（左下深蓝 → 右上青），遮罩露出边角时不会跳色
Save-Text -OutFile (Join-Path $res 'drawable/ic_launcher_background.xml') -Content @'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="45"
        android:centerColor="#FF0086D5"
        android:endColor="#FF3EF4FE"
        android:startColor="#FF012169" />
</shape>
'@

$adaptiveIcon = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@
Save-Text -OutFile (Join-Path $res 'mipmap-anydpi-v26/ic_launcher.xml') -Content $adaptiveIcon
Save-Text -OutFile (Join-Path $res 'mipmap-anydpi-v26/ic_launcher_round.xml') -Content $adaptiveIcon

# 状态栏小图标：必须是单色剪影，不能拿桌面图标复用。桌面图标现在是 adaptive-icon
# （mipmap-anydpi-v26），FCM 与前台服务通知拿它当 small icon 会被涂成一整块白色。
Save-Text -OutFile (Join-Path $res 'drawable/ic_stat_keiyo.xml') -Content @'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,1c-4.97,0 -9,4.03 -9,9v7c0,1.66 1.34,3 3,3h3v-8H9v-2H6c0,-3.31 2.69,-6 6,-6s6,2.69 6,6h-3v2h-1v8h3c1.66,0 3,-1.34 3,-3v-7c0,-4.97 -4.03,-9 -9,-9z" />
</vector>
'@

# ---------------------------------------------------------------- iOS
# Xcode 的 AppIcon.appiconset 沿用原有文件名与 Contents.json，只替换图片内容。
Write-Output '--- ios ---'
$appIconDir = Join-Path $ProjectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$iosIcons = [ordered]@{
    'Icon-App-20x20@1x.png'     = 20
    'Icon-App-20x20@2x.png'     = 40
    'Icon-App-20x20@3x.png'     = 60
    'Icon-App-29x29@1x.png'     = 29
    'Icon-App-29x29@2x.png'     = 58
    'Icon-App-29x29@3x.png'     = 87
    'Icon-App-40x40@1x.png'     = 40
    'Icon-App-40x40@2x.png'     = 80
    'Icon-App-40x40@3x.png'     = 120
    'Icon-App-60x60@2x.png'     = 120
    'Icon-App-60x60@3x.png'     = 180
    'Icon-App-76x76@1x.png'     = 76
    'Icon-App-76x76@2x.png'     = 152
    'Icon-App-83.5x83.5@2x.png' = 167
    'Icon-App-1024x1024@1x.png' = 1024
}
foreach ($name in $iosIcons.Keys) {
    Save-Icon -Size $iosIcons[$name] -OutFile (Join-Path $appIconDir $name) -Mode 'square'
}

$src.Dispose()
Write-Output 'done'
