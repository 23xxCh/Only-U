@echo off
setlocal
cd /d "%~dp0"
where pwsh >nul 2>&1
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0portable\wipe-records.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0portable\wipe-records.ps1" %*
)
set "WIPE_EXIT=%ERRORLEVEL%"
if not "%WIPE_EXIT%"=="0" (
  echo.
  pause
)
exit /b %WIPE_EXIT%