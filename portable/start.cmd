@echo off
setlocal EnableExtensions
set "ROOT=%~dp0.."
pushd "%ROOT%"

if exist "%~dp0.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%~dp0.env") do (
    if not "%%A"=="" set "%%A=%%B"
  )
)

set "DSH_HOME=%~dp0.dsh-home"
if not exist "%DSH_HOME%" mkdir "%DSH_HOME%"
if not exist "%DSH_HOME%\skills" mkdir "%DSH_HOME%\skills"

echo Only-U U盘包
echo   离线诊断: portable\diagnose.cmd
echo   清理预览: portable\clean.cmd
echo   无线网卡: 比赛不做
echo.

if not exist "%ROOT%\dsh\package.json" (
  echo 找不到 dsh\ ，无法启动 Agent。先跑 diagnose.cmd。
  popd
  exit /b 1
)

cd /d "%ROOT%\dsh"

where pnpm >nul 2>&1
if errorlevel 1 (
  echo 未找到 pnpm。离线路径请用 portable\diagnose.cmd
  popd
  exit /b 1
)

if "%~1"=="" (
  echo 启动 headless 运维会话。把 C 盘诊断交给 Agent。
  echo 无网请改跑 portable\diagnose.cmd
  call pnpm dsh --profile headless "这是一次 Only-U 运维会话。先读仓库 CONTEXT.md 和 skill only-u-ops。对当前 Windows 机器做诊断：C 盘空间、临时目录、近期系统错误、打印机。不要删除文件。给出可回收项预览。无线网卡路径本次不做。"
) else (
  call pnpm dsh --profile headless %*
)

set "ERR=%ERRORLEVEL%"
popd
exit /b %ERR%
