# Сборка веб-версии (для iPhone) — docs/09, шаг 7.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_web.ps1            боевая
#   powershell -ExecutionPolicy Bypass -File tool\build_web.ps1 -Emulators локальные эмуляторы
#   powershell -ExecutionPolicy Bypass -File tool\build_web.ps1 -Wasm      эксперимент с WebAssembly
#   … -ApiUrl https://<сайт>.netlify.app/api   другой сервер функций (docs/10_netlify.md)
#
# Что включено:
#   --no-web-resources-cdn  движок (canvaskit) — со своего хостинга, а не с
#                           www.gstatic.com: меньше зависимость от Google с
#                           мобильных сетей;
#   --source-maps           карты исходников: стеки из журнала ошибок можно
#                           расшифровать;
#   APP_VERSION             версия из pubspec.yaml — попадает в отчёты об ошибках.
#
# Потом: firebase deploy --only hosting
#   (сначала — канал предпросмотра: firebase hosting:channel:deploy <имя> --expires 7d)

param(
  [switch]$Emulators,
  [switch]$Wasm,
  [string]$ApiUrl
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value

$flags = @(
  'build', 'web', '--release',
  '--no-web-resources-cdn',
  '--source-maps',
  "--dart-define=APP_VERSION=$version"
)
if ($Emulators) {
  $flags += '--dart-define=USE_FIREBASE_EMULATORS=true'
  $flags += '--dart-define=FUNCTIONS_API_URL=http://127.0.0.1:5002'
}
if ($Wasm) { $flags += '--wasm' }
if ($ApiUrl) { $flags += "--dart-define=FUNCTIONS_API_URL=$ApiUrl" }

Write-Output "flutter $($flags -join ' ')"
& flutter @flags
if ($LASTEXITCODE -ne 0) { throw 'Сборка не удалась.' }
Write-Output "Готово: build\web (версия $version)"
