@echo off
setlocal EnableExtensions
title Only-U

set "PORTABLE_DIR=%~dp0"
set "NODE_EXE=%PORTABLE_DIR%runtime\node\node.exe"
set "DSH_HOME=%PORTABLE_DIR%runtime\dsh"
rem Do not load host ~/.agents skills; USB-only user-agents root
set "DSH_AGENTS_HOME=%PORTABLE_DIR%.agents-home"
set "DSH_BIN=%DSH_HOME%\lib\bin.js"
set "DSH_PROFILE=%DSH_HOME%\profiles\dsh-tui\package.json"
set "ENV_FILE=%PORTABLE_DIR%.env"
set "STAGE_ROOT=%LOCALAPPDATA%\Only-U\cache"
set "USB_TUI=%DSH_HOME%\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui"
set "CACHE_TUI=%STAGE_ROOT%\dsh\profiles\dsh-tui\node_modules\@deepseek-harness-tui\dsh-tui"

if not exist "%NODE_EXE%" (
  echo Missing portable\runtime\node\node.exe. Cannot start Only-U.
  echo Double-click portable\diagnose.cmd instead.
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_BIN%" (
  echo Missing portable\runtime\dsh\lib\bin.js. Cannot start Only-U.
  echo Double-click portable\diagnose.cmd instead.
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_PROFILE%" (
  echo Missing portable\runtime\dsh\profiles\dsh-tui\package.json. Cannot start Only-U.
  echo Double-click portable\diagnose.cmd instead.
  echo.
  pause
  exit /b 1
)

rem Use local cache only if already complete. Never robocopy on this click.
set "RUN_NODE=%NODE_EXE%"
set "RUN_HOME=%DSH_HOME%"
if not exist "%STAGE_ROOT%\node\node.exe" goto :run_ready
if not exist "%STAGE_ROOT%\dsh\lib\bin.js" goto :run_ready
if not exist "%STAGE_ROOT%\dsh\profiles\dsh-tui\package.json" goto :run_ready
if not exist "%DSH_HOME%\BAKE-ID" goto :run_ready
if not exist "%STAGE_ROOT%\BAKE-ID" goto :run_ready
fc /b "%DSH_HOME%\BAKE-ID" "%STAGE_ROOT%\BAKE-ID" >nul 2>&1
if errorlevel 1 goto :run_ready
if not exist "%USB_TUI%\lib\types\components\LogoV2.js" goto :use_cache
if not exist "%CACHE_TUI%\lib\types\components\LogoV2.js" goto :use_cache
fc /b "%USB_TUI%\lib\types\components\LogoV2.js" "%CACHE_TUI%\lib\types\components\LogoV2.js" >nul 2>&1
if errorlevel 1 goto :run_ready
:use_cache
set "RUN_NODE=%STAGE_ROOT%\node\node.exe"
set "RUN_HOME=%STAGE_ROOT%\dsh"
:run_ready
set "RUN_BIN=%RUN_HOME%\lib\bin.js"
set "PATH=%PORTABLE_DIR%runtime\node;%PATH%"
set "NODE_COMPILE_CACHE=%LOCALAPPDATA%\Only-U\node-compile-cache"
set "NODE_COMPILE_CACHE_PORTABLE=1"

set "DEEPSEEK_API_KEY="
set "DEEPSEEK_BASE_URL="
if exist "%ENV_FILE%" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    if /I "%%A"=="DEEPSEEK_API_KEY" set "DEEPSEEK_API_KEY=%%B"
    if /I "%%A"=="DEEPSEEK_BASE_URL" set "DEEPSEEK_BASE_URL=%%B"
  )
)

set "ONLY_U_KEY_PASTED="
if "%DEEPSEEK_API_KEY%"=="" (
  echo Paste DeepSeek API Key, then Enter:
  set /p DEEPSEEK_API_KEY=
  set "ONLY_U_KEY_PASTED=1"
)
set "KEY_CHECK=%DEEPSEEK_API_KEY: =%"
if "%KEY_CHECK%"=="" (
  echo No API Key. If offline, double-click portable\diagnose.cmd.
  echo.
  pause
  exit /b 1
)
if "%DEEPSEEK_BASE_URL%"=="" set "DEEPSEEK_BASE_URL=https://api.deepseek.com"
if "%ONLY_U_KEY_PASTED%"=="1" (
  >"%ENV_FILE%" echo DEEPSEEK_API_KEY=%DEEPSEEK_API_KEY%
  >>"%ENV_FILE%" echo DEEPSEEK_BASE_URL=%DEEPSEEK_BASE_URL%
)

rem Theme JSON is loaded from %USERPROFILE%\.dsh-tui\themes. Copy is best-effort.
set "THEME_SRC=%PORTABLE_DIR%themes"
set "THEME_DST=%USERPROFILE%\.dsh-tui\themes"
set "THEME_COPY_FAIL="
if exist "%THEME_SRC%\only-u.json" (
  if not exist "%THEME_DST%" mkdir "%THEME_DST%" >nul 2>&1
  copy /y "%THEME_SRC%\only-u.json" "%THEME_DST%\only-u.json" >nul 2>&1
  if errorlevel 1 set "THEME_COPY_FAIL=1"
  copy /y "%THEME_SRC%\only-u-dark.json" "%THEME_DST%\only-u-dark.json" >nul 2>&1
  if errorlevel 1 set "THEME_COPY_FAIL=1"
)
if defined THEME_COPY_FAIL echo [Only-U] theme copy failed; TUI still starting.
set "DSH_TUI_THEME=only-u"
set "DSH_TUI_NO_UPDATE=1"

set "PRESET_FILE=%USERPROFILE%\.dsh-tui\agent-preset.json"
if not exist "%PRESET_FILE%" (
  if not exist "%USERPROFILE%\.dsh-tui" mkdir "%USERPROFILE%\.dsh-tui" >nul 2>&1
  >"%PRESET_FILE%" echo {"preset":"only-u-repair"}
)

echo Opening TUI...
"%RUN_NODE%" "%RUN_BIN%" --profile dsh-tui
set "START_EXIT=%ERRORLEVEL%"
if not "%START_EXIT%"=="0" (
  echo TUI failed, exit %START_EXIT%.
  echo Double-click portable\diagnose.cmd instead.
  echo.
  pause
)
exit /b %START_EXIT%
