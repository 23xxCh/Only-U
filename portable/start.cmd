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
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_BIN%" (
  echo 找不到 portable\runtime\dsh\lib\bin.js，无法启动 Only-U。
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
  exit /b 1
)

if not exist "%DSH_PROFILE%" (
  echo 找不到 portable\runtime\dsh\profiles\dsh-tui\package.json，无法启动 Only-U。
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
  exit /b 1
)

set "PATH=%PORTABLE_DIR%runtime\node;%PATH%"

ping -n 1 -w 2000 223.5.5.5 >nul 2>&1
if errorlevel 1 (
  echo 当前无网络，无法启动 Only-U 在线会话。
  echo 请双击 portable\diagnose.cmd 完成 U 盘体检。
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
echo 请粘贴 DeepSeek API Key，然后按回车（输入会隐藏）。
set "DEEPSEEK_API_KEY="
for /f "usebackq delims=" %%K in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$secure = Read-Host -AsSecureString '请粘贴 DeepSeek API Key'; $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }"`) do set "DEEPSEEK_API_KEY=%%K"

if not defined DEEPSEEK_API_KEY (
  echo 未收到 API Key，无法启动 Only-U。
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
  exit /b 1
)

set "ONLY_U_ENV_FILE=%ENV_FILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$path = $env:ONLY_U_ENV_FILE; $key = $env:DEEPSEEK_API_KEY; $lines = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllLines($path) } else { @() }; $found = $false; for ($i = 0; $i -lt $lines.Length; $i++) { if ($lines[$i] -match '^[ \t]*DEEPSEEK_API_KEY[ \t]*=') { $lines[$i] = 'DEEPSEEK_API_KEY=' + $key; $found = $true } }; if (-not $found) { $lines += 'DEEPSEEK_API_KEY=' + $key }; $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllLines($path, $lines, $utf8NoBom)"
if errorlevel 1 (
  echo 写入 portable\.env 失败，无法启动 Only-U。
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
  exit /b 1
)

:start
set "ONLY_U_DSH_BIN=%DSH_BIN%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$target = $env:ONLY_U_DSH_BIN; try { $existing = Get-CimInstance -ClassName Win32_Process -Filter 'Name = ''node.exe''' -ErrorAction Stop | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($target, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 1; if ($null -ne $existing) { exit 1 } } catch { exit 0 }"
if errorlevel 1 (
  echo DSH TUI 已在运行。请关闭现有窗口，或在任务管理器中结束残留的 node.exe 后重试。
  echo.
  pause
  exit /b 1
)
echo 正在启动 Only-U 运维会话...
"%NODE_EXE%" "%DSH_BIN%" --profile dsh-tui
set "START_EXIT=%ERRORLEVEL%"
if not "%START_EXIT%"=="0" (
  echo TUI 启动失败（退出码 %START_EXIT%）。
  echo 请先运行 portable\diagnose.cmd 检查 U 盘包。
  echo.
  pause
)
exit /b %START_EXIT%
