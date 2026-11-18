@echo off
title Temp Cleaner installer - V-Sharp AI Labs
cd /d "%~dp0"

REM Make sure the ZIP was extracted first
if not exist "%~dp0TempCleaner.ps1" goto notextracted
if not exist "%~dp0Install.ps1" goto notextracted

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 (
  echo.
  echo Something went wrong. Please email vsharpailabs@gmail.com with a photo of this window.
  pause
)
exit /b

:notextracted
echo.
echo  Please extract the ZIP first:
echo  right-click TempCleaner.zip, choose "Extract All", then open the new folder
echo  and double-click "Install Temp Cleaner" again.
echo.
pause
