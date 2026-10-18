@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
  echo Primero crea el entorno virtual e instala requirements.txt. Lee README.md.
  pause
  exit /b 1
)
call .venv\Scripts\activate
python -m uvicorn app.main:app --host 127.0.0.1 --port 8790
