@echo off
setlocal
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0save-report.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0save-report.ps1" %*
)
exit /b %ERRORLEVEL%
