@echo off
cd /d "%~dp0"
if exist "%~dp0RB-Legacy-Java-Converter.exe" (
  start "" "%~dp0RB-Legacy-Java-Converter.exe"
  exit /b 0
)
if exist "%~dp0src\RB.LegacyJavaConverter\bin\Release\net8.0-windows\RB-Legacy-Java-Converter.exe" (
  start "" "%~dp0src\RB.LegacyJavaConverter\bin\Release\net8.0-windows\RB-Legacy-Java-Converter.exe"
  exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'Build the GUI first: .\scripts\Build-Release.ps1' -ForegroundColor Yellow; pause"
