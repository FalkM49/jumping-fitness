# Новая версия Android-приложения для клиентов: сборка и загрузка по
# постоянной ссылке https://jumpingfitness.web.app/android
# (файл лежит в Yandex Object Storage — у Firebase Hosting на бесплатном
# тарифе лимит трафика 360 МБ в сутки, APK туда не помещается по объёму).
#
#   powershell -ExecutionPolicy Bypass -File tool\publish_apk.ps1
#
# Перед запуском поднимите версию в pubspec.yaml (число после «+» растёт
# всегда) — иначе Android не поставит обновление поверх.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:PATH = "$env:USERPROFILE\yandex-cloud\bin;$env:PATH"
$env:YC_CLI_INITIALIZATION_SILENCE = 'true'

if (-not (Test-Path 'android\key.properties')) {
  throw 'Нет android\key.properties — без постоянного ключа обновление не встанет поверх.'
}

flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'Сборка не удалась.' }

yc storage s3 cp 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk' `
  's3://jumpingfitness-download/jumping-fitness.apk' `
  --content-type 'application/vnd.android.package-archive' `
  --content-disposition 'attachment; filename="JumpingFitness.apk"'
if ($LASTEXITCODE -ne 0) { throw 'Загрузка не удалась.' }

Write-Output 'Готово: https://jumpingfitness.web.app/android'
