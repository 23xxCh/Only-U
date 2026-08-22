@echo off
setlocal
set "PS=powershell"
where pwsh >nul 2>&1 && set "PS=pwsh"
if /I "%~1"=="-Execute" (
  %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean.ps1" -Execute
) else if /I "%~1"=="-Interactive" (
  %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean.ps1" -Interactive
) else (
  %PS% -NoProfile -ExecutionPolicy Bypass -File "%~dp0clean.ps1"
)
exit /b %ERRORLEVEL%
