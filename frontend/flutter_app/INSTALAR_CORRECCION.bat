@echo off
setlocal
cd /d "%~dp0"
echo ================================================
echo TradePilot MT5 - Correccion directa de main.dart
echo ================================================
if not exist "pubspec.yaml" (
  echo ERROR: No encuentro pubspec.yaml.
  echo Extrae ESTE ZIP directamente dentro de:
  echo D:\TradePilotMT5\TradePilotMT5_Package\frontend\flutter_app
  pause
  exit /b 1
)
if not exist "main.dart" (
  echo ERROR: No encuentro el main.dart de correccion junto a este BAT.
  pause
  exit /b 1
)
if not exist "lib" mkdir "lib"
copy /Y "%~dp0main.dart" "%~dp0lib\main.dart"
if errorlevel 1 (
  echo ERROR: no pude copiar el archivo a lib\main.dart
  pause
  exit /b 1
)
echo.
echo Se ha copiado el archivo corregido a:
echo %CD%\lib\main.dart
echo.
echo Verificacion de contenido:
findstr /n /c:"Símbolo del broker" "lib\main.dart"
findstr /n /c:"Future<void> pickSymbol()" "lib\main.dart"
echo.
echo Ejecutando flutter clean...
call flutter clean
if errorlevel 1 goto error
echo Ejecutando flutter pub get...
call flutter pub get
if errorlevel 1 goto error
echo Ejecutando Flutter para Windows...
call flutter run -d windows
if errorlevel 1 goto error
goto end
:error
echo.
echo Ha fallado un paso. Copia el error completo que aparece arriba.
pause
:end
endlocal
