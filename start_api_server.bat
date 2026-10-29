@echo off
cd /d "%~dp0"
if exist ".tools\python\python.exe" (
  ".tools\python\python.exe" api_server.py
) else (
  python api_server.py
)
pause
