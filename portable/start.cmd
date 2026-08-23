@echo off
setlocal EnableExtensions

set "PORTABLE_DIR=%~dp0"
set "NODE_EXE=%PORTABLE_DIR%runtime\node\node.exe"
set "DSH_HOME=%PORTABLE_DIR%runtime\dsh"
set "DSH_BIN=%DSH_HOME%\lib\bin.js"
set "DSH_PROFILE=%DSH_HOME%\profiles\dsh-tui\package.json"
set "ENV_FILE=%PORTABLE_DIR%.env"

if not exist "%NODE_EXE%" (
  echo 找不到 portable\runtime\node\node.exe，无法启动 Only-U。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_BIN%" (
  echo 找不到 portable\runtime\dsh\lib\bin.js，无法启动 Only-U。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_PROFILE%" (
  echo 找不到 portable\runtime\dsh\profiles\dsh-tui\package.json，无法启动 Only-U。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

rem ===== 本地暂存启动（staged boot）=====
rem U 盘随机读慢（实测 44s，同一棵树内置盘 3.5s），把 runtime 实体拷到本地缓存再启动。
rem 数据不离开 U 盘：会话/预设经 junction 回指，settings/凭据启动拷入退出拷回。
rem 任一步失败回退 U 盘直跑（fail-open，与单实例锁同纪律）。
set "STAGE_ROOT=%LOCALAPPDATA%\Only-U\cache"
set "STAGE_OK="
call :stage_runtime
if defined ONLY_U_STAGE_ONLY (
  if "%STAGE_OK%"=="1" (echo [stage-test] STAGED OK) else (echo [stage-test] FALLBACK DIRECT)
  exit /b 0
)

:run
if "%STAGE_OK%"=="1" (
  set "RUN_NODE=%STAGE_ROOT%\node\node.exe"
  set "RUN_HOME=%STAGE_ROOT%\dsh"
) else (
  set "RUN_NODE=%NODE_EXE%"
  set "RUN_HOME=%DSH_HOME%"
)
set "RUN_BIN=%RUN_HOME%\lib\bin.js"
set "PATH=%PORTABLE_DIR%runtime\node;%PATH%"

rem V8 编译缓存（Node 官方：ON-DISK CODE CACHE，失败静默，零风险）
set "NODE_COMPILE_CACHE=%LOCALAPPDATA%\Only-U\node-compile-cache"
set "NODE_COMPILE_CACHE_PORTABLE=1"

ping -n 1 -w 2000 223.5.5.5 >nul 2>&1
if errorlevel 1 (
  echo 当前无网络，无法启动 Only-U 联机会话。
  请双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

set "DEEPSEEK_API_KEY="
set "DEEPSEEK_BASE_URL="
if exist "%ENV_FILE%" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ENV_FILE%") do (
    if /I "%%A"=="DEEPSEEK_API_KEY" set "DEEPSEEK_API_KEY=%%B"
    if /I "%%A"=="DEEPSEEK_BASE_URL" set "DEEPSEEK_BASE_URL=%%B"
  )
)

if defined DEEPSEEK_API_KEY goto :start

echo 未找到可用的 DeepSeek API Key。
echo 粘贴你的 DeepSeek API Key，然后按回车（输入不可见）：
set "DEEPSEEK_API_KEY="
for /f "usebackq delims=" %%K in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$secure = Read-Host -AsSecureString '粘贴你的 DeepSeek API Key'; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }"`) do set "DEEPSEEK_API_KEY=%%K"

if not defined DEEPSEEK_API_KEY (
  echo 未收到 API Key，无法启动 Only-U。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

set "ONLY_U_ENV_FILE=%ENV_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$path = $env:ONLY_U_ENV_FILE; $key = $env:DEEPSEEK_API_KEY; $lines = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllLines($path) } else { @() }; $found = $false; for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match '^[ \t]*DEEPSEEK_API_KEY[ \t]*=') { $lines[$i] = 'DEEPSEEK_API_KEY=' + $key; $found = $true } }; if (-not $found) { $lines += 'DEEPSEEK_API_KEY=' + $key }; $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllLines($path, $lines, $utf8NoBom)"
if errorlevel 1 (
  echo 写入 portable\.env 失败，无法启动 Only-U。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
  exit /b 1
)

:start
set "ONLY_U_DSH_BIN=%RUN_BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$target = $env:ONLY_U_DSH_BIN; try { $existing = Get-CimInstance -ClassName Win32_Process -Filter 'Name = ''node.exe''' -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1; if ($null -ne $existing) { exit 42 } } catch { exit 0 }"
set "DSH_GUARD_EXIT=%ERRORLEVEL%"
if "%DSH_GUARD_EXIT%"=="42" (
  echo DSH TUI 已在运行中。请关闭那个窗口（或结束其中的 node.exe）再试。
  echo.
  pause
  exit /b 1
)
echo 正在启动 Only-U 运维会话...
"%RUN_NODE%" "%RUN_BIN%" --profile dsh-tui
set "START_EXIT=%ERRORLEVEL%"

rem 退出时把 settings/凭据拷回 U 盘（数据跟盘走）
if "%STAGE_OK%"=="1" (
  if exist "%RUN_HOME%\settings.yaml" copy /y "%RUN_HOME%\settings.yaml" "%DSH_HOME%\settings.yaml" >nul 2>&1
  if exist "%RUN_HOME%\.credentials.yaml" copy /y "%RUN_HOME%\.credentials.yaml" "%DSH_HOME%\.credentials.yaml" >nul 2>&1
)

if not "%START_EXIT%"=="0" (
  echo TUI 启动失败（退出码 %START_EXIT%）。
  echo 请先双击 portable\diagnose.cmd 做 U 盘体检。
  echo.
  pause
)
exit /b %START_EXIT%

rem ===== 暂存子程序：成功置 STAGE_OK=1，失败静默返回（回退直跑）=====
:stage_runtime
set "SRC_ID=%DSH_HOME%\BAKE-ID"
if not exist "%SRC_ID%" goto :eof
if not exist "%STAGE_ROOT%" md "%STAGE_ROOT%" >nul 2>&1
if not exist "%STAGE_ROOT%" goto :eof
set "CACHE_ID=%STAGE_ROOT%\BAKE-ID"
set "NEED_STAGE=1"
if exist "%CACHE_ID%" if exist "%STAGE_ROOT%\dsh\lib\bin.js" if exist "%STAGE_ROOT%\node\node.exe" (
  fc /b "%SRC_ID%" "%CACHE_ID%" >nul 2>&1
  if not errorlevel 1 set "NEED_STAGE="
)
if not defined NEED_STAGE goto :stage_links
echo 正在准备本地运行环境（仅此一次，约 1-3 分钟）...
robocopy "%PORTABLE_DIR%runtime\node" "%STAGE_ROOT%\node" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /MT:8 /XF BAKE-ID >nul
if errorlevel 8 goto :eof
robocopy "%DSH_HOME%" "%STAGE_ROOT%\dsh" /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NP /MT:8 /XD "%DSH_HOME%\sessions" "%DSH_HOME%\.agent-presets" /XF BAKE-ID >nul
if errorlevel 8 goto :eof
copy /y "%SRC_ID%" "%CACHE_ID%" >nul
:stage_links
rem 可变数据回指 U 盘：junction（目录）；yaml 双向拷贝（文件不能 junction）
if not exist "%DSH_HOME%\sessions" md "%DSH_HOME%\sessions" >nul 2>&1
if not exist "%STAGE_ROOT%\dsh\sessions" cmd /c mklink /J "%STAGE_ROOT%\dsh\sessions" "%DSH_HOME%\sessions" >nul 2>&1
if exist "%DSH_HOME%\.agent-presets" if not exist "%STAGE_ROOT%\dsh\.agent-presets" cmd /c mklink /J "%STAGE_ROOT%\dsh\.agent-presets" "%DSH_HOME%\.agent-presets" >nul 2>&1
if exist "%DSH_HOME%\settings.yaml" copy /y "%DSH_HOME%\settings.yaml" "%STAGE_ROOT%\dsh\settings.yaml" >nul 2>&1
if exist "%DSH_HOME%\.credentials.yaml" copy /y "%DSH_HOME%\.credentials.yaml" "%STAGE_ROOT%\dsh\.credentials.yaml" >nul 2>&1
rem 暂存产物校验：三缺一回退
if not exist "%STAGE_ROOT%\node\node.exe" goto :eof
if not exist "%STAGE_ROOT%\dsh\lib\bin.js" goto :eof
if not exist "%STAGE_ROOT%\dsh\profiles\dsh-tui\package.json" goto :eof
set "STAGE_OK=1"
goto :eof
