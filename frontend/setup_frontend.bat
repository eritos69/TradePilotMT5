@echo off
cd /d "%~dp0"
if not exist "flutter_app\pubspec.yaml" (
  flutter create --platforms=windows --project-name tradepilot_mt5 flutter_app
  if errorlevel 1 (echo No se ha podido crear Flutter. Comprueba PATH y Visual Studio.& pause & exit /b 1)
)
xcopy /E /I /Y "lib_source" "flutter_app\lib" >nul
copy /Y "pubspec.yaml" "flutter_app\pubspec.yaml" >nul
echo Proyecto preparado. Ahora: cd flutter_app ^& flutter pub get ^& flutter run -d windows
pause
