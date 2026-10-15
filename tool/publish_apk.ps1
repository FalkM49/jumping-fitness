# Новая версия Android-приложения для клиентов. Постоянная ссылка
# https://jumpingfitness.web.app/android ведёт на файл JumpingFitness.apk
# последнего релиза на GitHub (firebase.json → redirects):
#   https://github.com/FalkM49/jumping-fitness/releases/latest/download/JumpingFitness.apk
# Firebase Hosting на тарифе Spark не принимает APK (исполняемые файлы
# запрещены), Yandex Object Storage больше не используем.
#
#   powershell -ExecutionPolicy Bypass -File tool\publish_apk.ps1
#
# Перед запуском поднимите версию в pubspec.yaml (число после «+» растёт
# всегда) — иначе Android не поставит обновление поверх.
#
# Скрипт собирает APK в dist\JumpingFitness.apk и открывает страницу нового
# релиза на GitHub. Там: Tag — v<версия>, перетащить файл, Publish release.
# Имя файла должно остаться JumpingFitness.apk — на него ведёт ссылка.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Test-Path 'android\key.properties')) {
  throw 'Нет android\key.properties — без постоянного ключа обновление не встанет поверх.'
}

$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value

flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw 'Сборка не удалась.' }

New-Item -ItemType Directory -Force 'dist' | Out-Null
Copy-Item 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk' 'dist\JumpingFitness.apk' -Force

Write-Output "Готово: dist\JumpingFitness.apk (версия $version)"
Write-Output "Загрузите его в новый релиз с тегом v$version — страница открывается в браузере."
$tag = [uri]::EscapeDataString("v$version")
$title = [uri]::EscapeDataString("Jumping Fitness $version")
Start-Process "https://github.com/FalkM49/jumping-fitness/releases/new?tag=$tag&title=$title"
