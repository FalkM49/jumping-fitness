# Иконка приложения: монограмма «JF» в «лепестке» (ТЗ 11: радиусы 24/4/4/4,
# фирменный розовый bloom на тёмном фоне приложения).
# Запуск: powershell -File tool\make_icon.ps1 — пишет assets/icon/*.png,
# затем `dart run flutter_launcher_icons` раскладывает их по платформам.

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'assets\icon'
New-Item -ItemType Directory -Force $out | Out-Null

$dark = [System.Drawing.ColorTranslator]::FromHtml('#1C1418')
$bloom = [System.Drawing.ColorTranslator]::FromHtml('#C81E5E')
$bloomLight = [System.Drawing.ColorTranslator]::FromHtml('#E85A8C')
$ink = [System.Drawing.ColorTranslator]::FromHtml('#FFF8FA')

function New-Petal([float]$x, [float]$y, [float]$size) {
  # Большой радиус — сверху слева, остальные маленькие (как у PetalCard).
  $big = $size * 0.36; $small = $size * 0.07
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $p.AddArc($x, $y, 2 * $big, 2 * $big, 180, 90)
  $p.AddArc($x + $size - 2 * $small, $y, 2 * $small, 2 * $small, 270, 90)
  $p.AddArc($x + $size - 2 * $small, $y + $size - 2 * $small, 2 * $small, 2 * $small, 0, 90)
  $p.AddArc($x, $y + $size - 2 * $small, 2 * $small, 2 * $small, 90, 90)
  $p.CloseFigure()
  return $p
}

function Draw-Icon([string]$file, [bool]$withBackground) {
  $n = 1024
  $bmp = New-Object System.Drawing.Bitmap $n, $n, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)
  if ($withBackground) { $g.Clear($dark) }

  # Лепесток в безопасной зоне адаптивной иконки (центральные ~66%).
  $size = 600; $x = ($n - $size) / 2; $y = ($n - $size) / 2
  $petal = New-Petal $x $y $size
  $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
    (New-Object System.Drawing.PointF $x, $y),
    (New-Object System.Drawing.PointF ($x + $size), ($y + $size)),
    $bloomLight, $bloom)
  $g.FillPath($grad, $petal)

  # Буквы — толстые линии со скруглёнными концами (геометрия как у Unbounded).
  $pen = New-Object System.Drawing.Pen $ink, 62
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $top = 382; $bottom = 642; $mid = 506
  # J: ножка и крючок.
  $jx = 468
  $g.DrawLine($pen, $jx, $top, $jx, 560)
  $g.DrawArc($pen, ($jx - 164), (560 - 82), 164, 164, 0, 150)
  # F: ножка и две перекладины.
  $fx = 552
  $g.DrawLine($pen, $fx, $top, $fx, $bottom)
  $g.DrawLine($pen, $fx, $top, 684, $top)
  $g.DrawLine($pen, $fx, $mid, 656, $mid)

  $bmp.Save((Join-Path $out $file), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
}

Draw-Icon 'icon.png' $true        # обычная иконка (iOS, веб, старые Android)
Draw-Icon 'foreground.png' $false # передний слой адаптивной иконки Android
Write-Output "Готово: $out"
