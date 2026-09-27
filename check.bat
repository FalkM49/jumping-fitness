@echo off
rem Проверка проекта: flutter create (если нет платформ), pub get, analyze, test.
rem Весь вывод пишется в flutter_log.txt рядом с этим файлом.
chcp 65001 >nul
cd /d "%~dp0"
set "LOG=%~dp0flutter_log.txt"
echo ==== START %date% %time% > "%LOG%"
where flutter >> "%LOG%" 2>&1
if errorlevel 1 (
  echo FLUTTER_NOT_FOUND >> "%LOG%"
  goto end
)
call flutter --version >> "%LOG%" 2>&1
call flutter doctor -v >> "%LOG%" 2>&1
if not exist "android" (
  echo ==== FLUTTER CREATE >> "%LOG%"
  call flutter create . --org ru.jumpingfitness --project-name jumping_fitness --platforms=android,ios >> "%LOG%" 2>&1
)
echo ==== PUB GET >> "%LOG%"
call flutter pub get >> "%LOG%" 2>&1
echo ==== ANALYZE >> "%LOG%"
call flutter analyze >> "%LOG%" 2>&1
echo ==== TEST >> "%LOG%"
call flutter test >> "%LOG%" 2>&1
:end
echo ==== DONE %date% %time% >> "%LOG%"
